#[compute]
#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D heightmap;
layout(r8, set = 0, binding = 1) uniform restrict readonly image2D holes;
layout(r32f, set = 0, binding = 2) uniform restrict writeonly image2D result;
layout(push_constant, std430) uniform Constant {
	float nan;
	float inverse_scale;
} constant;

void main() {
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
	float h = imageLoad(holes, uv).r;
	if(h > 0.1) {
		imageStore(result, uv, vec4(constant.nan));
	}
	else {
		imageStore(result, uv, imageLoad(heightmap, uv)*constant.inverse_scale);
	}
}
