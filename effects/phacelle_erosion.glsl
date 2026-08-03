#[compute]
/*
=====================================================================================

Advanced terrain erosion filter based on stacked faded gullies,
with controls for erosion strength, detail, ridge and crease rounding,
and producing a ridge map output useful for e.g. water drainage.

For more on the technique, see:
https://blog.runevision.com/2026/03/fast-and-gorgeous-erosion-filter.html

This buffer has three parts:

 - Phacelle Nose function (used by the erosion function)
 - Erosion function
 - Demonstration

For explanations of the erosion parameters, see the demonstration section.

This erosion technique was originally derived from versions by
Clay John (https://www.shadertoy.com/view/MtGcWh)
and Fewes (https://www.shadertoy.com/view/7ljcRW)
and my own cleaned up version (https://www.shadertoy.com/view/33cXW8),
but at this point has little in common with them, apart from the high level concept.

Also see "Advanced Terrain Erosion Filter" variation with animated parameters.
https://www.shadertoy.com/view/wXcfWn

Ported to Godot Compute Shaders by Devin Hastings
=====================================================================================
*/

#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer Target {
	// The size of the main heightmap
	uvec2 size;
} target;

layout(r32f, set = 0, binding = 1) uniform restrict image2D height_map;
layout(rg16f, set=0, binding = 2) uniform restrict image2D normal_map;
layout(push_constant, std430) uniform Parameters {
	// Horizontal scale
	float scale;	// default = .06;

	// The strength of the erosion effect, affecting the magnitude of all octaves,
	// and indirectly affecting the directions of the gullies as a result.
	float strength;	// default = 20.0;

	// The magnitude of the gullies as a weight value from 0 to 1.
	// A value of 0 can sharpen peaks and valleys but feature virtually no gullies.
	// A value of 1 produces full gullies but may leave peaks and valleys rounded.
	// Adjusting erosion gully weight while inversely adjusting erosion scale can be
	// used to control the sharpness of peaks and valleys while leaving gully
	// magnitudes largely untocuhed.
	float gully_weight;	// default = 0.5;

	// The overall detail of the erosion. Lower values restrict the effect of higher
	// frequency gullies to steeper slopes.
	float detail;	// default = 1.5;

	// Separate rounding control of ridges and creases.
	//  x: Rounding of ridges.
	//  y: Rounding of creases.
	//  z: Multiplier applied to the initial height function.
	//     E.g. if the height function has noise of 5 times lower frequency
	//     than the largest gullies, a value of 0.2 can compensate for that.
	//  w: Multiplier applied to each subsequent gully octave after the first.
	//     Setting it to the same value as the erosion lacunarity will produce
	//     consistent rounding of all octaves.
	vec4 rounding;	// default = vec4(2.0, 0.5, 0.1, 1.5);

	// Control over how far away from ridges/creases the erosion takes effect.
	//  x: Onset used on the initial height function.
	//  y: Onset used on each gully octave.
	//  z: RidgeMap-specific onset used on the initial height function.
	//  w: RidgeMap-specific onset used on each gully octave.
	vec4 onset;	// default = vec4(0.7, 1.25, 2.8, 1.5);

	// Gullies are based on stripes within Voronoi-like cells in the Phacelle noise
	// function. The cell scale parameter controls the sizes of the cells relative
	// to the overall erosion scale, while keeping the stripe widths unaffected.
	// Values close to 1 usually produce good results. Smaller values produce more
	// grainy gullies while larger values produce longer unbroken gullies, but too
	// large values produce chaotic curved gullies that are not aligned with the
	// slopes. Value changes can cause abrupt changes in output, especially far away
	// from the origin, so this parameter is not well suited for animation or for
	// modulation by other functions.
	float cell_scale;	// default = 0.7;
	// The degree of normalization applied in the Phacelle noise, between 0 and 1.
	// The erosion filter depends on a certain consistency in magnitude of the
	// Phacelle output. However, high values can create loopy results where ridges
	// and creases meet up at a point, which produces unnatural looking results.
	float normalization; // default = 0.5;
	// The lacunarity controls the frequency (the inverse
	// horizontal scale) of each octave relative to the last.
	float lacunarity;	// default = 1.5;
	// The gain controls the magnitude (the vertical
	// scale) of each octave relative to the last.
	float gain;	// default = 0.5;

	// Control over the erosion octaves, with each successive octave layering
	// smaller gullies onto the terrain.

	int octaves; // defualt = 5;
} param;


// UTILITY FUNCTIONS
float clamp01(float x) {
	return clamp(x, 0, 1);
}

// NOISE FUNCTION

#define TAU 6.28318530717959

vec2 hash(in vec2 x) {
	const vec2 k = vec2(0.3183099, 0.3678794);
	x = x * k + k.yx;
	return -1.0 + 2.0 * fract(16.0 * k * fract(x.x * x.y * (x.x + x.y)));
}

// The Simple Phacelle Noise function produces a stripe pattern aligned with the input vector.
// The name Phacelle is a portmanteau of phase and cell, since the function produces a phase by
// interpolating cosine and sine waves from multiple cells.
//  - p is the input point being evaluated.
//  - normDir is the direction of the stripes at this point. It must be a normalized vector.
//  - freq is the freqency of the stripes within each cell. It's best to keep it close to 1.0, as
//    high values will produce distortions and other artifacts.
//  - offset is the phase offset of the stripes, where 1.0 is a full cycle.
//  - normalization is the degree of normalization applied, between 0 and 1. With e.g. a value of
//    0.4, raw output with a magnitude below 0.6 won't get fully normalized to a magnitude of 1.0.
// Phacelle Noise function copyright (c) 2025 Rune Skovbo Johansen
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
vec4 PhacelleNoise(in vec2 p, vec2 normDir, float freq, float offset, float normalization) {
	// Get a vector orthogonal to the input direction, with a
	// magnitude proportional to the frequency of the stripes.
	vec2 sideDir = normDir.yx * vec2(-1.0, 1.0) * freq * TAU;
	offset *= TAU;

	// Iterate over 4x4 cells, calculating a stripe pattern for each and blending between them.
	// pInt is the integer part of the current coordinate p, pFrac is the remainder.
	//
	// o   o   o   o
	//
	// o   o   o   o
	//       p
	// o   i   o   o
	//
	// o   o   o   o
	//
	// p: current coordinate    i: integer part of p    o: grid points for 4x4 cells
	//
	vec2 pInt = floor(p);
	vec2 pFrac = fract(p);
	vec2 phaseDir = vec2(0.0);
	float weightSum = 0.0;
	for (int i = -1; i <= 2; i++) {
		for (int j = -1; j <= 2; j++) {
			vec2 gridOffset = vec2(i, j);

			// Calculate a cell point by starting off with a point in the integer grid.
			vec2 gridPoint = pInt + gridOffset;

			// Calculate a random offset for the cell point between -0.5 and 0.5 on each axis.
			vec2 randomOffset = hash(gridPoint) * 0.5;

			// The final cell point (we don't store it) is the gridPoint plus the randomOffset.
			// Calculate a vector representing the input point relative to this cell point:
			// p - (gridPoint + randomOffset)
			// = (pFrac + pInt) - ((pInt + gridOffset) + randomOffset)
			// = pFrac + pInt - pInt - gridOffset - randomOffset
			// = pFrac - gridOffset - randomOffset
			vec2 vectorFromCellPoint = pFrac - gridOffset - randomOffset;

			// Bell-shaped weight function which is 1 at dist 0 and nearly 0 at dist 1.5.
			// Due to the random offsets of up to 0.5, the closest a cell point not in the 4x4
			// grid can be to the current point p is 1.5 units away.
			float sqrDist = dot(vectorFromCellPoint, vectorFromCellPoint);
			float weight = exp(-sqrDist * 2.0);
			// Subtract 0.01111 to make the function actually 0 at distance 1.5, which avoids
			// some (very subtle) grid line artefacts.
			weight = max(0.0, weight - 0.01111);

			// Keep track of the total sum of weights.
			weightSum += weight;

			// The waveInput is a gradient which increases in value along sideDir. Its rate of
			// change is the freq times tau, due to the multiplier pre-applied to sideDir.
			float waveInput = dot(vectorFromCellPoint, sideDir) + offset;

			// Add this cell's cosine and sine wave contributions to the interpolated value.
			phaseDir += vec2(cos(waveInput), sin(waveInput)) * weight;
		}
	}

	// Get the raw interpolated value.
	vec2 interpolated = phaseDir / weightSum;
	// Interpret the value as a vector whose length represents the magnitude of both waves.
	float magnitude = length(interpolated);
	// Apply a lower threshold to show small magnitudes we're going to fully normalize.
	magnitude = max(1.0 - normalization, magnitude);
	// Return a vector containing the normalized cosine and sine waves, as well as the direction
	// vector, which can be multiplied onto the sine to get the derivatives of the cosine.
	return vec4(interpolated / magnitude, sideDir);
}

// -----------------------------------------------------------------------------
// EROSION FUNCTION
// -----------------------------------------------------------------------------


// First a few utility functions.

float pow_inv(float t, float power) {
	// Flip, raise to the specified power, and flip back.
	return 1.0 - pow(1.0 - clamp01(t), power);
}

float ease_out(float t) {
	// Flip by subtracting from one.
	float v = 1.0 - clamp01(t);
	// Raise to a power of two and flip back.
	return 1.0 - v * v;
}

float smooth_start(float t, float smoothing) {
	if (t >= smoothing)
		return t - 0.5 * smoothing;
	return 0.5 * t * t / smoothing;
}

vec2 safe_normalize(vec2 n) {
	// A div-by-zero-safe replacement for normalize.
	float l = length(n);
	return (abs(l) > 1e-10) ? (n / l) : n;  
}

// Advanced Terrain Erosion Filter copyright (c) 2025 Rune Skovbo Johansen
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Adapted to NP-Terrain by Devin Hastings
vec4 ErosionFilter(in vec2 p, float height, vec2 normal, float fadeTarget) {
	float strength = param.strength;
	fadeTarget = clamp(fadeTarget, -1.0, 1.0);
	
	float freq = 1.0 / (param.scale * param.cell_scale);
	// 0: flat
	// 1: totally vertical
	float slope = length(normal);
	float magnitude = 0.0;
	float roundingMult = 1.0;
	
	float roundingForInput = mix(param.rounding.y, param.rounding.x, clamp01(fadeTarget + 0.5)) * param.rounding.z;
	// The combined accumulating mask, based first on initial slope, and later on slope of each octave too.
	float combiMask = ease_out(smooth_start(slope * param.onset.x, roundingForInput * param.onset.x));

	// Initialize the ridgeMap fadeTarget and mask.
	float ridgeMapCombiMask = ease_out(slope * param.onset.z);
	float ridgeMapFadeTarget = fadeTarget;
	
	vec2 gullyNormal = normal;

	for (int i = 0; i < param.octaves; i++) {
		// Calculate and add gullies to the height and slope.
		vec4 phacelle = PhacelleNoise(p * freq, safe_normalize(gullyNormal), param.cell_scale, 0.25, param.normalization);
		// Multiply with freq since p was multiplied with freq.
		// Negate since we use slope directions that point down.
		phacelle.zw *= freq;
		// Amount of slope as value from 0 to 1.
		float sloping = abs(phacelle.y);
		
		// Add non-masked, normalized slope to gullyNormal, for use by subsequent octaves.
		// It's normalized to use the steepest part of the sine wave everywhere.
		gullyNormal += sign(phacelle.y) * phacelle.zw * strength * param.gully_weight;
		
		// Handle height offset and approximate output slope.
		
		// Gullies has height offset (from -1 to 1) in x and derivative in yz.
		vec3 gullies = vec3(phacelle.x, phacelle.y * phacelle.zw);
		// Fade gullies towards fadeTarget based on combiMask.
		vec3 fadedGullies = mix(vec3(fadeTarget, 0.0, 0.0), gullies * param.gully_weight, combiMask);
		// Apply height offset and derivative (slope) according to strength of current octave.
		vec3 hn = fadedGullies;
		height += hn.x * strength;
		normal += hn.yz;
		magnitude += strength;
		
		// Update fadeTarget to include the new octave.
		fadeTarget = fadedGullies.x;
		
		// Update the mask to include the new octave.
		float roundingForOctave = mix(param.rounding.y, param.rounding.x, clamp01(phacelle.x + 0.5)) * roundingMult;
		float newMask = ease_out(smooth_start(sloping * param.onset.y, roundingForOctave * param.onset.y));
		combiMask = pow_inv(combiMask, param.detail) * newMask;
		
		// Update the ridgeMap fadeTarget and mask.
		ridgeMapFadeTarget = mix(ridgeMapFadeTarget, gullies.x, ridgeMapCombiMask);
		float newRidgeMapMask = ease_out(sloping * param.onset.w);
		ridgeMapCombiMask = ridgeMapCombiMask * newRidgeMapMask;

		// Prepare the next octave.
		strength *= param.gain;
		freq *= param.lacunarity;
		roundingMult *= param.rounding.w;
	}
	
	return vec4(height, normal, magnitude);
}


void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	float height = imageLoad(height_map, p).r;
	vec2 normal = imageLoad(normal_map, p).rg;
	vec2 uv = vec2(p)/vec2(target.size);
	
	float fadeTarget = clamp(height/40, -1, 1);

	vec4 erosion = ErosionFilter(uv, height, normal, fadeTarget);
	imageStore(height_map, p, vec4(erosion.x));
}