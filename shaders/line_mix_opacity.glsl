#[compute]
#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r32f, set = 0, binding = 0) uniform restrict image2D opacity;

layout(push_constant, std430) uniform Line {
	vec4 color;
	vec2 start, end;
	float radius, attenuation;
	uvec2 opacity_size;
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

float get_weight(float distance) {
	return pow(
		clamp(1.0 - distance/max(line.radius, 0.01), 0.0, 1.0),
		line.attenuation
	);
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