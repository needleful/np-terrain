#[compute]
// Convert from RGBA to the internal RG for heightmaps, where green is the alpha
#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform restrict readonly image2D rgba;
layout(rg32f, set = 0, binding = 1) uniform restrict writeonly image2D rg;

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	imageStore(rg, c, vec4(imageLoad(rgba, c).ra, 0, 0));
}