class_name Crew
extends Node2D
## The engineers. Ordered blueprints are built one member at a time, outward from the ground or finished
## structure. Finished members stay on scaffolding until their structure is done: nothing of it left to build
## and no engineer on it. Then its scaffolding is struck and the physics decides. Separate structures (not
## joined by built or ordered members) are struck separately. Cells marked for digging are dug from a spot within reach;
## plans connected to nothing are built from a spot on the ground within reach of an end.
## Each engineer takes the closest free job of either kind; a job has one engineer at a time. While
## plans wait to be ordered, idle engineers stand ready beside them. Engineer nodes only show state. Tuning lives in CrewRules.

signal scaffolding_struck
## An engineer finished digging a marked cell. The level takes the tile and its supplies.
signal dig_finished(cell: Vector2i)
## An engineer died; count is how many are left.
signal count_changed(count: int)

## Seconds between looks for work by an idle engineer.
const THINK_INTERVAL: float = 0.2
## Engineers look this far ahead for edges and walls.
const ENGINEER_HALF_WIDTH: float = 0.2
## Joints on a cell edge are reached from the side the engineer comes from.
const EDGE: float = 0.01
## Idle engineers wait this far short of a plan's start joint.
const READY_GAP: float = 0.4


class Engineer:
	var node: Soldier
	var pos: Vector2
	var job: Bridge.Member
	## End of the job the engineer builds from.
	var goal: Bridge.Joint
	## Joints still to walk through. The first one is reached over the ground when not on the structure.
	var route: Array[Bridge.Joint] = []
	## Joint the engineer stands on, or last passed while climbing. null on the ground.
	var at: Bridge.Joint
	## Seconds until the next look for work.
	var think: float = 0.0
	## Has a cell to dig, and digs it standing at spot_x.
	var digging: bool = false
	var dig: Vector2i
	var spot_x: float
	## Working this tick (building or digging).
	var working: bool = false
	## Builds the job from the ground standing at this x (a plan not connected to anything), else NAN.
	var reach_x: float = NAN
	## Falling speed while nothing holds the engineer up.
	var vy: float = 0.0
	## Seconds the idle engineer has been unable to get back to its place.
	var stranded: float = 0.0
	## Climbs up or down any height of ground (it was stranded), until it reaches its place.
	var any_height: bool = false
	## Walks the ground beneath decks, climbing down past them (to dig a cell only reached from below one).
	var under_decks: bool = false


@export var rules: CrewRules
@export var engineer_scene: PackedScene
## Debris colours when an engineer dies.
@export var body_colors: Array[Color] = [Color("8c2f2f"), Color("ece4d2")]

var terrain: Terrain
var bridge: Bridge
var army: Army
var engineers: Array[Engineer] = []

## Where idle engineers wait for a plan to be ordered: a start joint's x, and the side they come from. NAN if none.
var _ready_x: float = NAN
var _ready_side: float = 1.0
var _ready_think: float = 0.0
var _strike_wait: Dictionary = {} # Member -> seconds its structure has been ready to strike
var _work_sound_left: float = 0.0


## Places the crew on the ground behind x.
func spawn(x: float) -> void:
	for e in engineers:
		e.node.queue_free()
	engineers.clear()
	for i in rules.crew_size:
		var e := Engineer.new()
		var ex := maxf(0.5, x - rules.follow_gap - i * rules.spacing)
		e.pos = Vector2(ex, terrain.surface_row(floori(ex)))
		e.node = engineer_scene.instantiate()
		add_child(e.node)
		engineers.append(e)
		_show(e, false, 1)


func step(dt: float) -> void:
	for e in engineers.duplicate():
		var t := _hazard_at(e)
		if t:
			_kill(e, t.death_text)
	if rules.instant_work:
		for m in bridge.members.duplicate():
			if m.blueprint and m.ordered:
				bridge.finish(m)
		for cell in terrain.marked_cells():
			dig_finished.emit(cell)
	_update_ready_spot(dt)
	for i in engineers.size():
		var e := engineers[i]
		e.working = false
		if e.at and e.at.degree == 0:
			e.at = null
			e.route.clear()
		if e.at and e.route.is_empty():
			e.pos = e.at.pos
		if _fall(e, dt):
			continue
		if e.job and (e.job.dead or not e.job.blueprint or (e.route.is_empty() and e.at != e.goal and is_nan(e.reach_x))):
			_drop(e)
		if e.digging and not terrain.is_marked(e.dig):
			e.digging = false
		e.under_decks = e.under_decks and e.digging
		if (e.job and e.goal and not _in_zone(e.goal.pos.x)) or (e.digging and not _in_zone(e.dig.x + 0.5)):
			_drop(e)
		e.think -= dt
		if e.job == null and not e.digging and e.route.is_empty() and e.think <= 0.0:
			e.think = THINK_INTERVAL
			_take_job(e)
			if e.job == null and not e.digging and e.at == null:
				e.route = _route_toward(e, _idle_x(i))
		if e.job and e.route.is_empty():
			if is_nan(e.reach_x) or _reach_step(e, dt):
				e.working = true
				_work(e, dt)
				_show(e, false, signi(roundi((e.goal.pos.x - e.pos.x) * 100)) if e.goal else 1)
		elif not e.route.is_empty():
			_follow_route(e, dt)
		elif e.at:
			e.route = _route_toward(e, _idle_x(i))
			if e.route.is_empty():
				e.route = _route_down(e.at)
			if e.route.is_empty():
				e.at = null
		elif e.digging:
			_dig_step(e, dt)
		else:
			var x := _idle_x(i)
			var was := e.pos
			_walk_to(e, x, dt)
			_update_stranded(e, x, was, dt)
	_update_strike(dt)
	_update_work_sound(dt)


## An idle engineer that has made no way toward its place x for stranded_time climbs any height until it is there.
func _update_stranded(e: Engineer, x: float, was: Vector2, dt: float) -> void:
	if absf(x - e.pos.x) <= 0.05:
		e.any_height = false
	if e.pos != was or absf(x - e.pos.x) <= 0.05 or rules.stranded_time <= 0.0:
		e.stranded = 0.0
		return
	e.stranded += dt
	e.any_height = e.any_height or e.stranded >= rules.stranded_time


## The hazard (spikes, water) the engineer's feet or body are in, else null.
func _hazard_at(e: Engineer) -> TerrainType:
	for p: Vector2 in [e.pos + Vector2(0, 0.01), e.pos - Vector2(0, 0.5)]:
		var t := terrain.type_at(Grid.cell_of(p))
		if t and t.is_hazard():
			return t
	return null


func _kill(e: Engineer, text: String) -> void:
	var at := Grid.to_px(e.pos - Vector2(0, 0.5))
	for c in body_colors:
		Effects.debris(at, c, 4, 190.0)
	Effects.say(Grid.to_px(e.pos - Vector2(0, 1.4)), text, Color("ff6a55"))
	Audio.play(rules.death_sound, at)
	e.node.queue_free()
	engineers.erase(e)
	count_changed.emit(engineers.size())


## Drops an engineer that nothing holds up (its structure fell away) and that can not simply climb down.
## True while it falls; it gives up its job.
func _fall(e: Engineer, dt: float) -> bool:
	if e.at:
		e.vy = 0.0
		return false
	# Either foot on something holds it, like a soldier standing at a cliff edge.
	var below: float = minf(army.surface_at(e.pos.x - ENGINEER_HALF_WIDTH, e.pos.y, not e.under_decks).y, army.surface_at(e.pos.x + ENGINEER_HALF_WIDTH, e.pos.y, not e.under_decks).y)
	if below - e.pos.y <= 0.02 or (e.vy == 0.0 and not is_nan(_ground_of(e, e.pos.x))):
		e.vy = 0.0
		return false
	_drop(e)
	e.vy = minf(e.vy + rules.fall_gravity * dt, rules.max_fall_speed)
	e.pos.y = minf(e.pos.y + e.vy * dt, below)
	_show(e, false, 0)
	return true


## Picks the closest job the engineer can reach. A member is reached along the structure from where the
## engineer stands, or over safe ground to a joint it can climb to and then along the structure. A marked cell is
## dug from a spot on safe ground within dig_reach. Only when nothing can be reached within max_climb and max_drop
## does it look again climbing any height of ground, and then climbs (any_height) to get there.
func _take_job(e: Engineer) -> void:
	for any_height: bool in [false, true]:
		_find_job(e, any_height)
		if e.job or e.digging:
			e.any_height = any_height
			return


func _find_job(e: Engineer, any_height: bool) -> void:
	e.reach_x = NAN
	var starts := _starts_for(e, any_height)
	var best_cost := INF
	for m in bridge.members:
		if _builder_of(m):
			continue
		for j in bridge.work_ends(m):
			if not _in_zone(j.pos.x):
				continue
			var route := bridge.route(j, starts)
			if route.is_empty() or not _in_zone(route[0].pos.x):
				continue
			var cost := _route_cost(e, route)
			if cost < best_cost:
				best_cost = cost
				e.job = m
				e.goal = j
				e.route = route
	if e.at == null:
		# A plan's loose end (not bolted, not on anything built) is built from the ground below it, also when the
		# plan's other end can be built from but is out of reach (across a pit).
		for m in bridge.members:
			if not (m.blueprint and m.ordered) or _builder_of(m):
				continue
			var ends := bridge.work_ends(m)
			for j: Bridge.Joint in [m.a, m.b]:
				if j in ends:
					continue
				var x := _spot_within_reach(e.pos, j.pos, rules.build_reach, true, any_height)
				var cost := absf(x - e.pos.x)
				if not is_nan(x) and cost < best_cost and _in_zone(x) and _in_zone(j.pos.x):
					best_cost = cost
					e.job = m
					e.goal = j
					e.route.clear()
					e.reach_x = x
		for cell in terrain.marked_cells():
			if _dig_taken(cell) or not _in_zone(cell.x + 0.5):
				continue
			var under := false
			var x := _dig_spot(e.pos, cell, true, any_height)
			if is_nan(x):
				under = true
				x = _dig_spot(e.pos, cell, false, any_height)
			var cost := absf(x - e.pos.x)
			if not is_nan(x) and cost < best_cost and _in_zone(x):
				best_cost = cost
				_drop(e)
				e.digging = true
				e.dig = cell
				e.spot_x = x
				e.under_decks = under
	if e.job and e.at:
		e.route.erase(e.at)


## Joints the engineer can start a climb from: the one it stands on, or (off the structure) any it can walk
## below and then climb up to (max_climb) or down to (max_drop), or any height with any_height.
func _starts_for(e: Engineer, any_height: bool = false) -> Callable:
	var reachable := {}
	return func(n: Bridge.Joint) -> bool:
		if e.at:
			return n == e.at
		if not reachable.has(n):
			var y := _walk_y(e.pos, n.pos.x, true, any_height)
			reachable[n] = not is_nan(y) and (any_height or (y - n.pos.y <= rules.max_climb and n.pos.y - y <= rules.max_drop))
		return reachable[n]


## Walking distance to a route's first joint plus the climb along it.
func _route_cost(e: Engineer, route: Array[Bridge.Joint]) -> float:
	var cost := absf(route[0].pos.x - e.pos.x) if e.at == null else 0.0
	for k in range(1, route.size()):
		cost += route[k - 1].pos.distance_to(route[k].pos)
	return cost


func _dig_taken(cell: Vector2i) -> bool:
	return engineers.any(func(e: Engineer) -> bool: return e.digging and e.dig == cell)


## Closest x to p on safe ground from where the cell (a tree's base for trees) is within dig_reach, or NAN.
## With decks false the engineer walks beneath decks instead of on them.
func _dig_spot(p: Vector2, cell: Vector2i, decks: bool = true, any_height: bool = false) -> float:
	return _spot_within_reach(p, Vector2(terrain.work_cell(cell)) + Vector2(0.5, 0.5), rules.dig_reach, decks, any_height)


## Closest x to p on safe ground from where target is within reach of the engineer's chest, or NAN.
func _spot_within_reach(p: Vector2, target: Vector2, reach: float, decks: bool = true, any_height: bool = false) -> float:
	var best := NAN
	for k in range(-4, 5):
		var x := target.x + k * 0.5
		var y := _walk_y(p, x, decks, any_height)
		if is_nan(y) or Vector2(x, y - 0.5).distance_to(target) > reach:
			continue
		if is_nan(best) or absf(x - p.x) < absf(best - p.x):
			best = x
	return best


## Walks to the spot below a plan's end. True once there and within reach; gives the job up if the way or
## the reach is lost.
func _reach_step(e: Engineer, dt: float) -> bool:
	var ground := _next_y(e.pos.y, e.pos.x)
	var arrived := absf(e.reach_x - e.pos.x) <= 0.05 and (is_nan(ground) or absf(ground - e.pos.y) <= 0.02)
	if not arrived:
		var was := e.pos
		_walk_to(e, e.reach_x, dt)
		if e.pos == was:
			_drop(e)
		return false
	if (e.pos - Vector2(0, 0.5)).distance_to(e.goal.pos) > rules.build_reach:
		_drop(e)
		return false
	return true


## Walks to the dig spot, then digs. Gives the job up if the way or the reach is lost.
func _dig_step(e: Engineer, dt: float) -> void:
	var ground := _ground_of(e, e.pos.x)
	var arrived := absf(e.spot_x - e.pos.x) <= 0.05 and (is_nan(ground) or absf(ground - e.pos.y) <= 0.02)
	if not arrived:
		var was := e.pos
		_walk_to(e, e.spot_x, dt)
		if e.pos == was:
			e.digging = false
		return
	var target := Vector2(terrain.work_cell(e.dig)) + Vector2(0.5, 0.5)
	if (e.pos - Vector2(0, 0.5)).distance_to(target) > rules.dig_reach:
		e.digging = false
		return
	e.working = true
	var t := terrain.type_at(e.dig)
	var done := terrain.dig_progress(e.dig) + dt * rules.dig_speed / t.dig_time
	terrain.set_dig_progress(e.dig, done)
	_show(e, false, signi(roundi((target.x - e.pos.x) * 100)))
	if done >= 1.0:
		e.digging = false
		dig_finished.emit(e.dig)


## An engineer already building m, or null.
func _builder_of(m: Bridge.Member) -> Engineer:
	for e in engineers:
		if e.job == m:
			return e
	return null


func _drop(e: Engineer) -> void:
	e.job = null
	e.goal = null
	e.route.clear()
	e.digging = false
	e.reach_x = NAN


func _work(e: Engineer, dt: float) -> void:
	var m := e.job
	m.from_joint = e.at if e.at else e.goal
	m.progress = minf(1.0, m.progress + dt * m.material.build_speed / maxf(m.length, 0.1))
	if m.progress >= 1.0:
		bridge.finish(m)
		e.job = null
		e.goal = null
		e.reach_x = NAN


## Climbs from joint to joint. Reaches the first joint over the ground when not on the structure yet.
func _follow_route(e: Engineer, dt: float) -> void:
	var target := e.route[0]
	if e.at == null and absf(target.pos.x - e.pos.x) > 0.05:
		_walk_to(e, target.pos.x, dt)
		return
	var to := target.pos - e.pos
	var stepped := rules.climb_speed * dt
	if to.length() <= stepped:
		e.pos = target.pos
		e.at = target
		e.route.pop_front()
		if e.job == null and target.pinned and e.route.is_empty():
			e.at = null
	else:
		e.pos += to.normalized() * stepped
	_show(e, true, signi(roundi(to.x * 100)))


## Route back to the ground from j: along the structure to the nearest bolted joint.
func _route_down(j: Bridge.Joint) -> Array[Bridge.Joint]:
	var r := bridge.route_from_ground(j)
	r.reverse()
	r.erase(j)
	return r


## Route over the structure to a bolted joint from where x can be walked to, for an engineer that can not
## walk there (a deck it walked out on ends in a drop). [] if the walk is clear or no such route exists.
func _route_toward(e: Engineer, x: float) -> Array[Bridge.Joint]:
	var none: Array[Bridge.Joint] = []
	if e.at == null and not is_nan(_walk_y(e.pos, x)):
		return none
	var starts := _starts_for(e)
	var best := none
	var best_cost := INF
	for n in bridge.nodes:
		if not n.pinned or n == e.at or is_nan(_walk_y(n.pos, x)):
			continue
		var route := bridge.route(n, starts)
		if route.is_empty():
			continue
		var cost := _route_cost(e, route)
		if cost < best_cost:
			best_cost = cost
			best = route
	best.erase(e.at)
	return best


## Walks along safe ground toward x: climbs to the surface first, stops at hazards, walls and drops.
func _walk_to(e: Engineer, x: float, dt: float) -> void:
	var dx := x - e.pos.x
	var facing := signi(roundi(dx * 100))
	var nx := e.pos.x + clampf(dx, -rules.walk_speed * dt, rules.walk_speed * dt)
	# Look ahead for edges, but never past the target: a joint on a cliff edge is reached from this side.
	var look := nx + signf(dx) * ENGINEER_HALF_WIDTH
	var limit := x - signf(dx) * EDGE
	if signf(dx) * (look - limit) > 0.0:
		look = limit
	var ahead := _ground_of(e, look) if absf(dx) > 0.05 else NAN
	var ground := _ground_of(e, e.pos.x)
	# Climbing the face of a higher ledge ahead: stay up on the face instead of settling back to the ground.
	var on_face := not is_nan(ahead) and not is_nan(ground) and ahead < ground - 0.02 and e.pos.y < ground
	if not is_nan(ground) and absf(ground - e.pos.y) > 0.02 and not on_face:
		e.pos.y = move_toward(e.pos.y, ground, rules.climb_speed * dt)
		_show(e, true, facing)
		return
	if absf(dx) <= 0.05:
		_show(e, false, facing)
		return
	if is_nan(ahead):
		_show(e, false, facing)
		return
	# Climb a higher ledge up its face first, then step onto it, so the body never enters the rock.
	if ahead < e.pos.y - 0.02:
		e.pos.y = move_toward(e.pos.y, ahead, rules.climb_speed * dt)
		_show(e, true, facing)
		return
	e.pos.x = nx
	_show(e, true, facing)


## Ground surface at x for an engineer standing at height y, or NAN if it can not get there:
## a hazard, a wall higher than max_climb or a drop deeper than max_drop. Built decks count as ground.
## The engineer's own level (within step_up) wins over climbing.
## With decks false the engineer walks beneath decks instead of on them.
## any_height lifts max_climb and max_drop.
func _next_y(y: float, x: float, decks: bool = true, any_height: bool = false) -> float:
	var level_y := _surface_y(y, x, rules.step_up, decks, any_height)
	return level_y if not is_nan(level_y) else _surface_y(y, x, INF if any_height else rules.max_climb, decks, any_height)


## _next_y for engineer e where it stands now, by the way it is walking (beneath decks, any height).
func _ground_of(e: Engineer, x: float) -> float:
	return _next_y(e.pos.y, x, not e.under_decks, e.any_height)


## First safe surface at x no more than up above y and (unless any_drop) max_drop below it, or NAN.
func _surface_y(y: float, x: float, up: float, decks: bool = true, any_drop: bool = false) -> float:
	var s := army.surface_at(x, y - up, decks)
	if s.hazard != null or (s.y - y > rules.max_drop and not any_drop) or terrain.is_solid(Vector2i(floori(x), floori(s.y - 0.5))):
		return NAN
	return s.y


## Height an engineer at p stands at after walking over safe ground to x, or NAN if it can not get there.
## A spot on a cell edge counts as reached from the side the engineer comes from.
func _walk_y(p: Vector2, x: float, decks: bool = true, any_height: bool = false) -> float:
	var y := p.y
	var at := p.x
	x = move_toward(x, p.x, EDGE)
	var first := true
	while first or absf(x - at) > 0.001:
		first = false
		at = move_toward(at, x, 0.25)
		y = _next_y(y, at, decks, any_height)
		if is_nan(y):
			return NAN
	return y


## Where idle engineer i stands: ready beside a plan waiting to be ordered, else behind the last soldier.
func _idle_x(i: int) -> float:
	if not is_nan(_ready_x):
		return _keep_in_zone(maxf(0.5, _ready_x - _ready_side * (READY_GAP + i * rules.spacing)))
	if army == null or army.lead() == null:
		return _keep_in_zone(engineers[i].pos.x)
	# At camp the crew waits in front of the column, never back along the sleeping line.
	if army.resting or army.hold:
		return _keep_in_zone(army.lead().pos.x + rules.follow_gap + i * rules.spacing)
	return _keep_in_zone(maxf(0.5, army.rear().pos.x - rules.follow_gap - i * rules.spacing))


## Is x within the crew's work area: anywhere the camera can be panned to show, so nobody runs off to an old
## site the player can no longer see.
func _in_zone(x: float) -> bool:
	var r := _zone()
	return x >= r.x and x <= r.y


func _keep_in_zone(x: float) -> float:
	var r := _zone()
	return clampf(x, r.x, r.y)


func _zone() -> Vector2:
	var cam := get_viewport().get_camera_2d() as CameraRig
	return cam.reach_m() if cam and cam.world else Vector2(-INF, INF)


## Strikes each structure's scaffolding once it is done and clear of engineers for strike_delay.
## Finds the start joint of a plan not yet ordered that the crew can walk to, closest first.
func _update_ready_spot(dt: float) -> void:
	_ready_think -= dt
	if _ready_think > 0.0 or engineers.is_empty():
		return
	_ready_think = THINK_INTERVAL
	_ready_x = NAN
	var from := engineers[0].pos
	var best := INF
	for m in bridge.members:
		if not m.blueprint or m.ordered:
			continue
		for j: Bridge.Joint in [m.a, m.b]:
			var d := absf(j.pos.x - from.x)
			if (j.pinned or j.built) and d < best and _in_zone(j.pos.x) and not is_nan(_walk_y(from, j.pos.x)):
				best = d
				_ready_x = j.pos.x
				_ready_side = 1.0 if j.pos.x >= from.x else -1.0


func _update_strike(dt: float) -> void:
	if not bridge.has_scaffolding():
		_strike_wait.clear()
		return
	var waiting := {}
	for group: Array in bridge.structures():
		var held: Array[Bridge.Member] = []
		held.assign(group.filter(func(m: Bridge.Member) -> bool: return m.scaffolded))
		if held.is_empty() or group.any(func(m: Bridge.Member) -> bool: return m.blueprint) or _crew_on(group):
			continue
		var wait := 0.0
		for m: Bridge.Member in group:
			wait = maxf(wait, _strike_wait.get(m, 0.0))
		wait += dt
		if wait < rules.strike_delay:
			for m: Bridge.Member in group:
				waiting[m] = wait
			continue
		bridge.strike_scaffolding(held)
		Audio.play(rules.strike_sound, Grid.to_px((held[0].a.pos + held[0].b.pos) / 2))
		scaffolding_struck.emit()
	_strike_wait = waiting


## Is an engineer standing on, climbing through or building part of this structure.
func _crew_on(group: Array) -> bool:
	var joints := {}
	for m: Bridge.Member in group:
		joints[m.a] = true
		joints[m.b] = true
	for e in engineers:
		if (e.at and joints.has(e.at)) or group.has(e.job) or e.route.any(func(j: Bridge.Joint) -> bool: return joints.has(j)):
			return true
	return false


func _update_work_sound(dt: float) -> void:
	_work_sound_left -= dt
	if _work_sound_left > 0.0:
		return
	for e in engineers:
		if e.working:
			_work_sound_left = rules.work_sound_interval
			Audio.play(rules.work_sound, Grid.to_px(e.pos))
			return


## Sideways shift that draws an engineer at p clear of a wall face beside it (on a joint bolted to the face,
## or climbing it): its position stays on the face.
func _clear_of_rock(p: Vector2) -> Vector2:
	var out := 0
	for side: int in [-1, 1]:
		if terrain.is_solid(Grid.cell_of(p + Vector2(side * ENGINEER_HALF_WIDTH, -0.3))):
			out -= side
	return Vector2(out * (ENGINEER_HALF_WIDTH + 0.05), 0.0)


func _show(e: Engineer, moving: bool, facing: int) -> void:
	e.node.pos = e.pos + _clear_of_rock(e.pos)
	e.node.moving = moving
	e.node.speed = rules.walk_speed if e.at == null else rules.climb_speed
	if facing != 0:
		e.node.facing = facing
	e.node.sync()
