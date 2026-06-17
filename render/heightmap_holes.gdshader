shader_type spatial;
render_mode world_vertex_coords;

uniform sampler2D holes;

#include "heightmap.gdshaderinc"

void fragment() {
	if(texture(holes, terrain_uv).r > 0.2) {
		discard;
	}
	//ALBEDO = NORMAL;
	ALBEDO = (COLOR * color).rgb;
}