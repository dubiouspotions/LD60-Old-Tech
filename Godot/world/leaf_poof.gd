class_name LeafPoof
extends Node2D
## Leaves bursting from a tree as it comes down: a few per leaf cell, pushed outward from the middle of the crown,
## then fluttering down (light gravity, strong air drag, a sideways sway). Each swing of the axe while it is
## being felled shakes a few loose too. Each is gone when it touches solid ground, or after max_life. The World
## connects it to Terrain.felled and Crew.chopped.

## Terrain types whose cells shed leaves.
@export var leaf_types: Array[TerrainType] = []
## Leaves per leaf cell.
@export_range(0, 20) var per_cell: int = 5
## Leaves shaken loose by each swing of the axe.
@export_range(0, 20) var per_chop: int = 3
## Most leaves in the air at once.
@export_range(0, 500) var max_leaves: int = 80
## Outward speed of the poof, metres per second.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var poof: float = 3.5
@export_range(0.0, 30.0, 0.1, "suffix:m/s²") var gravity: float = 6.0
## Air drag: how quickly a leaf loses speed (per second). Sets how slowly it settles.
@export_range(0.0, 10.0, 0.05) var drag: float = 2.5
## Sideways sway while falling, metres per second.
@export_range(0.0, 5.0, 0.05, "suffix:m/s") var sway: float = 0.8
@export_range(0.5, 20.0, 0.1, "suffix:s") var max_life: float = 6.0
## Leaf colours; each leaf takes one (empty uses the leaf type's debris colour).
@export var colors: Array[Color] = [Color("3f6e34"), Color("5a8a3a"), Color("2e5528"), Color("7aa04a")]
## Size of a leaf in pixels (one art pixel at 4x).
@export_range(1, 16) var pixel: int = 4

var _leaves: Array[Dictionary] = [] # {pos, vel, age, rate, phase, color}; metres
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _physics_process(dt: float) -> void:
	advance(dt)
	queue_redraw()


## Leaves burst from the leaf cells among cells (a tree about to be cleared, so its types are still there).
func burst(cells: Array[Vector2i]) -> void:
	var world := World.of(self)
	if world == null:
		return
	var crown: Array[Vector2i] = []
	for c in cells:
		if world.terrain.type_at(c) in leaf_types:
			crown.append(c)
	if crown.is_empty():
		return
	var centre := Vector2.ZERO
	for c in crown:
		centre += Vector2(c) + Vector2(0.5, 0.5)
	centre /= crown.size()
	for c in crown:
		for i in per_cell:
			var p := Vector2(c) + Vector2(_rng.randf(), _rng.randf())
			var out := p - centre
			out = out.normalized() if out.length() > 0.05 else Vector2.from_angle(_rng.randf() * TAU)
			_add(p, (out * _rng.randf_range(0.5, 1.0) + Vector2(0, -0.4)) * poof, world.terrain.type_at(c))


## A swing of the axe at the tree that cell belongs to shakes per_chop leaves loose from its crown, gently.
func shake(cell: Vector2i) -> void:
	var world := World.of(self)
	if world == null:
		return
	var crown: Array[Vector2i] = []
	for c in world.terrain.tree_cells(cell):
		if world.terrain.type_at(c) in leaf_types:
			crown.append(c)
	if crown.is_empty():
		return
	for i in per_chop:
		var c := crown[_rng.randi() % crown.size()]
		var p := Vector2(c) + Vector2(_rng.randf(), _rng.randf_range(0.3, 1.0))
		_add(p, Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.1, 0.2)) * poof, world.terrain.type_at(c))


func _add(p: Vector2, vel: Vector2, from: TerrainType) -> void:
	if _leaves.size() >= max_leaves:
		return
	var tint: Color = colors[_rng.randi() % colors.size()] if not colors.is_empty() else from.debris_color
	_leaves.append({
		pos = p,
		vel = vel,
		age = 0.0,
		rate = _rng.randf_range(0.6, 1.4),
		phase = _rng.randf() * TAU,
		color = tint.lightened(_rng.randf_range(-0.1, 0.15)),
	})


## Moves the leaves on by dt seconds; drops those that touch the ground or are too old.
func advance(dt: float) -> void:
	var world := World.of(self)
	if world == null or _leaves.is_empty():
		return
	var keep: Array[Dictionary] = []
	for l in _leaves:
		l.age += dt
		var v: Vector2 = l.vel
		v.y += gravity * dt
		v *= exp(-drag * dt)
		l.vel = v
		var wobble := Vector2(sin(l.age * TAU * float(l.rate) + float(l.phase)) * sway, 0.0)
		l.pos += (v + wobble) * dt
		if l.age < max_life and not world.terrain.is_solid(Grid.cell_of(l.pos)):
			keep.append(l)
	_leaves = keep


## Leaves in the air now.
func count() -> int:
	return _leaves.size()


func positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for l in _leaves:
		out.append(l.pos)
	return out


func _draw() -> void:
	for l in _leaves:
		var p := (Grid.to_px(l.pos) / pixel).floor() * pixel
		var c: Color = l.color
		c.a = clampf((max_life - float(l.age)) / 0.5, 0.0, 1.0)
		# Tumbling: wide when it shows its face, a single pixel when edge on.
		var wide := sin(float(l.age) * TAU * float(l.rate) * 1.5 + float(l.phase)) > 0.0
		draw_rect(Rect2(p, Vector2(pixel * (2 if wide else 1), pixel)), c)
