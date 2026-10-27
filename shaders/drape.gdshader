// Kenney road models draped onto the terrain, repainted with photo textures:
// bluish toon asphalt -> real asphalt, light-blue sidewalks -> concrete pavers.
shader_type spatial;
#include "res://shaders/terrain.gdshaderinc"
uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pave_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float realism = 1.0;
global uniform float night;
global uniform float snow;
global uniform float wet;
varying vec3 wp;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += terrain_h(w.xz);
	wp = w;
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 s = pow(c, vec3(1.0 / 2.2));
	float greyblue = step(abs(s.r - s.g), 0.07) * step(s.r, s.b + 0.02);
	float asphalt = greyblue * step(s.r, 0.45);
	float walk = greyblue * step(0.48, s.r) * step(s.r, 0.72);
	vec3 a = texture(asphalt_tex, wp.xz * 0.45).rgb / vec3(0.139, 0.126, 0.141);
	a = mix(vec3(dot(a, vec3(0.333))), a, 0.3);
	vec3 p = texture(pave_tex, wp.xz * 0.9).rgb / vec3(0.22, 0.18, 0.137);
	p = mix(vec3(dot(p, vec3(0.333))), p, 0.4);
	float l = dot(c, vec3(0.333));
	vec3 road = vec3(l * 0.62) * a * tint;
	vec3 side = vec3(l * 1.05, l * 1.02, l * 0.96) * p;
	vec3 real = mix(c, road, asphalt);
	real = mix(real, side, walk);
	vec3 col = mix(mix(c, c * tint, asphalt), real, realism);
	col = mix(col, vec3(0.9, 0.92, 0.95), snow * 0.55 * (asphalt * 0.6 + walk));
	// rain: darker asphalt, glossy puddles in the dips of the texture
	float puddle = smoothstep(0.92, 0.8, dot(a, vec3(0.333))) * asphalt;
	float w = wet * (1.0 - snow);
	col *= 1.0 - w * (0.3 * asphalt + 0.15 * walk + 0.15 * puddle);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.9, 0.75, asphalt), mix(0.28, 0.06, puddle), w * (asphalt + walk * 0.6));
}
