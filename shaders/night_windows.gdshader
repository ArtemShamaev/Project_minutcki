// Overlay pass for Kenney models: glowing windows at night and snow on roofs.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;

global uniform float night;
global uniform float snow;
uniform sampler2D tex : source_color, filter_nearest;
instance uniform float lit_seed = 0.0;
varying float up;

void vertex() {
	up = (MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
}

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float win = smoothstep(0.10, 0.22, c.b - c.r) * step(0.45, c.b);
	float h = fract(sin(lit_seed * 91.7) * 43758.5);
	vec3 add = vec3(1.0, 0.72, 0.38) * win * night * (0.55 + 0.45 * h);
	float roof = smoothstep(0.7, 0.95, up) * snow;
	add += vec3(0.55, 0.57, 0.6) * roof * (1.0 - night * 0.6);
	ALBEDO = add;
}
