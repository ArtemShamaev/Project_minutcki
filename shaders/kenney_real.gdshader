// Kenney colormap models with a more realistic finish: muted colours, fine surface grain,
// slightly glossy windows (bluish pixels), rough walls.
shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform sampler2D grain_tex : filter_linear, repeat_enable;
uniform float mute = 0.35;
global uniform float snow;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 m = mix(c, vec3(l), mute);
	// triplanar grain so flat colours read as plaster, brick or concrete
	vec3 bw = abs(wn) / (abs(wn.x) + abs(wn.y) + abs(wn.z));
	float g = texture(grain_tex, wp.zy * 2.5).r * bw.x + texture(grain_tex, wp.xz * 2.5).r * bw.y + texture(grain_tex, wp.xy * 2.5).r * bw.z;
	m *= 0.9 + 0.2 * g;
	float glass = step(c.r + 0.08, c.b) * step(0.25, l);
	m = mix(m, vec3(0.93, 0.95, 0.98), snow * smoothstep(0.6, 0.9, wn.y) * 0.8);
	ALBEDO = m;
	ROUGHNESS = mix(0.82, 0.15, glass);
	METALLIC = glass * 0.2;
}
