#[compute]
#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer Target {
	// The size of the main heightmap
	uvec2 size;
} target;

layout(set = 0, binding = 1) uniform sampler2D source_sampler;
layout(r32f, set = 0, binding = 2) uniform restrict image2D output_image;

layout(push_constant, std430) uniform Source {
	// Inverse transform of the source object relative to the corner of the object
	vec4[3] inverse_transform;
	// The min and max heights to interpret from our source's 0-1
	vec2 height_range;
	// Size of the source/target in pixels
	uvec2 size;
	// The starting position of the shader in the destination's pixel-space
	uvec2 corner;
	uint blend_mode;
} source;

// from https://stackoverflow.com/questions/13501081/efficient-bicubic-filtering-code-in-glsl
// in turn from http://www.java-gaming.org/index.php?topic=35123.0
vec4 cubic(float v){
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	float w = 6.0 - x - y - z;
	return vec4(x, y, z, w) * (1.0/6.0);
}

vec4 textureBicubic(sampler2D stamp, vec2 uv){
	if(uv.x < 0. || uv.y < 0. || uv.x > 1.0 || uv.y > 1.0) {
		return vec4(0);
	}
	vec2 texSize = textureSize(stamp, 0);
	vec2 invTexSize = 1.0 / texSize;

	uv = uv * texSize - 0.5;


	vec2 fxy = fract(uv);
	uv -= fxy;

	vec4 xcubic = cubic(fxy.x);
	vec4 ycubic = cubic(fxy.y);

	vec4 c = uv.xxyy + vec2 (-0.5, +1.5).xyxy;

	vec4 s = vec4(xcubic.xz + xcubic.yw, ycubic.xz + ycubic.yw);
	vec4 offset = c + vec4 (xcubic.yw, ycubic.yw) / s;

	offset *= invTexSize.xxyy;

	vec4 sample0 = texture(stamp, offset.xz);
	vec4 sample1 = texture(stamp, offset.yz);
	vec4 sample2 = texture(stamp, offset.xw);
	vec4 sample3 = texture(stamp, offset.yw);

	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);

	return mix(
		mix(sample3, sample2, sx), mix(sample1, sample0, sx)
	, sy);
}


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

	vec2 color = textureBicubic(source_sampler, pos.xz).rg;
	float terrain_height = imageLoad(output_image, coords).r;
	float stamp_height = source.height_range.x + source.height_range.y*color.r;

	float result;
	if(source.blend_mode == 0){
		result = stamp_height + pos.y;
	}
	else if(source.blend_mode == 1) {
		result = terrain_height + stamp_height;
	}
	else if(source.blend_mode == 2) {
		result = min(terrain_height, stamp_height + pos.y);
	}
	else if(source.blend_mode == 3) {
		result = max(terrain_height, stamp_height + pos.y);
	}
	else if (source.blend_mode == 4) {
		result = 0.0;
	}
	else if(source.blend_mode == 5) {
		result = terrain_height - stamp_height;
	}

	imageStore(output_image, coords, vec4(mix(terrain_height, result, clamp(color.g, 0, 1)), vec3(0)));
}