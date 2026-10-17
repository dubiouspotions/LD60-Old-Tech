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
		if done.call():
			return


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


func test_crew_digs_down_into_its_own_hole() -> void:
	world.terrain.mark(Vector2i(3, 6))
	world.terrain.mark(Vector2i(3, 7))
	_run(15.0, func() -> bool: return world.terrain.type_at(Vector2i(3, 7)) == null)
	assert_null(world.terrain.type_at(Vector2i(3, 6)))
	assert_null(world.terrain.type_at(Vector2i(3, 7)))


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
	assert_gt(GameState.supplies.logs, logs)


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


func test_column_follows_the_engineer_out_onto_a_piece_being_built() -> void:
	world.army.spawn(3, 3.5)
	var m := _plan(Vector2(6, 6), Vector2(10, 6))
	world.bridge.order_blueprints()
	var furthest := [0.0]
	for i in 600:
		world._physics_process(1.0 / 60.0)
		if m.blueprint and world.army.lead():
			furthest[0] = maxf(furthest[0], world.army.lead().pos.x)
	assert_gt(furthest[0], 6.5, "out on the built part before the piece is finished")


## A flat 40 m strip with the column at x 20.5 and the crew around it.
func _flat_strip() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for x in 40:
		world.terrain.set_type(Vector2i(x, 6), WorldFixture.type("soil"))
		world.terrain.set_type(Vector2i(x, 7), WorldFixture.type("bedrock"))
	world.army.spawn(1, 20.5)
	world.crew.spawn(20.5)


func _nobody_behind() -> bool:
	var edge := world.army.rear().pos.x - world.crew.rules.work_behind
	return world.crew.engineers.all(func(e: Crew.Engineer) -> bool: return e.pos.x >= edge - 0.05)


func test_crew_leaves_old_sites_behind_the_column_alone() -> void:
	_flat_strip()
	world.terrain.mark(Vector2i(3, 6))
	var stayed := [true]
	_run(8.0, func() -> bool:
		stayed[0] = stayed[0] and _nobody_behind()
		return false)
	assert_true(stayed[0], "nobody runs back to the old site")
	assert_true(world.terrain.is_marked(Vector2i(3, 6)))


func test_crew_builds_ahead_of_the_column_wherever_the_camera_is() -> void:
	_flat_strip()
	world.terrain.mark(Vector2i(34, 6))
	_run(10.0, func() -> bool: return world.terrain.type_at(Vector2i(34, 6)) == null)
	assert_null(world.terrain.type_at(Vector2i(34, 6)), "far ahead, still done")


func test_crew_left_behind_catches_up_with_the_column() -> void:
	_flat_strip()
	world.crew.spawn(3.0)
	_run(8.0)
	assert_true(_nobody_behind())


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
