shader_type canvas_item;
// Plays the tall grass sheet's frames (left to right) on the grass tile. Each column of cells in the world starts
// delay_frames later than the column to its left, so the sway rolls along like wind. Also runs in the editor.

// Seconds per frame.
uniform float frame_time : hint_range(0.02, 2.0) = 0.15;
// Frames each column lags behind the one to its left. Negative rolls the other way, 0 sways all in step.
uniform float delay_frames = 1.0;
// Width of one frame in the sheet, in sheet pixels.
uniform float frame_px = 8.0;
// Width of a world cell on screen, in pixels.
uniform float cell_px = 32.0;

varying float world_x;

void vertex() {
	world_x = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).x;
}

void fragment() {
	float frame_u = frame_px * TEXTURE_PIXEL_SIZE.x;
	float frames = round(1.0 / frame_u);
	float frame = mod(floor(TIME / frame_time) - floor(world_x / cell_px) * delay_frames, frames);
	COLOR = texture(TEXTURE, UV + vec2(frame * frame_u, 0.0));
}
