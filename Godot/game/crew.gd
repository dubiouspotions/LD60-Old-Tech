class_name Crew
extends Node2D
## The engineers. Ordered blueprints are built one member at a time, outward from the ground or finished
## structure. Finished members stay on scaffolding until their structure is done: nothing of it left to build
## and no engineer on it. Then its scaffolding is struck and the physics decides. Separate structures (not
## joined by built or ordered members) are struck separately. Cells marked for digging are dug from a spot within reach;
## plans connected to nothing are built from a spot on the ground within reach of an end. Ordered throws (sandbags)
## are thrown from a standing spot at most throw_reach aside of their cell, at any height, as near throw_distance
## aside as it can be, and with a clear arc (see ThrownBag).
## Each engineer takes the closest free job of either kind; a job has one engineer at a time. While
## plans wait to be ordered, idle engineers stand ready beside them. Engineer nodes only show state. Tuning lives in CrewRules.

signal scaffolding_struck
## An engineer finished digging a marked cell. The level takes the tile and its supplies.
signal dig_finished(cell: Vector2i)
## An engineer finished taking apart a built member marked for it. The level takes it back.
signal dismantled(m: Bridge.Member)
## A swing of the axe at a tree being felled (cell), on the beat of the work sound.
signal chopped(cell: Vector2i)
## An engineer picked up a piece of wood. The level takes it and its log.
signal picked_up(piece: Wood.Piece, by: Engineer)
## An engineer threw an ordered throw from its hands at from (metres); the level sends it flying to its cell.
signal threw(order: Throw, from: Vector2)
## An engineer died; count is how many are left.
signal count_changed(count: int)

## Seconds between looks for work by an idle engineer.
const THINK_INTERVAL: float = 0.2
## Engineers look this far ahead for edges and walls.
const ENGINEER_HALF_WIDTH: float = 0.2
## Joints on a cell edge are reached from the side the engineer comes from.
const EDGE: float = 0.01
## A piece of wood is picked up from at most this far above or below the engineer's feet.
const FETCH_HEIGHT: float = 1.2
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
	## The way from its chest to what it digs, chops, builds or takes apart this tick, else zero: it jolts that way
	## on each blow.
	var blow_dir: Vector2 = Vector2.ZERO
	## Drawn this far from pos (a builder hopping about its piece, see CrewRules.build_wander); the piece it hops
	## on, the spot it stands at till the next hop (metres along the piece from where it builds from), and seconds
	## to that hop.
	var shown: Vector2 = Vector2.ZERO
	## Tilt towards where its piece grows (see CrewRules.build_lean_max), and the way it faces it (0: as it was).
	var lean: float = 0.0
	var lean_face: int = 0
	var wander_job: Bridge.Member
	var wander_along: float = 0.0
	var wander_left: float = 0.0
	## Seconds to the next swing of the axe while felling.
	var chop_wait: float = 0.0
	## Builds the job from the ground standing at this x (a plan not connected to anything), else NAN.
	var reach_x: float = NAN
	## Falling speed while nothing holds the engineer up.
	var vy: float = 0.0
	## Seconds the idle engineer has been unable to get back to its place.
	var stranded: float = 0.0
	## Climbs up or down any height of ground (it was stranded), until it reaches its place.
	var any_height: bool = false
	## Stranded and still no way back after stuck_time more, climbing any height (see stuck_count).
	var stuck: bool = false
	## Walks the ground beneath decks, climbing down past them (to dig a cell only reached from below one).
	var under_decks: bool = false
	## Pieces of wood from the tree it felled, still to pick up. It takes no other work until they are in.
	var gather: Array[Wood.Piece] = []
	## The piece it is on its way to pick up, or null; how long it has been going for it, and stooping over it.
	var fetch: Wood.Piece
	var fetch_time: float = 0.0
	var stoop: float = 0.0
	## The throw it has taken, thrown standing at spot_x; null if none.
	var throwing: Throw
	## The turns of its walk to the spot of its job (see CrewNav.path), walked one after another.
	var path: Array[Vector2] = []
	## Where it can walk (CrewNav) by way of walking, kept while it stands at nav_from and the ground is as it was.
	var navs: Dictionary = {}
	var nav_from: Vector2 = Vector2.INF
	var nav_ground: Vector3i


## Something (a sandbag) ordered onto cell by a thrown Fill tool, waiting for an engineer to throw it there.
class Throw:
	var cell: Vector2i
	var tool: ToolDefinition
	## The engineer on its way to throw it, or null.
	var taker: Engineer
	## Seconds it has wound up to throw.
	var windup: float = 0.0


@export var rules: CrewRules
@export var engineer_scene: PackedScene
## Debris colours when an engineer dies.
@export var body_colors: Array[Color] = [Color("8c2f2f"), Color("ece4d2")]

var terrain: Terrain:
	set(v):
		if terrain:
			terrain.cell_changed.disconnect(_on_ground_changed)
		terrain = v
		if terrain:
			terrain.cell_changed.connect(_on_ground_changed)
var bridge: Bridge
var army: Army
var wood: Wood
var engineers: Array[Engineer] = []
## Throws ordered and not thrown yet.
var throws: Array[Throw] = []

## Where idle engineers wait for a plan to be ordered: a start joint's x, and the side they come from. NAN if none.
var _ready_x: float = NAN
var _ready_side: float = 1.0
var _ready_think: float = 0.0
var _strike_wait: Dictionary = {} # Member -> seconds its structure has been ready to strike
var _work_sound_left: float = 0.0
var _rng := RandomNumberGenerator.new()
## The engineer that last finished digging, while dig_finished is handled.
var _finisher: Engineer
## Cells of ground changed so far, so the engineers know their CrewNav is out of date.
var _ground_changes: int = 0


## Places the crew on the ground behind x.
func spawn(x: float, count: int = 0) -> void:
	for e in engineers:
		e.node.queue_free()
	engineers.clear()
	throws.clear()
	for i in count if count > 0 else rules.crew_size:
		_add(maxf(0.5, x - rules.follow_gap - i * rules.spacing))
	count_changed.emit(engineers.size())


## One more engineer joins the crew, on the ground at x (hired at camp).
func hire(x: float) -> Engineer:
	var e := _add(x)
	count_changed.emit(engineers.size())
	return e


func _add(x: float) -> Engineer:
	var e := Engineer.new()
	e.pos = Vector2(x, terrain.surface_row(floori(x)))
	e.node = engineer_scene.instantiate()
	add_child(e.node)
	engineers.append(e)
	_show(e, false, 1)
	return e


func step(dt: float) -> void:
	for e in engineers.duplicate():
		var t := _hazard_at(e)
		if t:
			_kill(e, t.death_text)
	if rules.instant_work:
		for m in bridge.members.duplicate():
			if m.blueprint and m.ordered:
				bridge.finish(m)
			elif bridge.needs_work(m):
				dismantled.emit(m)
		_finisher = null
		for cell in terrain.marked_cells():
			dig_finished.emit(cell)
		if wood:
			for p in wood.pieces.duplicate():
				picked_up.emit(p, null)
		for t in throws.duplicate():
			_throw(t, Vector2(t.cell) + Vector2(0.5, 0.5))
	_update_ready_spot(dt)
	for i in engineers.size():
		var e := engineers[i]
		e.working = false
		e.blow_dir = Vector2.ZERO
		e.lean_face = 0
		if e.shown != Vector2.ZERO or e.lean != 0.0:
			# Pops back where it is, upright (a builder hopping about pops to its next spot below, if still at it).
			e.shown = Vector2.ZERO
			e.lean = 0.0
			_show(e, e.node.moving, 0)
		if e.at and e.at.degree == 0:
			_let_go(e)
			e.route.clear()
		if e.at and e.route.is_empty():
			e.pos = e.at.pos
		if _fall(e, dt):
			continue
		if e.job and (not bridge.needs_work(e.job) or (e.route.is_empty() and e.at != e.goal and is_nan(e.reach_x))):
			_drop(e)
		if e.digging and not terrain.is_marked(e.dig):
			e.digging = false
		e.under_decks = e.under_decks and (e.digging or e.fetch != null)
		if (e.job and e.goal and not _in_zone(e.goal.pos.x)) or (e.digging and not _in_zone(e.dig.x + 0.5)):
			_drop(e)
		_prune_gather(e)
		if not _busy(e) and e.route.is_empty() and e.at == null and (_gathering(e) or _offer_help(e)):
			_gather_step(e, dt)
			continue
		e.think -= dt
		if not _busy(e) and e.route.is_empty() and e.think <= 0.0 and not _gathering(e):
			e.think = THINK_INTERVAL
			_take_job(e)
			if not _busy(e) and e.at == null:
				e.route = _route_toward(e, _idle_x(i))
		elif e.think <= 0.0 and _en_route(e):
			e.think = THINK_INTERVAL
			_rethink(e)
		if e.job and e.route.is_empty():
			if is_nan(e.reach_x) or _reach_step(e, dt):
				e.working = true
				_wander(e, dt)
				_work(e, dt)
				_show(e, false, signi(roundi((e.goal.pos.x - e.pos.x) * 100)) if e.goal else 1)
		elif not e.route.is_empty():
			_follow_route(e, dt)
		elif e.at:
			e.route = _route_toward(e, _idle_x(i))
			if e.route.is_empty():
				e.route = _route_down(e.at)
			if e.route.is_empty():
				_let_go(e)
		elif e.digging:
			_dig_step(e, dt)
		elif e.throwing:
			_throw_step(e, dt)
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
		e.stuck = false
		return
	e.stranded += dt
	e.any_height = e.any_height or e.stranded >= rules.stranded_time
	e.stuck = e.stranded >= rules.stranded_time + rules.stuck_time


## Engineers that have no way back to the column at all (see CrewRules.stuck_time).
func stuck_count() -> int:
	return engineers.filter(func(e: Engineer) -> bool: return e.stuck).size()


## The hazard (spikes, water) the engineer's body is in, else null (see Terrain.hazard_for_body).
func _hazard_at(e: Engineer) -> TerrainType:
	return terrain.hazard_for_body(e.pos)


## Kills an engineer crushed by something heavy (a falling tower or tree).
func crush(e: Engineer) -> void:
	_kill(e, rules.crushed_text)


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
## Can the engineer, not falling, stay where it is: ground it can climb to under it, or beside it (it clings to a
## cliff face it can climb, like one it was building from).
func _can_hold_on(e: Engineer) -> bool:
	for dx: float in [0.0, -ENGINEER_HALF_WIDTH, ENGINEER_HALF_WIDTH]:
		if not is_nan(_ground_of(e, e.pos.x + dx)):
			return true
	return false


func _fall(e: Engineer, dt: float) -> bool:
	if e.at:
		e.vy = 0.0
		return false
	# Either foot on something holds it, like a soldier standing at a cliff edge. A hazard holds neither: it falls in.
	var below := INF
	for dx: float in [-ENGINEER_HALF_WIDTH, ENGINEER_HALF_WIDTH]:
		var s := army.surface_at(e.pos.x + dx, e.pos.y, not e.under_decks)
		if s.hazard == null:
			below = minf(below, s.y)
	if below - e.pos.y <= 0.02 or (e.vy == 0.0 and _can_hold_on(e)):
		e.vy = 0.0
		return false
	_drop(e)
	e.vy = minf(e.vy + rules.fall_gravity * dt, rules.max_fall_speed)
	var was := e.pos
	e.pos.y = minf(e.pos.y + e.vy * dt, below)
	terrain.splash(was, e.pos, e.vy)
	_show(e, false, 0)
	return true


## Picks the most urgent job the engineer can reach (see _urgency). A member is reached along the structure from
## where the engineer stands, or over safe ground to a joint it can climb to and then along the structure. A marked
## cell is dug from a spot on safe ground within dig_reach. Only when nothing can be reached within max_climb and
## max_drop does it look again climbing any height of ground, and then climbs (any_height) to get there.
func _take_job(e: Engineer) -> void:
	for any_height: bool in [false, true]:
		_find_job(e, any_height)
		if _busy(e):
			e.any_height = any_height
			return


func _find_job(e: Engineer, any_height: bool) -> void:
	_drop(e)
	var best := _most_urgent(_jobs_for(e, any_height))
	if not best.is_empty():
		best.take.call()
	if e.job and e.at:
		e.route.erase(e.at)


## On its way to a job, the engineer takes a more urgent one instead if it is nearer to it than the one it is
## going to.
func _rethink(e: Engineer) -> void:
	var mine: Variant = e.dig if e.digging else (e.throwing if e.throwing else e.job)
	var jobs := _jobs_for(e, e.any_height)
	var current := {}
	for j in jobs:
		if is_same(j.what, mine):
			current = j
	if current.is_empty():
		return
	var better := _most_urgent(jobs.filter(func(j: Dictionary) -> bool:
		return _urgency(j.x) < _urgency(current.x) and j.cost < current.cost))
	if not better.is_empty():
		better.take.call()
		if e.job and e.at:
			e.route.erase(e.at)


## Has a job and is still on the ground on its way to it.
func _en_route(e: Engineer) -> bool:
	if e.at != null or not _busy(e):
		return false
	if e.job and is_nan(e.reach_x):
		return not e.route.is_empty()
	var x := e.reach_x if e.job else e.spot_x
	return not e.path.is_empty() or absf(x - e.pos.x) > 0.05


## How urgent a job at x is, lower first: the nearer ahead of the column's leader, the sooner it is in the way.
## Jobs behind the leader come after every job ahead, nearest first. In half-metre steps, so a shorter walk
## decides between jobs about as urgent.
func _urgency(x: float) -> int:
	var lead := army.lead()
	if lead == null:
		return 0
	var ahead := x - lead.pos.x
	return roundi((ahead if ahead >= -1.0 else 1000.0 - ahead) * 2.0)


## The most urgent of jobs (see _jobs_for), the shortest way between those as urgent, or {}.
func _most_urgent(jobs: Array) -> Dictionary:
	var best := {}
	for j: Dictionary in jobs:
		if best.is_empty() or _urgency(j.x) < _urgency(best.x) or (_urgency(j.x) == _urgency(best.x) and j.cost < best.cost):
			best = j
	return best


## Every job engineer e can reach and nobody else has: {x: where the job is, cost: metres of the way there, what: the
## member, cell or throw, take: gives it to e}.
func _jobs_for(e: Engineer, any_height: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var starts := _starts_for(e, any_height)
	for m in bridge.members:
		var builder := _builder_of(m)
		if builder and builder != e:
			continue
		for j in bridge.work_ends(m):
			if not _in_zone(j.pos.x):
				continue
			var route := bridge.route(j, starts)
			if route.is_empty() or not _in_zone(route[0].pos.x):
				continue
			out.append({x = j.pos.x, cost = _route_cost(e, route), what = m, take = func() -> void:
				_drop(e)
				e.job = m
				e.goal = j
				e.route = route})
	if e.at != null:
		return out
	# A plan's loose end (not bolted, not on anything built) is built from the ground below it, also when the
	# plan's other end can be built from but is out of reach (across a pit).
	for m in bridge.members:
		var builder := _builder_of(m)
		if not (m.blueprint and m.ordered) or (builder and builder != e):
			continue
		var ends := bridge.work_ends(m)
		for j: Bridge.Joint in [m.a, m.b]:
			if j in ends:
				continue
			var spot := _spot_within_reach(_nav(e, true, any_height), j.pos, rules.build_reach)
			if spot.is_empty() or not _in_zone(spot.x) or not _in_zone(j.pos.x):
				continue
			out.append({x = j.pos.x, cost = spot.cost, what = m, take = func() -> void:
				_drop(e)
				e.job = m
				e.goal = j
				e.reach_x = spot.x
				e.path = spot.path})
	for cell in terrain.marked_cells():
		if _dig_taken(cell, e) or not _in_zone(cell.x + 0.5):
			continue
		var under := false
		var spot := _dig_spot(_nav(e, true, any_height), cell)
		if spot.is_empty():
			under = true
			spot = _dig_spot(_nav(e, false, any_height), cell)
		if spot.is_empty() or not _in_zone(spot.x):
			continue
		out.append({x = cell.x + 0.5, cost = spot.cost, what = cell, take = func() -> void:
			_drop(e)
			e.digging = true
			e.dig = cell
			e.spot_x = spot.x
			e.path = spot.path
			e.under_decks = under})
	for t in throws:
		if (t.taker and t.taker != e) or not _in_zone(t.cell.x + 0.5):
			continue
		var spot := _throw_spot(_nav(e, true, any_height), t.cell)
		if spot.is_empty() or not _in_zone(spot.x):
			continue
		out.append({x = t.cell.x + 0.5, cost = spot.cost, what = t, take = func() -> void:
			_drop(e)
			e.throwing = t
			t.taker = e
			e.spot_x = spot.x
			e.path = spot.path})
	return out


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


## Somebody (other than except) is digging cell.
func _dig_taken(cell: Vector2i, except: Engineer = null) -> bool:
	return engineers.any(func(e: Engineer) -> bool: return e != except and e.digging and e.dig == cell)


## The nearest spot nav can walk to from where the cell (a tree's base for trees) is within dig_reach (see
## _spot_within_reach), or {}.
func _dig_spot(nav: CrewNav, cell: Vector2i) -> Dictionary:
	return _spot_within_reach(nav, Vector2(terrain.work_cell(cell)) + Vector2(0.5, 0.5), rules.dig_reach)


## The nearest spot on safe ground nav can walk to from where target is within reach of the engineer's chest:
## {x, y, cost (metres walked), path (CrewNav.path)}, or {}.
func _spot_within_reach(nav: CrewNav, target: Vector2, reach: float) -> Dictionary:
	var best := {}
	for k in range(-4, 5):
		var x := target.x + k * 0.5
		for s in nav.spots_at(x):
			if Vector2(x, s.y - 0.5).distance_to(target) <= reach and (best.is_empty() or s.cost < best.cost):
				best = s
	if not best.is_empty():
		best.path = nav.path(best)
	return best


## Where engineer e can walk from where it stands, by way of walking: on or beneath decks, and any height. Kept
## until it moves or the ground or the bridge changes.
func _nav(e: Engineer, decks: bool, any_height: bool) -> CrewNav:
	var built := 0
	for m in bridge.members:
		if not m.blueprint:
			built += 1
	var ground := Vector3i(_ground_changes, bridge.members.size(), built)
	if e.nav_from.distance_to(e.pos) > 0.01 or e.nav_ground != ground:
		e.navs.clear()
		e.nav_from = e.pos
		e.nav_ground = ground
	var key := Vector2i(int(decks), int(any_height))
	if not e.navs.has(key):
		var z := _zone()
		var span := Vector2(maxf(z.x, terrain.min_x), minf(z.y, terrain.size.x))
		e.navs[key] = CrewNav.new(func(y: float, x: float) -> float: return _next_y(y, x, decks, any_height), e.pos, span)
	return e.navs[key]


func _on_ground_changed(_cell: Vector2i) -> void:
	_ground_changes += 1


## Drops the turns of e's path it has reached: at a turn's x, at its height or settled on the ground there (it got
## down off a deck at the turn itself, a step before the way did).
func _trim_path(e: Engineer) -> void:
	while not e.path.is_empty() and absf(e.path[0].x - e.pos.x) <= 0.05 and (absf(e.path[0].y - e.pos.y) <= 0.05 or _settled(e)):
		e.path.pop_front()


## Stands on the ground (or deck) under it, by the way it is walking.
func _settled(e: Engineer) -> bool:
	var ground := _ground_of(e, e.pos.x)
	return not is_nan(ground) and absf(ground - e.pos.y) <= 0.02


## Walks e toward the next turn of its path, or toward x once all of it is behind.
func _walk_on(e: Engineer, x: float, dt: float) -> void:
	_walk_to(e, e.path[0].x if not e.path.is_empty() else x, dt)


## Walks to the spot below a plan's end. True once there and within reach; gives the job up if the way or
## the reach is lost.
func _reach_step(e: Engineer, dt: float) -> bool:
	var ground := _next_y(e.pos.y, e.pos.x)
	_trim_path(e)
	var arrived := e.path.is_empty() and absf(e.reach_x - e.pos.x) <= 0.05 and (is_nan(ground) or absf(ground - e.pos.y) <= 0.02)
	if not arrived:
		var was := e.pos
		_walk_on(e, e.reach_x, dt)
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
	_trim_path(e)
	var arrived := e.path.is_empty() and absf(e.spot_x - e.pos.x) <= 0.05 and (is_nan(ground) or absf(ground - e.pos.y) <= 0.02)
	if not arrived:
		var was := e.pos
		_walk_on(e, e.spot_x, dt)
		if e.pos == was:
			e.digging = false
		return
	var target := Vector2(terrain.work_cell(e.dig)) + Vector2(0.5, 0.5)
	if (e.pos - Vector2(0, 0.5)).distance_to(target) > rules.dig_reach:
		e.digging = false
		return
	e.working = true
	e.blow_dir = target - (e.pos - Vector2(0, 0.5))
	var t := terrain.type_at(e.dig)
	var done := terrain.dig_progress(e.dig) + dt * rules.dig_speed / t.dig_time
	terrain.set_dig_progress(e.dig, done)
	if t.dig_action == TerrainType.DigAction.FELL:
		e.chop_wait -= dt
		if e.chop_wait <= 0.0:
			e.chop_wait = rules.work_sound_interval
			chopped.emit(e.dig)
	_show(e, false, signi(roundi((target.x - e.pos.x) * 100)))
	if done >= 1.0:
		_final_blow(e)
		e.digging = false
		_finisher = e
		dig_finished.emit(e.dig)
		_finisher = null


## Has a job of any kind: building, digging or throwing.
func _busy(e: Engineer) -> bool:
	return e.job != null or e.digging or e.throwing != null


## Orders tool's thing thrown onto cell. Returns the order.
func order_throw(cell: Vector2i, tool: ToolDefinition) -> Throw:
	var t := Throw.new()
	t.cell = cell
	t.tool = tool
	throws.append(t)
	return t


## The throw ordered onto cell, or null.
func throw_at(cell: Vector2i) -> Throw:
	for t in throws:
		if t.cell == cell:
			return t
	return null


## Takes a throw order back (it was not thrown).
func cancel_throw(t: Throw) -> void:
	if t.taker:
		_drop(t.taker)
	throws.erase(t)


## The spot on safe ground nav can walk to from where an engineer throws at cell: at most throw_reach aside of it
## (any height) and not under it (what it throws falls from there), as near throw_distance aside as it can be
## without a long way round (a quarter of the walk counts against a spot), and with a clear arc. {} if none, else
## as _spot_within_reach.
func _throw_spot(nav: CrewNav, cell: Vector2i) -> Dictionary:
	var target := Vector2(cell) + Vector2(0.5, 0.5)
	var best := {}
	var best_score := INF
	for k in range(-floori(rules.throw_reach * 2.0), floori(rules.throw_reach * 2.0) + 1):
		var x := target.x + k * 0.5
		var aside := absf(x - target.x)
		if aside < 0.75:
			continue
		for s in nav.spots_at(x):
			var score: float = absf(aside - rules.throw_distance) + 0.25 * s.cost
			if score >= best_score or not ThrownBag.clear(terrain, bridge, rules, _hands(Vector2(x, s.y)), target):
				continue
			best = s
			best_score = score
	if not best.is_empty():
		best.path = nav.path(best)
	return best


## Where an engineer standing at pos (metres) holds what it throws.
func _hands(pos: Vector2) -> Vector2:
	return pos - Vector2(0, 1.0)


## Walks to the throwing spot, faces the target, winds up and throws. Gives the throw up if the way is lost.
func _throw_step(e: Engineer, dt: float) -> void:
	var t := e.throwing
	var target := Vector2(t.cell) + Vector2(0.5, 0.5)
	var ground := _ground_of(e, e.pos.x)
	_trim_path(e)
	var arrived := e.path.is_empty() and absf(e.spot_x - e.pos.x) <= 0.05 and (is_nan(ground) or absf(ground - e.pos.y) <= 0.02)
	if not arrived:
		var was := e.pos
		_walk_on(e, e.spot_x, dt)
		if e.pos == was:
			_drop(e)
		return
	e.working = true
	_show(e, false, signi(roundi((target.x - e.pos.x) * 100)))
	t.windup += dt
	if t.windup >= rules.throw_windup:
		e.throwing = null
		_throw(t, _hands(e.pos))


func _throw(t: Throw, from: Vector2) -> void:
	throws.erase(t)
	t.taker = null
	threw.emit(t, from)


## The engineer that has just finished digging cell (while dig_finished is handled), or null.
func finisher_of(cell: Vector2i) -> Engineer:
	return _finisher if _finisher and _finisher.dig == cell and _finisher in engineers else null


## Gives e the pieces of wood from the tree it felled to pick up.
func gather(e: Engineer, pieces: Array[Wood.Piece]) -> void:
	for p in pieces:
		p.owner = e
	e.gather.append_array(pieces)


## Has wood of its own to pick up, or is fetching a piece.
func _gathering(e: Engineer) -> bool:
	return not e.gather.is_empty() or e.fetch != null


func _prune_gather(e: Engineer) -> void:
	e.gather = e.gather.filter(func(p: Wood.Piece) -> bool: return not p.gone)
	if e.fetch and e.fetch.gone:
		e.fetch = null


## An idle engineer goes for a nearby piece nobody is fetching. True if it found one.
func _offer_help(e: Engineer) -> bool:
	if wood == null:
		return false
	var best: Wood.Piece = null
	var best_d := rules.help_radius
	for p in wood.pieces:
		var d := absf(p.pos.x - e.pos.x)
		if p.taker == null and d <= best_d:
			best = p
			best_d = d
	if best:
		_set_fetch(e, best)
	return best != null


func _set_fetch(e: Engineer, p: Wood.Piece) -> void:
	e.fetch = p
	e.fetch_time = 0.0
	e.stoop = 0.0
	e.path.clear()
	p.taker = e


## Sets e's path to a spot by the piece it fetches, on decks or (if only that way) beneath them: down a deck to
## where the ground beneath is within reach, then under it. Keeps walking straight at it if there is no such spot
## (yet: the piece may still be falling).
func _route_fetch(e: Engineer, p: Wood.Piece) -> void:
	for decks: bool in [true, false]:
		var nav := _nav(e, decks, e.any_height)
		var best := {}
		for dx: float in [0.0, -0.25, 0.25]:
			for s in nav.spots_at(p.pos.x + dx):
				if absf(s.y - p.pos.y) <= FETCH_HEIGHT and (best.is_empty() or s.cost < best.cost):
					best = s
		if not best.is_empty():
			e.path = nav.path(best)
			e.under_decks = not decks
			return


## Goes for the next of its own pieces (or the one it is fetching), and picks it up when there.
func _gather_step(e: Engineer, dt: float) -> void:
	if e.fetch == null:
		var best: Wood.Piece = null
		for p in e.gather:
			if p.taker == null and (best == null or absf(p.pos.x - e.pos.x) < absf(best.pos.x - e.pos.x)):
				best = p
		if best == null:
			# The rest are being fetched by helpers: wait for them.
			_show(e, false, 0)
			return
		_set_fetch(e, best)
	var p := e.fetch
	e.fetch_time += dt
	if e.fetch_time >= rules.gather_give_up:
		_pick(e, p)
		return
	_trim_path(e)
	var there := absf(p.pos.x - e.pos.x) <= rules.pickup_reach and absf(p.pos.y - e.pos.y) <= FETCH_HEIGHT
	e.think -= dt
	if not there and e.path.is_empty() and p.resting and e.think <= 0.0:
		e.think = THINK_INTERVAL
		_route_fetch(e, p)
	if not e.path.is_empty() or absf(p.pos.x - e.pos.x) > rules.pickup_reach:
		_walk_on(e, p.pos.x, dt)
		return
	if not p.resting or not there:
		_show(e, false, 0)
		return
	e.stoop += dt
	_show(e, false, signi(roundi((p.pos.x - e.pos.x) * 100)))
	if e.stoop >= rules.pickup_time:
		_pick(e, p)


func _pick(e: Engineer, p: Wood.Piece) -> void:
	Audio.play(rules.pickup_sound, Grid.to_px(p.pos))
	e.fetch = null
	e.stoop = 0.0
	p.taker = null
	e.gather.erase(p)
	if p.owner:
		(p.owner as Engineer).gather.erase(p)
	picked_up.emit(p, e)


## An engineer already building m, or null.
func _builder_of(m: Bridge.Member) -> Engineer:
	for e in engineers:
		if e.job == m:
			return e
	return null


func _drop(e: Engineer) -> void:
	if e.throwing:
		e.throwing.taker = null
		e.throwing.windup = 0.0
		e.throwing = null
	e.job = null
	e.goal = null
	e.route.clear()
	e.digging = false
	e.reach_x = NAN
	e.path.clear()


## Builds the member it has the job of on, or takes it apart if it is marked for that.
func _work(e: Engineer, dt: float) -> void:
	var m := e.job
	m.from_joint = e.at if e.at else e.goal
	var step := dt * m.material.build_speed / maxf(m.length, 0.1)
	if m.dismantle:
		m.progress = maxf(0.0, m.progress - step)
	else:
		m.progress = minf(1.0, m.progress + step)
	# It works at the end of what is built so far.
	var far := m.b if m.from_joint == m.a else m.a
	e.blow_dir = m.from_joint.pos.lerp(far.pos, m.progress) - (e.pos + e.shown - Vector2(0, 0.5))
	if m.progress > 0.0 and m.progress < 1.0:
		return
	_final_blow(e)
	e.job = null
	e.goal = null
	e.reach_x = NAN
	if m.dismantle:
		dismantled.emit(m)
	else:
		bridge.finish(m)


## Where a builder working out from a joint is drawn: a spot on the built part of its piece, at most build_wander
## back from where it grows, popping to a new one every build_wander_interval. A builder on the ground (reach_x)
## stays put.
func _wander(e: Engineer, dt: float) -> void:
	var m := e.job
	if not is_nan(e.reach_x) or m.length <= 0.0:
		return
	var built := m.progress * m.length
	e.wander_left -= dt
	if e.wander_job != m or e.wander_left <= 0.0:
		# Hops to a new spot and stays there until the next hop (it does not slide along as the piece grows).
		e.wander_left = rules.build_wander_interval
		var lo := maxf(built - rules.build_wander, 0.0)
		var was := e.wander_along if e.wander_job == m else -INF
		# A clear jump away from the last spot, back or forth, where the built part leaves room for one.
		var spot := _rng.randf_range(lo, built)
		for k in 8:
			if absf(spot - was) >= rules.build_hop:
				break
			spot = _rng.randf_range(lo, built)
		e.wander_along = spot
		e.wander_job = m
	# Taken apart below it meanwhile: it stands on what is left.
	e.wander_along = minf(e.wander_along, built)
	var from := e.at if e.at else e.goal
	var far := m.b if from == m.a else m.a
	e.shown = from.pos.lerp(far.pos, e.wander_along / m.length) - e.pos
	# Face where it grows and tilt that way: its front (+x when facing right) points at it, as far as the max lets.
	# Right over it, there is no way to face: it keeps the last.
	var to := from.pos.lerp(far.pos, m.progress) - (e.pos + e.shown - Vector2(0, 0.5))
	if absf(to.x) > 0.05:
		var most := deg_to_rad(rules.build_lean_max)
		e.lean = clampf(atan(to.y / to.x), -most, most)
		e.lean_face = signi(roundi(to.x * 100))
	else:
		e.lean = e.node.lean


## The blow that finishes a job (the cell breaks, the piece is put in place): a jolt with the sound of it.
func _final_blow(e: Engineer) -> void:
	if e.blow_dir != Vector2.ZERO:
		e.node.work_blow(e.blow_dir)


## Takes the engineer off the joint it holds. A joint bolted to a wall lies on the wall's line, which counts as the
## wall; the engineer steps to its open side, so the ground under it is the ground there and not the wall's top.
func _let_go(e: Engineer) -> void:
	e.at = null
	for side: int in [-1, 1]:
		var wall := terrain.is_solid(Grid.cell_of(e.pos + Vector2(side * EDGE, -0.3)))
		var open := not terrain.is_solid(Grid.cell_of(e.pos + Vector2(-side * EDGE, -0.3)))
		if wall and open:
			e.pos.x -= side * EDGE * 2.0
			return


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
			_let_go(e)
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
	# Climb a higher ledge up its face first, then step onto it, so the body never enters the rock. Ground rising
	# no steeper than 45 degrees (a slope up a step) is walked instead, from the ground (not part way up a face).
	var slope := absf(look - e.pos.x) if not on_face else 0.0
	# Up a face only to the foot of a slope on top of it (the ledge's edge), then up the slope on foot, so the engineer
	# never hangs higher over the ground behind it than it can hold on at.
	var top := ahead
	if on_face and terrain.ramp_at(Vector2i(floori(look), ceili(ahead) - 1)) != 0:
		top = ceilf(ahead)
	if top < e.pos.y - 0.02 - slope:
		e.pos.y = move_toward(e.pos.y, top, rules.climb_speed * dt)
		_show(e, true, facing)
		return
	var step := absf(nx - e.pos.x)
	e.pos.x = nx
	var along := _ground_of(e, nx)
	if not is_nan(along) and absf(along - e.pos.y) <= step + 0.02:
		e.pos.y = along
	_show(e, true, facing)


## Ground surface at x for an engineer standing at height y, or NAN if it can not get there:
## a hazard, a wall higher than max_climb or a drop deeper than max_drop. Built decks count as ground.
## The engineer's own level (within step_up) wins over climbing.
## With decks false the engineer walks beneath decks instead of on them. A deck over ground it can not get to
## (too far down, or a hazard) it walks along, to get down past it where the ground beneath is within reach.
## any_height lifts max_climb and max_drop.
func _next_y(y: float, x: float, decks: bool = true, any_height: bool = false) -> float:
	var level_y := _surface_y(y, x, rules.step_up, decks, any_height)
	var out := level_y if not is_nan(level_y) else _surface_y(y, x, INF if any_height else rules.max_climb, decks, any_height)
	if is_nan(out) and not decks:
		return _next_y(y, x, true, any_height)
	return out


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
			# Everyone at work strikes on the blow you hear.
			for d in engineers:
				if d.blow_dir != Vector2.ZERO:
					d.node.work_blow(d.blow_dir)
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
	e.node.pos = e.pos + e.shown + _clear_of_rock(e.pos + e.shown)
	e.node.moving = moving
	e.node.lean = e.lean
	if e.lean_face != 0:
		facing = e.lean_face
	e.node.speed = rules.walk_speed if e.at == null else rules.climb_speed
	if facing != 0:
		e.node.facing = facing
	e.node.sync()
