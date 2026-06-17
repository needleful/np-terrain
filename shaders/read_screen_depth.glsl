#[compute]
#version 460
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;


layout(set = 0, binding = 0, std430) restrict writeonly buffer Output {
	float depth;
} outvars;

layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D depth_texture;

layout(push_constant, std430) uniform Input {
	ivec2 screen_coordinates;
} invars;

void main() {
	outvars.depth = 1.0 - imageLoad(depth_texture, invars.screen_coordinates).r;
}