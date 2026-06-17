#[compute]
#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D height;
layout(rg16f, set = 0, binding = 1) uniform restrict writeonly image2D normals;

float at(ivec2 coords) {
	return imageLoad(height, coords).r;
}

vec2 derive(ivec2 coords) {
	float here = at(coords);

	float next = at(coords + ivec2(1, 0));
	float prev = at(coords - ivec2(1, 0));
	float up   = at(coords + ivec2(0, 1));
	float down = at(coords - ivec2(0, 1));

	// float nextup = at(coords + vec2(1,1));
	// float prevdown = at(coords + vec2(1,1));
	// float nextdown = at(coords + vec2(1,-1));
	// float prevup = at(coords + vec2(1,-1));

	vec3 n = normalize(
		vec3(prev - here, 1.0, down - here)
		+ vec3(here - next, 1.0, here - up));
	return n.xz;
}

void main() {
	ivec2 coords = ivec2(gl_GlobalInvocationID.xy);
	imageStore(normals, coords, vec4(derive(coords), 0.0, 1.0));
}