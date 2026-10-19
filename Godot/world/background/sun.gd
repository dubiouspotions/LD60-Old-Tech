@tool
class_name Sun
extends Node2D
## The sun crossing the sky over a day: Progress 0 is dawn, on the horizon at Rise X; 0.5 the top of its arc at
## Peak Y; 1 sunset, on the horizon at Set X. Past either end it is below the horizon (behind the hills). The Game
## sets Progress from the column's way across the level (World.sun_progress). Put it on the background layer.

## Where it is in its day (see above).
@export var progress: float = 0.5:
	set(v):
		progress = v
		_place()
## Across the screen where it rises and where it sets, as shares of the screen width (east is to the right).
@export_range(-0.5, 1.5, 0.01) var rise_x: float = 0.85:
	set(v):
		rise_x = v
		_place()
@export_range(-0.5, 1.5, 0.01) var set_x: float = 0.15:
	set(v):
		set_x = v
		_place()
## Heights as shares of the screen height: the horizon it rises from and sets into, and the top of its arc.
@export_range(0.0, 1.5, 0.01) var horizon_y: float = 0.62:
	set(v):
		horizon_y = v
		_place()
@export_range(-0.5, 1.0, 0.01) var peak_y: float = 0.18:
	set(v):
		peak_y = v
		_place()


func _ready() -> void:
	_place()


func _place() -> void:
	if not is_inside_tree():
		return
	var size := get_viewport_rect().size
	position = Vector2(lerpf(rise_x, set_x, progress) * size.x,
			(horizon_y - sin(progress * PI) * (horizon_y - peak_y)) * size.y)
