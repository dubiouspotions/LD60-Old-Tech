class_name Fireflies
extends Node2D
## Fireflies drifting and blinking under the trees at night. Put it on a CanvasLayer above the night grade (with
## Follow Viewport on), so they keep their own glow. DayNight fades amount in at dusk; while it is up, a new one
## comes out now and then at the foot of a tree on screen, wanders inside roam, and fades away after its life.

## 0 by day, 1 at night. DayNight sets this.
@export_range(0.0, 1.0, 0.01) var amount: float = 0.0
## Terrain types that make a tree. A cell of one standing on solid ground is a tree's foot.
@export var tree_types: Array[TerrainType] = []
## Most fireflies out at once.
@export_range(0, 50) var max_count: int = 6
## Seconds between new fireflies, picked at random in this range.
@export var spawn_interval: Vector2 = Vector2(0.8, 2.5)
## Seconds each one lives, picked at random in this range.
@export var life: Vector2 = Vector2(6.0, 12.0)
## How far a firefly roams from its tree: sideways either way, and up from the ground.
@export var roam: Vector2 = Vector2(2.0, 2.2)
@export_range(0.05, 5.0, 0.05, "suffix:m/s") var speed: float = 0.9
## How quickly a firefly changes direction as it wanders, in turns per second at most.
@export_range(0.0, 3.0, 0.05) var wander: float = 0.6
## Blinks per second, each one picking a pace in this range.
@export var blink_rate: Vector2 = Vector2(0.3, 0.8)
## How bright a firefly stays between flashes (0 = goes dark).
@export_range(0.0, 1.0, 0.01) var dim: float = 0.2
@export var color: Color = Color("e8ff7a")
## Radius of the soft glow around each one, in pixels.
@export_range(1.0, 40.0, 0.5) var glow_radius: float = 9.0
## Size of the bright core, in pixels (one art pixel at 4x).
@export_range(1, 16) var core_px: int = 4

var _flies: Array[Dictionary] = [] # {pos, heading, home: Rect2, age, life, rate, phase}; metres and radians
var _rng := RandomNumberGenerator.new()
var _next: float = 0.0


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	advance(delta)
	queue_redraw()


## Moves the fireflies on by delta seconds and lets a new one out when it is time.
func advance(delta: float) -> void:
	for f in _flies:
		f.age += delta
		var home: Rect2 = f.home
		var pos: Vector2 = f.pos
		var heading: float = f.heading + _rng.randf_range(-1.0, 1.0) * TAU * wander * delta
		var step := Vector2.from_angle(heading) * speed * delta
		# Turn back at the edge of its patch under the tree.
		if pos.x + step.x < home.position.x or pos.x + step.x > home.end.x:
			heading = PI - heading
		if pos.y + step.y < home.position.y or pos.y + step.y > home.end.y:
			heading = -heading
		f.heading = heading
		f.pos = (pos + Vector2.from_angle(heading) * speed * delta).clamp(home.position, home.end)
	_flies = _flies.filter(func(f: Dictionary) -> bool: return f.age < f.life)
	if amount < 0.5:
		return
	_next -= delta
	if _next > 0.0:
		return
	_next = _rng.randf_range(spawn_interval.x, spawn_interval.y)
	if _flies.size() >= max_count:
		return
	var bases := tree_bases(_area())
	if bases.is_empty():
		return
	var base: Vector2i = bases[_rng.randi() % bases.size()]
	var ground := float(base.y + 1)
	var home := Rect2(base.x + 0.5 - roam.x, ground - roam.y, roam.x * 2.0, roam.y - 0.15)
	_flies.append({
		pos = Vector2(_rng.randf_range(home.position.x, home.end.x), _rng.randf_range(home.position.y, home.end.y)),
		heading = _rng.randf() * TAU,
		home = home,
		age = 0.0,
		life = _rng.randf_range(life.x, life.y),
		rate = _rng.randf_range(blink_rate.x, blink_rate.y),
		phase = _rng.randf(),
	})


## Fireflies out now.
func count() -> int:
	return _flies.size()


## Where each firefly is, in metres.
func positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for f in _flies:
		out.append(f.pos)
	return out


## The foot of every tree in area (cells): a tree cell standing on solid ground.
func tree_bases(area: Rect2i) -> Array[Vector2i]:
	var terrain := _terrain()
	var out: Array[Vector2i] = []
	if terrain == null:
		return out
	for x in range(area.position.x, area.end.x):
		for y in range(area.position.y, area.end.y):
			var c := Vector2i(x, y)
			if terrain.type_at(c) in tree_types and terrain.is_solid(c + Vector2i.DOWN):
				out.append(c)
	return out


func _terrain() -> Terrain:
	var world := World.of(self)
	return world.terrain if world else null


## Cells on screen, or the whole terrain when there is no camera.
func _area() -> Rect2i:
	var terrain := _terrain()
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2i(terrain.min_x, 0, terrain.size.x - terrain.min_x, terrain.size.y)
	var size := get_viewport_rect().size / cam.zoom
	var r := Rect2(Grid.to_m(cam.get_screen_center_position() - size / 2), Grid.to_m(size))
	return Rect2i(Vector2i(r.position.floor()), Vector2i(r.size.ceil()) + Vector2i.ONE)


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for f in _flies:
		var fade := minf(1.0, minf(f.age, f.life - f.age) / 1.0)
		var blink := lerpf(dim, 1.0, pow(0.5 + 0.5 * sin(TAU * (f.rate * t + f.phase)), 2.0))
		var a := fade * blink * maxf(amount, 0.0 if f.age > 0.0 else 1.0)
		if a <= 0.01:
			continue
		var p := (Grid.to_px(f.pos) / core_px).floor() * core_px
		var mid := p + Vector2.ONE * core_px / 2.0
		draw_circle(mid, glow_radius, Color(color, 0.18 * a))
		draw_circle(mid, glow_radius * 0.5, Color(color, 0.3 * a))
		draw_rect(Rect2(p, Vector2.ONE * core_px), Color(color.lightened(0.5), a))
