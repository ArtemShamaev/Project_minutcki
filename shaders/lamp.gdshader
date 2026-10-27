// Small light sources that glow at night (street lamps, car lights).
shader_type spatial;
render_mode unshaded, shadows_disabled;
global uniform float night;
uniform vec4 color : source_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform float day_level = 0.15;
void fragment() {
	float k = mix(day_level, 1.0, night);
	ALBEDO = color.rgb * k * 2.2;
}
