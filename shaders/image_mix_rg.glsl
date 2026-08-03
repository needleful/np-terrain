#[compute]
#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer Target {
	// The size of the main heightmap
	uvec2 size;
} target;

layout(set = 0, binding = 1) uniform sampler2D source_sampler;
layout(r32f, set = 0, binding = 2) uniform restrict image2D output_image;

layout(push_constant, std430) uniform Source {
	// Inverse transform of the source object relative to the corner of the object
	vec4[3] inverse_transform;
	// The min and max heights to interpret from our source's 0-1
	vec2 height_range;
	// Size of the source/target in pixels
	uvec2 size;
	// The starting position of the shader in the destination's pixel-space
	uvec2 corner;
	uint blend_mode;
} source;


// Derived from https://github.com/visionworkbench/
// Licensed under the Apache License, Version 2.0
vec4 textureBicubic(sampler2D stamp, vec2 uv) {
	ivec2 ts = textureSize(stamp, 0);
	vec2 its = 1.0/vec2(ts);
	vec2 ij = floor(ts*uv);
	vec2 n = ts*uv - ij;
	vec2[4] dv;
	dv[0] = ((-n + 2) * n - 1) * n;
	dv[1] = (3*n - 5) * n * n + 2;
	dv[2] = ((-3 * n + 4) * n + 1) * n;
	dv[3] = (n - 1) * n * n;

	vec4 result = vec4(0);
	for(int y = 0; y <= 3; y++) {
		vec4 row = vec4(0);
		for(int x = 0; x <= 3; x++) {
			vec2 uv2 = (ij+vec2(x, y) - 1)*its;
			row += texture(stamp, uv2)*dv[x].x;
		}
		result += row*dv[y].y;
	}
	return result/4.0;
}

#define SUPPORT_SIZE 4
#define PI 3.1415926535897932385

float sinc(float x) {
	if(x == 0.0) {
		return 1.0;
	}
	else {
		return sin(PI*x)/(PI*x);
	}
}

float L(float x) {
	if(abs(x) > float(SUPPORT_SIZE)) {
		return 0.0;
	}
	return sinc(x)*sinc(x/(float(SUPPORT_SIZE)));
}

float L2(vec2 v) {
	return L(v.x)*L(v.y);
}

vec4 textureLanczos(sampler2D stamp, vec2 uv) {
	if(uv.x < 0. || uv.y < 0. || uv.x > 1.0 || uv.y > 1.0) {
		return vec4(0);
	}
	vec2 texSize = vec2(textureSize(stamp, 0));
	vec4 c = vec4(0);
	float weight = 0.0;

	vec2 coord = uv*texSize;
	vec2 xy = floor(coord) + 0.5;

	for(int i = -SUPPORT_SIZE; i <= SUPPORT_SIZE; i++) {
		for(int j = -SUPPORT_SIZE; j <= SUPPORT_SIZE; j++) {
			vec2 texuv = ivec2(i, j) + xy;

			float w = L2(texuv - coord);
			c += w*texture(stamp, texuv/texSize);
			weight += w;
		}
	}
	return c/weight;
}

vec3 source_position(vec2 coords) {
	// Coordinates of a flat plane
	vec4 ecoords = vec4(coords.x, 0, coords.y, 1);

	vec4[3] m = source.inverse_transform;
	mat4x3 matrix = mat4x3(
		vec3(m[0].x, m[1].x, m[2].x),
		vec3(m[0].y, m[1].y, m[2].y),
		vec3(m[0].z, m[1].z, m[2].z),
		vec3(m[0].w, m[1].w, m[2].w)
	);

	// Transformed to get the coordinates relative to the source
	vec3 relpos = matrix*ecoords;

	// Now we scale the result by the size of the image
	// Avoid division by zero
	uvec2 s2 = max(source.size, uvec2(16,16));
	// Scale x and z by the image size, flip y
	vec3 scale = vec3(s2.x, -1, s2.y);
	// Center the UVs
	return relpos / scale + vec3(0.5, 0, 0.5);
}

void main() {
	ivec2 coords = ivec2(source.corner + gl_GlobalInvocationID.xy);
	vec2 centered = vec2(coords) - vec2(target.size/2);
	vec3 pos = source_position(centered);

	vec2 color = textureBicubic(source_sampler, pos.xz).rg;
	float terrain_height = imageLoad(output_image, coords).r;
	float stamp_height = source.height_range.x + source.height_range.y*color.r;

	float result;
	if(source.blend_mode == 0){
		result = stamp_height + pos.y;
	}
	else if(source.blend_mode == 1) {
		result = terrain_height + stamp_height;
	}
	else if(source.blend_mode == 2) {
		result = min(terrain_height, stamp_height + pos.y);
	}
	else if(source.blend_mode == 3) {
		result = max(terrain_height, stamp_height + pos.y);
	}
	else if (source.blend_mode == 4) {
		result = 0.0;
	}
	else if(source.blend_mode == 5) {
		result = terrain_height - stamp_height;
	}

	imageStore(output_image, coords, vec4(mix(terrain_height, result, clamp(color.g, 0, 1)), vec3(0)));
}