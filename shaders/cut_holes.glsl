#[compute]
#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer Target {
	// The size of the main heightmap
	uvec2 size;
} target;

layout(set = 0, binding = 1) uniform sampler2D source_sampler;
layout(r8, set = 0, binding = 2) uniform restrict image2D output_image;

layout(push_constant, std430) uniform Source {
	// Inverse transform of the source object relative to the corner of the object
	vec4[3] inverse_transform;
	// The min and max heights to interpret from our source's 0-1
	vec2 height_range;
	// Size of the source/target in pixels
	uvec2 size;
	// The starting position of the shader in the destination's pixel-space
	uvec2 corner;
} source;


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
	imageStore(output_image, coords, vec4(imageLoad(output_image, coords) + texture(source_sampler, pos.xz)));
}