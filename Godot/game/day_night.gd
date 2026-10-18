class_name DayNight
extends Node
## Night falls while the column camps: tints the world and the sky and lights every NightLight (the cursor
## lantern, the engineers' lamps).

@export var world_tint: CanvasModulate
@export var sky_tint: CanvasModulate
@export var day_color: Color = Color.WHITE
@export var night_world_color: Color = Color(0.3, 0.34, 0.52)
@export var night_sky_color: Color = Color(0.2, 0.23, 0.4)
@export_range(0.0, 10.0, 0.1, "suffix:s") var fade_time: float = 2.0

var night: bool = false
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is NightLight:
			(n as NightLight).fade(night, 0.0))
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
	for l: NightLight in get_tree().get_nodes_in_group(NightLight.GROUP):
		l.fade(on, t)
