

uniform sampler2D heightmap: repeat_disable;
uniform sampler2D normals: repeat_disable;
uniform vec2 size;
uniform vec4 color: source_color;
uniform float inverse_scale = 1.0;

varying vec2 terrain_uv;
varying vec3 world_pos;

void vertex() {
	ROUGHNESS = 0.3;
	vec2 fuv = vec2(VERTEX.xz*inverse_scale + size/2.0);
	ivec2 uv = ivec2(fuv);
	terrain_uv = fuv/vec2(textureSize(heightmap, 0));
	world_pos = vec3(VERTEX.x, texelFetch(heightmap, uv, 0).r, VERTEX.z);
	VERTEX.y += world_pos.y;
	vec4 n = texelFetch(normals, uv, 0);
	float b = 1.0 - sqrt(n.x*n.x + n.y*n.y);
	NORMAL = normalize(vec3(n.x, b, n.y));
}