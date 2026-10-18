class_name Bridge
extends Node2D
## The player's truss: joints are hinges, members are logs (push + pull) or ropes (pull only).
## Simulated with XPBD (small-steps variant, one iteration per substep). SI units: m, kg, s, N.
## Joints touching solid ground are bolted down.
## New members start as blueprints: drawn, but not simulated or walkable. Ordered blueprints are built one by one
## by the Crew (finish), held on scaffolding, and released to the physics when the crew strikes the scaffolding.

## Flex is given for this load (kg) at the middle of a member this long (m).
const REFERENCE_LOAD: float = 80.0
const REFERENCE_LENGTH: float = 5.0
## A member never sags more than this share of its length.
const MAX_SAG: float = 0.08

signal member_built(member: Member)
signal member_broken(member: Member, text: String)
## Pieces hit the ground in cell at harm_speed or more this tick, doing this much damage in all (J: each hit's
## energy times its material's Ram).
signal struck(cell: Vector2i, damage: float)


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
	## How far its middle sinks under the soldiers on it, in metres (see BridgeMaterial.flex).
	var sag: float = 0.0

	## Sag at t along the member (0 at the ends, sag at the middle).
	func sag_at(t: float) -> float:
		return sag * 4.0 * t * (1.0 - t)
	var from_joint: Joint

	func stress() -> float:
		return absf(force) / material.break_force


## A candidate end point for a new member.
## A soldier or archer the bridge collides with: a solid circle. A built piece reaching it at harm_speed or more
## crushes it (crushed) and passes on; a slower one is stopped by it. A box (half > 0, a falling block) only
## stops pieces.
class Body:
	var center: Vector2
	var radius: float
	var half: Vector2 = Vector2.ZERO
	## The body's own velocity (m/s), so pieces falling along with it do not crush it.
	var vel: Vector2
	## The member it stands on, which never touches it.
	var skip: Member
	var crushed: bool = false
	## Weight (kg) of bridge pieces, and what they carry, resting on it this tick.
	var load: float = 0.0

	func _init(p_center: Vector2, p_radius: float, p_vel: Vector2 = Vector2.ZERO, p_skip: Member = null) -> void:
		center = p_center
		radius = p_radius
		vel = p_vel
		skip = p_skip

	static func box(p_center: Vector2, p_half: Vector2, p_skip: Member = null) -> Body:
		var b := Body.new(p_center, 0.0, Vector2.ZERO, p_skip)
		b.half = p_half
		return b

	func is_box() -> bool:
		return half != Vector2.ZERO

	## Top of the body (y, metres).
	func top() -> float:
		return center.y - (half.y if is_box() else radius)

	## How far either side of center a thing above it rests on it.
	func half_width() -> float:
		return half.x if is_box() else radius * 0.5


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
## How fast a plank bends to its load and springs back, per tick.
@export_range(0.01, 1.0) var sag_smoothing: float = 0.15
## Friction coefficient of ground and bodies against pieces (Coulomb): sliding is slowed by at most this times
## the push into the surface, so pieces slide on slopes steeper than about atan(friction).
@export_range(0.0, 2.0, 0.05) var ground_friction: float = 0.6

@export_group("Impact")
## A built piece hitting a soldier or archer at least this fast (m/s) crushes it (slower ones are stopped by
## it); hitting ground this fast breaks a cell that can be dug, or batters a tower.
@export var harm_speed: float = 6.0
## Weight (kg) resting on a soldier or archer (pieces, what they carry, falling blocks) that crushes them.
@export var crush_weight: float = 250.0
## Seconds of siege a tower cell takes per kJ of impact energy (½·m·v² of the joint and its load).
@export var siege_per_kj: float = 10.0

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

## Spacing (m) of the points along a member that are kept out of the ground.
const MEMBER_PROBE: float = 0.25

var terrain: Terrain
var nodes: Array[Joint] = []
var members: Array[Member] = []
## Length of the last substep, for joint velocities.
var _h: float = 1.0 / 600.0
var _hits: Array = [] # [cell, member, energy (J)] of every fast hit on the ground this tick


func _process(_delta: float) -> void:
	queue_redraw()


## Does a joint at p bolt down: does it touch natural ground (TerrainType.anchor, not bricks or trees)?
func anchorable(p: Vector2) -> bool:
	if terrain == null:
		return false
	var xs := [roundi(p.x) - 1, roundi(p.x)] if _on_grid(p.x) else [floori(p.x)]
	var ys := [roundi(p.y) - 1, roundi(p.y)] if _on_grid(p.y) else [floori(p.y)]
	for x: int in xs:
		for y: int in ys:
			if terrain.is_anchor(Vector2i(x, y)):
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


## A loose plan end buried in the ground (a) moved along the plan toward its other end (b) to where the plan
## leaves the ground, and bolted there. Any other end comes back as it is.
func fit_to_ground(a: Snap, b: Snap) -> Snap:
	if a.node or a.on_member or not _buried(a.pos):
		return a
	var steps := 48
	var lo := 0.0
	var hi := -1.0
	for i in range(1, steps + 1):
		if not _buried(a.pos.lerp(b.pos, float(i) / steps)):
			hi = float(i) / steps
			break
		lo = float(i) / steps
	if hi < 0.0:
		return a
	for i in 24:
		var mid := (lo + hi) / 2.0
		if _buried(a.pos.lerp(b.pos, mid)):
			lo = mid
		else:
			hi = mid
	var p := a.pos.lerp(b.pos, hi)
	# Onto the cell edge it crossed, so the joint sits exactly on the ground's face.
	for k in 2:
		if absf(p[k] - roundf(p[k])) < 0.001:
			p[k] = roundf(p[k])
	return Snap.new(p, null, anchorable(p))


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
## With walkable_only false, any piece solid along its length (see BridgeMaterial.solid_along) counts.
func walk_surface(x: float, y_from: float, walkable_only: bool = true) -> Dictionary:
	var best := {}
	for m in members:
		# Finished pieces are walkable even while still on scaffolding; of a piece being built, the part
		# already built is.
		var built := 1.0 if not m.blueprint else (m.progress if m.ordered and m.from_joint else 0.0)
		if built <= 0.0 or not (m.material.walkable if walkable_only else m.material.solid_along):
			continue
		var a := m.a.pos
		var b := m.b.pos
		var run := b.x - a.x
		if absf(run) < 0.2 or x < minf(a.x, b.x) or x > maxf(a.x, b.x):
			continue
		if absf((b.y - a.y) / run) > max_walk_slope:
			continue
		var t := (x - a.x) / run
		if built < 1.0 and (t > built if m.from_joint == m.a else t < 1.0 - built):
			continue
		var y := a.y + (b.y - a.y) * t - deck_offset + m.sag_at(t)
		if y >= y_from - 1e-6 and (best.is_empty() or y < best.y):
			best = {y = y, member = m, t = t}
	return best


## Advances the truss by dt. loads: [[member, t along member, kg], ...] from soldiers standing on it.
func step(dt: float, loads: Array = [], bodies: Array[Body] = []) -> void:
	if members.is_empty():
		return
	for n in nodes:
		n.load = 0.0
		if n.pinned and not anchorable(n.pos):
			n.pinned = false
	var bending := {}
	for l: Array in loads:
		var m: Member = l[0]
		if m.dead:
			continue
		m.a.load += l[2] * (1.0 - l[1])
		m.b.load += l[2] * l[1]
		# A load bends a member most at its middle and not at all at a joint.
		bending[m] = bending.get(m, 0.0) + l[2] * 4.0 * l[1] * (1.0 - l[1])
	_bend(bending)
	for n in nodes:
		n.inv_mass = 0.0 if n.fixed() else 1.0 / (n.mass + n.load)
	for m in members:
		m._acc = 0.0
	var h := dt / substeps
	var h2 := h * h
	_h = h
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
				_collide(n, h)
	var structures := _structures()
	# Whole pieces against the ground, each other and bodies: once per tick, which is plenty against cells and
	# bodies a metre wide (the joints, which move fastest, collide every substep above).
	for m in members:
		if not m.blueprint and m.material.solid_along:
			_collide_member(m, h)
	_collide_structures(structures, h)
	for b in bodies:
		_collide_body(b, h)
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
	_resolve_hits()


## Eases each member's sag toward what its loads ({member: kg weighted by where they stand}) call for.
func _bend(bending: Dictionary) -> void:
	for m in members:
		var mat := m.material
		var target := 0.0
		if not mat.draw_as_rope and mat.flex > 0.0 and bending.has(m):
			target = minf(mat.flex * bending[m] / REFERENCE_LOAD * pow(m.length / REFERENCE_LENGTH, 3.0), m.length * MAX_SAG)
		m.sag += (target - m.sag) * sag_smoothing
		if m.sag < 0.0005 and target == 0.0:
			m.sag = 0.0


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
		elif m.sag > 0.002:
			var pts := PackedVector2Array()
			for i in 13:
				var t := i / 12.0
				pts.append(a.lerp(b, t) + Vector2(0, m.sag_at(t) * px))
			var lit := pts.duplicate()
			for i in lit.size():
				lit[i] -= Vector2(0, 0.05 * px)
			draw_polyline(pts, mat.edge_color, mat.thickness * 1.5 * px, true)
			draw_polyline(pts, hot, mat.thickness * px, true)
			draw_polyline(lit, highlight_color, maxf(1.0, 0.04 * px), true)
			draw_circle(a, mat.thickness * 0.75 * px, mat.edge_color)
			draw_circle(b, mat.thickness * 0.75 * px, mat.edge_color)
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


## Inside the ground: solid all around, not on its surface.
func _buried(p: Vector2) -> bool:
	for d: Vector2 in [Vector2(-0.01, -0.01), Vector2(0.01, -0.01), Vector2(-0.01, 0.01), Vector2(0.01, 0.01)]:
		if not terrain.is_solid(Grid.cell_of(p + d)):
			return false
	return true


func _through_ground(a: Vector2, b: Vector2) -> bool:
	for i in range(1, 12):
		var p := a.lerp(b, i / 12.0)
		if terrain.is_solid(Vector2i(floori(p.x + 0.02), floori(p.y - 0.02))) \
				and terrain.is_solid(Vector2i(floori(p.x - 0.02), floori(p.y - 0.02))):
			return true
	return false


func _collide(n: Joint, h: float) -> void:
	var out := _push_out(n.pos, n.prev)
	if out.is_empty():
		return
	var v := n.pos - n.prev
	# The joint's mass and load come from its members: each takes its share of the hit.
	for m in members:
		if not m.blueprint and (m.a == n or m.b == n):
			_strike(Grid.cell_of(n.pos), m, (n.mass + n.load) * (m.mass / 2.0) / maxf(n.mass, 1e-6), v, out[1], h)
	n.pos = out[0]
	n.prev = n.pos - (v + _contact_dv(v, out[1]))


## Keeps built member m out of what push_out (point -> [pushed point, normal] or []) reports: by default the
## ground, along its length between the joints (the joints collide on their own), with impact damage.
## For anything else (ground false) its ends count too, and nothing is damaged.
func _collide_member(m: Member, h: float, push_out: Callable = _push_out, ground: bool = true) -> void:
	if m.a.inv_mass == 0.0 and m.b.inv_mass == 0.0:
		return
	var steps := ceili(m.length / MEMBER_PROBE)
	var hit := false
	for k in range(1 if ground else 0, steps if ground else steps + 1):
		var t := float(k) / steps
		var p := m.a.pos.lerp(m.b.pos, t)
		var out: Array = push_out.call(p, m.a.prev.lerp(m.b.prev, t))
		if out.is_empty():
			continue
		var wa := m.a.inv_mass * (1.0 - t)
		var wb := m.b.inv_mass * t
		var w := wa * (1.0 - t) + wb * t
		if w <= 0.0:
			continue
		var va := m.a.pos - m.a.prev
		var vb := m.b.pos - m.b.prev
		if ground and not hit:
			# One hit per piece: its first point in the ground carries the piece's mass and load.
			hit = true
			_strike(Grid.cell_of(p), m, m.mass + m.a.load * (1.0 - t) + m.b.load * t, va.lerp(vb, t), out[1], h)
		var push: Vector2 = (out[0] - p) / w
		m.a.pos += push * wa
		m.b.pos += push * wb
		_contact_at(m, t, va, vb, wa, wb, w, out[1])


## Where p, if inside solid ground, is pushed out to, and that face's outward normal: [Vector2, Vector2]. [] if p is
## not in the ground. It leaves through the open face it came in through, going by where it was before (from);
## if that tells nothing, through the nearest open face.
func _push_out(p: Vector2, from: Vector2) -> Array:
	var c := Grid.cell_of(p)
	if not terrain.is_solid(c):
		return []
	# Just clear of the cell edge. Further would leave the joint falling back every few substeps.
	var e := 0.001
	var lo := Vector2(c)
	var hi := lo + Vector2.ONE
	# [normal, pushed point, how far through the move the face was crossed (later = the face it came in by),
	# distance to the face]
	var faces := [
		[Vector2.UP, Vector2(p.x, lo.y - e), _crossed(from.y, p.y, lo.y), p.y - lo.y],
		[Vector2.DOWN, Vector2(p.x, hi.y + e), _crossed(-from.y, -p.y, -hi.y), hi.y - p.y],
		[Vector2.LEFT, Vector2(lo.x - e, p.y), _crossed(from.x, p.x, lo.x), p.x - lo.x],
		[Vector2.RIGHT, Vector2(hi.x + e, p.y), _crossed(-from.x, -p.x, -hi.x), hi.x - p.x],
	]
	var best: Array = []
	for f: Array in faces:
		if terrain.is_solid(c + Vector2i(f[0])):
			continue
		if best.is_empty() or f[2] > best[2] or (f[2] == best[2] and f[3] < best[3]):
			best = f
	if best.is_empty():
		return [Vector2(p.x, lo.y - e), Vector2.UP]
	return [best[1], best[0]]


## When, as a share of the move from a to b along one axis, the plane at edge was crossed going up the axis;
## -1 if the move started past it.
static func _crossed(a: float, b: float, edge: float) -> float:
	if a > edge:
		return -1.0
	return (edge - a) / maxf(b - a, 1e-9)


## Where p, if inside box body b, is pushed out to (just clear of its nearest side), and that side's normal.
func _push_out_of_box(p: Vector2, _from: Vector2, b: Body) -> Array:
	var d := p - b.center
	var pen := b.half - d.abs()
	if pen.x <= 0.0 or pen.y <= 0.0:
		return []
	var e := 0.001
	if pen.x < pen.y:
		var nx := 1.0 if d.x >= 0.0 else -1.0
		return [Vector2(b.center.x + nx * (b.half.x + e), p.y), Vector2(nx, 0.0)]
	var ny := 1.0 if d.y >= 0.0 else -1.0
	return [Vector2(p.x, b.center.y + ny * (b.half.y + e)), Vector2(0.0, ny)]


## Built members by connected structure: Member -> id. Members joined through joints share an id.
func _structures() -> Dictionary:
	var at := {} # Joint -> Array of built members on it
	for m in members:
		if not m.blueprint:
			for j: Joint in [m.a, m.b]:
				if not at.has(j):
					at[j] = []
				at[j].append(m)
	var of := {}
	var id := 0
	for start in members:
		if start.blueprint or of.has(start):
			continue
		var queue: Array[Member] = [start]
		of[start] = id
		while not queue.is_empty():
			var m: Member = queue.pop_back()
			for j: Joint in [m.a, m.b]:
				for o: Member in at[j]:
					if not of.has(o):
						of[o] = id
						queue.append(o)
		id += 1
	return of


## Keeps pieces of different structures (of: from _structures) from passing through each other, by their
## thickness. Pieces of one structure may cross (an X brace).
func _collide_structures(of: Dictionary, h: float) -> void:
	# Only pieces sharing a 2 m bucket can touch.
	var buckets := {}
	for m: Member in of:
		var box := Rect2(m.a.pos, Vector2.ZERO).expand(m.b.pos).grow(m.material.thickness)
		for x in range(floori(box.position.x / 2.0), floori(box.end.x / 2.0) + 1):
			for y in range(floori(box.position.y / 2.0), floori(box.end.y / 2.0) + 1):
				var key := Vector2i(x, y)
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append(m)
	var done := {}
	for list: Array in buckets.values():
		for i in list.size():
			var p: Member = list[i]
			for k in range(i + 1, list.size()):
				var q: Member = list[k]
				if of[p] == of[q] or not (p.material.solid_along and q.material.solid_along):
					continue
				var pair := [p, q] if p.get_instance_id() < q.get_instance_id() else [q, p]
				if done.has(pair):
					continue
				done[pair] = true
				_collide_pair(p, q, h)


func _collide_pair(p: Member, q: Member, h: float) -> void:
	var gap := (p.material.thickness + q.material.thickness) / 2.0
	var box_p := Rect2(p.a.pos, Vector2.ZERO).expand(p.b.pos).grow(gap)
	if not box_p.intersects(Rect2(q.a.pos, Vector2.ZERO).expand(q.b.pos)):
		return
	var cp := Geometry2D.get_closest_points_between_segments(p.a.pos, p.b.pos, q.a.pos, q.b.pos)
	var off: Vector2 = cp[1] - cp[0]
	var dist := off.length()
	if dist >= gap:
		return
	var n := off / dist if dist > 1e-6 else (p.b.pos - p.a.pos).orthogonal().normalized()
	var tp := _t_along(p, cp[0])
	var tq := _t_along(q, cp[1])
	# Each joint's share of the correction: p is pushed back along n, q forward.
	var js: Array[Joint] = [p.a, p.b, q.a, q.b]
	var ws: Array[float] = [-p.a.inv_mass * (1.0 - tp), -p.b.inv_mass * tp, q.a.inv_mass * (1.0 - tq), q.b.inv_mass * tq]
	var arms: Array[float] = [1.0 - tp, tp, 1.0 - tq, tq]
	var w := 0.0
	for k in 4:
		w += absf(ws[k]) * arms[k]
	if w <= 0.0:
		return
	var vs: Array[Vector2] = []
	for j in js:
		vs.append(j.pos - j.prev)
	var closing := (vs[2].lerp(vs[3], tq) - vs[0].lerp(vs[1], tp)).dot(n)
	var push := (gap - dist) / w
	var stop := -minf(closing, 0.0) / w
	for k in 4:
		js[k].pos += n * push * ws[k]
		js[k].prev = js[k].pos - (vs[k] + n * stop * ws[k])


static func _t_along(m: Member, p: Vector2) -> float:
	var d := m.b.pos - m.a.pos
	return clampf((p - m.a.pos).dot(d) / maxf(d.length_squared(), 1e-6), 0.0, 1.0)


## Records a hit on cell by member m with mass moving v (per substep h) against a face with this normal, if at
## harm_speed.
func _strike(cell: Vector2i, m: Member, mass: float, v: Vector2, normal: Vector2, h: float) -> void:
	var into := -v.dot(normal) / h
	if into >= harm_speed:
		_hits.append([cell, m, 0.5 * mass * into * into])


## Settles this tick's hits: each cell takes the damage of all its hits (struck); a piece whose hit carried more
## than its Impact Strength breaks if the cell held.
func _resolve_hits() -> void:
	var hits := _hits
	_hits = []
	var damage := {}
	for hit: Array in hits:
		var m: Member = hit[1]
		damage[hit[0]] = damage.get(hit[0], 0.0) + hit[2] * m.material.ram
	for hit: Array in hits:
		var m: Member = hit[1]
		var t := terrain.type_at(hit[0])
		var strength := m.material.impact_strength
		if not m.dead and t and not t.breaks_under(damage[hit[0]]) and strength > 0.0 and hit[2] > strength:
			break_member(m)
	for c: Vector2i in damage:
		if damage[c] > 0.0:
			struck.emit(c, damage[c])


## Velocity change (per substep) a contact with this outward normal gives a point moving v: no velocity into the
## surface, and sliding slowed by Coulomb friction (at most ground_friction times that stop). Working velocity out
## from the push-out instead would make every contact a small kick upward, and loose pieces would never rest.
func _contact_dv(v: Vector2, normal: Vector2) -> Vector2:
	var vn := v.dot(normal)
	if vn >= 0.0:
		return Vector2.ZERO
	var vt := v - normal * vn
	var grip := ground_friction * -vn
	var dt := -vt if vt.length() <= grip else -vt.normalized() * grip
	return normal * -vn + dt


## Applies a contact at t along member m (its ends moving va, vb before; wa, wb, w: their shares, as for the
## push) as an impulse at that point only, so the piece turns about it instead of stopping dead.
## surface_vel: how fast what it touches moves (per substep).
func _contact_at(m: Member, t: float, va: Vector2, vb: Vector2, wa: float, wb: float, w: float, normal: Vector2,
		surface_vel: Vector2 = Vector2.ZERO) -> void:
	var dv := _contact_dv(va.lerp(vb, t) - surface_vel, normal) / w
	m.a.prev = m.a.pos - (va + dv * wa)
	m.b.prev = m.b.pos - (vb + dv * wb)


## Keeps built members out of body b, or marks it crushed by one reaching it at harm_speed or more.
func _collide_body(b: Body, h: float) -> void:
	if b.crushed:
		return
	if b.is_box():
		for m in members:
			if not m.blueprint and m != b.skip and m.material.solid_along:
				_collide_member(m, h, _push_out_of_box.bind(b), false)
		return
	for m in members:
		if m.blueprint or m == b.skip or not m.material.solid_to_bodies:
			continue
		var d := m.b.pos - m.a.pos
		var t := clampf((b.center - m.a.pos).dot(d) / maxf(d.length_squared(), 1e-6), 0.0, 1.0)
		var off := m.a.pos.lerp(m.b.pos, t) - b.center
		var dist := off.length()
		if dist >= b.radius:
			continue
		var n := off / dist if dist > 1e-6 else Vector2.UP
		var va := m.a.pos - m.a.prev
		var vb := m.b.pos - m.b.prev
		if -(va.lerp(vb, t) / h - b.vel).dot(n) >= harm_speed:
			b.crushed = true
			return
		if n.y < -0.5:
			# Lying on the body: it carries the piece's weight there, and what the piece carries.
			b.load += (m.a.mass + m.a.load) * (1.0 - t) + (m.b.mass + m.b.load) * t
		var wa := m.a.inv_mass * (1.0 - t)
		var wb := m.b.inv_mass * t
		var w := wa * (1.0 - t) + wb * t
		if w <= 0.0:
			continue
		var push := (b.radius - dist) / w
		m.a.pos += n * push * wa
		m.b.pos += n * push * wb
		_contact_at(m, t, va, vb, wa, wb, w, n, b.vel * h)


static func _on_grid(v: float) -> bool:
	return absf(v - roundf(v)) < 1e-6


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
