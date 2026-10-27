shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://shaders/terrain.gdshaderinc"
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += terrain_h(w.xz);
}
uniform sampler2D data_tex : filter_linear;
uniform float opacity = 0.75;
void fragment() {
	vec4 c = texture(data_tex, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a * opacity;
}
