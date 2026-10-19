@tool
class_name Stars
extends Node2D
## Stars in the night sky, twinkling gently. Put it on the background CanvasLayer, after the Sky and before the
## ridges. DayNight fades amount in at dusk and out at dawn. The stars undo the layer's night tint (tint), so they
## shine in their own colour while the sky around them darkens. Now and then a shooting star streaks across.

## Shown from 0 (day) to 1 (night). DayNight sets this.
@export_range(0.0, 1.0, 0.01) var amount: float = 0.0:
	set(v):
		amount = v
		queue_redraw()
@export_range(0, 500) var star_count: int = 90:
	set(v):
		star_count = v
		_layout()
@export var star_seed: int = 7:
	set(v):
		star_seed = v
		_layout()
@export var color: Color = Color("fff6dc")
## How far down the screen stars reach, as a fraction of its height. Thinner towards the bottom.
@export_range(0.05, 1.0, 0.01) var sky_height: float = 0.6:
	set(v):
		sky_height = v
		queue_redraw()
## How far the stars drift sideways with the camera: 0 = fixed to the screen, 1 = moves with the world. Keep it
## below the furthest mountains' Scroll Scale so the stars look furthest away. They wrap round the screen.
@export_range(0.0, 1.0, 0.001) var parallax: float = 0.02
## Size of one star pixel on screen (the art is drawn at 4x).
@export_range(1, 16) var pixel: int = 4
## Share of stars drawn as a small cross instead of one pixel.
@export_range(0.0, 1.0, 0.01) var big_share: float = 0.12:
	set(v):
		big_share = v
		_layout()
## How much a star dims at the low point of its twinkle (0 = steady, 1 = goes out).
@export_range(0.0, 1.0, 0.01) var twinkle_depth: float = 0.6
## Twinkles per second, each star picking a speed in this range.
@export var twinkle_speed: Vector2 = Vector2(0.15, 0.6):
	set(v):
		twinkle_speed = v
		_layout()
## The CanvasModulate tinting this layer at night, undone for the stars (optional).
@export var tint: CanvasModulate

@export_group("Shooting stars")
## Seconds between shooting stars, picked at random in this range. Only while the stars are out.
@export var shooting_interval: Vector2 = Vector2(8.0, 20.0)
## Seconds a shooting star lasts, picked at random in this range.
@export var shooting_life: Vector2 = Vector2(0.5, 0.9)
@export_range(100.0, 3000.0, 10.0, "suffix:px/s") var shooting_speed: float = 900.0
## Length of the trail in star pixels.
@export_range(1, 40) var shooting_trail: int = 10

var _stars: Array[Vector4] = [] # x 0..1, y 0..1, twinkle speed (Hz), phase; big stars have a negative speed
var _meteors: Array[Dictionary] = [] # {pos, vel, age, life}
var _rng := RandomNumberGenerator.new()
var _next_meteor: float = -1.0
## The camera's left edge in metres, for the parallax.
var _cam_x: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_layout()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		advance(delta)
		var cam := get_viewport().get_camera_2d()
		_cam_x = Grid.to_m(cam.get_screen_center_position() - get_viewport_rect().size / 2).x if cam else 0.0
	if amount > 0.0:
		queue_redraw()


## Moves the shooting stars on by delta seconds and sends a new one when it is time.
func advance(delta: float) -> void:
	for m in _meteors:
		m.age += delta
		m.pos += m.vel * delta
	_meteors = _meteors.filter(func(m: Dictionary) -> bool: return m.age < m.life)
	if amount < 0.5:
		_next_meteor = -1.0
		return
	if _next_meteor < 0.0:
		_next_meteor = _rng.randf_range(shooting_interval.x, shooting_interval.y)
	_next_meteor -= delta
	if _next_meteor <= 0.0:
		_next_meteor = _rng.randf_range(shooting_interval.x, shooting_interval.y)
		_shoot()


## Shooting stars in the sky right now.
func shooting() -> int:
	return _meteors.size()


func _shoot() -> void:
	var size := get_viewport_rect().size
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var angle := deg_to_rad(_rng.randf_range(15.0, 35.0))
	_meteors.append({
		pos = Vector2(_rng.randf_range(0.15, 0.85) * size.x, _rng.randf_range(0.05, 0.35) * sky_height * size.y),
		vel = Vector2(side * cos(angle), sin(angle)) * shooting_speed,
		age = 0.0,
		life = _rng.randf_range(shooting_life.x, shooting_life.y),
	})


func count() -> int:
	return _stars.size()


## Where star i sits on a screen of size with the camera's left edge at cam_x (metres), snapped to the pixel
## grid: shifted sideways by the parallax share of the camera's travel, wrapping round the screen.
func star_position(i: int, size: Vector2, cam_x: float = 0.0) -> Vector2:
	var s := _stars[i]
	var p := Vector2(fposmod(s.x * size.x - cam_x * Grid.PX * parallax, size.x), s.y * sky_height * size.y)
	return (p / pixel).floor() * pixel


## Star i's twinkle at time t (seconds), from 1 - twinkle_depth to 1.
func brightness(i: int, t: float) -> float:
	var s := _stars[i]
	var wave := 0.5 + 0.5 * sin(TAU * (absf(s.z) * t + s.w))
	return 1.0 - twinkle_depth * wave


## The colour star i is drawn with at time t: its twinkle and amount as alpha, with the night tint undone.
func draw_color(i: int, t: float) -> Color:
	var c := color
	if tint:
		var k := tint.color
		c = Color(c.r / maxf(k.r, 0.01), c.g / maxf(k.g, 0.01), c.b / maxf(k.b, 0.01))
	c.a = color.a * amount * brightness(i, t)
	return c


func _draw() -> void:
	if amount <= 0.0:
		return
	var size := get_viewport_rect().size
	var t := Time.get_ticks_msec() / 1000.0
	for i in _stars.size():
		var p := star_position(i, size, _cam_x)
		var c := draw_color(i, t)
		draw_rect(Rect2(p, Vector2.ONE * pixel), c)
		if _stars[i].z < 0.0:
			for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				draw_rect(Rect2(p + d * pixel, Vector2.ONE * pixel), Color(c, c.a * 0.45))
	var base := draw_color(0, 0.0)
	for m in _meteors:
		var fade := sin(PI * m.age / m.life) * amount
		var back: Vector2 = -(m.vel as Vector2).normalized() * pixel
		for k in shooting_trail:
			var at: Vector2 = ((m.pos + back * k) / pixel).floor() * pixel
			draw_rect(Rect2(at, Vector2.ONE * pixel), Color(base, color.a * fade * (1.0 - float(k) / shooting_trail)))


func _layout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = star_seed
	_stars.clear()
	for i in star_count:
		var speed := rng.randf_range(twinkle_speed.x, twinkle_speed.y)
		if rng.randf() < big_share:
			speed = -speed
		_stars.append(Vector4(rng.randf(), pow(rng.randf(), 1.6), speed, rng.randf()))
	queue_redraw()
