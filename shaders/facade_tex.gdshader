// Textured building facades (style packs): albedo texture plus a window mask that lights
// up at night. Each window cell gets its own random on/off state from the building seed.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D emit_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 cells = vec2(2.0, 1.0);   // window cells per UV unit (hash granularity)
uniform float always_lit = 0.0;        // signs: lit every night
uniform float rough = 0.85;
global uniform float night;
global uniform float snow;
instance uniform float lit_seed = 0.0;
varying vec3 wnormal;

void vertex() {
	wnormal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 e = texture(emit_tex, UV).rgb;
	vec2 cell = floor(UV * cells);
	float h = fract(sin(dot(cell, vec2(12.9898, 78.233)) + lit_seed * 91.7) * 43758.5453);
	float lit = max(step(0.38, h), always_lit);
	// roofs get a little snow in winter
	c = mix(c, vec3(0.93, 0.95, 0.98), snow * smoothstep(0.6, 0.9, normalize(wnormal).y) * 0.8);
	// lit windows look a bit darker by day (glass), warm and bright at night
	ALBEDO = c * (1.0 - 0.6 * night * step(0.05, e.r));
	ROUGHNESS = mix(rough, 0.2, step(0.05, e.r));
	EMISSION = e * lit * night * (0.8 + 0.6 * h) * 1.4;
}
