class_name DayNight
extends Node
## Night falls while the column camps: tints the world and the sky and lights the engineers' lantern.

@export var world_tint: CanvasModulate
@export var sky_tint: CanvasModulate
## Light that follows the cursor at night (optional).
@export var lantern: PointLight2D
@export var day_color: Color = Color.WHITE
@export var night_world_color: Color = Color(0.3, 0.34, 0.52)
@export var night_sky_color: Color = Color(0.2, 0.23, 0.4)
@export_range(0.0, 4.0, 0.05) var lantern_energy: float = 0.9
@export_range(0.0, 10.0, 0.1, "suffix:s") var fade_time: float = 2.0

var night: bool = false
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_night(false, true)


## Fades to night or day over seconds (fade_time when negative).
func set_night(on: bool, instant: bool = false, seconds: float = -1.0) -> void:
	night = on
	if _tween:
		_tween.kill()
	var t := 0.0 if instant else (seconds if seconds >= 0.0 else fade_time)
	_tween = create_tween().set_parallel()
	if world_tint:
		_tween.tween_property(world_tint, ^"color", night_world_color if on else day_color, maxf(t, 0.01))
	if sky_tint:
		_tween.tween_property(sky_tint, ^"color", night_sky_color if on else day_color, maxf(t, 0.01))
	if lantern:
		if on:
			lantern.visible = true
		_tween.tween_property(lantern, ^"energy", lantern_energy if on else 0.0, maxf(t, 0.01))
		if not on:
			_tween.chain().tween_callback(func() -> void: lantern.visible = night)
