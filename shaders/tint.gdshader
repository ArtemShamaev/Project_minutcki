// Multiplicative overlay used for abandoned / burnt buildings and highlight.
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.55, 0.5, 0.45, 1.0);
void fragment() {
	ALBEDO = tint.rgb;
}
