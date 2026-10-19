class_name DayNight
extends Node
## Night falls while the column camps: tints the world and the sky, brings out the stars, grades the colours to night
## (except around lights) and lights every NightLight
## (the cursor lantern, the engineers' lamps).
## How dark it is (darkness) follows the sun along Darkness By Sun once the Game feeds it the sun (set_sun), so the
## light changes over the whole day; without it, set_night fades it between day and night.

@export var world_tint: CanvasModulate
@export var sky_tint: CanvasModulate
## Faded in at night (optional).
@export var stars: Stars
## The night colour grade, faded in at night (optional).
@export var grade: NightGrade
## The layer holding the levels' fireflies, out at night (optional).
@export var fireflies: FireflyLayer
## Pollen on the wind, out by day (optional).
@export var pollen: Pollen
@export var day_color: Color = Color.WHITE
@export var night_world_color: Color = Color(0.3, 0.34, 0.52)
@export var night_sky_color: Color = Color(0.3, 0.35, 0.55, 1.0)
@export_range(0.0, 10.0, 0.1, "suffix:s") var fade_time: float = 1.0
## How dark it is (0 full day, 1 full night) by where the sun is in its day (Sun.progress: 0 dawn, 1 sunset, below
## 0 or above 1 under the horizon). Edit the graph to shape dawn, midday and dusk.
@export var darkness_by_sun: Curve

var night: bool = false
## 0 full day, 1 full night: the tints, the stars, the night grade and the fireflies (the pollen the other way).
var darkness: float = 0.0:
	set(v):
		darkness = clampf(v, 0.0, 1.0)
		_apply()
var _tween: Tween
## Darkness follows the sun (set_sun has been called).
var _by_sun: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is NightLight:
			(n as NightLight).fade(night, 0.0))
	set_night(false, true)


## Fades to night or day over seconds (fade_time when negative): the lights, and the darkness unless it follows the
## sun.
func set_night(on: bool, instant: bool = false, seconds: float = -1.0) -> void:
	night = on
	var t := 0.0 if instant else (seconds if seconds >= 0.0 else fade_time)
	if not _by_sun:
		if _tween:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, ^"darkness", 1.0 if on else 0.0, maxf(t, 0.01))
		if t == 0.0:
			_tween.custom_step(1.0)
	for l: NightLight in get_tree().get_nodes_in_group(NightLight.GROUP):
		l.fade(on, t)


## Sets the darkness by where the sun is (Sun.progress), along darkness_by_sun. From then on nightfall leaves the
## darkness to the sun.
func set_sun(progress: float) -> void:
	if darkness_by_sun == null:
		return
	if not _by_sun and _tween:
		_tween.kill()
	_by_sun = true
	darkness = darkness_by_sun.sample(progress)


func _apply() -> void:
	if world_tint:
		world_tint.color = day_color.lerp(night_world_color, darkness)
	if sky_tint:
		sky_tint.color = day_color.lerp(night_sky_color, darkness)
	if stars:
		stars.amount = darkness
	if grade:
		grade.amount = darkness
	if fireflies:
		fireflies.night = darkness
	if pollen:
		pollen.amount = 1.0 - darkness
