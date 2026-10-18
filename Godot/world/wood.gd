class_name Wood
extends Node2D
## Pieces of wood from felled trees, one per log, lying about until an engineer picks them up (see Crew). They
## tumble out of the tree, fall and come to rest on the ground. The logs count as supplies once picked up.


## One piece of wood, in metres.
class Piece:
	var pos: Vector2
	var vel: Vector2
	var resting: bool = false
	## The engineer that felled the tree: it gathers its pieces before taking other work.
	var owner: Object
	## The engineer on its way to pick it up, or null.
	var taker: Object
	## Picked up or cleared away.
	var gone: bool = false
	## Drawn mirrored, so a pile does not look copied.
	var flip: bool = false


## Pull while falling.
@export_range(1.0, 60.0, 0.5, "suffix:m/s²") var gravity: float = 18.0
## Speed out of the tree: sideways (either way) and up, at most.
@export var scatter: Vector2 = Vector2(4.0, 3.0)
## How a piece looks, drawn with its bottom edge on the ground. Some are drawn mirrored.
@export var texture: Texture2D

var pieces: Array[Piece] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _physics_process(dt: float) -> void:
	advance(dt)
	queue_redraw()


## Drops count pieces out of the tree made of cells (just felled; any cells will do as places to come from).
func drop(cells: Array[Vector2i], count: int) -> Array[Piece]:
	var out: Array[Piece] = []
	if cells.is_empty():
		return out
	for i in count:
		var p := Piece.new()
		var c := cells[_rng.randi() % cells.size()]
		p.pos = Vector2(c) + Vector2(_rng.randf_range(0.2, 0.8), _rng.randf_range(0.2, 0.8))
		p.vel = Vector2(_rng.randf_range(-scatter.x, scatter.x), -_rng.randf_range(0.0, scatter.y))
		p.flip = _rng.randf() < 0.5
		pieces.append(p)
		out.append(p)
	return out


## Lets the pieces fall by dt seconds; a falling piece stops on the first solid ground under it.
func advance(dt: float) -> void:
	var terrain := _terrain()
	if terrain == null:
		return
	for p in pieces:
		if p.resting:
			continue
		p.vel.y += gravity * dt
		var to := p.pos + p.vel * dt
		if terrain.is_solid(Grid.cell_of(Vector2(to.x, p.pos.y - 0.05))):
			to.x = p.pos.x
			p.vel.x = 0.0
		if p.vel.y > 0.0 and terrain.is_solid(Grid.cell_of(to)):
			to.y = floorf(to.y)
			p.vel = Vector2.ZERO
			p.resting = true
		p.pos = to


## Takes p away (picked up).
func remove(p: Piece) -> void:
	p.gone = true
	pieces.erase(p)


func count() -> int:
	return pieces.size()


## Clears the pieces from column x on (that ground is placed anew).
func clear_from(x: int) -> void:
	_clear(func(p: Piece) -> bool: return p.pos.x >= x)


## Clears the pieces left of column x (unloaded).
func clear_before(x: int) -> void:
	_clear(func(p: Piece) -> bool: return p.pos.x < x)


func clear_all() -> void:
	_clear(func(_p: Piece) -> bool: return true)


func _clear(hit: Callable) -> void:
	for p in pieces.duplicate():
		if hit.call(p):
			remove(p)


func _terrain() -> Terrain:
	var world := World.of(self)
	return world.terrain if world else null


func _draw() -> void:
	if texture == null:
		return
	var size := texture.get_size()
	for p in pieces:
		var foot := (Grid.to_px(p.pos) / 4.0).floor() * 4.0
		draw_set_transform(foot, 0.0, Vector2(-1.0 if p.flip else 1.0, 1.0))
		draw_texture(texture, Vector2(-size.x / 2.0, -size.y))
	draw_set_transform(Vector2.ZERO)
