shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform vec3 deep : source_color = vec3(0.07, 0.3, 0.5);
uniform vec3 shallow : source_color = vec3(0.25, 0.62, 0.72);
uniform sampler2D pol_tex : filter_linear, repeat_disable;
// water simulation: R = surface height (very low when dry), G = depth, B/A = flow velocity
uniform sampler2D sim_tex : filter_nearest, repeat_disable;
uniform bool use_sim = false;
uniform float map_n = 120.0;
global uniform float snow;
varying vec3 wpos;
varying vec2 flow;
varying float wdepth;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow = vec2(0.0);
	wdepth = 2.0;
	if (use_sim) {
		// a mesh vertex sits on a tile corner: average the wet tiles around it
		ivec2 c = ivec2(round(wpos.xz));
		int nn = int(map_n);
		float s = 0.0;
		float dsum = 0.0;
		vec2 v = vec2(0.0);
		float cnt = 0.0;
		for (int k = 0; k < 4; k++) {
			ivec2 t = clamp(c - ivec2(1 - (k & 1), 1 - (k >> 1)), ivec2(0), ivec2(nn - 1));
			vec4 d = texelFetch(sim_tex, t, 0);
			if (d.g > 0.0) {
				s += d.r;
				dsum += d.g;
				v += d.ba;
				cnt += 1.0;
			}
		}
		if (cnt > 0.0) {
			VERTEX.y = s / cnt - MODEL_MATRIX[3].y;
			flow = v / cnt;
			wdepth = dsum / cnt;
		} else {
			// just past the shore: continue the surface slightly lower so the ground cuts a smooth shoreline
			for (int k = 0; k < 16; k++) {
				ivec2 t = clamp(c + ivec2(k % 4 - 2, k / 4 - 2), ivec2(0), ivec2(nn - 1));
				vec4 d = texelFetch(sim_tex, t, 0);
				if (d.g > 0.0) {
					s += d.r;
					cnt += 1.0;
				}
			}
			if (cnt > 0.0) {
				VERTEX.y = s / cnt - 0.04 - MODEL_MATRIX[3].y;
				wdepth = 0.02;
			} else {
				VERTEX.y = -6.0 - MODEL_MATRIX[3].y;
				wdepth = 0.0;
			}
		}
		wpos.y = VERTEX.y + MODEL_MATRIX[3].y;
	}
}

void fragment() {
	// flow map: two noise layers advected along the current, cross-faded to hide resets
	vec2 fl = flow * 9.0;
	float fl_len = length(fl);
	if (fl_len > 1.6) fl *= 1.6 / fl_len;
	float ph0 = fract(TIME * 0.22);
	float ph1 = fract(TIME * 0.22 + 0.5);
	float wgt = abs(1.0 - 2.0 * ph0);
	vec2 base = wpos.xz * 0.12;
	float a0 = texture(noise_tex, base - fl * ph0 + vec2(TIME * 0.02, TIME * 0.013)).r;
	float a1 = texture(noise_tex, base - fl * ph1 + vec2(0.37, 0.71) + vec2(TIME * 0.02, TIME * 0.013)).r;
	float a = mix(a1, a0, wgt);
	vec2 uv2 = wpos.xz * 0.19 - vec2(TIME * 0.017, -TIME * 0.021);
	float b = texture(noise_tex, uv2 - fl * 0.6 * ph0).r;
	// depth below the surface for shore foam / shallow tint
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	float depth_diff = clamp(-vpos.z - (-VERTEX.z), 0.0, 10.0);
	float shore = 1.0 - smoothstep(0.0, 0.6, depth_diff);
	shore = max(shore, 1.0 - smoothstep(0.0, 0.12, wdepth));
	vec3 col = mix(deep, shallow, clamp(a * b * 1.4 + shore * 0.6, 0.0, 1.0));
	// white water where the current is fast
	float rapid = smoothstep(0.05, 0.16, length(flow)) * smoothstep(0.55, 0.85, a);
	float foam = smoothstep(0.55, 1.0, shore + (a - 0.5) * 0.6) * 0.8;
	foam = max(foam, rapid * 0.7);
	col = mix(col, vec3(0.95, 0.97, 1.0), foam);
	vec2 puv = wpos.xz / map_n;
	float pol = (puv.x < 0.0 || puv.y < 0.0 || puv.x > 1.0 || puv.y > 1.0) ? 0.0 : texture(pol_tex, puv).r;
	pol = smoothstep(0.05, 0.8, pol) * (0.85 + (a - 0.5) * 0.4);
	col = mix(col, mix(vec3(0.33, 0.27, 0.13), vec3(0.28, 0.33, 0.12), b), clamp(pol, 0.0, 0.9));
	foam *= 1.0 - pol * 0.5;
	col = mix(col, vec3(0.8, 0.88, 0.95), snow * 0.35);
	ALBEDO = col;
	ROUGHNESS = mix(0.06, 0.5, foam);
	METALLIC = 0.1;
	SPECULAR = 0.6;
	vec3 nmap = normalize(vec3((a - 0.5) * 0.6, 1.0, (b - 0.5) * 0.6));
	NORMAL = normalize((VIEW_MATRIX * vec4(nmap, 0.0)).xyz);
	ALPHA = clamp(0.75 + depth_diff * 0.15, 0.75, 0.95) * smoothstep(0.0, 0.03, wdepth);
}
