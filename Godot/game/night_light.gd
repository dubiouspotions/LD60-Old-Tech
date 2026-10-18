class_name NightLight
extends PointLight2D
## A light that is on at night only. DayNight fades every NightLight in and out, including ones added at night.

const GROUP := &"night_lights"

## Energy at full night.
@export_range(0.0, 4.0, 0.05) var night_energy: float = 0.6


func _enter_tree() -> void:
	add_to_group(GROUP)
