// Draws zone cells, the zoning-allowed area (zone tool) and district borders.
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://shaders/terrain.gdshaderinc"
uniform sampler2D zone_tex : filter_nearest;
uniform sampler2D district_tex : filter_nearest;
uniform float n = 120.0;
uniform float show_area = 0.0;
uniform float district_fill = 0.0;
uniform sampler2D owned_tex : filter_nearest;
uniform float land_n = 5.0;
uniform float land_view = 0.0;   // 1 while the land purchase window is open
global uniform float night;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += terrain_h(w.xz);
}

bool differs(vec4 a, vec4 b) {
	return abs(a.a - b.a) > 0.1 || distance(a.rgb, b.rgb) > 0.02;
}

void fragment() {
	vec2 cellf = UV * n;
	vec4 z = texture(zone_tex, UV);
	vec2 f = fract(cellf);
	vec2 fe = abs(f - 0.5);
	float edge = smoothstep(0.36, 0.42, max(fe.x, fe.y));
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (z.a > 0.6) {
		col = z.rgb * (1.0 - night * 0.7);
		// zoned empty land is only shown clearly while zoning (as in C:S)
		a = mix(0.22, 0.75, edge) * (0.25 + 0.75 * show_area);
	} else if (z.a > 0.2) {
		col = vec3(1.0);
		a = edge * 0.35 * show_area;
	}
	vec4 d = texture(district_tex, UV);
	if (d.a > 0.5) {
		float t = 1.0 / n;
		float bw = 0.12;
		float border = 0.0;
		if (f.x < bw && differs(d, texture(district_tex, UV - vec2(t, 0.0)))) border = 1.0;
		if (f.x > 1.0 - bw && differs(d, texture(district_tex, UV + vec2(t, 0.0)))) border = 1.0;
		if (f.y < bw && differs(d, texture(district_tex, UV - vec2(0.0, t)))) border = 1.0;
		if (f.y > 1.0 - bw && differs(d, texture(district_tex, UV + vec2(0.0, t)))) border = 1.0;
		if (border > 0.5) {
			col = d.rgb;
			a = 0.85;
		} else if (district_fill > 0.5) {
			col = mix(col, d.rgb, 0.6);
			a = max(a, 0.3);
		}
	}
	// land not owned by the city is shaded; plot borders are drawn on the edge of the city's land
	vec2 lp = UV * land_n;
	float own = texture(owned_tex, UV).r;
	if (own < 0.5) {
		col = mix(col, vec3(0.05, 0.06, 0.08), 0.85);
		a = max(a, 0.22 + 0.2 * land_view);
	}
	vec2 lf = fract(lp);
	float lb = max(step(max(abs(lf.x - 0.5), abs(lf.y - 0.5)), 0.49) < 0.5 ? 1.0 : 0.0, 0.0);
	float near_own = max(max(texture(owned_tex, UV + vec2(0.004, 0.0)).r, texture(owned_tex, UV - vec2(0.004, 0.0)).r), max(texture(owned_tex, UV + vec2(0.0, 0.004)).r, texture(owned_tex, UV - vec2(0.0, 0.004)).r));
	float far_own = min(min(texture(owned_tex, UV + vec2(0.004, 0.0)).r, texture(owned_tex, UV - vec2(0.004, 0.0)).r), min(texture(owned_tex, UV + vec2(0.0, 0.004)).r, texture(owned_tex, UV - vec2(0.0, 0.004)).r));
	if (near_own > 0.5 && far_own < 0.5) {
		col = vec3(1.0, 0.85, 0.35);
		a = 0.9;
	} else if (land_view > 0.5 && lb > 0.5) {
		col = vec3(1.0);
		a = 0.6;
	}
	if (a < 0.01) discard;
	ALBEDO = col;
	ALPHA = a;
}
