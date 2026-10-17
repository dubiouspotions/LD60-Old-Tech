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


## 5 m down: survivable, so the column walks off the edge and marches on.
const LEDGE: Array = [
	"..........",
	"#####.....",
	"#####.....",
	"#####.....",
	"#####.....",
	"#####.....",
	"##########",
	"BBBBBBBBBB",
]


func test_warns_of_drop_but_walks_off_it() -> void:
	var a := _world(LEDGE)
	a.spawn(1, 1.5)
	_run(a, 0.8)
	assert_eq(a.danger, "5 m drop ahead", "warned")
	assert_eq(a.halt_reason, "", "not halted")
	_run(a, 3.0)
	assert_gt(a.lead().pos.x, 6.0, "walked off and on")
	assert_eq(a.lead().pos.y, 6.0)


func test_marches_into_water() -> void:
	var a := _world(["..........", "#####~~~~~", "##########", "BBBBBBBBBB"])
	a.spawn(1, 1.5)
	watch_signals(a)
	_run(a, 3.0)
	assert_eq(a.soldiers.size(), 0, "orders are orders")
	assert_signal_emitted(a, "soldier_died")


func test_marches_into_deep_ravine() -> void:
	var a := _world([
		"............",
		"####....####",
		"####....####",
		"####....####",
		"####....####",
		"####....####",
		"####....####",
		"####....####",
		"####....####",
		"############",
		"BBBBBBBBBBBB",
	])
	a.spawn(1, 1.5)
	_run(a, 4.0)
	assert_eq(a.soldiers.size(), 0, "fell to its death")


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


## Ground at row 4, a 3 m wall from x = 10.
const RAMP_WALL: Array = [
	"....................",
	"..........##########",
	"..........##########",
	"..........##########",
	"####################",
	"BBBBBBBBBBBBBBBBBBBB",
]


func test_marches_under_unfinished_ramp_to_the_wall() -> void:
	var a := _world(RAMP_WALL)
	var b := a.bridge
	b.build(b.snap_point(Vector2(6, 4)), b.snap_point(Vector2(10, 1)), preload("res://data/bridge/log.tres"), true)
	b.order_blueprints()
	a.spawn(1, 2.5)
	_run(a, 6.0)
	assert_gt(a.lead().pos.x, 9.0, "did not wait for the engineers")
	assert_eq(a.halt_reason, "3 m wall ahead", "only a wall stops it")


func test_climbs_finished_ramp() -> void:
	var a := _world(RAMP_WALL)
	var b := a.bridge
	b.build(b.snap_point(Vector2(6, 4)), b.snap_point(Vector2(10, 1)), preload("res://data/bridge/log.tres"))
	a.spawn(1, 2.5)
	_run(a, 8.0)
	assert_gt(a.lead().pos.x, 10.5, "over the wall")
	assert_almost_eq(a.lead().pos.y, 1.0, 0.05)


func _archer_at(feet: Vector2) -> Archer:
	var archer: Archer = load("res://objects/archer/archer.tscn").instantiate()
	archer.position = Grid.to_px(feet)
	add_child_autofree(archer)
	return archer


func test_attacks_archer_it_reaches_then_marches_on() -> void:
	var a := _world(["....................", "####################", "BBBBBBBBBBBBBBBBBBBB"])
	var archer := _archer_at(Vector2(6.5, 1))
	a.foes = [archer]
	a.spawn(1, 2.5)
	for i in 40:
		_run(a, 0.1)
		if a.halt_reason == a.rules.fight_text:
			break
	assert_eq(a.halt_reason, a.rules.fight_text, "reached him and fights")
	assert_lt(a.lead().pos.x, 6.5, "stopped at him")
	_run(a, 0.2)
	assert_lt(archer.hp, archer.hit_points, "hit him")
	_run(a, 3.0)
	assert_false(archer.alive(), "slain")
	_run(a, 2.0)
	assert_gt(a.lead().pos.x, 8.0, "marched on")
