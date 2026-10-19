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
// The dithered fade around lights: see LightDither (night_grade.gd passes its settings). dither_steps 0 is smooth.
uniform float pixel_size = 4.0;
uniform float dither_steps = 3.0;
uniform int pattern = 1;
uniform float spread = 1.0;
uniform int frame = 0;
uniform int frames = 4;
// On: dither pixels are counted from the world's origin (world_origin, on screen), else from each light's centre.
uniform bool world_space = true;
uniform vec2 world_origin = vec2(0.0);
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform int spot_count = 0;
uniform vec4 spots[32];

float noise(ivec2 c, int seed) {
	uint h = uint(c.x) * 374761393u + uint(c.y) * 668265263u + uint(seed) * 2246822519u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h = h ^ (h >> 16u);
	return float(h & 65535u) / 65536.0;
}

// The dither threshold (0..1) of the dither pixel at cell. Keep in step with LightDither.threshold().
float threshold(ivec2 cell) {
	float t;
	if (pattern == 4) {
		return 0.5;
	} else if (pattern == 3) {
		t = noise(cell, frame);
	} else {
		int n = pattern + 1;
		int v = 0;
		for (int i = 0; i < n; i++) {
			int xb = (cell.x >> i) & 1;
			int yb = (cell.y >> i) & 1;
			v += ((xb ^ yb) * 2 + yb) << (2 * (n - 1 - i));
		}
		t = fract((float(v) + 0.5) / float(1 << (2 * n)) + float(frame) / float(frames));
	}
	return 0.5 + (t - 0.5) * spread;
}

// v rounded to one of dither_steps + 1 levels, up or down by the threshold of the dither pixel at cell.
float dither(float v, vec2 cell) {
	if (dither_steps <= 0.0) {
		return v;
	}
	return clamp(floor(v * dither_steps + threshold(ivec2(cell))) / dither_steps, 0.0, 1.0);
}

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	if (amount <= 0.0) {
		COLOR = vec4(c, 1.0);
	} else {
		vec3 cell = clamp(c, 0.0, 1.0) * (lut_size - 1.0) / lut_size + 0.5 / lut_size;
		vec3 night = texture(lut, cell).rgb;
		vec2 p = SCREEN_UV * view_size;
		float lit = 0.0;
		// The dither is laid out from the centre of the brightest light here, like its DitheredLightTexture.
		vec2 from_light = p;
		for (int i = 0; i < spot_count; i++) {
			vec2 rel = p - spots[i].xy;
			float l = spots[i].w * pow(clamp(1.0 - length(rel) / max(spots[i].z, 1.0), 0.0, 1.0), falloff);
			if (l > lit) {
				lit = l;
				from_light = rel;
			}
		}
		lit = dither(lit, floor((world_space ? p - world_origin : from_light) / pixel_size));
		COLOR = vec4(mix(c, night, amount * (1.0 - lit)), 1.0);
	}
}
