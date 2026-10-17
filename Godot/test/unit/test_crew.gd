extends GutTest
## The engineer crew building an ordered plan on a real level scene, stepped by hand.

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

var level: Level


func before_each() -> void:
	GameState.save_path = "user://test_sappers.cfg"
	GameState.new_campaign()
	level = load("res://levels/level_base.tscn").instantiate()
	add_child_autofree(level)
	level.set_physics_process(false)
	level.terrain.clear()
	level.terrain.rebuild()
	for y in MAP.size():
		for x in MAP[y].length():
			var key: String = WorldFixture.LEGEND[MAP[y][x]]
			if key != "":
				level.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	level.army.spawn(4, 5.5)
	level.crew.spawn(5.5)


func _plan(a: Vector2, b: Vector2, mat: BridgeMaterial = LOG) -> Bridge.Member:
	var bridge := level.bridge
	return bridge.build(bridge.snap_point(a), bridge.snap_point(b), mat, true)


## Steps bridge and crew (the column stays put) until done() or seconds pass. speed is the game speed.
func _run(seconds: float, done: Callable = func() -> bool: return false, speed: float = 1.0) -> void:
	for i in int(seconds * 60 / speed):
		level.bridge.step(speed / 60.0)
		level.crew.step(speed / 60.0)
		if done.call():
			return


func test_engineers_outpace_the_column() -> void:
	assert_gt(level.crew.rules.walk_speed, level.army.rules.march_speed * 1.5)


## Engineers have their own look, so new soldier art does not turn them into soldiers.
func test_engineer_scene_does_not_inherit_soldier_art() -> void:
	var scene: PackedScene = level.crew.engineer_scene
	assert_null(scene.get_state().get_node_instance(0), "not an inherited scene")
	var engineer: Node = scene.instantiate()
	assert_eq(engineer.find_children("*", "Sprite2D", true, false).size(), 0, "no soldier sprites")
	engineer.free()


func test_crew_size_comes_from_rules() -> void:
	assert_eq(level.crew.engineers.size(), level.crew.rules.crew_size)


func test_crew_builds_plan_outward_then_strikes() -> void:
	var first := _plan(Vector2(6, 6), Vector2(8, 6))
	var second := _plan(Vector2(8, 6), Vector2(10, 6))
	level.bridge.order_blueprints()
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
	level.bridge.order_blueprints()
	var in_pit := [false]  # an array, so the lambda can write to it
	_run(60.0, func() -> bool:
		for e in level.crew.engineers:
			in_pit[0] = in_pit[0] or (e.pos.x > 6.3 and e.pos.x < 9.7 and e.pos.y > 7.5)
		return plan.all(func(m: Bridge.Member) -> bool: return not m.blueprint))
	for m in plan:
		assert_false(m.blueprint, "%s built" % m.material.display_name)
	assert_false(in_pit[0], "nobody walks through the spikes")


## At 2× speed the last step toward a joint on the cliff edge lands exactly on the edge.
func test_crew_reaches_edge_joint_at_double_speed() -> void:
	for e in level.crew.engineers:
		e.pos.x = 5.93
	var m := _plan(Vector2(6, 6), Vector2(8, 6))
	level.bridge.order_blueprints()
	_run(10.0, func() -> bool: return not m.blueprint, 2.0)
	assert_false(m.blueprint)


func test_crew_digs_marked_soil() -> void:
	var earth := GameState.supplies.earth
	level.terrain.mark(Vector2i(3, 6))
	_run(10.0, func() -> bool: return level.terrain.type_at(Vector2i(3, 6)) == null)
	assert_null(level.terrain.type_at(Vector2i(3, 6)))
	assert_false(level.terrain.is_marked(Vector2i(3, 6)))
	assert_eq(GameState.supplies.earth, earth + 1)


func test_crew_digs_down_into_its_own_hole() -> void:
	level.terrain.mark(Vector2i(3, 6))
	level.terrain.mark(Vector2i(3, 7))
	_run(15.0, func() -> bool: return level.terrain.type_at(Vector2i(3, 7)) == null)
	assert_null(level.terrain.type_at(Vector2i(3, 6)))
	assert_null(level.terrain.type_at(Vector2i(3, 7)))


func test_crew_fells_marked_tree() -> void:
	var trunk := WorldFixture.type("trunk")
	var leaves := WorldFixture.type("leaves")
	level.terrain.set_type(Vector2i(2, 5), trunk)
	level.terrain.set_type(Vector2i(2, 4), trunk)
	level.terrain.set_type(Vector2i(1, 4), leaves)
	level.terrain.set_type(Vector2i(3, 4), leaves)
	var logs := GameState.supplies.logs
	level.terrain.mark(Vector2i(2, 5))
	_run(15.0, func() -> bool: return level.terrain.type_at(Vector2i(2, 5)) == null)
	assert_null(level.terrain.type_at(Vector2i(2, 4)), "whole tree felled")
	assert_gt(GameState.supplies.logs, logs)


func test_crew_fells_tree_marked_at_the_top() -> void:
	var trunk := WorldFixture.type("trunk")
	var leaves := WorldFixture.type("leaves")
	for y in [3, 4, 5]:
		level.terrain.set_type(Vector2i(2, y), trunk)
	for x in [1, 2, 3]:
		level.terrain.set_type(Vector2i(x, 2), leaves)
	level.terrain.mark(Vector2i(2, 2))
	_run(15.0, func() -> bool: return level.terrain.type_at(Vector2i(2, 5)) == null)
	assert_null(level.terrain.type_at(Vector2i(2, 5)), "cut at the base")
	assert_null(level.terrain.type_at(Vector2i(2, 2)))


func test_crew_leaves_unreachable_marks() -> void:
	level.terrain.mark(Vector2i(11, 6))
	var in_pit := [false]  # an array, so the lambda can write to it
	_run(10.0, func() -> bool:
		for e in level.crew.engineers:
			in_pit[0] = in_pit[0] or (e.pos.x > 6.3 and e.pos.x < 9.7 and e.pos.y > 7.5)
		return false)
	assert_true(level.terrain.is_marked(Vector2i(11, 6)), "across the pit")
	assert_false(in_pit[0], "nobody walks through the spikes")


func test_crew_idles_without_orders() -> void:
	_plan(Vector2(6, 6), Vector2(8, 6))
	_run(1.0)
	for e in level.crew.engineers:
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
	level.terrain.clear()
	level.terrain.rebuild()
	for y in TUNNEL.size():
		for x in TUNNEL[y].length():
			var key: String = WorldFixture.LEGEND[TUNNEL[y][x]]
			if key != "":
				level.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	level.army.spawn(1, 12.5)
	level.crew.spawn(3.0)
	var highest := [99.0]  # an array, so the lambda can write to it
	_run(10.0, func() -> bool:
		for e in level.crew.engineers:
			highest[0] = minf(highest[0], e.pos.y)
		return level.crew.engineers.all(func(e: Crew.Engineer) -> bool: return e.pos.x > 9.0))
	for e in level.crew.engineers:
		assert_gt(e.pos.x, 9.0, "came through")
	assert_gt(highest[0], 5.5, "stayed in the tunnel")
