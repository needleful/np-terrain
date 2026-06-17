shader_type spatial;
render_mode world_vertex_coords;

#include "heightmap.gdshaderinc"

void fragment() {
	//ALBEDO = NORMAL;
	ALBEDO = (COLOR * color).rgb;
}