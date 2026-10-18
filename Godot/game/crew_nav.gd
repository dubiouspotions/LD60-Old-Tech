class_name CrewNav
extends RefCounted
## Every spot on the ground an engineer can walk to from where it stands, and the way to each: walking left and
## right, turning as often as it needs to (back off a ledge, down into the pit beside it, along the floor under
## it). It walks by one rule, next_y(y, x): the height it stands at after a step to x from height y, or NAN where
## it can not go. Spots are kept every STEP metres; the way to one is the turns along it.

const STEP: float = 0.25
## Spots on a cell edge are reached from the side the engineer comes from.
const EDGE: float = 0.01
## The search stops after this many spots, however wide the ground.
const MAX_SPOTS: int = 20000


class Spot:
	var column: int
	var y: float
	## Metres walked (along the ground, not counting climbs) to get here.
	var cost: float
	var prev: Spot


var _next_y: Callable
var _at: Dictionary = {} # column -> Array[Spot]


## Searches from start over columns between x_range.x and x_range.y (metres).
func _init(next_y: Callable, start: Vector2, x_range: Vector2) -> void:
	_next_y = next_y
	var first := _first_spot(start)
	if first == null:
		return
	var lo := ceili(x_range.x / STEP)
	var hi := floori(x_range.y / STEP)
	var seen := {_key(first.column, first.y): true}
	_add(first)
	var queue: Array[Spot] = [first]
	var head := 0
	while head < queue.size() and seen.size() < MAX_SPOTS:
		var s := queue[head]
		head += 1
		for dir: int in [-1, 1]:
			var c := s.column + dir
			if c < lo or c > hi:
				continue
			var y: float = _next_y.call(s.y, c * STEP - dir * EDGE)
			if is_nan(y):
				continue
			var key := _key(c, y)
			if seen.has(key):
				continue
			seen[key] = true
			var n := Spot.new()
			n.column = c
			n.y = y
			n.cost = s.cost + STEP
			n.prev = s
			_add(n)
			queue.append(n)


## The spots at x the engineer can get to: {x, y, cost, spot}, cheapest way first.
func spots_at(x: float) -> Array[Dictionary]:
	var c := roundi(x / STEP)
	var off := x - c * STEP
	var out: Array[Dictionary] = []
	for s: Spot in _at.get(c, []):
		var y := s.y
		if absf(off) > 0.001:
			y = _next_y.call(s.y, x - signf(off) * EDGE)
			if is_nan(y):
				continue
		out.append({x = x, y = y, cost = s.cost + absf(off), spot = s})
	return out


## The way to a spot from spots_at: the points where the walk turns round, then the spot itself.
func path(to: Dictionary) -> Array[Vector2]:
	var chain: Array[Spot] = []
	var s: Spot = to.spot
	while s:
		chain.push_front(s)
		s = s.prev
	var out: Array[Vector2] = []
	for k in range(1, chain.size() - 1):
		if signi(chain[k].column - chain[k - 1].column) != signi(chain[k + 1].column - chain[k].column):
			out.append(Vector2(chain[k].column * STEP, chain[k].y))
	out.append(Vector2(to.x, to.y))
	return out


func _first_spot(start: Vector2) -> Spot:
	var c := roundi(start.x / STEP)
	var off := c * STEP - start.x
	var y := start.y
	if absf(off) > 0.001:
		y = _next_y.call(start.y, c * STEP - signf(off) * EDGE)
		if is_nan(y):
			# The nearest column is out of reach (an edge beside the engineer): start from the one on its other side.
			c -= signi(off)
			off = c * STEP - start.x
			y = _next_y.call(start.y, c * STEP - signf(off) * EDGE)
			if is_nan(y):
				return null
	var s := Spot.new()
	s.column = c
	s.y = y
	s.cost = absf(off)
	return s


func _add(s: Spot) -> void:
	if not _at.has(s.column):
		_at[s.column] = []
	(_at[s.column] as Array).append(s)


func _key(column: int, y: float) -> Vector2i:
	return Vector2i(column, roundi(y * 100.0))
