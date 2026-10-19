@tool
class_name Fireflies
extends Node2D
## A swarm of fireflies drifting and blinking at night, placed by hand in a level's Objects (by a tree or a bush).
## When the level is stitched on, the World moves it onto its FireflyLayer, above the night grade, so they keep
## their own glow. At night a new one comes out now and then inside radius around this node, wanders there
## (keeping out of solid ground), and fades away after its life. In the editor they fly as if it were night.

## Most fireflies of this swarm out at once (0 turns it off).
@export_range(0, 30) var amount: int = 3
## How far a firefly roams from this node, in metres (1 m = 1 tile). Shown as a circle in the editor.
@export_range(0.25, 10.0, 0.05, "suffix:m") var radius: float = 1.8
@export_range(0.05, 5.0, 0.05, "suffix:m/s") var speed: float = 0.9
## Seconds each one lives, picked at random in this range.
@export var life: Vector2 = Vector2(6.0, 12.0)
## Seconds between new fireflies, picked at random in this range.
@export var spawn_interval: Vector2 = Vector2(0.8, 2.5)
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
@export_group("Plant")
## Come out only while the nearest tree or bush (a plant cell within Plant Reach) still stands: once it is
## chopped down, no new fireflies come out here. With no plant in reach they come out regardless.
@export var needs_plant: bool = true
## Terrain types that make a tree or bush (trunk, leaves).
@export var plant_types: Array[TerrainType] = []
## How far from this node to look for the nearest plant cell, in metres.
@export_range(0.5, 10.0, 0.5, "suffix:m") var plant_reach: float = 3.0

## 0 by day, 1 at night. The FireflyLayer sets this from DayNight.
var night: float = 0.0

var _flies: Array[Dictionary] = [] # {pos, heading, age, life, rate, phase}; metres from this node, radians
var _rng := RandomNumberGenerator.new()
var _next: float = 0.0
## The nearest plant cell, looked up once the swarm is in a terrain; null when there is none in reach.
var _plant: Variant = null
var _plant_looked: bool = false


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	advance(delta)
	queue_redraw()


## Moves the fireflies on by delta seconds and lets a new one out when it is time.
func advance(delta: float) -> void:
	# Find the tree or bush while it still stands: it may be chopped down by day.
	plant_stands()
	for f in _flies:
		f.age += delta
		var pos: Vector2 = f.pos
		var heading: float = f.heading + _rng.randf_range(-1.0, 1.0) * TAU * wander * delta
		var to := pos + Vector2.from_angle(heading) * speed * delta
		# Turn back at the edge of its patch or at the ground.
		if to.length() > radius or _solid(to):
			heading += PI + _rng.randf_range(-0.5, 0.5)
			to = pos
		f.heading = heading
		f.pos = to
	_flies = _flies.filter(func(f: Dictionary) -> bool: return f.age < f.life)
	if _night() < 0.5:
		return
	_next -= delta
	if _next > 0.0:
		return
	_next = _rng.randf_range(spawn_interval.x, spawn_interval.y)
	if _flies.size() >= amount or not plant_stands():
		return
	for i in 8:
		var pos := Vector2.from_angle(_rng.randf() * TAU) * radius * sqrt(_rng.randf())
		if _solid(pos):
			continue
		_flies.append({
			pos = pos,
			heading = _rng.randf() * TAU,
			age = 0.0,
			life = _rng.randf_range(life.x, life.y),
			rate = _rng.randf_range(blink_rate.x, blink_rate.y),
			phase = _rng.randf(),
		})
		return


## Fireflies out now.
func count() -> int:
	return _flies.size()


## Where each firefly is, in metres from this node.
func positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for f in _flies:
		out.append(f.pos)
	return out


## False once the nearest tree or bush has been chopped down (when needs_plant is on).
func plant_stands() -> bool:
	if not needs_plant or Engine.is_editor_hint():
		return true
	var terrain := _terrain()
	if terrain == null:
		return true
	if not _plant_looked:
		_plant_looked = true
		_plant = _nearest_plant(terrain)
	return _plant == null or terrain.type_at(_plant) in plant_types


func _nearest_plant(terrain: Terrain) -> Variant:
	var home := Grid.to_m(terrain.to_local(global_position))
	var reach := ceili(plant_reach)
	var centre := Grid.cell_of(home)
	var best: Variant = null
	var best_d := INF
	for x in range(centre.x - reach, centre.x + reach + 1):
		for y in range(centre.y - reach, centre.y + reach + 1):
			var c := Vector2i(x, y)
			var d := (Vector2(c) + Vector2(0.5, 0.5)).distance_to(home)
			if d <= plant_reach and d < best_d and terrain.type_at(c) in plant_types:
				best = c
				best_d = d
	return best


func _night() -> float:
	return 1.0 if Engine.is_editor_hint() else night


## The terrain of the World or of the level this swarm is in.
func _terrain() -> Terrain:
	var world := World.of(self)
	if world:
		return world.terrain
	var n := get_parent()
	while n and not n is Level:
		n = n.get_parent()
	return (n as Level).terrain() if n else null


## Whether the spot offset metres from this node is in solid ground.
func _solid(offset: Vector2) -> bool:
	var terrain := _terrain()
	if terrain == null:
		return false
	var at := terrain.to_local(global_position + Grid.to_px(offset))
	return terrain.is_solid(Grid.cell_of(Grid.to_m(at)))


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_arc(Vector2.ZERO, Grid.to_px(Vector2(radius, 0)).x, 0.0, TAU, 48, Color(color, 0.4), 1.0)
	var t := Time.get_ticks_msec() / 1000.0
	var snap := global_position.posmod(core_px)
	for f in _flies:
		var fade := minf(1.0, minf(f.age, f.life - f.age) / 1.0)
		var blink := lerpf(dim, 1.0, pow(0.5 + 0.5 * sin(TAU * (f.rate * t + f.phase)), 2.0))
		var a := fade * blink * _night()
		if a <= 0.01:
			continue
		# On the art pixel grid of the world, not of this node.
		var p := ((Grid.to_px(f.pos) + snap) / core_px).floor() * core_px - snap
		var mid := p + Vector2.ONE * core_px / 2.0
		draw_circle(mid, glow_radius, Color(color, 0.18 * a))
		draw_circle(mid, glow_radius * 0.5, Color(color, 0.3 * a))
		draw_rect(Rect2(p, Vector2.ONE * core_px), Color(color.lightened(0.5), a))
