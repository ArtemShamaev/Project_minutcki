// Window glass of untextured (flat-colour) building models: glows warmly at night.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

global uniform float night;
uniform vec4 albedo : source_color = vec4(0.74, 0.89, 1.0, 1.0);
instance uniform float lit_seed = 0.0;
varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	// not every window is lit: hash of the building seed and the window position
	vec3 cell = floor(lpos * vec3(6.0, 9.0, 6.0));
	float h = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719)) + lit_seed * 91.7) * 43758.5453);
	float lit = step(0.35, h);
	ALBEDO = mix(albedo.rgb, albedo.rgb * 0.35, night * 0.8);
	ROUGHNESS = 0.15;
	METALLIC = 0.25;
	EMISSION = vec3(1.0, 0.72, 0.38) * lit * night * (0.9 + 0.5 * h);
}
