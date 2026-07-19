#[compute]
#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D stroke_opacity;
layout(rgba32f, set = 0, binding = 1) uniform restrict readonly image2D source;
layout(rgba32f, set = 0, binding = 2) uniform restrict writeonly image2D destination;

layout(push_constant, std430) uniform Stroke {
	vec4 color;
	uint blend_mode;
} stroke;

vec4 blur(ivec2 coords) {
	vec4 sum = vec4(0);
	ivec2 start = coords - ivec2(4);

	for(int x = 0; x < 9; x++) {
		for(int y = 0; y < 9; y++) {
			ivec2 uv = start + ivec2(x, y);
			sum += imageLoad(source, uv);
		}
	}

	return sum/81.0;
}

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
		result = vec4(original.rgb, 0);
	}
	else if(stroke.blend_mode == 5) {
		result = original - stroke.color;
	}
	else if(stroke.blend_mode == 6) {
		result = blur(coords);
		result.a = clamp(result.a, 0.0, 1.0);
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