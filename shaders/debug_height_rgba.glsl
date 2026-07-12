#[compute]
#version 460

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform restrict readonly image2D rgba;
layout(rgba32f, set = 0, binding = 1) uniform restrict writeonly image2D debug_out;

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	vec4 data = imageLoad(rgba, c);
	vec4 result_color = data.rgba;
	if(data.a > 1.0 || data.a < 0.0) {
		result_color.a = 1.0;
		result_color.b = 1.0;
	}
	if(data.r < -1000) {
		result_color.r = 1.0;
		result_color.b = 0.4;
		result_color.a = 1.0;
	}
	imageStore(debug_out, c, data);
}