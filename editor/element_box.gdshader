shader_type spatial;
render_mode blend_mix, unshaded, depth_test_disabled, depth_draw_never, cull_front;

uniform vec4 color : source_color;
uniform sampler2D depth: hint_depth_texture;
uniform float power: hint_range(1.0, 10.0) = 6.0;

void fragment() {
	float d = textureLod(depth, SCREEN_UV, 0.0).r;
	
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vec4 wpos = INV_VIEW_MATRIX*upos;
	vec3 pixel_position = (inverse(MODEL_MATRIX)*vec4(wpos.xyz / wpos.w, 1.0)).xyz;
	
	ALBEDO = color.rgb;
	vec2 bounded = abs(pixel_position.xz)*2.0;
	float in_bounds = float((bounded.x < 1.0) && (bounded.y < 1.0));
	ALPHA = color.a*in_bounds*(pow(bounded.x, power) + pow(bounded.y, power));
}