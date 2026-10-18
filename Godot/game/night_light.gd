class_name NightLight
extends PointLight2D
## A light that is on at night only. DayNight fades every NightLight in and out, including ones added at night.
## The fade runs on the light's own tween, so it ends with the light.
## Use the Mix blend mode, so overlapping lights do not add up: the brighter one wins. A Mix light pulls what it
## lights towards night_energy x its colour, so it fades from daylight (energy 1, white) instead of from dark.

const GROUP := &"night_lights"
## Energy and colour of a Mix light that leaves everything at its day colour.
const DAY_ENERGY: float = 1.0
const DAY_COLOR: Color = Color.WHITE

## Energy at full night.
@export_range(0.0, 4.0, 0.05) var night_energy: float = 0.6


var _tween: Tween
## The colour set on the light, taken before the first fade changes it.
var _night_color: Variant = null


func _enter_tree() -> void:
	add_to_group(GROUP)


## Fades on (to night_energy in its colour) or off (back to daylight, then out) over seconds; 0 switches at once.
## Runs while the game is paused.
func fade(on: bool, seconds: float) -> void:
	if _tween:
		_tween.kill()
	if _night_color == null:
		_night_color = color
	if on and not visible:
		energy = DAY_ENERGY
		color = DAY_COLOR
		visible = true
	var to_energy := night_energy if on else DAY_ENERGY
	var to_color: Color = _night_color if on else DAY_COLOR
	if seconds <= 0.0:
		energy = to_energy
		color = to_color
		visible = on
		return
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel()
	_tween.tween_property(self, ^"energy", to_energy, seconds)
	_tween.tween_property(self, ^"color", to_color, seconds)
	_tween.chain().tween_callback(func() -> void: visible = on)
