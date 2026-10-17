extends GutTest


func _world(rows: Array) -> Army:
	var t := WorldFixture.terrain(self, rows)
	var b := WorldFixture.bridge(self, t)
	return WorldFixture.army(self, t, b)


func _run(a: Army, seconds: float) -> void:
	for i in int(seconds * 60):
		a.bridge.step(1.0 / 60.0, a.bridge_loads())
		a.step(1.0 / 60.0)


func test_marches_on_flat_ground() -> void:
	var a := _world(["....................", "####################", "BBBBBBBBBBBBBBBBBBBB"])
	a.spawn(1, 2.5)
	var x0: float = a.lead().pos.x
	_run(a, 1.0)
	assert_almost_eq(a.lead().pos.x - x0, a.rules.march_speed, a.rules.march_speed * 0.15)
	assert_eq(a.lead().pos.y, 1.0)


func test_steps_up_one_metre() -> void:
	var a := _world(["..........", "......####", "##########", "BBBBBBBBBB"])
	a.spawn(1, 2.5)
	_run(a, 3.0)
	assert_gt(a.lead().pos.x, 6.5)
	assert_eq(a.halt_reason, "")


func test_halts_at_two_metre_wall() -> void:
	var a := _world(["..........", "......####", "......####", "##########", "BBBBBBBBBB"])
	a.spawn(1, 2.5)
	_run(a, 3.0)
	assert_lt(a.lead().pos.x, 6.0)
	assert_eq(a.halt_reason, "2 m wall ahead")


func test_halts_before_deep_drop() -> void:
	var a := _world([
		"..........",
		"#####.....",
		"#####.....",
		"#####.....",
		"#####.....",
		"#####.....",
		"##########",
		"BBBBBBBBBB",
	])
	a.spawn(1, 1.5)
	_run(a, 3.0)
	assert_lt(a.lead().pos.x, 5.0)
	assert_eq(a.halt_reason, "5 m drop ahead")


func test_halts_before_water() -> void:
	var a := _world(["..........", "#####~~~~~", "##########", "BBBBBBBBBB"])
	a.spawn(1, 1.5)
	_run(a, 3.0)
	assert_lt(a.lead().pos.x, 5.0)
	assert_eq(a.halt_reason, "Water ahead")


func test_long_fall_kills() -> void:
	var a := _world(["..........", "..........", "..........", "..........", "..........", "..........", "..........", "##########", "BBBBBBBBBB"])
	a.spawn(1, 2.5)
	var s: Soldier = a.lead()
	s.pos.y = 0.0
	s.airborne = true
	s.fall_from = 0.0
	watch_signals(a)
	_run(a, 1.0)
	assert_signal_emitted_with_parameters(a, "soldier_died", [Vector2(s.pos.x, s.pos.y), "Fell"])
	assert_eq(a.soldiers.size(), 0)


func test_crosses_log_bridge() -> void:
	var a := _world([
		"............",
		"............",
		"####....####",
		"####....####",
		"####....####",
		"BBBBBBBBBBBB",
	])
	var b := a.bridge
	b.build(b.snap_point(Vector2(4, 2)), b.snap_point(Vector2(8, 2)), preload("res://data/bridge/log.tres"))
	a.spawn(1, 1.5)
	_run(a, 6.0)
	assert_gt(a.lead().pos.x, 9.0, "made it across")


func test_queue_keeps_spacing() -> void:
	var a := _world(["..........", "......####", "......####", "##########", "BBBBBBBBBB"])
	a.spawn(3, 3.5)
	_run(a, 4.0)
	var s := a.soldiers
	assert_gte(s[0].pos.x - s[1].pos.x, a.rules.spacing - 0.05)
	assert_gte(s[1].pos.x - s[2].pos.x, a.rules.spacing - 0.05)


func test_holds_until_released() -> void:
	var a := _world(["....................", "####################", "BBBBBBBBBBBBBBBBBBBB"])
	a.spawn(1, 2.5)
	a.hold = true
	var x0: float = a.lead().pos.x
	_run(a, 1.0)
	assert_eq(a.lead().pos.x, x0, "waits")
	assert_eq(a.halt_reason, a.rules.hold_text)
	a.hold = false
	_run(a, 1.0)
	assert_gt(a.lead().pos.x, x0 + 1.0, "marches")
