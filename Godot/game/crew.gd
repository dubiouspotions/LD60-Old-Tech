class_name Crew
extends Node2D
## The engineers. Ordered blueprints are built one member at a time, outward from the ground or finished
## structure. Finished members stay on scaffolding until every engineer is back on the ground; then the
## scaffolding is struck and the physics decides. Engineer nodes only show state. Tuning lives in CrewRules.

signal scaffolding_struck

## Seconds between looks for work by an idle engineer.
const THINK_INTERVAL: float = 0.2
## Engineers look this far ahead for edges and walls.
const ENGINEER_HALF_WIDTH: float = 0.2
## Joints on a cell edge are reached from the side the engineer comes from.
const EDGE: float = 0.01


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


@export var rules: CrewRules
@export var engineer_scene: PackedScene

var terrain: Terrain
var bridge: Bridge
var army: Army
var engineers: Array[Engineer] = []

var _strike_wait: float = 0.0
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
	var working := false
	for i in engineers.size():
		var e := engineers[i]
		if e.at and e.at.degree == 0:
			e.at = null
			e.route.clear()
		if e.at and e.route.is_empty():
			e.pos = e.at.pos
		if e.job and (e.job.dead or not e.job.blueprint or (e.route.is_empty() and e.at != e.goal)):
			_drop(e)
		e.think -= dt
		if e.job == null and e.route.is_empty() and e.think <= 0.0:
			e.think = THINK_INTERVAL
			_take_job(e)
		if e.job and e.route.is_empty():
			working = true
			_work(e, dt)
			_show(e, false, 1)
		elif not e.route.is_empty():
			_follow_route(e, dt)
		elif e.at:
			e.route = _route_down(e.at)
			if e.route.is_empty():
				e.at = null
		else:
			_walk_to(e, _idle_x(i), dt)
	_update_strike(dt)
	_update_work_sound(dt, working)


## Is any engineer building or on its way to build.
func busy() -> bool:
	return engineers.any(func(e: Engineer) -> bool: return e.job != null)


## Picks the closest member the engineer can reach: along the structure from where it stands,
## or over safe ground to a bolted joint and then along the structure.
func _take_job(e: Engineer) -> void:
	var reachable := {}
	var starts := func(n: Bridge.Joint) -> bool:
		if e.at:
			return n == e.at
		if not n.pinned:
			return false
		if not reachable.has(n):
			reachable[n] = _ground_reachable(e.pos, n.pos.x)
		return reachable[n]
	var best_cost := INF
	for m in bridge.members:
		if _taken(m):
			continue
		for j in bridge.work_ends(m):
			var route := bridge.route(j, starts)
			if route.is_empty():
				continue
			var cost := absf(route[0].pos.x - e.pos.x) if e.at == null else 0.0
			for k in range(1, route.size()):
				cost += route[k - 1].pos.distance_to(route[k].pos)
			if cost < best_cost:
				best_cost = cost
				e.job = m
				e.goal = j
				e.route = route
	if e.job and e.at:
		e.route.erase(e.at)


func _taken(m: Bridge.Member) -> bool:
	return engineers.any(func(e: Engineer) -> bool: return e.job == m)


func _drop(e: Engineer) -> void:
	e.job = null
	e.goal = null
	e.route.clear()


func _work(e: Engineer, dt: float) -> void:
	var m := e.job
	m.from_joint = e.at
	m.progress = minf(1.0, m.progress + dt * rules.build_speed / maxf(m.length, 0.1))
	if m.progress >= 1.0:
		bridge.finish(m)
		e.job = null
		e.goal = null


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
		if e.job == null and target.pinned:
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


## Walks along safe ground toward x: climbs to the surface first, stops at hazards, walls and drops.
func _walk_to(e: Engineer, x: float, dt: float) -> void:
	var dx := x - e.pos.x
	var facing := signi(roundi(dx * 100))
	var ground := _next_y(e.pos.y, e.pos.x)
	if not is_nan(ground) and absf(ground - e.pos.y) > 0.02:
		e.pos.y = move_toward(e.pos.y, ground, rules.climb_speed * dt)
		_show(e, true, facing)
		return
	if absf(dx) <= 0.05:
		_show(e, false, facing)
		return
	var nx := e.pos.x + clampf(dx, -rules.walk_speed * dt, rules.walk_speed * dt)
	var look := minf(ENGINEER_HALF_WIDTH, maxf(absf(x - nx) - EDGE, 0.0))
	if is_nan(_next_y(e.pos.y, nx + signf(dx) * look)):
		_show(e, false, facing)
		return
	e.pos.x = nx
	_show(e, true, facing)


## Ground surface at x for an engineer standing at height y, or NAN if it can not get there:
## a hazard, a wall higher than max_climb or a drop deeper than max_drop. Built decks count as ground.
func _next_y(y: float, x: float) -> float:
	var s := army.surface_at(x, y - rules.max_climb)
	if s.hazard != null or s.y - y > rules.max_drop or terrain.is_solid(Vector2i(floori(x), floori(s.y - 0.5))):
		return NAN
	return s.y


## Can an engineer at p walk over safe ground to x. A joint on a cell edge counts as reached from either side.
func _ground_reachable(p: Vector2, x: float) -> bool:
	var y := p.y
	var at := p.x
	x = move_toward(x, p.x, EDGE)
	while absf(x - at) > 0.001:
		at = move_toward(at, x, 0.25)
		y = _next_y(y, at)
		if is_nan(y):
			return false
	return true


func _idle_x(i: int) -> float:
	var lead := army.lead() if army else null
	if lead == null:
		return engineers[i].pos.x
	return maxf(0.5, lead.pos.x - rules.follow_gap - i * rules.spacing)


func _update_strike(dt: float) -> void:
	var can_strike := bridge.has_scaffolding() and not busy() \
			and engineers.all(func(e: Engineer) -> bool: return e.at == null and e.route.is_empty())
	_strike_wait = _strike_wait + dt if can_strike else 0.0
	if can_strike and _strike_wait >= rules.strike_delay:
		_strike_wait = 0.0
		bridge.strike_scaffolding()
		Audio.play(rules.strike_sound, Grid.to_px(engineers[0].pos) if not engineers.is_empty() else null)
		scaffolding_struck.emit()


func _update_work_sound(dt: float, working: bool) -> void:
	_work_sound_left -= dt
	if not working or _work_sound_left > 0.0:
		return
	_work_sound_left = rules.work_sound_interval
	for e in engineers:
		if e.job and e.route.is_empty():
			Audio.play(rules.work_sound, Grid.to_px(e.pos))
			return


func _show(e: Engineer, moving: bool, facing: int) -> void:
	e.node.pos = e.pos
	e.node.moving = moving
	e.node.speed = rules.walk_speed if e.at == null else rules.climb_speed
	e.node.sync()
	if facing != 0:
		e.node.scale.x = facing
