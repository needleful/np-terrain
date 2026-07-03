shader_type spatial;
render_mode world_vertex_coords;

#include "heightmap.gdshaderinc"

void fragment() {
	//ALBEDO = NORMAL;
	ROUGHNESS = 0.3;
	ALBEDO = (COLOR * color).rgb;
}