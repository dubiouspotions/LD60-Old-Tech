shader_type canvas_item;
// Night colour grade: blends the picture into the night LUT by amount, except near the light spots, which keep
// their colours. Spots are (x, y, radius) in viewport pixels and a strength 0..1 (see NightGrade).

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform sampler3D lut : filter_linear;
// LUT cells per side (a 17x17x17 LUT is 17).
uniform float lut_size = 17.0;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// How the light fades towards its edge: 1 is linear, higher keeps the day colours closer to the light.
uniform float falloff = 1.0;
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform int spot_count = 0;
uniform vec4 spots[32];

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	if (amount <= 0.0) {
		COLOR = vec4(c, 1.0);
	} else {
		vec3 cell = clamp(c, 0.0, 1.0) * (lut_size - 1.0) / lut_size + 0.5 / lut_size;
		vec3 night = texture(lut, cell).rgb;
		vec2 p = SCREEN_UV * view_size;
		float lit = 0.0;
		for (int i = 0; i < spot_count; i++) {
			float d = distance(p, spots[i].xy) / max(spots[i].z, 1.0);
			lit = max(lit, spots[i].w * pow(clamp(1.0 - d, 0.0, 1.0), falloff));
		}
		COLOR = vec4(mix(c, night, amount * (1.0 - lit)), 1.0);
	}
}
