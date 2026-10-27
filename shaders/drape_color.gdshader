// Plain coloured geometry draped onto the terrain (highway barriers etc).
shader_type spatial;
#include "res://shaders/terrain.gdshaderinc"
uniform vec4 color : source_color = vec4(0.8, 0.8, 0.82, 1.0);
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += terrain_h(w.xz);
}
void fragment() {
	ALBEDO = color.rgb;
	ROUGHNESS = 0.8;
}
