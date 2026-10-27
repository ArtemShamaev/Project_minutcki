// Sky: colour gradient, sun with a soft halo, layered clouds lit by the sun,
// and at night stars and the moon (the directional light becomes moonlight).
// No TIME here: the clouds drift through cloud_offset, set rarely from the game,
// so the sky radiance isn't recomputed every frame.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.32, 0.52, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.7, 0.8, 0.9);
uniform vec3 ground_color : source_color = vec3(0.35, 0.4, 0.42);
uniform float day_k = 1.0;            // 0 night .. 1 day
uniform float cover = 0.45;           // cloud cover 0..1
uniform float rain = 0.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float fbm(vec2 uv) {
	float v = texture(noise_tex, uv).r * 0.55;
	v += texture(noise_tex, uv * 2.3 + vec2(0.17, 0.41)).r * 0.3;
	v += texture(noise_tex, uv * 5.1 + vec2(0.63, 0.29)).r * 0.15;
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.55));
	} else {
		col = mix(horizon_color, ground_color, clamp(-h * 5.0, 0.0, 1.0));
	}
	vec3 ld = LIGHT0_DIRECTION;
	float sd = max(dot(d, ld), 0.0);
	vec3 lc = LIGHT0_COLOR;
	// sun halo and warm scattering near the horizon at sunrise / sunset
	float low = 1.0 - smoothstep(0.0, 0.45, ld.y);
	col += lc * (pow(sd, 6.0) * 0.18 + pow(sd, 48.0) * 0.45) * day_k * (1.0 - rain * 0.7);
	col += vec3(1.0, 0.45, 0.2) * pow(sd, 3.0) * low * 0.35 * day_k * smoothstep(-0.05, 0.25, h + 0.1);
	// disc: sun by day, moon by night
	float disc = smoothstep(0.99955, 0.99975, dot(d, ld));
	vec3 moon = vec3(0.85, 0.88, 0.95) * (0.8 + 0.2 * texture(noise_tex, d.xy * 40.0).r);
	col += mix(moon * 1.2, lc * 12.0, day_k) * disc * (1.0 - rain);
	// stars
	if (h > 0.0 && day_k < 0.6) {
		vec3 g = d * 220.0;
		vec3 cell = floor(g);
		float st = hash(cell);
		vec3 sp = vec3(hash(cell + 3.0), hash(cell + 5.0), hash(cell + 9.0)) * 0.6 + 0.2;
		float r = length(fract(g) - sp);
		float star = step(0.994, st) * smoothstep(0.16, 0.0, r) * (0.5 + 0.8 * hash(cell + 7.0));
		col += vec3(star) * (1.0 - day_k / 0.6) * smoothstep(0.0, 0.15, h) * (1.0 - rain);
	}
	// clouds: a flat layer seen in perspective
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 0.09 + cloud_offset;
		float n = fbm(uv);
		float lo = 0.66 - cover * 0.32;
		float c = smoothstep(lo, lo + 0.13, n);
		c *= smoothstep(0.0, 0.12, h);
		// lit top / grey bottom; sunset tints them
		float lit = clamp(0.55 + 0.6 * (fbm(uv + ld.xz * 0.02) - n) + sd * 0.4, 0.0, 1.2);
		vec3 bright = mix(vec3(1.0), lc, 0.55) * mix(0.07, 1.05, day_k * day_k);
		vec3 dark = mix(vec3(0.015, 0.02, 0.04), vec3(0.55, 0.58, 0.64), day_k);
		vec3 cc = mix(dark, bright, lit);
		cc = mix(cc, vec3(0.42, 0.44, 0.48) * mix(0.15, 1.0, day_k), rain * 0.8);
		col = mix(col, cc, c * 0.92);
	}
	COLOR = col;
}
