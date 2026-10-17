extends GutTest
## The king's patience: the column waits at the start of a level until ordered to march.

const MAP: Array = [
	"..............",
	"..............",
	"##############",
	"BBBBBBBBBBBBBB",
]

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


func _run(seconds: float) -> void:
	for i in int(seconds * 60):
		level._physics_process(1.0 / 60.0)


func test_column_waits_for_the_king() -> void:
	level.march_delay = 2.0
	level.start(2, 1)
	watch_signals(level)
	var x0 := level.army.lead().pos.x
	_run(1.0)
	assert_true(level.army.hold)
	assert_almost_eq(level.march_left(), 1.0, 0.05)
	assert_eq(level.army.lead().pos.x, x0)
	_run(1.5)
	assert_false(level.army.hold, "king lost patience")
	assert_signal_emitted_with_parameters(level, "march_ordered", [false])
	assert_eq(level.march_left(), 0.0)


func test_player_can_march_early() -> void:
	level.march_delay = 30.0
	level.start(2, 1)
	watch_signals(level)
	level.march()
	assert_false(level.army.hold)
	assert_signal_emitted_with_parameters(level, "march_ordered", [true])
	level.march()
	assert_signal_emit_count(level, "march_ordered", 1, "only once")


func test_no_delay_marches_at_once() -> void:
	level.march_delay = 0.0
	level.start(2, 1)
	assert_false(level.army.hold)
