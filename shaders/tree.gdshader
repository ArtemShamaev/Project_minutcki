// Kenney tree with wind sway and snow; the cyan toon foliage is repainted in natural greens
// (every tree gets its own shade: some darker, some yellowish, conifers bluer).
shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform float realism = 1.0;
global uniform float snow;
global uniform float wind;
varying float up;
varying float tvar;
varying float th;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sway = sin(TIME * 1.7 + w.x * 0.7 + w.z * 0.4) * 0.5 + sin(TIME * 2.9 + w.z) * 0.25;
	VERTEX.x += sway * VERTEX.y * VERTEX.y * 0.35 * (0.4 + wind);
	VERTEX.z += sway * VERTEX.y * VERTEX.y * 0.2 * (0.4 + wind);
	up = (MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
	tvar = fract(sin(dot(w.xz, vec2(12.9898, 78.233))) * 43758.5453);
	th = VERTEX.y;
}
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 s = pow(c, vec3(1.0 / 2.2));
	float leaf = step(s.r + 0.05, s.g);
	float l = clamp(s.g * 1.1, 0.0, 1.0);
	vec3 dark = mix(vec3(0.045, 0.085, 0.03), vec3(0.03, 0.07, 0.045), step(0.7, tvar));
	vec3 light = mix(vec3(0.20, 0.30, 0.08), vec3(0.28, 0.30, 0.07), step(0.85, tvar));
	vec3 g = mix(dark, light, l * l) * (0.85 + 0.3 * tvar);
	// lighter tips at the top of the crown
	g *= 0.9 + 0.25 * smoothstep(0.0, 1.5, th);
	vec3 bark = vec3(dot(c, vec3(0.333))) * vec3(0.55, 0.42, 0.32);
	vec3 real = mix(bark, g, leaf);
	vec3 col = mix(c, real, realism);
	float sn = snow * smoothstep(0.2, 0.7, up);
	ALBEDO = mix(col, vec3(0.92, 0.95, 0.98), sn * 0.85);
	ROUGHNESS = 0.9;
}
