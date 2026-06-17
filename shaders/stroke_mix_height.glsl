#[compute]
#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D stroke_opacity;
layout(rg32f, set = 0, binding = 1) uniform restrict readonly image2D source;
layout(rg32f, set = 0, binding = 2) uniform restrict writeonly image2D destination;

layout(push_constant, std430) uniform Stroke {
	vec4 color;
	uint blend_mode;
} stroke;

void main() {
	ivec2 coords = ivec2(gl_GlobalInvocationID.xy);
	vec4 result;
	vec4 original = imageLoad(source, coords);

	if(stroke.blend_mode == 0){
		result = stroke.color;
	}
	else if (stroke.blend_mode == 1) {
		result = original + stroke.color;
	}
	else if(stroke.blend_mode == 2) {
		result = min(original, stroke.color);
	}
	else if(stroke.blend_mode == 3) {
		result = max(original, stroke.color);
	}
	else if(stroke.blend_mode == 4) {
		result = vec4(original.r, vec3(0));
	}
	else if(stroke.blend_mode == 5) {
		result = original - stroke.color;
	}

	imageStore(
		destination, coords,
		mix(
			original,
			result,
			imageLoad(stroke_opacity, coords).r
		)
	);
}