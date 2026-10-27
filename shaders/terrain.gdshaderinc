// Shared terrain height lookup (matches the ground mesh triangulation).
global uniform sampler2D heightmap : filter_nearest;
global uniform float hm_size;

float hm_corner(ivec2 c) {
	ivec2 m = ivec2(int(hm_size) - 1);
	return texelFetch(heightmap, clamp(c, ivec2(0), m), 0).r;
}

float terrain_h(vec2 p) {
	vec2 b = floor(p);
	vec2 f = p - b;
	ivec2 c = ivec2(b);
	float h0 = hm_corner(c);
	float h1 = hm_corner(c + ivec2(1, 0));
	float h2 = hm_corner(c + ivec2(1, 1));
	float h3 = hm_corner(c + ivec2(0, 1));
	if (f.x >= f.y) return h0 + f.x * (h1 - h0) + f.y * (h2 - h1);
	return h0 + f.y * (h3 - h0) + f.x * (h2 - h3);
}
