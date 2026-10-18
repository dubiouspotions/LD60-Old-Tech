class_name Pollen
extends Node2D
## Pollen and seed fluff drifting on the wind by day, left to right with a gentle flutter. Keeps a sparse handful
## around the view: new motes blow in from the left edge, and those left behind or blown past the right are
## dropped. Put it on the same CanvasLayer as the fireflies. DayNight fades amount out at night.

## 1 by day, 0 at night. DayNight sets this.
@export_range(0.0, 1.0, 0.01) var amount: float = 1.0
## Most motes around the view at once.
@export_range(0, 200) var max_count: int = 18
## Wind, metres per second. Each mote drifts at 70 to 130 % of it.
@export var wind: Vector2 = Vector2(1.1, -0.05)
## Height of the up-and-down flutter, metres.
@export_range(0.0, 2.0, 0.01) var flutter: float = 0.25
## Flutters per second, each mote picking a pace in this range.
@export var flutter_rate: Vector2 = Vector2(0.2, 0.6)
## How far down the view motes drift, as a fraction of its height from the top.
@export_range(0.1, 1.0, 0.01) var height: float = 0.85
## Metres outside the view where motes appear and are dropped.
@export_range(0.0, 10.0, 0.1) var margin: float = 1.0
@export var color: Color = Color(1.0, 0.97, 0.85, 0.55)
## Size of a mote in pixels (one art pixel at 4x). Some get a faint fluffy halo.
@export_range(1, 16) var pixel: int = 4
## Share of motes drawn as fluffy seeds (a faint cross around the pixel).
@export_range(0.0, 1.0, 0.01) var fluff_share: float = 0.35

var _motes: Array[Dictionary] = [] # {pos, speed, rate, phase, fluff, age}; metres
var _rng := RandomNumberGenerator.new()
var _t: float = 0.0


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam:
		var size := get_viewport_rect().size / cam.zoom
		advance(delta, Rect2(Grid.to_m(cam.get_screen_center_position() - size / 2), Grid.to_m(size)))
	queue_redraw()


## Moves the motes on by delta seconds over view (metres): drops those outside it and blows in new ones.
func advance(delta: float, view: Rect2) -> void:
	_t += delta
	var area := view.grow(margin)
	for m in _motes:
		m.age += delta
		m.pos += velocity_of(m) * delta
	_motes = _motes.filter(func(m: Dictionary) -> bool: return area.has_point(m.pos))
	if amount < 0.5:
		return
	# When the day starts or the view jumps, scatter some over the view so it does not start empty.
	if _motes.is_empty():
		for i in max_count / 2:
			_add(Vector2(_rng.randf_range(view.position.x, view.end.x), _top(view)))
	# Then keep a steady trickle from the left edge: as many as cross the view at this wind.
	var per_second := max_count * wind.x / maxf(area.size.x, 1.0)
	if _motes.size() < max_count and _rng.randf() < per_second * delta:
		_add(Vector2(area.position.x + 0.01, _top(view)))


## Motes around the view now.
func count() -> int:
	return _motes.size()


func positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for m in _motes:
		out.append(m.pos)
	return out


func velocities() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for m in _motes:
		out.append(velocity_of(m))
	return out


## A mote's velocity now: the wind at its own pace, plus its flutter.
func velocity_of(m: Dictionary) -> Vector2:
	var w: Vector2 = wind * float(m.speed)
	var bob := cos(TAU * (float(m.rate) * _t + float(m.phase))) * TAU * float(m.rate) * flutter * 0.5
	return Vector2(w.x, w.y + bob)


func _top(view: Rect2) -> float:
	return view.position.y + _rng.randf() * view.size.y * height


func _add(at: Vector2) -> void:
	_motes.append({
		pos = at,
		speed = _rng.randf_range(0.7, 1.3),
		rate = _rng.randf_range(flutter_rate.x, flutter_rate.y),
		phase = _rng.randf(),
		fluff = _rng.randf() < fluff_share,
		age = 0.0,
	})


func _draw() -> void:
	for m in _motes:
		var a := color.a * amount * minf(1.0, float(m.age) / 0.8)
		if a <= 0.01:
			continue
		var p := (Grid.to_px(m.pos) / pixel).floor() * pixel
		draw_rect(Rect2(p, Vector2.ONE * pixel), Color(color, a))
		if m.fluff:
			for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				draw_rect(Rect2(p + d * pixel, Vector2.ONE * pixel), Color(color, a * 0.3))
