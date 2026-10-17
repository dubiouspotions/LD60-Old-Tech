class_name WorldButton
extends Button
## A HUD button that floats above a point in the world, centred, with its bottom edge on the point.


## Puts the button above screen_px (a point already in screen pixels).
func pin(screen_px: Vector2) -> void:
	size = get_combined_minimum_size()
	position = (screen_px - Vector2(size.x / 2, size.y)).round()
