class_name PlanButtons
extends HBoxContainer
## Build and cancel buttons that float together above a plan.


## Puts the pair above screen_px (screen pixels), centred.
func pin(screen_px: Vector2) -> void:
	WorldButton.pin_control(self, screen_px)
