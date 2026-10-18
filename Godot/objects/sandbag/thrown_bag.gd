class_name ThrownBag
extends Node2D
## Something an engineer threw (a sandbag): flies in an arc (CrewRules) from its hands to the cell it was thrown at,
## spinning about its centre, then becomes the falling block it carries there, which falls on and lands as usual.
## If it hits anything on the way (ground, a bridge piece, a soldier, archer, engineer or falling block) it breaks
## as its block does (FallingBlock.smash), hurting nobody; whoever it leaves the hands inside (the thrower, those beside it) it does
## not hit. The World makes it (see Crew.threw) and steps it. The node origin is the bag's centre.

## Turns per second while flying.
@export_range(0.0, 4.0, 0.1) var spin: float = 1.5
## How far around itself (metres) it hits things.
@export_range(0.0, 1.0, 0.05, "suffix:m") var hit_margin: float = 0.3

## The block it becomes on arrival (not in the tree until then).
var block: FallingBlock
var _rules: CrewRules
var _from: Vector2
var _to: Vector2
var _at: Vector2
var _time: float = 0.0
var _flight: float = 0.0
## Bodies it left the hands inside, which it does not hit; null until its first step.
var _ignored: Variant = null


## Throws block from from (metres) to the cell's centre.
func throw(from: Vector2, cell: Vector2i, rules: CrewRules, texture: Texture2D) -> void:
	_rules = rules
	_from = from
	_to = Vector2(cell) + Vector2(0.5, 0.5)
	_at = from
	_flight = rules.throw_time(_from, _to)
	position = Grid.to_px(_at)
	$Sprite.texture = texture


## Flies for dt. bodies: [[who, Bridge.Body], ...] it can hit.
func step(dt: float, world: World, bodies: Array) -> void:
	if _ignored == null:
		_ignored = bodies.filter(func(pair: Array) -> bool: return (pair[1] as Bridge.Body).touches(_from, hit_margin)).map(func(pair: Array) -> Object: return pair[0])
	var was := _at
	_time += dt
	var s := clampf(_time / _flight, 0.0, 1.0) if _flight > 0.0 else 1.0
	_at = _rules.throw_point(_from, _to, s)
	position = Grid.to_px(_at)
	$Sprite.rotation = TAU * spin * _time
	if hits_ground(world.terrain, world.bridge, was, _at) or bodies.any(func(pair: Array) -> bool: return not pair[0] in _ignored and (pair[1] as Bridge.Body).touches(_at, hit_margin)):
		_break()
		return
	if s >= 1.0:
		block.position = Grid.to_px(_to - Vector2(0.5, 0.5))
		get_parent().add_child(block)
		queue_free()


## Does a throw moving from a to b (metres) hit the ground or a built bridge piece.
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
