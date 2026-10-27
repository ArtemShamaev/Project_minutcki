shader_type spatial;
render_mode unshaded, depth_draw_always, shadows_disabled;
uniform vec4 color : source_color = vec4(0.3, 0.9, 0.4, 0.45);
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	ALBEDO = color.rgb * (0.6 + rim);
	ALPHA = color.a;
}
