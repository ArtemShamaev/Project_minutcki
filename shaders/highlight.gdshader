shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(0.25, 0.45, 0.7, 1.0);
void fragment() {
	float p = 0.6 + 0.4 * sin(TIME * 5.0);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = color.rgb * (0.35 + rim) * p;
}
