shader_type spatial;
render_mode world_vertex_coords;

uniform sampler2D holes;
uniform sampler2D attributes;
uniform sampler2D dither: source_color, filter_linear_mipmap;
uniform float dither_uv_scale = 1.0;

#include "heightmap.gdshaderinc"

void fragment() {
	if(texture(holes, terrain_uv).r > 0.2) {
		discard;
	}
	//ALBEDO = NORMAL;
	float min_alpha = 0.99 - texture(dither, world_pos.xz*dither_uv_scale).r;
	vec4 c = texture(attributes, terrain_uv);
	if(COLOR.a*c.a < min_alpha){
		discard;
	}
	ALBEDO = (color* COLOR * c).rgb;
}