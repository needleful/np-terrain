shader_type spatial;
render_mode world_vertex_coords;

uniform sampler2D holes;
uniform sampler2D topology: repeat_enable, filter_linear;
uniform float repeat_height = 16.0;

uniform sampler2D heightmap: repeat_disable;
uniform sampler2D normals: repeat_disable;
uniform vec2 size;
uniform vec4 color: source_color;
uniform float inverse_scale = 1.0;

varying vec2 terrain_uv;
varying float height;

void vertex() {
	ROUGHNESS = 0.3;
	vec2 fuv = vec2(VERTEX.xz*inverse_scale + size/2.0);
	ivec2 uv = ivec2(fuv);
	terrain_uv = fuv/vec2(textureSize(heightmap, 0));
	height = texelFetch(heightmap, uv, 0).r;
	VERTEX.y += height;
	vec4 n = texelFetch(normals, uv, 0);
	float b = 1.0 - sqrt(n.x*n.x + n.y*n.y);
	NORMAL = normalize(vec3(n.x, b, n.y));
}

void fragment() {
	if(texture(holes, terrain_uv).r > 0.2) {
		discard;
	}
	//ALBEDO = NORMAL;
	ALBEDO = (COLOR * color).rgb*texture(topology, vec2(0.5, height/repeat_height)).rgb;
}