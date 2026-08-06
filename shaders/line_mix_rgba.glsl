#[compute]
#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform restrict image2D result;

layout(push_constant, std430) uniform Line {
	vec2 start, end;
	vec4 color;
	float radius, attenuation;

	vec4 color2;
	float radius2, attenuation2;

	uvec2 result_size;
} line;

// Derived from https://stackoverflow.com/questions/849211/shortest-distance-between-a-point-and-a-line-segment
vec2 distance_from_line(vec2 coords, vec2 start, vec2 end) {
	vec2 relative_end = end - start;
	vec2 relative_point = vec2(coords) - start;

	if (length(relative_end) == 0) {
		return vec2(length(relative_point), 0);
	}

	float lsq = dot(relative_end, relative_end);
	float D = clamp(dot(relative_end, relative_point)/lsq, 0., 1.);
	vec2 proj = D*relative_end;
	// Return the length from any point on the line, and a bound [0, 1] indicating which point along the line is closest
	return vec2(length(relative_point - proj), D);
}

#define PI 3.141592653589793
#define HPI 1.5707963267948966

float get_weight(float distance, float radius, float attenuation) {
	// -pi/2 to pi/2
	float x = PI*pow(
		clamp(1.0 - distance/max(radius, 0.01), 0.0, 1.0),
		attenuation
	) - HPI;
	// Half-sine wave for smooth curves
	return (sin(x) + 1.0)/2.0;
}

// float get_weight(float distance, float radius, float attenuation) {
// 	return clamp(1.0 - distance/max(radius, 0.01), 0, 1);
// }

void main() {
	ivec2 coords = ivec2(gl_GlobalInvocationID.xy);
	vec2 dm = distance_from_line(coords, line.start, line.end);
	float distance = dm.x;

	float radius = mix(line.radius, line.radius2, dm.y);
	float attenuation = mix(line.attenuation, line.attenuation2, dm.y);
	vec4 color = mix(line.color, line.color2, dm.y);
	float w = get_weight(distance, radius, attenuation);
	color.a *= w;

	vec4 old = imageLoad(result, coords);
	// Reduce alpha if the previous line segment ended nearby
	float wstart = old.a*max(sign(old.a),get_weight(length(coords - line.start), line.radius, 1.0));

	if(w > wstart) {
		imageStore(result, coords, color);
	}
}