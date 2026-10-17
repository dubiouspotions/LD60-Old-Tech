class_name WorldButton
extends Button
## A HUD button that floats above a point in the world, centred, with its bottom edge on the point.


## Puts the button above screen_px (a point already in screen pixels).
func pin(screen_px: Vector2) -> void:
	pin_control(self, screen_px)


## Sizes c to fit and places it centred above screen_px.
static func pin_control(c: Control, screen_px: Vector2) -> void:
	c.size = c.get_combined_minimum_size()
	c.position = (screen_px - Vector2(c.size.x / 2, c.size.y)).round()
