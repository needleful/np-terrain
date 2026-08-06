#[compute]
#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r32f, set = 0, binding = 0) uniform restrict image2D opacity;

layout(push_constant, std430) uniform Line {
	vec2 start, end;
	vec4 color;
	float radius, attenuation;

	vec4 color2;
	float radius2, attenuation2;

	uvec2 result_size;
} line;


// Stolen from https://stackoverflow.com/questions/849211/shortest-distance-between-a-point-and-a-line-segment

float distance_from_line(vec2 coords, vec2 start, vec2 end) {
	vec2 relative_end = end - start;
	vec2 relative_point = vec2(coords) - start;

	if (length(relative_end) == 0) {
		return length(relative_point);
	}

	float lsq = dot(relative_end, relative_end);
	float D = clamp(dot(relative_end, relative_point)/lsq, 0., 1.);
	vec2 proj = D*relative_end;
	return length(relative_point - proj);
}

#define PI 3.141592653589793
#define HPI 1.5707963267948966

float get_weight2(float distance) {
	// -pi/2 to pi/2
	float ndist = distance/max(line.radius, 0.01);
	float x = PI*pow(
		clamp(1.0 - ndist, 0.0, 1.0),
		line.attenuation
	) - HPI;
	// Half-sine wave for smooth curves
	return (sin(x) + 1.0)/2.0;
}

float get_weight(float distance) {
	return clamp(1.0 - distance/max(line.radius, 0.01), 0, 1);
}

void main() {
	ivec2 coords = ivec2(gl_GlobalInvocationID.xy);
	float distance = distance_from_line(coords, line.start, line.end);

	float factor = line.color.a*get_weight(distance);
	float start_factor = line.color.a*get_weight(length(coords-line.start));
	float old = max(imageLoad(opacity, coords).r - start_factor, 0);
	
	imageStore(
		opacity, coords, 
		vec4(clamp(old + factor, 0, 1))
	);
}