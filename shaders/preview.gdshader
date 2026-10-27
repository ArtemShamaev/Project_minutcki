shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * (0.75 + 0.25 * sin(TIME * 6.0));
}
