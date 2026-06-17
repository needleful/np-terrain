#[compute]
#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r8ui, set = 0, binding = 0) uniform restrict writeonly uimage2D data;

void main() {
	imageStore(data, ivec2(gl_GlobalInvocationID.xy), uvec4(0));
}
