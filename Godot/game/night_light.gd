class_name NightLight
extends PointLight2D
## A light that is on at night only. DayNight fades every NightLight in and out, including ones added at night.
## The fade runs on the light's own tween, so it ends with the light.

const GROUP := &"night_lights"

## Energy at full night.
@export_range(0.0, 4.0, 0.05) var night_energy: float = 0.6


var _tween: Tween


func _enter_tree() -> void:
	add_to_group(GROUP)


## Fades on (to night_energy) or off over seconds; 0 switches at once. Runs while the game is paused.
func fade(on: bool, seconds: float) -> void:
	if _tween:
		_tween.kill()
	if on:
		visible = true
	if seconds <= 0.0:
		energy = night_energy if on else 0.0
		visible = on
		return
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, ^"energy", night_energy if on else 0.0, seconds)
	_tween.tween_callback(func() -> void: visible = on)
