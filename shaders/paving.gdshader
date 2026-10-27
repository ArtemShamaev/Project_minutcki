// Paved pedestrian paths: stone pavers laid in a running bond pattern.
shader_type spatial;
render_mode diffuse_burley;
global uniform float snow;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = wpos.xz * vec2(14.0, 9.0);
	p.x += step(1.0, mod(floor(p.y), 2.0)) * 0.5;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float joint = smoothstep(0.0, 0.07, f.x) * smoothstep(1.0, 0.93, f.x) * smoothstep(0.0, 0.1, f.y) * smoothstep(1.0, 0.9, f.y);
	float v = 0.9 + 0.2 * hash(cell);
	vec3 col = COLOR.rgb * v * mix(0.72, 1.0, joint);
	col = mix(col, vec3(0.92, 0.94, 0.97), snow * 0.7);
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
