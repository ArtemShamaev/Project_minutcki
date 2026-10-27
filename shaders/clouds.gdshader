// High cloud layer, only visible when the camera is far away.
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
global uniform float clouds;
global uniform float night;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n = texture(noise_tex, wpos.xz * 0.008 + vec2(TIME * 0.004, TIME * 0.0025)).r;
	float n2 = texture(noise_tex, wpos.xz * 0.03 + vec2(TIME * 0.006, 0.0)).r;
	float c = smoothstep(0.5, 0.75, n * 0.8 + n2 * 0.3);
	float cam = smoothstep(45.0, 95.0, CAMERA_POSITION_WORLD.y);
	ALBEDO = mix(vec3(1.0), vec3(0.25, 0.28, 0.35), night * 0.8) * (0.85 + n2 * 0.2);
	ALPHA = c * cam * 0.6 * clouds;
}
