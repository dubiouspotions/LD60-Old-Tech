extends GutTest
## The engineer crew building an ordered plan on a real world, stepped by hand.

const MAP: Array = [
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
	"######....####",
	"######....####",
	"######^^^^####",
	"BBBBBBBBBBBBBB",
]

const LOG := preload("res://data/bridge/log.tres")
const SUPPORT := preload("res://data/bridge/support.tres")
const ROPE := preload("res://data/bridge/rope.tres")

var world: World


func before_each() -> void:
	GameState.save_path = "user://test_sappers.cfg"
	GameState.new_campaign()
	world = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	world.set_physics_process(false)
	world.terrain.clear()
	world.terrain.rebuild()
	for y in MAP.size():
		for x in MAP[y].length():
			var key: String = WorldFixture.LEGEND[MAP[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(4, 5.5)
	world.crew.spawn(5.5)


func _plan(a: Vector2, b: Vector2, mat: BridgeMaterial = LOG) -> Bridge.Member:
	var bridge := world.bridge
	return bridge.build(bridge.snap_point(a), bridge.snap_point(b), mat, true)


## Steps bridge and crew (the column stays put) until done() or seconds pass. speed is the game speed.
func _run(seconds: float, done: Callable = func() -> bool: return false, speed: float = 1.0) -> void:
	for i in int(seconds * 60 / speed):
		world.bridge.step(speed / 60.0)
		world.crew.step(speed / 60.0)
		world.wood.advance(speed / 60.0)
		if done.call():
			return


func test_an_engineer_takes_a_marked_piece_apart_and_gets_back_one_less() -> void:
	var bridge := world.bridge
	var m := bridge.build(bridge.snap_point(Vector2(5, 6)), bridge.snap_point(Vector2(7, 6)), LOG)
	var logs := GameState.supplies.logs
	m.dismantle = true
	_run(0.5)
	assert_true(m in bridge.members, "takes a while, like building")
	_run(15.0, func() -> bool: return not m in bridge.members)
	assert_false(m in bridge.members, "taken apart")
	assert_eq(GameState.supplies.logs, logs + m.paid.logs - 1)


func test_instant_work_takes_marked_pieces_apart_at_once() -> void:
	var bridge := world.bridge
	var m := bridge.build(bridge.snap_point(Vector2(5, 6)), bridge.snap_point(Vector2(7, 6)), LOG)
	m.dismantle = true
	world.crew.rules.instant_work = true
	_run(1.0 / 60.0)
	world.crew.rules.instant_work = false
	assert_false(m in bridge.members)


func test_engineers_outpace_the_column() -> void:
	assert_gt(world.crew.rules.walk_speed, world.army.rules.march_speed * 3.5)


## Engineers have their own look, so new soldier art does not turn them into soldiers.
func test_engineer_scene_does_not_inherit_soldier_art() -> void:
	var scene: PackedScene = world.crew.engineer_scene
	assert_null(scene.get_state().get_node_instance(0), "not an inherited scene")
	var engineer: Node = scene.instantiate()
	assert_eq(engineer.find_children("*", "Sprite2D", true, false).size(), 0, "no soldier sprites")
	engineer.free()


func test_crew_size_comes_from_rules() -> void:
	assert_eq(world.crew.engineers.size(), world.crew.rules.crew_size)


func test_crew_builds_plan_outward_then_strikes() -> void:
	var first := _plan(Vector2(6, 6), Vector2(8, 6))
	var second := _plan(Vector2(8, 6), Vector2(10, 6))
	world.bridge.order_blueprints()
	_run(0.5)
	assert_true(second.blueprint, "not built in one go")
	_run(30.0, func() -> bool: return not first.blueprint and not second.blueprint)
	assert_false(first.blueprint)
	assert_false(second.blueprint)
	_run(10.0, func() -> bool: return not second.scaffolded)
	assert_false(second.scaffolded, "scaffolding struck when done")


## The layout from the playtest: deck to a mid joint held by a support from the wall, then deck and rope across.
func test_crew_climbs_finished_parts_to_reach_far_members() -> void:
	var plan: Array[Bridge.Member] = [
		_plan(Vector2(6, 6), Vector2(8, 6)),
		_plan(Vector2(6, 8), Vector2(8, 6), SUPPORT),
		_plan(Vector2(8, 6), Vector2(10, 6)),
		_plan(Vector2(8, 6), Vector2(10, 8), ROPE),
	]
	world.bridge.order_blueprints()
	# Standing in the pit means y >= 8. Climbing the support or rope stays above that.
	var in_pit := [false]  # an array, so the lambda can write to it
	_run(60.0, func() -> bool:
		for e in world.crew.engineers:
			in_pit[0] = in_pit[0] or (e.pos.x > 6.3 and e.pos.x < 9.7 and e.pos.y > 7.9)
		return plan.all(func(m: Bridge.Member) -> bool: return not m.blueprint))
	for m in plan:
		assert_false(m.blueprint, "%s built" % m.material.display_name)
	assert_false(in_pit[0], "nobody walks through the spikes")


## At 2× speed the last step toward a joint on the cliff edge lands exactly on the edge.
func test_crew_reaches_edge_joint_at_double_speed() -> void:
	for e in world.crew.engineers:
		e.pos.x = 5.93
	var m := _plan(Vector2(6, 6), Vector2(8, 6))
	world.bridge.order_blueprints()
	_run(10.0, func() -> bool: return not m.blueprint, 2.0)
	assert_false(m.blueprint)


func test_crew_digs_marked_soil() -> void:
	var earth := GameState.supplies.earth
	world.terrain.mark(Vector2i(3, 6))
	_run(10.0, func() -> bool: return world.terrain.type_at(Vector2i(3, 6)) == null)
	assert_null(world.terrain.type_at(Vector2i(3, 6)))
	assert_false(world.terrain.is_marked(Vector2i(3, 6)))
	assert_eq(GameState.supplies.earth, earth + 1)


## Steps the world until done(), counting the work sound's blows and each engineer's jolts (with the point of each
## jolt checked against where(e)). Returns [blows heard, {engineer: jolts}].
func _count_jolts(seconds: float, done: Callable, where: Callable) -> Array:
	var blows := [0]
	var listen := func(sfx: SoundEffect) -> void:
		if sfx == world.crew.rules.work_sound:
			blows[0] += 1
	Audio.played.connect(listen)
	var jolts := {}
	var was := {}
	_run(seconds, func() -> bool:
		for e: Crew.Engineer in world.crew.engineers:
			e.node._process(1.0 / 60.0) # the frame that passes with each step here
			var now: bool = e.node.work_shake() != Vector2.ZERO
			if now and not was.get(e, false):
				jolts[e] = jolts.get(e, 0) + 1
				var to: Vector2 = where.call(e) - (e.pos - Vector2(0, 0.5))
				assert_gt(e.node.work_shake().dot(to), 0.0, "towards the work")
			was[e] = now
		return done.call())
	Audio.played.disconnect(listen)
	return [blows[0], jolts]


## The engineer digging (or chopping) jolts towards its work once on every blow you hear, the last being the one
## that breaks the cell (soil breaks with the same sound), and not in between; the others stay still.
func test_the_digger_jolts_once_per_audible_blow() -> void:
	var cell := Vector2i(3, 6)
	world.terrain.mark(cell)
	var counted := _count_jolts(12.0, func() -> bool: return world.terrain.type_at(cell) == null,
			func(_e: Crew.Engineer) -> Vector2: return Vector2(cell) + Vector2(0.5, 0.5))
	assert_null(world.terrain.type_at(cell), "dug")
	var jolts: Dictionary = counted[1]
	assert_eq(jolts.size(), 1, "only the digger jolts")
	assert_gt(counted[0], 1, "several blows heard")
	assert_eq(jolts.values()[0], counted[0], "one jolt per blow heard")


## Building a bridge piece jolts its builder towards the piece on every blow you hear, and once more as it is put
## in place (with the material's place sound).
func test_the_builder_jolts_once_per_audible_blow() -> void:
	var m := _plan(Vector2(6, 6), Vector2(8, 6))
	world.bridge.order_blueprints()
	var counted := _count_jolts(30.0, func() -> bool: return not m.blueprint,
			func(_e: Crew.Engineer) -> Vector2: return (m.a.pos + m.b.pos) / 2.0)
	assert_false(m.blueprint, "built")
	var jolts: Dictionary = counted[1]
	assert_eq(jolts.size(), 1, "only the builder jolts")
	assert_gt(counted[0], 1, "several blows heard")
	assert_eq(jolts.values()[0], counted[0] + 1, "one jolt per blow, and one as it is placed")


## Building out from a joint, the builder is drawn hopping about the built part of the piece near where it grows
## (Build Wander): it pops from spot to spot (Build Wander Interval) without walking, a cartoon busy look. Only the
## look moves: the builder itself stays on its joint. It faces the growing end and tilts towards it (at most Build
## Lean Max). Once the piece is done it pops back where it is, upright.
func test_the_builder_moves_about_near_the_growing_end() -> void:
	var rules: CrewRules = world.crew.rules
	assert_gt(rules.build_wander, 0.0)
	assert_gt(rules.build_wander_interval, 0.0)
	var m := _plan(Vector2(6, 6), Vector2(10, 6))
	world.bridge.order_blueprints()
	var spots := {}
	var builder := [null]
	var hops := [0]
	var moves := [0]
	var backs := [0]
	var last := [Vector2.INF]
	_run(30.0, func() -> bool:
		for e: Crew.Engineer in world.crew.engineers:
			if e.job == m and e.working and is_nan(e.reach_x) and m.progress > 0.0:
				builder[0] = e
				assert_eq(e.pos, e.at.pos if e.at else e.pos, "the builder itself stays on its joint")
				var drawn := e.node.pos
				var from := m.from_joint.pos
				var far := m.b.pos if m.from_joint == m.a else m.a.pos
				var along := (drawn - from).dot((far - from).normalized())
				var tip := m.progress * m.length
				assert_lte(along, tip + 0.3, "not past the built part")
				# A spot stays put till the next hop while the piece grows on past it.
				var grown := m.material.build_speed * rules.build_wander_interval
				assert_gte(along, tip - rules.build_wander - grown - 0.05, "near where it grows")
				assert_almost_eq(absf((drawn - from).cross((far - from).normalized())), 0.0, 0.3, "on the piece")
				spots[snappedf(along, 0.25)] = true
				assert_false(e.node.moving, "no walking between spots")
				var to := from.lerp(far, m.progress) - (drawn - Vector2(0, 0.5))
				if absf(to.x) > 0.3:
					assert_eq(e.node.facing, signi(roundi(to.x * 100)), "facing the growing end")
					var lean := clampf(atan(to.y / to.x), -deg_to_rad(rules.build_lean_max), deg_to_rad(rules.build_lean_max))
					assert_almost_eq(e.node.lean, lean, 0.25, "tilted towards it")
				if last[0] != Vector2.INF and drawn.distance_to(last[0]) > 0.01:
					moves[0] += 1
					if drawn.distance_to(last[0]) > rules.climb_speed / 60.0 + 0.01:
						hops[0] += 1
						if (drawn - last[0]).dot(far - from) < 0.0:
							backs[0] += 1
				last[0] = drawn
		return not m.blueprint)
	assert_false(m.blueprint, "built")
	assert_not_null(builder[0], "built from a joint")
	assert_gt(spots.size(), 3, "moved about while building")
	assert_gt(hops[0], 3, "popping from spot to spot in one frame")
	assert_gt(backs[0], 0, "now and then back along the piece, not only following its end")
	assert_lte(moves[0], ceili(m.length / m.material.build_speed / rules.build_wander_interval) + 2,
			"only on hops: no sliding along with the growing end in between")
	_run(1.0 / 60.0)
	var e: Crew.Engineer = builder[0]
	assert_almost_eq(e.node.pos.x, e.pos.x, 0.3, "popped back where it is once done")
	assert_eq(e.node.rotation, 0.0, "and upright")


func test_crew_digs_down_into_its_own_hole() -> void:
	world.terrain.mark(Vector2i(3, 6))
	world.terrain.mark(Vector2i(3, 7))
	_run(15.0, func() -> bool: return world.terrain.type_at(Vector2i(3, 7)) == null)
	assert_null(world.terrain.type_at(Vector2i(3, 6)))
	assert_null(world.terrain.type_at(Vector2i(3, 7)))


func test_crew_does_not_dig_through_soil() -> void:
	world.terrain.mark(Vector2i(3, 7))
	_run(8.0)
	assert_true(world.terrain.is_marked(Vector2i(3, 7)), "the cell above is still there")


func test_crew_climbs_under_a_bridge_to_dig_the_floor_of_the_hole() -> void:
	world.terrain.set_type(Vector2i(3, 6), null)
	world.bridge.build(world.bridge.snap_point(Vector2(3, 6)), world.bridge.snap_point(Vector2(4, 6)), LOG)
	world.terrain.mark(Vector2i(3, 7))
	_run(15.0, func() -> bool: return world.terrain.type_at(Vector2i(3, 7)) == null)
	assert_null(world.terrain.type_at(Vector2i(3, 7)), "dug from down in the hole")
	_run(6.0)
	for e in world.crew.engineers:
		assert_lt(e.pos.y, 6.05, "climbed back out")


func test_crew_fells_marked_tree() -> void:
	var trunk := WorldFixture.type("trunk")
	var leaves := WorldFixture.type("leaves")
	world.terrain.set_type(Vector2i(2, 5), trunk)
	world.terrain.set_type(Vector2i(2, 4), trunk)
	world.terrain.set_type(Vector2i(1, 4), leaves)
	world.terrain.set_type(Vector2i(3, 4), leaves)
	var logs := GameState.supplies.logs
	world.terrain.mark(Vector2i(2, 5))
	_run(15.0, func() -> bool: return world.terrain.type_at(Vector2i(2, 5)) == null)
	assert_null(world.terrain.type_at(Vector2i(2, 4)), "whole tree felled")
	_run(20.0, func() -> bool: return world.wood.count() == 0)
	assert_gt(GameState.supplies.logs, logs, "its logs, once the wood is picked up")


## Each swing of the axe while felling: on the beat of the work sound, at the cell being felled.
func test_felling_chops_on_the_work_beat() -> void:
	var trunk := WorldFixture.type("trunk")
	world.terrain.set_type(Vector2i(2, 5), trunk)
	world.terrain.set_type(Vector2i(2, 4), trunk)
	var chops: Array[Vector2i] = []
	world.crew.chopped.connect(func(cell: Vector2i) -> void: chops.append(cell))
	world.terrain.mark(Vector2i(2, 5))
	_run(15.0, func() -> bool: return world.terrain.type_at(Vector2i(2, 5)) == null)
	var work := trunk.dig_time / world.crew.rules.dig_speed
	assert_between(chops.size(), 1, int(work / world.crew.rules.work_sound_interval) + 2, "about one per beat")
	for c in chops:
		assert_eq(c, Vector2i(2, 5))


func test_digging_earth_is_not_chopping() -> void:
	var chops := []
	world.crew.chopped.connect(func(cell: Vector2i) -> void: chops.append(cell))
	world.terrain.mark(Vector2i(2, 6))
	_run(15.0, func() -> bool: return world.terrain.type_at(Vector2i(2, 6)) == null)
	assert_eq(chops.size(), 0)


func test_crew_fells_tree_marked_at_the_top() -> void:
	var trunk := WorldFixture.type("trunk")
	var leaves := WorldFixture.type("leaves")
	for y in [3, 4, 5]:
		world.terrain.set_type(Vector2i(2, y), trunk)
	for x in [1, 2, 3]:
		world.terrain.set_type(Vector2i(x, 2), leaves)
	world.terrain.mark(Vector2i(2, 2))
	_run(15.0, func() -> bool: return world.terrain.type_at(Vector2i(2, 5)) == null)
	assert_null(world.terrain.type_at(Vector2i(2, 5)), "cut at the base")
	assert_null(world.terrain.type_at(Vector2i(2, 2)))


func test_crew_leaves_unreachable_marks() -> void:
	world.terrain.mark(Vector2i(11, 6))
	var in_pit := [false]  # an array, so the lambda can write to it
	_run(10.0, func() -> bool:
		for e in world.crew.engineers:
			in_pit[0] = in_pit[0] or (e.pos.x > 6.3 and e.pos.x < 9.7 and e.pos.y > 7.9)
		return false)
	assert_true(world.terrain.is_marked(Vector2i(11, 6)), "across the pit")
	assert_false(in_pit[0], "nobody walks through the spikes")


func test_crew_gets_ready_beside_a_new_plan() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for y in TWO_PITS.size():
		for x in TWO_PITS[y].length():
			var key: String = WorldFixture.LEGEND[TWO_PITS[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(1, 10.5)
	world.crew.spawn(10.5)
	_plan(Vector2(16, 6), Vector2(18.5, 6))
	_run(5.0)
	for e in world.crew.engineers:
		assert_null(e.job, "not ordered yet")
		assert_between(e.pos.x, 13.0, 16.0, "waiting at the near end of the plan")


func test_only_one_engineer_builds_a_member() -> void:
	var m := _plan(Vector2(6, 6), Vector2(8, 6))
	world.bridge.order_blueprints()
	var most := [0]  # an array, so the lambda can write to it
	_run(10.0, func() -> bool:
		most[0] = maxi(most[0], world.crew.engineers.filter(func(e: Crew.Engineer) -> bool: return e.job == m).size())
		return not m.blueprint)
	assert_false(m.blueprint, "built")
	assert_eq(most[0], 1, "one engineer per member")


func test_only_one_engineer_digs_a_cell() -> void:
	world.terrain.mark(Vector2i(3, 6))
	var most := [0]
	_run(5.0, func() -> bool:
		most[0] = maxi(most[0], world.crew.engineers.filter(func(e: Crew.Engineer) -> bool: return e.digging and e.dig == Vector2i(3, 6)).size())
		return world.terrain.type_at(Vector2i(3, 6)) == null)
	assert_null(world.terrain.type_at(Vector2i(3, 6)), "dug")
	assert_eq(most[0], 1, "one engineer per cell")


func test_crew_idles_without_orders() -> void:
	_plan(Vector2(6, 6), Vector2(8, 6))
	_run(1.0)
	for e in world.crew.engineers:
		assert_null(e.job)


## A rock hill with a tunnel dug under it. The hill top is within climbing reach of the tunnel floor.
const TUNNEL: Array = [
	"..............",
	"..............",
	"..............",
	"...RRRR.......",
	"..............",
	"..............",
	"##############",
	"##############",
	"BBBBBBBBBBBBBB",
]


func test_crew_walks_through_tunnel_not_over_hill() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for y in TUNNEL.size():
		for x in TUNNEL[y].length():
			var key: String = WorldFixture.LEGEND[TUNNEL[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(1, 12.5)
	world.crew.spawn(3.0)
	var highest := [99.0]  # an array, so the lambda can write to it
	_run(10.0, func() -> bool:
		for e in world.crew.engineers:
			highest[0] = minf(highest[0], e.pos.y)
		return world.crew.engineers.all(func(e: Crew.Engineer) -> bool: return e.pos.x > 9.0))
	for e in world.crew.engineers:
		assert_gt(e.pos.x, 9.0, "came through")
	assert_gt(highest[0], 5.5, "stayed in the tunnel")



## Two pits: a 2 m one and a 5 m one, with ground between them.
const TWO_PITS: Array = [
	"........................",
	"........................",
	"........................",
	"........................",
	"........................",
	"........................",
	"######..########.....###",
	"######..########.....###",
	"######^^########^^^^^###",
	"BBBBBBBBBBBBBBBBBBBBBBBB",
]


func test_each_structure_comes_off_scaffolding_when_it_is_done() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for y in TWO_PITS.size():
		for x in TWO_PITS[y].length():
			var key: String = WorldFixture.LEGEND[TWO_PITS[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	# The crew stands between the pits, so both bridges are worked on at once. The column waits behind both,
	# so neither counts as an old site behind it.
	world.army.spawn(1, 2.5)
	world.crew.spawn(12.5)
	var near := _plan(Vector2(6, 6), Vector2(8, 6))
	var far: Array[Bridge.Member] = [
		_plan(Vector2(16, 6), Vector2(18.5, 6)),
		_plan(Vector2(18.5, 6), Vector2(21, 6)),
		_plan(Vector2(16, 8), Vector2(18.5, 6), SUPPORT),
		_plan(Vector2(21, 8), Vector2(18.5, 6), SUPPORT),
	]
	world.bridge.order_blueprints()
	_run(30.0, func() -> bool: return not near.blueprint and not near.scaffolded)
	assert_false(near.scaffolded, "near bridge struck on its own")
	assert_true(far.any(func(m: Bridge.Member) -> bool: return m.blueprint or m.scaffolded), "far bridge still in work")
	_run(60.0, func() -> bool: return far.all(func(m: Bridge.Member) -> bool: return not m.blueprint and not m.scaffolded))
	for m in far:
		assert_false(m.scaffolded, "far bridge struck when done")


func test_crew_builds_a_floating_plan_it_can_reach_from_the_ground() -> void:
	var m := _plan(Vector2(2, 4), Vector2(4, 4))
	world.bridge.order_blueprints()
	_run(15.0, func() -> bool: return not m.blueprint)
	assert_false(m.blueprint, "built from the ground, not from a joint")
	assert_true(m.scaffolded, "held up by scaffolding")


func test_crew_leaves_a_floating_plan_out_of_reach() -> void:
	var m := _plan(Vector2(2, 1), Vector2(4, 1))
	world.bridge.order_blueprints()
	_run(10.0)
	assert_true(m.blueprint, "too high to reach from the ground")


func test_idle_crew_walks_behind_the_army() -> void:
	_run(3.0)
	var rear := world.army.rear().pos.x
	for e in world.crew.engineers:
		assert_lt(e.pos.x, rear, "behind the last soldier")


func test_each_material_builds_at_its_own_speed() -> void:
	var quick: BridgeMaterial = LOG.duplicate()
	quick.build_speed = 8.0
	var slow: BridgeMaterial = LOG.duplicate()
	slow.build_speed = 0.5
	var fast_member := _plan(Vector2(6, 6), Vector2(8, 6), quick)
	world.bridge.order_blueprints()
	_run(5.0, func() -> bool: return not fast_member.blueprint)
	var slow_member := _plan(Vector2(10, 6), Vector2(12, 6), slow)
	world.bridge.order_blueprints()
	var started := [false]
	_run(5.0, func() -> bool:
		started[0] = started[0] or slow_member.progress > 0.0
		return started[0])
	_run(1.0)
	assert_lt(slow_member.progress, 0.5, "0.5 m/s takes 4 s for 2 m")


func test_dig_speed_scales_digging() -> void:
	world.crew.rules = world.crew.rules.duplicate()
	world.crew.rules.dig_speed = 4.0
	world.terrain.mark(Vector2i(3, 6))
	var seconds := [0.0]
	_run(5.0, func() -> bool:
		if world.crew.engineers.any(func(e: Crew.Engineer) -> bool: return e.working):
			seconds[0] += 1.0 / 60.0
		return world.terrain.type_at(Vector2i(3, 6)) == null)
	assert_lt(seconds[0], WorldFixture.type("soil").dig_time / 4.0 + 0.1, "digs four times as fast")


func test_engineer_left_in_the_air_falls_to_the_ground() -> void:
	var e: Crew.Engineer = world.crew.engineers[0]
	e.at = null
	e.route.clear()
	e.pos = Vector2(3.0, 2.0)
	_run(2.0)
	assert_almost_eq(e.pos.y, 6.0, 0.05, "landed on the ground")


func test_engineer_falls_when_the_bridge_under_it_breaks() -> void:
	var m := _plan(Vector2(6, 6), Vector2(10, 6))
	world.bridge.order_blueprints()
	_run(20.0, func() -> bool: return not m.blueprint)
	var e: Crew.Engineer = world.crew.engineers[0]
	var mid := world.bridge.split(m, Vector2(8, 6))
	e.at = mid
	e.route.clear()
	e.pos = mid.pos
	for other in world.bridge.members.duplicate():
		world.bridge.break_member(other, true)
	_run(2.0)
	assert_gt(e.pos.y, 7.5, "fell into the pit")


## Ground at row 6 on the left, a 2 m step up from x = 8.
const STEP: Array = [
	"..................",
	"..................",
	"..................",
	"..................",
	"........##########",
	"........##########",
	"##################",
	"BBBBBBBBBBBBBBBBBB",
]


func test_crew_climbs_a_step_without_entering_the_rock() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for y in STEP.size():
		for x in STEP[y].length():
			var key: String = WorldFixture.LEGEND[STEP[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(1, 16.5)
	world.crew.spawn(4.0)
	var inside := [false]
	_run(6.0, func() -> bool:
		for e in world.crew.engineers:
			for h in [0.1, 0.8, 1.5]:
				inside[0] = inside[0] or world.terrain.is_solid(Grid.cell_of(e.pos - Vector2(0, h)))
		return false)
	assert_false(inside[0], "nobody walks into the rock")
	for e in world.crew.engineers:
		assert_almost_eq(e.pos.y, 4.0, 0.05, "up on the step")


## Ground at row 6 with a one-high step up from x = 8 to 13: both ends are slopes.
const BUMP: Array = [
	"......................",
	"......................",
	"......................",
	"......................",
	"......................",
	"........######........",
	"######################",
	"BBBBBBBBBBBBBBBBBBBBBB",
]


func test_engineers_walk_over_slopes_at_walking_speed_without_shaking() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for y in BUMP.size():
		for x in BUMP[y].length():
			var key: String = WorldFixture.LEGEND[BUMP[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(1, 21.5)
	world.crew.spawn(4.0)
	var e: Crew.Engineer = world.crew.engineers[0]
	var path: Array[Vector2] = [e.pos]
	_run(4.0, func() -> bool:
		path.append(e.pos)
		return e.pos.x > 16.0)
	assert_gt(e.pos.x, 16.0, "over the bump")
	var dt := 1.0 / 60.0
	var started := -1
	for i in range(1, path.size()):
		var d := path[i] - path[i - 1]
		assert_lt(absf(d.y), world.crew.rules.walk_speed * dt + 0.01, "no jump at %s" % path[i])
		if started < 0 and path[i].x > 6.0:
			started = i
		if i > 1 and path[i].x > 6.0 and path[i].x < 16.0:
			assert_gt(d.x, 0.0, "keeps walking at %s" % path[i])
			assert_true(signf(d.y) == 0.0 or signf(path[i - 1].y - path[i - 2].y) != -signf(d.y), "no shaking at %s" % path[i])
	assert_lt((path.size() - started) * dt, 10.0 / world.crew.rules.walk_speed * 1.2, "about walking speed from x 6 to 16")


## The column does not follow the engineer out onto a piece being built: it waits at the foot of it.
func test_column_waits_while_the_engineer_builds_a_piece() -> void:
	world.army.spawn(3, 3.5)
	var m := _plan(Vector2(6, 6), Vector2(10, 6))
	world.bridge.order_blueprints()
	var furthest := [0.0]
	for i in 600:
		world._physics_process(1.0 / 60.0)
		if m.blueprint and world.army.lead():
			furthest[0] = maxf(furthest[0], world.army.lead().pos.x)
	assert_gt(furthest[0], 5.0, "walked up to it")
	assert_lt(furthest[0], 6.0, "and waited at the foot while it was being built")


## A flat 100 m strip with the column at x 50.5, the crew around it and a camera on it.
func _flat_strip() -> CameraRig:
	world.terrain.clear()
	world.terrain.rebuild()
	for x in 100:
		world.terrain.set_type(Vector2i(x, 6), WorldFixture.type("soil"))
		world.terrain.set_type(Vector2i(x, 7), WorldFixture.type("bedrock"))
	world.army.spawn(1, 50.5)
	world.crew.spawn(50.5)
	var cam := CameraRig.new()
	cam.world = world
	add_child_autofree(cam)
	cam.make_current()
	return cam


## Nobody is further back than the camera can be panned.
func _nobody_behind(cam: CameraRig) -> bool:
	var edge := cam.reach_m().x
	return world.crew.engineers.all(func(e: Crew.Engineer) -> bool: return e.pos.x >= edge - 0.05)


func test_crew_leaves_old_sites_behind_the_column_alone() -> void:
	var cam := _flat_strip()
	world.terrain.mark(Vector2i(3, 6))
	assert_gt(cam.reach_m().x, 4.0, "the old site is out of the camera's reach")
	var stayed := [true]
	_run(8.0, func() -> bool:
		stayed[0] = stayed[0] and _nobody_behind(cam)
		return false)
	assert_true(stayed[0], "nobody runs back to the old site")
	assert_true(world.terrain.is_marked(Vector2i(3, 6)))


func test_crew_builds_behind_the_column_as_far_as_the_camera_reaches() -> void:
	var cam := _flat_strip()
	var m := _plan(Vector2(30, 6), Vector2(31, 3), ROPE)
	assert_lt(cam.reach_m().x, 30.0, "the camera can be panned to it")
	world.bridge.order_blueprints()
	_run(30.0, func() -> bool: return not m.blueprint)
	assert_false(m.blueprint, "20 m behind the column, built")


func test_crew_builds_ahead_of_the_column_wherever_the_camera_is() -> void:
	_flat_strip()
	world.terrain.mark(Vector2i(64, 6))
	_run(10.0, func() -> bool: return world.terrain.type_at(Vector2i(64, 6)) == null)
	assert_null(world.terrain.type_at(Vector2i(64, 6)), "far ahead, still done")


func test_crew_left_behind_catches_up_with_the_column() -> void:
	var cam := _flat_strip()
	world.crew.spawn(3.0)
	_run(8.0)
	assert_true(_nobody_behind(cam))


func test_idle_crew_waits_in_front_of_the_camp_at_night() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for x in 40:
		world.terrain.set_type(Vector2i(x, 6), WorldFixture.type("soil"))
		world.terrain.set_type(Vector2i(x, 7), WorldFixture.type("bedrock"))
	world.start_at(30.5, 6, 30.0)
	world.crew.spawn(29.5)
	var behind := [false]
	_run(10.0, func() -> bool:
		var lead := world.army.lead().pos.x
		behind[0] = behind[0] or world.crew.engineers.any(func(e: Crew.Engineer) -> bool: return e.pos.x < lead - 0.1 and e.pos.x < 25.0)
		return false)
	var lead := world.army.lead().pos.x
	assert_false(behind[0], "nobody heads back along the sleeping column")
	for e in world.crew.engineers:
		assert_gte(e.pos.x, lead - 0.1, "waiting in front of the camp")


## Flat ground at row 10 with a 4 m tower from x = 10, a deck from the tower out to x = 6 on a support.
const TOWER: Array = [
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
	"..........####",
	"..........####",
	"..........####",
	"..........####",
	"##############",
	"BBBBBBBBBBBBBB",
]


func _tower_with_deck() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for y in TOWER.size():
		for x in TOWER[y].length():
			var key: String = WorldFixture.LEGEND[TOWER[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	var bridge := world.bridge
	bridge.build(bridge.snap_point(Vector2(8, 10)), bridge.snap_point(Vector2(6, 6)), SUPPORT)
	bridge.build(bridge.snap_point(Vector2(6, 6)), bridge.snap_point(Vector2(10, 6)), LOG)
	world.army.spawn(1, 3.5)


func test_idle_engineer_climbs_down_the_support_to_the_column() -> void:
	_tower_with_deck()
	var e: Crew.Engineer = world.crew.engineers[0]
	e.at = world.bridge.snap_point(Vector2(6, 6)).node
	e.route.clear()
	e.pos = e.at.pos
	_run(10.0)
	assert_almost_eq(e.pos.y, 10.0, 0.05, "down on the ground")
	assert_lt(e.pos.x, 6.0, "back with the column")


func test_idle_engineer_on_the_deck_climbs_down_the_support() -> void:
	_tower_with_deck()
	var e: Crew.Engineer = world.crew.engineers[0]
	e.at = null
	e.route.clear()
	e.pos = Vector2(7.0, 6.0)
	_run(10.0)
	assert_almost_eq(e.pos.y, 10.0, 0.05, "down on the ground")
	assert_lt(e.pos.x, 6.0, "back with the column")


func test_idle_engineer_on_the_tower_climbs_down_the_support() -> void:
	_tower_with_deck()
	var e: Crew.Engineer = world.crew.engineers[0]
	e.at = null
	e.route.clear()
	e.pos = Vector2(11.5, 6.0)
	_run(10.0)
	assert_almost_eq(e.pos.y, 10.0, 0.05, "down on the ground")
	assert_lt(e.pos.x, 6.0, "back with the column")


## A 4 m plateau from x = 4 to 9 above ground at row 6.
const PLATEAU: Array = [
	"..................",
	"..................",
	"....######........",
	"....######........",
	"....######........",
	"....######........",
	"##################",
	"BBBBBBBBBBBBBBBBBB",
]


func _on_plateau() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for y in PLATEAU.size():
		for x in PLATEAU[y].length():
			var key: String = WorldFixture.LEGEND[PLATEAU[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(1, 5.5)
	world.army.hold = true
	world.crew.spawn(5.5)
	world.crew.engineers[0].pos = Vector2(9.7, 2.0)


func test_crew_on_a_plateau_builds_a_support_down_off_its_edge() -> void:
	_on_plateau()
	var m := _plan(Vector2(10, 2), Vector2(12, 6), SUPPORT)
	world.bridge.order_blueprints()
	_run(15.0, func() -> bool: return not m.blueprint)
	assert_false(m.blueprint, "built from the plateau")


func test_crew_on_a_plateau_builds_a_deck_and_support_off_its_face() -> void:
	_on_plateau()
	var deck := _plan(Vector2(10, 2), Vector2(13, 2))
	var prop := _plan(Vector2(10, 4), Vector2(13, 2), SUPPORT)
	world.bridge.order_blueprints()
	_run(30.0, func() -> bool: return not deck.blueprint and not prop.blueprint)
	assert_false(deck.blueprint, "deck built")
	assert_false(prop.blueprint, "support built")


func test_crew_on_a_plateau_builds_a_support_off_its_face() -> void:
	_on_plateau()
	var prop := _plan(Vector2(10, 4), Vector2(12, 2), SUPPORT)
	world.bridge.order_blueprints()
	_run(15.0, func() -> bool: return not prop.blueprint)
	assert_false(prop.blueprint, "support built")


## A 5 m pit from x = 4 to 8 with a 1 m ledge on its right, ground at row 2.
const PIT: Array = [
	"............",
	"............",
	"####....####",
	"####....####",
	"####....####",
	"####....####",
	"####...#####",
	"############",
	"BBBBBBBBBBBB",
]


## Bridges the pit at ground level with a support hanging from the middle of the deck down to bottom.
func _bridged_pit(bottom: Vector2 = Vector2(6.4, 6.6)) -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for y in PIT.size():
		for x in PIT[y].length():
			var key: String = WorldFixture.LEGEND[PIT[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	var bridge := world.bridge
	bridge.build(bridge.snap_point(Vector2(4, 2)), bridge.snap_point(Vector2(8, 2)), LOG)
	bridge.build(bridge.snap_point(Vector2(6, 2)), bridge.snap_point(bottom), SUPPORT)
	world.army.spawn(1, 2.5)


func _climbs_out_from(p: Vector2, bottom: Vector2 = Vector2(6.4, 6.6)) -> void:
	_bridged_pit(bottom)
	var e: Crew.Engineer = world.crew.engineers[0]
	e.at = null
	e.route.clear()
	e.pos = p
	_run(15.0)
	assert_almost_eq(e.pos.y, 2.0, 0.05, "out of the pit from %s" % p)


func test_engineer_on_the_pit_floor_climbs_out_up_the_support() -> void:
	_climbs_out_from(Vector2(6.0, 7.0))


func test_engineer_on_a_ledge_in_the_pit_climbs_out_up_the_support() -> void:
	_climbs_out_from(Vector2(7.5, 6.0))


func test_engineer_at_the_far_wall_of_the_pit_climbs_out_up_the_support() -> void:
	_climbs_out_from(Vector2(4.4, 7.0))


func test_engineer_climbs_up_to_a_support_hanging_above_his_head() -> void:
	_climbs_out_from(Vector2(5.5, 7.0), Vector2(6.4, 5.5))


func test_engineer_builds_from_a_support_hanging_above_his_head() -> void:
	_bridged_pit(Vector2(6.4, 5.5))
	var e: Crew.Engineer = world.crew.engineers[0]
	e.pos = Vector2(5.5, 7.0)
	var m := _plan(Vector2(6.4, 5.5), Vector2(7.5, 5.5))
	world.bridge.order_blueprints()
	_run(15.0, func() -> bool: return not m.blueprint)
	assert_false(m.blueprint, "built off the hanging end")


func test_stranded_engineer_climbs_down_to_the_column() -> void:
	_flat_strip()
	for y in range(1, 6):
		world.terrain.set_type(Vector2i(40, y), WorldFixture.type("soil"))
	var e: Crew.Engineer = world.crew.engineers[0]
	e.pos = Vector2(40.6, 1.0)
	_assert_climbs_back(e, 45.0)


func test_stranded_engineer_climbs_out_of_a_deep_pit() -> void:
	_flat_strip()
	for x in range(44, 46):
		for y in range(1, 7):
			world.terrain.set_type(Vector2i(x, y), null)
		world.terrain.set_type(Vector2i(x, 6), null)
	for x in range(44, 46):
		world.terrain.set_type(Vector2i(x, 7), WorldFixture.type("soil"))
	for x in [43, 46]:
		for y in range(1, 6):
			world.terrain.set_type(Vector2i(x, y), WorldFixture.type("soil"))
	var e: Crew.Engineer = world.crew.engineers[0]
	e.pos = Vector2(44.8, 7.0)
	_assert_climbs_back(e, 46.5)


## The engineer gets back on the column's ground beyond x by moving, never jumping more than a step.
func _assert_climbs_back(e: Crew.Engineer, x: float) -> void:
	var jump := [0.0]
	var last := [e.pos]
	_run(world.crew.rules.stranded_time + 8.0, func() -> bool:
		jump[0] = maxf(jump[0], e.pos.distance_to(last[0]))
		last[0] = e.pos
		return false)
	assert_lt(jump[0], 0.3, "moved, not teleported")
	assert_almost_eq(e.pos.y, 6.0, 0.05, "on the column's ground")
	assert_gt(e.pos.x, x, "back with the column")


func test_crew_builds_from_a_joint_on_a_cliff_face_without_entering_the_rock() -> void:
	var m := _plan(Vector2(6, 6.5), Vector2(10, 6.5))
	world.bridge.order_blueprints()
	var inside := [false]
	_run(20.0, func() -> bool:
		for e in world.crew.engineers:
			for h in [0.3, 1.0, 1.5]:
				for side in [-0.15, 0.15]:
					inside[0] = inside[0] or world.terrain.is_solid(Grid.cell_of(e.node.pos + Vector2(side, -h)))
		return not m.blueprint)
	assert_false(m.blueprint, "built")
	assert_false(inside[0], "nobody drawn inside the cliff")


func test_crew_climbs_any_height_to_marks_it_can_not_reach_otherwise() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	var rows := [
		"....................",
		"####....############",
		"####....############",
		"####....############",
		"####....############",
		"####....############",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
	]
	for y in rows.size():
		for x in rows[y].length():
			var key: String = WorldFixture.LEGEND[rows[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(1, 2.5)
	world.crew.spawn(2.5)
	world.terrain.mark(Vector2i(10, 1))
	_run(25.0, func() -> bool: return world.terrain.type_at(Vector2i(10, 1)) == null)
	assert_null(world.terrain.type_at(Vector2i(10, 1)), "dug across the 5 m pit")


## The way to a mark may lead away from it first: back off the ledge, down into the pit beside it, and along the
## floor under the ledge.
func test_crew_finds_a_way_round_to_a_mark_under_its_ledge() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	var rows := [
		"....................",
		"###.....##########..",
		"###.....##########..",
		"###.....##########..",
		"###.....##########..",
		"###...............##",
		"###...............##",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
	]
	for y in rows.size():
		for x in rows[y].length():
			var key: String = WorldFixture.LEGEND[rows[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(1, 1.5)
	world.crew.spawn(1.5)
	world.army.lead().pos = Vector2(14.5, 7.0)
	var e: Crew.Engineer = world.crew.engineers[0]
	e.pos = Vector2(13.5, 1.0)
	world.terrain.mark(Vector2i(12, 7))
	var jump := [0.0]
	var last := [e.pos]
	_run(30.0, func() -> bool:
		jump[0] = maxf(jump[0], e.pos.distance_to(last[0]))
		last[0] = e.pos
		return world.terrain.type_at(Vector2i(12, 7)) == null)
	assert_null(world.terrain.type_at(Vector2i(12, 7)), "dug from the floor under the ledge")
	assert_lt(jump[0], 0.3, "walked and climbed there, never teleported")


## Marks nobody can reach cost little: idle engineers keep looking for a way, without slowing the game down.
func test_unreachable_marks_do_not_slow_the_crew_down() -> void:
	_flat_strip()
	for i in 4:
		world.crew.hire(world.crew.engineers[0].pos.x)
	for x in range(20, 40):
		world.terrain.set_type(Vector2i(x, 8), WorldFixture.type("soil"))
		world.terrain.mark(Vector2i(x, 8))
	assert_eq(world.terrain.marked_cells().size(), 20, "under the bedrock: nobody can reach them")
	_run(1.0)
	var worst := 0.0
	var total := 0.0
	for i in 120:
		var t := Time.get_ticks_usec()
		_run(1.0 / 60.0)
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		worst = maxf(worst, ms)
		total += ms
	gut.p("crew step with 20 unreachable marks: %.2f ms on average, %.2f ms at worst" % [total / 120.0, worst])
	assert_lt(total / 120.0, 1.0, "ms per step on average")
	assert_lt(worst, 8.0, "ms in the slowest step")


## An engineer standing on a deck end at the water line lives, as a soldier there does: only a body in the water
## drowns, not feet resting on its surface.
func test_an_engineer_on_a_deck_end_at_the_water_line_lives() -> void:
	for x in range(6, 10):
		world.terrain.set_type(Vector2i(x, 6), WorldFixture.type("water"))
		world.terrain.set_type(Vector2i(x, 7), WorldFixture.type("water"))
	var e: Crew.Engineer = world.crew.engineers[0]
	e.pos = Vector2(7.5, 6.0)
	e.at = null
	var before := world.crew.engineers.size()
	world.crew.step(1.0 / 60.0)
	assert_eq(world.crew.engineers.size(), before, "feet on the water's surface: alive")
	e.pos = Vector2(7.5, 6.6)
	world.crew.step(1.0 / 60.0)
	assert_eq(world.crew.engineers.size(), before - 1, "body in the water: drowned")


## Marks on top of a ledge beside the engineer are dug without walking back and forth.
func test_crew_digs_marks_on_a_ledge_without_pinballing() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	var rows := [
		"....................",
		"....................",
		"....................",
		"..........##########",
		"..........##########",
		"....######EEE#######",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
	]
	var marks: Array[Vector2i] = []
	for y in rows.size():
		for x in rows[y].length():
			var ch: String = rows[y][x]
			if ch == "E":
				marks.append(Vector2i(x, y))
				ch = "#"
			var key: String = WorldFixture.LEGEND[ch]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(1, 2.5)
	world.crew.spawn(2.5)
	var e: Crew.Engineer = world.crew.engineers[0]
	e.pos = Vector2(6.5, 5.0)
	for c in [Vector2i(10, 3), Vector2i(11, 3), Vector2i(12, 3), Vector2i(10, 4), Vector2i(11, 4)]:
		world.terrain.mark(c)
	var turns := [0]
	var last := [e.pos.x]
	var dir := [0]
	_run(30.0, func() -> bool:
		var d := signi(roundi((e.pos.x - last[0]) * 1000))
		if d != 0 and dir[0] != 0 and d != dir[0]:
			turns[0] += 1
		if d != 0:
			dir[0] = d
		last[0] = e.pos.x
		return world.terrain.marked_cells().is_empty())
	assert_eq(world.terrain.marked_cells().size(), 0, "all dug")
	assert_lt(turns[0], 12, "no back and forth: %d turns" % turns[0])


## The job nearest ahead of the leader comes first, even when one behind the column is nearer to the engineer.
func test_crew_takes_the_job_nearest_ahead_of_the_leader_first() -> void:
	_flat_strip()
	var e: Crew.Engineer = world.crew.engineers[0]
	e.pos = Vector2(46.5, 6.0)
	world.terrain.mark(Vector2i(47, 6))
	world.terrain.mark(Vector2i(54, 6))
	_run(20.0, func() -> bool: return world.terrain.marked_cells().size() < 2)
	assert_null(world.terrain.type_at(Vector2i(54, 6)), "ahead of the leader: dug first")
	assert_not_null(world.terrain.type_at(Vector2i(47, 6)), "behind the column: waits")


## On its way to a job, an engineer takes a more urgent one that is nearer to it, but not one that is further.
func test_crew_switches_to_a_more_urgent_job_on_its_way_only_if_nearer() -> void:
	_flat_strip()
	var e: Crew.Engineer = world.crew.engineers[0]
	e.pos = Vector2(52.5, 6.0)
	world.terrain.mark(Vector2i(62, 6))
	_run(0.5)
	assert_true(e.digging and e.dig == Vector2i(62, 6), "on its way to the only job")
	world.terrain.mark(Vector2i(40, 6))
	_run(0.5)
	assert_eq(e.dig, Vector2i(62, 6), "a job behind the leader is less urgent: carries on")
	var near := Vector2i(floori(e.pos.x) + 1, 6)
	world.terrain.mark(near)
	_run(0.5)
	assert_eq(e.dig, near, "more urgent and nearer: switches")


## An engineer on a bridge over spikes that breaks falls with it and dies on the spikes. (Right at the pit's edge,
## with a foot over the ground, it holds on instead, as a soldier does.)
func test_an_engineer_falling_off_a_broken_bridge_onto_spikes_dies() -> void:
	for x0: float in [6.5, 7.5, 8.5]:
		world.terrain.clear()
		world.terrain.rebuild()
		var rows := [
			"..............",
			"..............",
			"..............",
			"..............",
			"..............",
			"######....####",
			"######^^^^####",
			"##############",
			"BBBBBBBBBBBBBB",
		]
		for y in rows.size():
			for x in rows[y].length():
				var key: String = WorldFixture.LEGEND[rows[y][x]]
				if key != "":
					world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
		world.bridge.clear()
		world.crew.spawn(2.5)
		var m := world.bridge.build(world.bridge.snap_point(Vector2(6, 5)), world.bridge.snap_point(Vector2(10, 5)), LOG)
		var e: Crew.Engineer = world.crew.engineers[0]
		e.pos = Vector2(x0, world.bridge.walk_surface(x0, 0.0).y)
		world.bridge.break_member(m, true)
		_run(4.0)
		assert_false(e in world.crew.engineers, "fell onto the spikes from x %s and died" % x0)


## An engineer cut off from the column (on ground between spike pits) that makes no way back, even climbing any
## height, counts as stuck; one that gets going again does not.
func test_an_engineer_with_no_way_back_counts_as_stuck() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	var rows := [
		"....................",
		"....................",
		"....................",
		"....................",
		"....................",
		"####^^^^##^^^^######",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
	]
	for y in rows.size():
		for x in rows[y].length():
			var key: String = WorldFixture.LEGEND[rows[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(1, 17.5)
	world.crew.spawn(17.5)
	var e: Crew.Engineer = world.crew.engineers[0]
	e.pos = Vector2(9.0, 5.0)
	_run(world.crew.rules.stranded_time)
	assert_eq(world.crew.stuck_count(), 0, "not stuck yet: it tries climbing any height first")
	_run(world.crew.rules.stuck_time + 1.0)
	assert_eq(world.crew.stuck_count(), 1, "no way back at all: stuck")
	e.pos = Vector2(16.5, 5.0)
	_run(0.5)
	assert_eq(world.crew.stuck_count(), 0, "free again")


func test_instant_work_cheat_finishes_ordered_plans_at_once() -> void:
	var rules := world.crew.rules
	rules.instant_work = true
	var first := _plan(Vector2(6, 6), Vector2(8, 4))
	var second := _plan(Vector2(8, 4), Vector2(10, 6))
	var waiting := _plan(Vector2(2, 6), Vector2(3, 5))
	world.bridge.order_plan([first, second])
	_run(1.0 / 60.0)
	rules.instant_work = false
	assert_false(first.blueprint, "built")
	assert_false(second.blueprint, "built")
	assert_true(waiting.blueprint, "a plan not ordered stays a plan")


func test_instant_work_cheat_digs_marks_and_fells_trees_at_once() -> void:
	var rules := world.crew.rules
	world.terrain.set_type(Vector2i(2, 5), WorldFixture.type("trunk"))
	world.terrain.set_type(Vector2i(2, 4), WorldFixture.type("trunk"))
	world.terrain.mark(Vector2i(3, 6))
	world.terrain.mark(Vector2i(2, 4))
	var logs := GameState.supplies.logs
	rules.instant_work = true
	_run(1.0 / 60.0)
	rules.instant_work = false
	assert_null(world.terrain.type_at(Vector2i(3, 6)), "dug")
	assert_null(world.terrain.type_at(Vector2i(2, 5)), "tree felled")
	assert_gt(GameState.supplies.logs, logs, "and its logs gained")


func test_crew_builds_from_a_loose_end_by_the_cliff_when_the_bolted_end_is_across_the_gap() -> void:
	# A plan from just off the left cliff's face (not touching it) to the right cliff's face. Its only bolted end is
	# across the pit, out of the crew's reach; the loose end is within reach of the left cliff's top.
	var m := _plan(Vector2(6.5, 6.5), Vector2(10, 6.5))
	assert_false(m.a.pinned, "loose end")
	assert_true(m.b.pinned, "bolted across the pit")
	world.bridge.order_blueprints()
	_run(20.0, func() -> bool: return not m.blueprint)
	assert_false(m.blueprint, "built out from the loose end")


func test_an_engineer_falling_on_spikes_dies() -> void:
	var e: Crew.Engineer = world.crew.engineers[0]
	e.pos = Vector2(7.5, 2.0)
	var crew := world.crew.engineers.size()
	_run(3.0)
	assert_eq(world.crew.engineers.size(), crew - 1, "spiked")
	assert_false(e in world.crew.engineers)


func test_the_level_is_lost_when_the_last_engineer_dies() -> void:
	watch_signals(world)
	for e: Crew.Engineer in world.crew.engineers:
		e.pos = Vector2(7.5, 2.0)
	for i in 180:
		world._physics_process(1.0 / 60.0)
	assert_eq(world.crew.engineers.size(), 0)
	assert_signal_emitted(world, "crew_lost", "no crew left: game over")


func test_an_engineer_left_idle_on_a_cliff_face_joint_climbs_back_up() -> void:
	# The plan's end is bolted to the left cliff's face, half a metre below its top. Another engineer took the
	# job, so this one is left at the joint with nothing to do.
	var m := _plan(Vector2(6, 6.5), Vector2(10, 6.5))
	var e: Crew.Engineer = world.crew.engineers[0]
	e.at = m.a
	e.pos = m.a.pos
	e.route.clear()
	var inside := [false]
	_run(6.0, func() -> bool:
		inside[0] = inside[0] or world.terrain.is_solid(Grid.cell_of(e.pos - Vector2(0, 0.3)))
		return false)
	assert_false(inside[0], "never inside the cliff")
	assert_almost_eq(e.pos.y, 6.0, 0.05, "back up on the cliff top")
	assert_lt(e.pos.x, 6.0)


func test_a_lone_engineer_climbs_down_to_a_face_joint_and_builds_from_it() -> void:
	# Only one engineer, so nobody else can take the job over if it is given up on the way.
	while world.crew.engineers.size() > 1:
		var extra: Crew.Engineer = world.crew.engineers.pop_back()
		extra.node.queue_free()
	var m := _plan(Vector2(6, 7), Vector2(10, 7))
	world.bridge.order_blueprints()
	var gave_up := [false]
	var e: Crew.Engineer = world.crew.engineers[0]
	var had := [false]
	_run(20.0, func() -> bool:
		had[0] = had[0] or e.job == m
		gave_up[0] = gave_up[0] or (had[0] and e.job != m and m.blueprint)
		return not m.blueprint)
	assert_false(gave_up[0], "kept the job on the way down the face")
	assert_false(m.blueprint, "built it")


func test_an_engineer_comes_down_off_a_structure_bolted_to_a_tower_wall_without_bobbing() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	var rows := [
		"..................",
		"..................",
		"..................",
		"..........KKK.....",
		"..........KKK.....",
		"..........KKK.....",
		"..........KKK.....",
		"..........KKK.....",
		"##################",
		"BBBBBBBBBBBBBBBBBB",
	]
	for y in rows.size():
		for x in rows[y].length():
			var key: String = WorldFixture.LEGEND[rows[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(1, 3.5)
	world.army.hold = true
	world.crew.spawn(3.5)
	var up := _plan(Vector2(10, 4.5), Vector2(8.5, 1.5))
	var low := _plan(Vector2(10, 6), Vector2(8.5, 1.5))
	world.bridge.order_blueprints()
	var turns := [0]
	var last := {}
	for i in 60 * 30:
		var before := world.crew.engineers.map(func(e: Crew.Engineer) -> float: return e.pos.y)
		world._physics_process(1.0 / 60.0)
		if up.blueprint or low.blueprint:
			continue
		for k in world.crew.engineers.size():
			var dir := signi(roundi((world.crew.engineers[k].pos.y - before[k]) * 1000))
			if dir != 0 and last.get(k, 0) != 0 and dir != last[k]:
				turns[0] += 1
			if dir != 0:
				last[k] = dir
	assert_false(up.blueprint or low.blueprint, "built")
	assert_lt(turns[0], 6, "came down without bobbing up and down")
	for e: Crew.Engineer in world.crew.engineers:
		assert_almost_eq(e.pos.y, 8.0, 0.05, "back on the ground")
		assert_lt(e.pos.x, 10.0, "on the column's side of the tower")


## Ground at row 6, a pit 4 wide at x 8..11 down to row 9.
const SANDBAG_PIT: Array = [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"########....########",
	"########....########",
	"########....########",
	"####################",
	"BBBBBBBBBBBBBBBBBBBB",
]


func _pit() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for y in SANDBAG_PIT.size():
		for x in SANDBAG_PIT[y].length():
			var key: String = WorldFixture.LEGEND[SANDBAG_PIT[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(1, 2.5)
	world.crew.spawn(2.5)


func _sandbag_tool() -> ToolDefinition:
	return GameState.campaign.tools.filter(func(t: ToolDefinition) -> bool: return t.kind == ToolDefinition.Kind.FILL)[0]


## Runs the world until cell holds something or seconds pass; returns where the throw left the hands (INF if never).
func _throw_and_wait(cell: Vector2i, seconds: float = 10.0) -> Vector2:
	var from := [Vector2.INF]
	world.crew.threw.connect(func(_t: Crew.Throw, at: Vector2) -> void: from[0] = at)
	for i in int(seconds * 60):
		world.terrain.settle()
		world._physics_process(1.0 / 60.0)
		if world.terrain.type_at(cell) != null:
			break
	return from[0]


func test_an_engineer_throws_an_ordered_sandbag_from_5_tiles_aside_and_it_falls_to_the_ground() -> void:
	_pit()
	world.crew.order_throw(Vector2i(10, 3), _sandbag_tool())
	var from := _throw_and_wait(Vector2i(10, 8))
	assert_ne(from, Vector2.INF, "thrown")
	assert_almost_eq(absf(from.x - 10.5), world.crew.rules.throw_distance, 0.26, "from its liked distance aside")
	assert_eq(world.crew.rules.throw_distance, 5.0)
	assert_eq(world.terrain.type_at(Vector2i(10, 8)), WorldFixture.type("sandbag"), "fell to the bottom of the pit")
	assert_eq(world.crew.throws.size(), 0, "done")


func test_there_is_no_height_limit_to_a_throw() -> void:
	_pit()
	world.crew.order_throw(Vector2i(10, -14), _sandbag_tool())
	assert_ne(_throw_and_wait(Vector2i(10, 8), 15.0), Vector2.INF, "thrown 19 tiles up")
	assert_eq(world.terrain.type_at(Vector2i(10, 8)), WorldFixture.type("sandbag"))


## Ground only at both ends: a spiked gap from x 2 to 19 nobody walks into.
const WIDE_GAP: Array = [
	"......................",
	"......................",
	"......................",
	"......................",
	"......................",
	"......................",
	"##..................##",
	"##..................##",
	"##^^^^^^^^^^^^^^^^^^##",
	"BBBBBBBBBBBBBBBBBBBBBB",
]


func _wide_gap() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for y in WIDE_GAP.size():
		for x in WIDE_GAP[y].length():
			var key: String = WorldFixture.LEGEND[WIDE_GAP[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(1, 1.0)
	world.crew.spawn(1.0)


func test_an_engineer_throws_up_to_8_tiles_aside() -> void:
	_wide_gap()
	assert_eq(world.crew.rules.throw_reach, 8.0)
	world.crew.order_throw(Vector2i(9, 3), _sandbag_tool())
	var from := _throw_and_wait(Vector2i(9, 3), 3.0)
	assert_ne(from, Vector2.INF, "thrown from the gap's edge, near 8 tiles aside")
	assert_between(absf(from.x - 9.5), 7.0, 8.0)


func test_an_engineer_does_not_throw_further_than_8_tiles_aside() -> void:
	_wide_gap()
	world.crew.order_throw(Vector2i(10, 3), _sandbag_tool())
	assert_eq(_throw_and_wait(Vector2i(10, 3), 3.0), Vector2.INF, "9 tiles from either edge: nobody throws it")
	assert_eq(world.crew.throws.size(), 1, "still ordered")


func test_an_engineer_throws_from_where_the_arc_is_clear() -> void:
	_pit()
	# A block of bedrock hanging in the arc from the liked spot (5 aside, x 5.5).
	world.terrain.set_type(Vector2i(7, 2), WorldFixture.type("bedrock"))
	world.crew.order_throw(Vector2i(10, 4), _sandbag_tool())
	var from := _throw_and_wait(Vector2i(10, 8), 15.0)
	assert_ne(from, Vector2.INF, "thrown")
	assert_gt(absf(from.x - 5.5), 0.4, "not from the liked spot")
	assert_eq(world.terrain.type_at(Vector2i(10, 8)), WorldFixture.type("sandbag"), "not broken on the roof: it landed")


func test_instant_work_throws_ordered_sandbags_at_once() -> void:
	_pit()
	world.crew.order_throw(Vector2i(10, 3), _sandbag_tool())
	world.crew.rules.instant_work = true
	world.terrain.settle()
	world._physics_process(1.0 / 60.0)
	world.crew.rules.instant_work = false
	assert_eq(world.crew.throws.size(), 0)
	for i in 120:
		world.terrain.settle()
		world._physics_process(1.0 / 60.0)
	assert_eq(world.terrain.type_at(Vector2i(10, 8)), WorldFixture.type("sandbag"))


## A tower as high as an engineer climbs, with a sandbag on its middle: its top is a slope up to the bag.
const SLOPED_TOWER: Array = [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	".........S..........",
	"........KKK.........",
	"........KKK.........",
	"........KKK.........",
	"####################",
	"BBBBBBBBBBBBBBBBBBBB",
]


## Climbing the face of SLOPED_TOWER (mirrored: from the right) to throw from up on the tower, 5 aside.
func _climb_sloped_tower(mirrored: bool) -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	var w: int = SLOPED_TOWER[0].length()
	for y in SLOPED_TOWER.size():
		for x in w:
			var key: String = WorldFixture.LEGEND[SLOPED_TOWER[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(w - 1 - x if mirrored else x, y), WorldFixture.type(key))
	world.army.spawn(1, 2.5)
	world.army.hold = true
	world.crew.spawn(w - 2.5 if mirrored else 4.5)
	var e := world.crew.engineers[0]
	world.crew.order_throw(Vector2i(w - 1 - 13 if mirrored else 13, 2), _sandbag_tool())
	var from := [Vector2.INF]
	world.crew.threw.connect(func(_t: Crew.Throw, at: Vector2) -> void: from[0] = at)
	var fell := false
	for i in 300:
		world.terrain.settle()
		world._physics_process(1.0 / 60.0)
		fell = fell or e.vy > 0.0
		if from[0] != Vector2.INF:
			break
	assert_false(fell, "never fell off the face")
	assert_almost_eq(from[0].x, w - 8.5 if mirrored else 8.5, 0.1, "thrown from up on the tower, 5 aside")
	assert_lt(from[0].y, 7.0, "standing on top")


func test_an_engineer_climbs_a_face_with_a_slope_on_top_without_falling_off() -> void:
	_climb_sloped_tower(false)


func test_an_engineer_climbs_a_face_with_a_slope_on_top_from_the_right_too() -> void:
	_climb_sloped_tower(true)
