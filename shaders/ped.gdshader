// Pedestrians: one palette texture (8 colour slots) per model; skin, clothes and hair
// are recoloured per person through instance uniforms.
shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D palette : source_color, filter_nearest;
instance uniform vec4 skin_col : source_color = vec4(0.85, 0.65, 0.5, 1.0);
instance uniform vec4 shirt_col : source_color = vec4(0.3, 0.4, 0.6, 1.0);
instance uniform vec4 pants_col : source_color = vec4(0.2, 0.2, 0.25, 1.0);
instance uniform vec4 hair_col : source_color = vec4(0.15, 0.1, 0.05, 1.0);
global uniform float night;

void fragment() {
	int slot = int(UV.x * 8.0);
	vec3 c = texture(palette, UV).rgb;
	if (slot == 0) c = skin_col.rgb;
	else if (slot == 1) c = shirt_col.rgb;
	else if (slot == 2) c = pants_col.rgb;
	else if (slot == 5 || slot == 6) c = hair_col.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.8;
	// a touch of self-lighting so people stay visible under street lamps at night
	EMISSION = c * 0.12 * night;
}
