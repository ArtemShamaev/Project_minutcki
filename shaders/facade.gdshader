// Procedural facade with window grid. UV is in world units (x along wall, y height).
// UV2.x > 0.5 marks roof faces.
shader_type spatial;
global uniform float night;
global uniform float snow;
instance uniform vec4 wall_color : source_color = vec4(0.85, 0.82, 0.76, 1.0);
instance uniform vec4 accent_color : source_color = vec4(0.3, 0.3, 0.35, 1.0);
instance uniform float style = 0.0;   // 0 apartments, 1 glass office, 2 service building
instance uniform float seed = 0.0;
instance uniform float dark = 0.0;    // abandoned

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed * 3.17) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	vec3 col;
	float win = 0.0;
	vec2 cell_id;
	if (UV2.x > 0.5) {
		col = mix(accent_color.rgb * 0.9, vec3(0.92, 0.94, 0.97), snow * 0.85);
		ROUGHNESS = 0.9;
	} else {
		vec2 cell;
		if (style > 0.5 && style < 1.5) cell = vec2(0.11, 0.14);
		else if (style > 1.5) cell = vec2(0.2, 0.2);
		else cell = vec2(0.16, 0.2);
		cell_id = floor(uv / cell);
		vec2 f = fract(uv / cell);
		if (style > 0.5 && style < 1.5) {
			win = step(0.05, f.x) * step(0.1, f.y) * step(f.y, 0.94);
		} else {
			win = step(0.22, f.x) * step(f.x, 0.78) * step(0.25, f.y) * step(f.y, 0.82);
		}
		if (uv.y < 0.06) win = 0.0;
		// floor slab lines
		float slab = step(fract(uv.y / cell.y), 0.07);
		vec3 wall = mix(wall_color.rgb, accent_color.rgb, slab * (style > 0.5 && style < 1.5 ? 1.0 : 0.35));
		vec3 glass = (style > 0.5 && style < 1.5) ? vec3(0.32, 0.48, 0.6) : vec3(0.36, 0.5, 0.62);
		glass *= 0.85 + 0.3 * hash(cell_id);
		col = mix(wall, glass, win);
		ROUGHNESS = mix(0.85, 0.15, win);
		METALLIC = win * 0.35;
	}
	col *= mix(1.0, 0.45, dark);
	ALBEDO = col;
	float lit = step(0.5, hash(cell_id + 7.0)) * win * night * (1.0 - dark);
	EMISSION = vec3(1.0, 0.78, 0.45) * lit * 1.3;
}
