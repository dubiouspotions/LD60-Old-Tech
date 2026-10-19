extends GutTest
## The king's patience: the column camps at the start of a level until ordered to march.

const MAP: Array = [
	"..............",
	"..............",
	"##############",
	"BBBBBBBBBBBBBB",
]

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


func _run(seconds: float) -> void:
	for i in int(seconds * 60):
		world._physics_process(1.0 / 60.0)


func test_column_waits_for_the_king() -> void:
	world.start_at(6.5, 2, 2.0)
	watch_signals(world)
	var front := world.army.camp_x + (world.army.soldiers.size() - 1) / 2.0 * world.army.rules.camp_spacing
	_run(1.0)
	assert_true(world.camping())
	assert_almost_eq(world.march_left(), 1.0, 0.05)
	assert_lte(world.army.lead().pos.x, front + 0.01, "no further than its camp spot")
	_run(1.5)
	assert_false(world.camping(), "king lost patience")
	assert_signal_emitted_with_parameters(world, "march_ordered", [false])
	assert_eq(world.march_left(), 0.0)


func test_player_can_march_early() -> void:
	world.start_at(6.5, 2, 30.0)
	watch_signals(world)
	world.march()
	assert_false(world.camping())
	assert_signal_emitted_with_parameters(world, "march_ordered", [true])
	world.march()
	assert_signal_emit_count(world, "march_ordered", 1, "only once")


func test_no_delay_marches_at_once() -> void:
	world.start_at(6.5, 2, 0.0)
	assert_false(world.camping())
