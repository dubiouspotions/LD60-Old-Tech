shader_type canvas_item;
// Draws a black-and-white mask sheet as a tinted shape: white is solid, black is transparent, and the colour
// comes from the sprite's modulate (self_modulate), so one sheet makes birds of any colour.

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	float mask = texture(TEXTURE, UV).r;
	COLOR = vec4(tint.rgb, tint.a * mask);
}
