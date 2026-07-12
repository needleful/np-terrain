#[compute]
#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform restrict image2D result;

layout(push_constant, std430) uniform Line {
	vec4 color;
	vec2 start, end;
	float radius, attenuation;
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

float get_weight(float distance, float radius, float attenuation) {
	return pow(
		clamp(1.0 - distance/max(radius, 0.01), 0.0, 1.0),
		attenuation
	);
}

void main() {
	ivec2 coords = ivec2(gl_GlobalInvocationID.xy);
	float distance = distance_from_line(coords, line.start, line.end);

	float factor = line.color.a*get_weight(distance, line.radius, line.attenuation);
	float start_factor = line.color.a*get_weight(length(coords-line.start), line.radius, line.attenuation);

	vec4 old = imageLoad(result, coords);
	float alpha_old = max(old.a - start_factor, 0);

	if(factor > 0) {
		float f = 0.0;
		float c_factor = old.a + factor;
		if(c_factor > 0) {
			f = factor/c_factor;
		}
		vec3 out_color = mix(old.rgb, line.color.rgb, clamp(f, 0, 1));
		imageStore(
			result, coords, 
			vec4(out_color, clamp(alpha_old + factor, 0, 1))
		);
	}
	
}