class_name Bridge
extends Node2D
## The player's truss: joints are hinges, members are logs (push + pull) or ropes (pull only).
## Simulated with XPBD (small-steps variant, one iteration per substep). SI units: m, kg, s, N.
## Joints touching solid ground are bolted down.
## New members start as blueprints: drawn, but not simulated or walkable. Ordered blueprints are built one by one
## by the Crew (finish), held on scaffolding, and released to the physics when the crew strikes the scaffolding.

signal member_built(member: Member)
signal member_broken(member: Member, text: String)


class Joint:
	var pos: Vector2
	var prev: Vector2
	var pinned: bool = false
	var mass: float = 0.0
	var load: float = 0.0
	var inv_mass: float = 0.0
	var degree: int = 0
	## Touched by at least one built member. Joints of a blueprint alone stay put.
	var built: bool = false
	## Held in place by scaffolding.
	var scaffolded: bool = false

	func fixed() -> bool:
		return pinned or scaffolded or not built


class Member:
	var a: Joint
	var b: Joint
	var length: float
	var material: BridgeMaterial
	var mass: float
	## Smoothed axial force in N, tension positive.
	var force: float = 0.0
	var _acc: float = 0.0
	var dead: bool = false
	## Planned but not built yet.
	var blueprint: bool = false
	## Handed to the crew.
	var ordered: bool = false
	## Built, still held by scaffolding.
	var scaffolded: bool = false
	## Share built so far (0..1), growing from from_joint.
	var progress: float = 0.0
	var from_joint: Joint

	func stress() -> float:
		return absf(force) / material.break_force


## A candidate end point for a new member.
class Snap:
	var pos: Vector2
	var node: Joint
	var anchor: bool
	## Lands part-way along this member (no joint there yet); building splits it here.
	var on_member: Member

	func _init(p_pos: Vector2, p_node: Joint, p_anchor: bool) -> void:
		pos = p_pos
		node = p_node
		anchor = p_anchor


@export_group("Physics")
@export var gravity: float = 9.81
@export_range(1, 40) var substeps: int = 10
## Velocity kept per substep (numerical damping).
@export var damping: float = 0.9995
## Upward push in buoyant terrain, in multiples of gravity (wood ~600 kg/m³ floats).
@export var buoyancy: float = 1.6
@export var water_drag: float = 0.97
## Smoothing of member force before the break test, per tick. Filters single-substep spikes.
@export_range(0.01, 1.0) var force_smoothing: float = 0.2
## Ground friction: fraction of velocity kept when a joint touches ground.
@export_range(0.0, 1.0) var ground_friction: float = 0.3

@export_group("Building")
## Walking surface sits this far above the member line (log radius).
@export var deck_offset: float = 0.14
## Rise/run above which a member is not walkable.
@export var max_walk_slope: float = 1.2
@export var max_members: int = 260
@export var snap_radius: float = 0.4
@export var grid_step: float = 0.5
@export var min_length: float = 0.45

@export_group("Messages")
@export var already_joined_text: String = "Already joined"
@export var through_ground_text: String = "Runs through ground"
@export var too_many_text: String = "Too many members"
@export var too_long_text: String = "%.1f m · max %.0f m"
@export var length_text: String = "%.1f m"

@export_group("Look")
@export var joint_color: Color = Color("3a2a1a")
@export var bolt_color: Color = Color("2b2f36")
@export var bolt_head_color: Color = Color("9aa6b4")
@export var highlight_color: Color = Color(1, 0.92, 0.78, 0.25)
@export var blueprint_color: Color = Color(0.55, 0.78, 1.0, 0.8)
## Blueprints handed to the crew.
@export var ordered_color: Color = Color(1.0, 0.85, 0.45, 0.9)
@export var blueprint_dash: float = 6.0
@export var scaffold_color: Color = Color(0.62, 0.55, 0.42, 0.85)
## Scaffold poles reach down at most this far.
@export var scaffold_max_depth: float = 24.0

var terrain: Terrain
var nodes: Array[Joint] = []
var members: Array[Member] = []


func _process(_delta: float) -> void:
	queue_redraw()


func anchorable(p: Vector2) -> bool:
	if terrain == null:
		return false
	var xs := [roundi(p.x) - 1, roundi(p.x)] if _on_grid(p.x) else [floori(p.x)]
	var ys := [roundi(p.y) - 1, roundi(p.y)] if _on_grid(p.y) else [floori(p.y)]
	for x: int in xs:
		for y: int in ys:
			if terrain.is_solid(Vector2i(x, y)):
				return true
	return false


func snap_point(p: Vector2, exclude: Joint = null) -> Snap:
	var best: Joint = null
	var bd := snap_radius
	for n in nodes:
		if n == exclude:
			continue
		var d := n.pos.distance_to(p)
		if d < bd:
			bd = d
			best = n
	if best:
		return Snap.new(best.pos, best, best.pinned)
	var along: Member = null
	var ad := snap_radius
	for m in members:
		if not m.material.attach_along or (exclude and (m.a == exclude or m.b == exclude)):
			continue
		var d := _seg_dist(p, m.a.pos, m.b.pos)
		if d < ad:
			ad = d
			along = m
	if along:
		var at := Geometry2D.get_closest_point_to_segment(p, along.a.pos, along.b.pos)
		var s := Snap.new(at, null, anchorable(at))
		s.on_member = along
		return s
	var g := (p / grid_step).round() * grid_step
	return Snap.new(g, null, anchorable(g))


## {ok: bool, msg: String, length: float}
func check_build(a: Snap, b: Snap, mat: BridgeMaterial, supplies: Supplies) -> Dictionary:
	var length := a.pos.distance_to(b.pos)
	var r := {ok = false, msg = "", length = length}
	if length < min_length:
		return r
	if length > mat.max_length + 1e-6:
		r.msg = too_long_text % [length, mat.max_length]
		return r
	if (a.node and b.node and _joined(a.node, b.node)) or _same_member(a, b) or _same_member(b, a):
		r.msg = already_joined_text
		return r
	if _through_ground(a.pos, b.pos):
		r.msg = through_ground_text
		return r
	if members.size() >= max_members:
		r.msg = too_many_text
		return r
	if supplies and not supplies.can_afford(mat.cost):
		r.msg = mat.no_supply_text
		return r
	r.ok = true
	r.msg = length_text % length
	return r


## Adds the member without any cost or validity check (see check_build).
## A blueprint is only a plan until commit_blueprints.
func build(a: Snap, b: Snap, mat: BridgeMaterial, blueprint: bool = false) -> Member:
	var m := Member.new()
	m.a = _joint_for(a)
	m.b = _joint_for(b)
	m.length = a.pos.distance_to(b.pos)
	m.material = mat
	m.mass = m.length * mat.kg_per_m
	m.blueprint = blueprint
	members.append(m)
	_recompute_mass()
	if not blueprint:
		Audio.play(mat.place_sound, Grid.to_px((m.a.pos + m.b.pos) / 2))
		member_built.emit(m)
	return m


## Blueprints not yet handed to the crew.
func blueprint_count() -> int:
	return members.reduce(func(n: int, m: Member) -> int: return n + int(m.blueprint and not m.ordered), 0)


## Unordered blueprints, grouped by shared joints: each group is one plan the player can order.
func plans() -> Array[Array]:
	var out: Array[Array] = []
	var seen := {}
	for m in members:
		if seen.has(m) or not (m.blueprint and not m.ordered):
			continue
		var group: Array[Member] = [m]
		var joints := {m.a: true, m.b: true}
		seen[m] = true
		var grew := true
		while grew:
			grew = false
			for o in members:
				if not seen.has(o) and o.blueprint and not o.ordered and (joints.has(o.a) or joints.has(o.b)):
					seen[o] = true
					group.append(o)
					joints[o.a] = true
					joints[o.b] = true
					grew = true
		out.append(group)
	return out


## Hands one plan (from plans()) to the crew.
func order_plan(plan: Array) -> void:
	for m: Member in plan:
		if m.blueprint and not m.dead:
			m.ordered = true


## Removes one plan (from plans()). Returns what it cost, to give back.
func cancel_plan(plan: Array) -> Supplies:
	var refund := Supplies.new()
	for m: Member in plan:
		if m.blueprint and not m.dead:
			refund.add(m.material.cost)
			remove_member(m)
	return refund


## Hands every unordered blueprint to the crew. Returns how many.
func order_blueprints() -> int:
	var n := 0
	for m in members:
		if m.blueprint and not m.ordered:
			m.ordered = true
			n += 1
	return n


## Ends of an ordered blueprint the crew can work from: bolted down or on a built member.
func work_ends(m: Member) -> Array[Joint]:
	var out: Array[Joint] = []
	if m.blueprint and m.ordered:
		for j: Joint in [m.a, m.b]:
			if j.pinned or j.built:
				out.append(j)
	return out


## Shortest walk from a bolted joint along built members to j, both ends included. [] if j is not reachable.
func route_from_ground(j: Joint) -> Array[Joint]:
	return route(j, func(n: Joint) -> bool: return n.pinned)


## Shortest walk along built members from a joint that matches is_start to goal. [] if none.
func route(goal: Joint, is_start: Callable) -> Array[Joint]:
	var came := {goal: null}
	var queue: Array[Joint] = [goal]
	while not queue.is_empty():
		var n: Joint = queue.pop_front()
		if is_start.call(n):
			var out: Array[Joint] = []
			while n != null:
				out.append(n)
				n = came[n]
			return out
		for m in members:
			if m.blueprint:
				continue
			var o: Joint = m.b if m.a == n else (m.a if m.b == n else null)
			if o and not came.has(o):
				came[o] = n
				queue.append(o)
	return []


## Builds one blueprint and holds it on scaffolding.
func finish(m: Member) -> void:
	m.blueprint = false
	m.ordered = false
	m.scaffolded = true
	m.progress = 1.0
	_recompute_mass()
	Audio.play(m.material.place_sound, Grid.to_px((m.a.pos + m.b.pos) / 2))
	member_built.emit(m)


func has_scaffolding() -> bool:
	return members.any(func(m: Member) -> bool: return m.scaffolded)


## Releases scaffolded members to the physics: those in only, or every one when only is empty. Returns how many.
func strike_scaffolding(only: Array[Member] = []) -> int:
	var n := 0
	for m in (only if not only.is_empty() else members):
		if m.scaffolded:
			m.scaffolded = false
			n += 1
	if n > 0:
		_recompute_mass()
	return n


## Separate structures: groups of built or ordered members joined through shared joints.
## Plans not yet ordered belong to no structure and join nothing.
func structures() -> Array[Array]:
	var out: Array[Array] = []
	var seen := {}
	for m in members:
		if not seen.has(m) and _in_structure(m):
			var group := structure_of(m)
			for g in group:
				seen[g] = true
			out.append(group)
	return out


## Every built or ordered member joined to m through shared joints, m included.
func structure_of(m: Member) -> Array[Member]:
	var out: Array[Member] = []
	if not _in_structure(m):
		return out
	var joints := {m.a: true, m.b: true}
	var grew := true
	while grew:
		grew = false
		for o in members:
			if _in_structure(o) and (joints.has(o.a) or joints.has(o.b)) and not (joints.has(o.a) and joints.has(o.b)):
				joints[o.a] = true
				joints[o.b] = true
				grew = true
	for o in members:
		if _in_structure(o) and joints.has(o.a) and joints.has(o.b):
			out.append(o)
	return out


func _in_structure(m: Member) -> bool:
	return not m.blueprint or m.ordered


func member_at(p: Vector2, radius: float) -> Member:
	var best: Member = null
	var bd := radius
	for m in members:
		var d := _seg_dist(p, m.a.pos, m.b.pos)
		if d < bd:
			bd = d
			best = m
	return best


func remove_member(m: Member) -> void:
	m.dead = true
	members.erase(m)
	_recompute_mass()


## Breaks a member with debris. quiet skips the message (player removal).
func break_member(m: Member, quiet: bool = false) -> void:
	var mid := (m.a.pos + m.b.pos) / 2
	var text := ""
	if not quiet:
		text = m.material.snapped_text if m.force > 0 or m.material.buckled_text.is_empty() else m.material.buckled_text
		Audio.play(m.material.break_sound, Grid.to_px(mid))
	Effects.debris(Grid.to_px(mid), m.material.color, 4 if m.material.draw_as_rope else 9, 140.0)
	remove_member(m)
	member_broken.emit(m, text)


## Where a path from a to b (metres) first hits a built member that blocks arrows, or null.
func arrow_block(a: Vector2, b: Vector2) -> Variant:
	var best: Variant = null
	for m in members:
		if m.blueprint or not m.material.blocks_arrows:
			continue
		var hit: Variant = Geometry2D.segment_intersects_segment(a, b, m.a.pos, m.b.pos)
		if hit != null and (best == null or a.distance_to(hit) < a.distance_to(best)):
			best = hit
	return best


## Highest walkable deck at x that is at or below y_from. {y, member, t} or {} if none.
func walk_surface(x: float, y_from: float) -> Dictionary:
	var best := {}
	for m in members:
		# Finished pieces are walkable even while still on scaffolding; pieces being built are not.
		if m.blueprint or not m.material.walkable:
			continue
		var a := m.a.pos
		var b := m.b.pos
		var run := b.x - a.x
		if absf(run) < 0.2 or x < minf(a.x, b.x) or x > maxf(a.x, b.x):
			continue
		if absf((b.y - a.y) / run) > max_walk_slope:
			continue
		var t := (x - a.x) / run
		var y := a.y + (b.y - a.y) * t - deck_offset
		if y >= y_from - 1e-6 and (best.is_empty() or y < best.y):
			best = {y = y, member = m, t = t}
	return best


## Advances the truss by dt. loads: [[member, t along member, kg], ...] from soldiers standing on it.
func step(dt: float, loads: Array = []) -> void:
	if members.is_empty():
		return
	for n in nodes:
		n.load = 0.0
		if n.pinned and not anchorable(n.pos):
			n.pinned = false
	for l: Array in loads:
		var m: Member = l[0]
		if m.dead:
			continue
		m.a.load += l[2] * (1.0 - l[1])
		m.b.load += l[2] * l[1]
	for n in nodes:
		n.inv_mass = 0.0 if n.fixed() else 1.0 / (n.mass + n.load)
	for m in members:
		m._acc = 0.0
	var h := dt / substeps
	var h2 := h * h
	for s in substeps:
		for n in nodes:
			if n.fixed():
				continue
			var v := (n.pos - n.prev) * damping
			var ay := gravity
			var t := terrain.type_at(Grid.cell_of(n.pos)) if terrain else null
			if t and t.buoyant:
				ay -= gravity * buoyancy
				v *= water_drag
			n.prev = n.pos
			n.pos += v + Vector2(0, ay * h2)
		for m in members:
			var w := m.a.inv_mass + m.b.inv_mass
			if w == 0.0 or m.blueprint:
				continue
			var d := m.b.pos - m.a.pos
			var dist := maxf(d.length(), 1e-6)
			var c := dist - m.length
			if m.material.tension_only and c <= 0.0:
				continue
			var dl := -c / (w + m.material.compliance / h2)
			var dir := d / dist
			m.a.pos -= dir * (m.a.inv_mass * dl)
			m.b.pos += dir * (m.b.inv_mass * dl)
			m._acc -= dl / h2
		for n in nodes:
			if not n.fixed():
				_collide(n)
	var broken: Array[Member] = []
	for m in members:
		if m.blueprint:
			continue
		m.force += (m._acc / substeps - m.force) * force_smoothing
		if absf(m.force) > m.material.break_force:
			broken.append(m)
	for m in broken:
		break_member(m)
	var bottom := (terrain.size.y + 2) if terrain else 1000
	for m in members.duplicate():
		if not m.blueprint and m.a.pos.y > bottom or m.b.pos.y > bottom:
			remove_member(m)


func clear() -> void:
	members.clear()
	nodes.clear()


## Removes every member, built or planned, with an end left of lo or right of hi (metres).
func remove_outside(lo: float, hi: float) -> void:
	for m in members.duplicate():
		if minf(m.a.pos.x, m.b.pos.x) < lo or maxf(m.a.pos.x, m.b.pos.x) > hi:
			m.dead = true
			members.erase(m)
	_recompute_mass()


func _draw() -> void:
	var px := Grid.PX
	for n in nodes:
		if n.scaffolded and not n.pinned:
			_draw_scaffold(n.pos)
	var layered := members.duplicate()
	layered.sort_custom(func(x: Member, y: Member) -> bool: return x.material.draw_layer < y.material.draw_layer)
	for m: Member in layered:
		var a := m.a.pos * px
		var b := m.b.pos * px
		var mat := m.material
		if m.blueprint:
			draw_dashed_line(a, b, ordered_color if m.ordered else blueprint_color, maxf(2.0, mat.thickness * 0.6 * px), blueprint_dash)
			if m.progress > 0.0 and m.from_joint:
				var from := m.from_joint.pos * px
				var to := (m.b.pos if m.from_joint == m.a else m.a.pos) * px
				draw_line(from, from.lerp(to, m.progress), mat.color, mat.thickness * px)
			continue
		var hot := mat.color.lerp(mat.hot_color, clampf((m.stress() - 0.3) / 0.7, 0.0, 1.0))
		if mat.draw_as_rope:
			var dist := m.a.pos.distance_to(m.b.pos)
			var sag := sqrt(m.length * m.length - dist * dist) * 0.5 if m.length > dist else 0.0
			var ctrl := (a + b) / 2 + Vector2(0, sag * px)
			var pts := PackedVector2Array()
			for i in 13:
				var t := i / 12.0
				pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
			draw_polyline(pts, hot if m.stress() > 0.3 else mat.color, maxf(1.5, mat.thickness * px), true)
		else:
			draw_line(a, b, mat.edge_color, mat.thickness * 1.5 * px)
			draw_line(a, b, hot, mat.thickness * px)
			draw_line(a - Vector2(0, 0.05 * px), b - Vector2(0, 0.05 * px), highlight_color, maxf(1.0, 0.04 * px))
			draw_circle(a, mat.thickness * 0.75 * px, mat.edge_color)
			draw_circle(b, mat.thickness * 0.75 * px, mat.edge_color)
	for n in nodes:
		var p := n.pos * px
		if not n.built:
			draw_arc(p, 0.13 * px, 0, TAU, 12, blueprint_color, 1.5)
		elif n.pinned:
			draw_rect(Rect2(p - Vector2.ONE * 0.15 * px, Vector2.ONE * 0.3 * px), bolt_color)
			draw_rect(Rect2(p - Vector2.ONE * 0.04 * px, Vector2.ONE * 0.08 * px), bolt_head_color)
		else:
			draw_circle(p, 0.11 * px, joint_color)


func _add_joint(p: Vector2) -> Joint:
	var n := Joint.new()
	n.pos = p
	n.prev = p
	n.pinned = anchorable(p)
	nodes.append(n)
	return n


func _recompute_mass() -> void:
	for n in nodes:
		n.mass = 0.0
		n.degree = 0
		n.built = false
		n.scaffolded = false
	for m in members:
		m.a.degree += 1
		m.b.degree += 1
		if m.blueprint:
			continue
		if m.scaffolded:
			m.a.scaffolded = true
			m.b.scaffolded = true
		m.a.mass += m.mass / 2
		m.b.mass += m.mass / 2
		m.a.built = true
		m.b.built = true
	nodes = nodes.filter(func(n: Joint) -> bool: return n.degree > 0)


## A pole from p down to the ground with a ledger every metre.
func _draw_scaffold(p: Vector2) -> void:
	var px := Grid.PX
	var x := floori(p.x)
	var y := p.y
	var top := ceili(p.y)
	var bottom := top
	while bottom < top + scaffold_max_depth and not terrain.is_solid(Vector2i(x, bottom)):
		bottom += 1
	draw_line(p * px, Vector2(p.x, bottom) * px, scaffold_color, maxf(1.5, 0.07 * px))
	while y < bottom - 0.5:
		y += 1.0
		draw_line(Vector2(p.x - 0.3, y) * px, Vector2(p.x + 0.3, y) * px, scaffold_color, maxf(1.0, 0.05 * px))


## The joint a new member uses at s: the existing one, a split of the member it lands on, or a new one.
func _joint_for(s: Snap) -> Joint:
	if s.node:
		return s.node
	if s.on_member and not s.on_member.dead:
		return split(s.on_member, s.pos)
	return _add_joint(s.pos)


## Cuts m in two at p (on m) with a new joint between the halves, keeping its state. Returns the joint.
func split(m: Member, p: Vector2) -> Joint:
	var t := clampf(m.a.pos.distance_to(p) / maxf(m.a.pos.distance_to(m.b.pos), 1e-6), 0.0, 1.0)
	var j := _add_joint(p)
	var rest := Member.new()
	rest.a = j
	rest.b = m.b
	rest.material = m.material
	rest.length = m.length * (1.0 - t)
	rest.mass = rest.length * m.material.kg_per_m
	rest.force = m.force
	rest.blueprint = m.blueprint
	rest.ordered = m.ordered
	rest.scaffolded = m.scaffolded
	rest.progress = m.progress
	m.b = j
	m.length *= t
	m.mass = m.length * m.material.kg_per_m
	members.append(rest)
	_recompute_mass()
	return j


## Does a land on b's member, or on one of that member's ends.
func _same_member(a: Snap, b: Snap) -> bool:
	if a.on_member == null:
		return false
	return b.on_member == a.on_member or b.node == a.on_member.a or b.node == a.on_member.b


func _joined(a: Joint, b: Joint) -> bool:
	for m in members:
		if (m.a == a and m.b == b) or (m.a == b and m.b == a):
			return true
	return false


func _through_ground(a: Vector2, b: Vector2) -> bool:
	for i in range(1, 12):
		var p := a.lerp(b, i / 12.0)
		if terrain.is_solid(Vector2i(floori(p.x + 0.02), floori(p.y - 0.02))) \
				and terrain.is_solid(Vector2i(floori(p.x - 0.02), floori(p.y - 0.02))):
			return true
	return false


func _collide(n: Joint) -> void:
	var c := Grid.cell_of(n.pos)
	if not terrain.is_solid(c):
		return
	var f := n.pos - Vector2(c)
	# Pushed out just clear of the cell edge. Further would leave the joint falling back every few substeps.
	var e := 0.001
	var best := Vector2(n.pos.x, c.y - e)
	var normal := Vector2.UP
	var bd := 9.0
	if not terrain.is_solid(c + Vector2i.UP) and f.y < bd:
		bd = f.y
		best = Vector2(n.pos.x, c.y - e)
	if not terrain.is_solid(c + Vector2i.LEFT) and f.x < bd:
		bd = f.x
		best = Vector2(c.x - e, n.pos.y)
		normal = Vector2.LEFT
	if not terrain.is_solid(c + Vector2i.RIGHT) and 1.0 - f.x < bd:
		bd = 1.0 - f.x
		best = Vector2(c.x + 1 + e, n.pos.y)
		normal = Vector2.RIGHT
	if not terrain.is_solid(c + Vector2i.DOWN) and 1.0 - f.y < bd:
		best = Vector2(n.pos.x, c.y + 1 + e)
		normal = Vector2.DOWN
	# Contact: no velocity into the ground, sliding slowed by friction. Working the velocity out from the
	# push-out instead would make every contact a small kick upward, and loose pieces would never rest.
	var v := n.pos - n.prev
	var slide := v - normal * v.dot(normal)
	n.pos = best
	n.prev = n.pos - slide * ground_friction


static func _on_grid(v: float) -> bool:
	return absf(v - roundf(v)) < 1e-6


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
