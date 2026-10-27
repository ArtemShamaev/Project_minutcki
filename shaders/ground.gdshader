shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
// photo textures (Poly Haven, CC0): grass, rock, sand, dry ground
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grid_alpha = 0.0;
uniform float realism = 1.0;
global uniform float snow;
global uniform float clouds;
global uniform float wet;
varying vec3 wpos;
varying float up;
void vertex() {
	wpos = VERTEX;
	up = NORMAL.y;
}

// texture detail normalised around 1.0 so the palette colour stays in charge
vec3 detail(sampler2D t, vec2 uv, vec3 avg) {
	return texture(t, uv).rgb / avg;
}

void fragment() {
	float n1 = texture(noise_tex, wpos.xz * 0.035).r;
	float n2 = texture(noise_tex, wpos.xz * 0.21).r;
	float n3 = texture(noise_tex, wpos.xz * 0.9).r;
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	// what kind of ground this is, from the palette colour
	float sandy = smoothstep(0.08, 0.18, base.r - base.b) * smoothstep(0.25, 0.4, base.r);
	float steep = 1.0 - smoothstep(0.72, 0.9, up);
	// two scales of the photo texture break up repetition
	vec2 uv1 = wpos.xz * 0.23;
	vec2 uv2 = wpos.xz * 0.061 + vec2(0.37, 0.11);
	vec3 g = mix(detail(grass_tex, uv1, vec3(0.172, 0.123, 0.025)), detail(grass_tex, uv2, vec3(0.172, 0.123, 0.025)), 0.5);
	vec3 gd = detail(dirt_tex, wpos.xz * 0.17, vec3(0.21, 0.118, 0.053)) * vec3(1.15, 0.95, 0.75);
	g = mix(g, gd, smoothstep(0.55, 0.8, n1) * 0.35);
	vec3 r = detail(rock_tex, wpos.xz * 0.2, vec3(0.175, 0.122, 0.05)) * vec3(0.95, 0.95, 1.1);
	vec3 s = detail(sand_tex, wpos.xz * 0.3, vec3(0.288, 0.242, 0.199));
	vec3 tex = mix(g, s, sandy);
	tex = mix(tex, r, steep * 0.85);
	// keep the photo's colour variation, but not its exact hue
	float tl = dot(tex, vec3(0.333));
	tex = mix(vec3(tl), tex, 0.35);
	tex = clamp(tex, vec3(0.0), vec3(2.2));
	vec3 col = base * (0.84 + 0.2 * n1 + 0.08 * n2);
	col = mix(col * (0.9 + 0.1 * n3), col * tex, realism);
	// rocky texture on steep slopes
	col = mix(col, col * (0.75 + 0.35 * n3), steep * 0.6 * (1.0 - realism));
	// snow on flat-ish surfaces
	float sn = snow * smoothstep(0.55, 0.85, up) * smoothstep(0.25, 0.55, n2 * 0.6 + snow * 0.7);
	col = mix(col, vec3(0.93, 0.95, 0.98), clamp(sn, 0.0, 1.0));
	// subtle grid lines
	vec2 gg = abs(fract(wpos.xz) - 0.5);
	float line = smoothstep(0.47, 0.5, max(gg.x, gg.y));
	col = mix(col, col * 0.7, line * grid_alpha);
	// moving cloud shadows
	float c = texture(noise_tex, wpos.xz * 0.008 + vec2(TIME * 0.004, TIME * 0.0025)).r;
	col *= 1.0 - smoothstep(0.5, 0.75, c) * 0.28 * clouds;
	col *= 1.0 - wet * 0.12 * (1.0 - snow);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.95, 0.6, sn), 0.7, wet * 0.5);
}
