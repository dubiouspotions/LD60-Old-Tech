class_name ThrownBag
extends Node2D
## Something an engineer threw (a sandbag): flies in an arc (CrewRules) from its hands to the cell it was thrown at,
## spinning about its centre, then becomes the falling block it carries there, which falls on and lands as usual.
## It flies through everything on the way (ground, bridge pieces, soldiers, engineers, falling blocks), so it always
## reaches its cell. Only an archer it hits, on the way or there, breaks it as its block does (FallingBlock.smash),
## hurting nobody. A soldier or engineer standing in its cell when it gets there gets it under their feet when there
## is room (FallingBlock.land_under), else it breaks on them. The World makes it (see Crew.threw) and steps it. The
## node origin is the bag's centre.

## Turns per second while flying.
@export_range(0.0, 4.0, 0.1) var spin: float = 1.5
## How far around itself (metres) it hits an archer, or someone standing in its cell.
@export_range(0.0, 1.0, 0.05, "suffix:m") var hit_margin: float = 0.3

## The block it becomes on arrival (not in the tree until then).
var block: FallingBlock
var _rules: CrewRules
var _from: Vector2
var _to: Vector2
var _at: Vector2
var _time: float = 0.0
var _flight: float = 0.0


## Throws block from from (metres) to the cell's centre.
func throw(from: Vector2, cell: Vector2i, rules: CrewRules, texture: Texture2D) -> void:
	_rules = rules
	_from = from
	_to = Vector2(cell) + Vector2(0.5, 0.5)
	_at = from
	_flight = rules.throw_time(_from, _to)
	position = Grid.to_px(_at)
	$Sprite.texture = texture


## Flies for dt. bodies: [[who, Bridge.Body], ...] it can hit (only archers, and those standing in its cell).
func step(dt: float, world: World, bodies: Array) -> void:
	var was := _at
	_time += dt
	var s := clampf(_time / _flight, 0.0, 1.0) if _flight > 0.0 else 1.0
	_at = _rules.throw_point(_from, _to, s)
	position = Grid.to_px(_at)
	$Sprite.rotation = TAU * spin * _time
	world.terrain.splash(was, _at, (_at.y - was.y) / dt if dt > 0.0 else 0.0)
	if bodies.any(func(pair: Array) -> bool: return pair[0] is Archer and (pair[1] as Bridge.Body).touches(_at, hit_margin)):
		_break()
		return
	if s >= 1.0:
		var cell_x := floori(_to.x)
		var here := bodies.filter(func(pair: Array) -> bool: return not pair[0] is FallingBlock and floori((pair[1] as Bridge.Body).center.x) == cell_x and (pair[1] as Bridge.Body).touches(_to, hit_margin))
		if not here.is_empty():
			if block.land_under(world, here[0][0]):
				block.free()
				queue_free()
			else:
				_break()
			return
		block.position = Grid.to_px(_to - Vector2(0.5, 0.5))
		get_parent().add_child(block)
		queue_free()


## Does a throw moving from a to b (metres) pass through the ground or a built bridge piece. The bag flies on
## through them; the crew only throws along a clear arc (see clear).
static func hits_ground(terrain: Terrain, bridge: Bridge, a: Vector2, b: Vector2) -> bool:
	return terrain.is_solid(Grid.cell_of(b)) or bridge.body_block(a, b) != null


## Does a throw from from to to (metres) fly clear of the ground and bridge pieces all the way.
static func clear(terrain: Terrain, bridge: Bridge, rules: CrewRules, from: Vector2, to: Vector2) -> bool:
	var steps := maxi(1, ceili(from.distance_to(to) / 0.25))
	var was := from
	for i in range(1, steps + 1):
		var at := rules.throw_point(from, to, float(i) / steps)
		if hits_ground(terrain, bridge, was, at):
			return false
		was = at
	return true


func _break() -> void:
	block.position = position - Vector2(0.5, 0.5) * Grid.PX
	get_parent().add_child(block)
	block.smash()
	queue_free()
