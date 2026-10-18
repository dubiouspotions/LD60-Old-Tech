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


## Walks the lead soldier from x to past end and returns its height at every tick.
func _heights(a: Army, end: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	while a.lead().pos.x < end and out.size() < 600:
		_run(a, 1.0 / 60.0)
		out.append(a.lead().pos)
	return out


func _largest_jump(path: Array[Vector2]) -> float:
	var most := 0.0
	for i in range(1, path.size()):
		most = maxf(most, absf(path[i].y - path[i - 1].y))
	return most


func test_walks_up_a_step_along_its_slope() -> void:
	var a := _world(["..........", "......####", "##########", "BBBBBBBBBB"])
	a.spawn(1, 3.5)
	var path := _heights(a, 7.5)
	assert_lt(_largest_jump(path), 0.1, "no jump up the step")
	for p in path:
		if absf(p.x - 5.5) < 0.05:
			assert_almost_eq(p.y, 1.5, 0.05, "halfway up in the cell at the foot of the step")
	assert_eq(path[-1].y, 1.0, "on top")


func test_walks_down_a_step_along_its_slope() -> void:
	var a := _world(["..........", "####......", "##########", "BBBBBBBBBB"])
	a.spawn(1, 2.5)
	var path := _heights(a, 6.5)
	assert_lt(_largest_jump(path), 0.1, "no drop down the step")
	for p in path:
		if absf(p.x - 4.5) < 0.05:
			assert_almost_eq(p.y, 1.5, 0.05, "halfway down in the cell at the foot of the step")
	assert_eq(path[-1].y, 2.0, "at the bottom")


func test_halts_at_two_metre_wall() -> void:
	var a := _world(["..........", "......####", "......####", "##########", "BBBBBBBBBB"])
	a.spawn(1, 2.5)
	_run(a, 3.0)
	assert_lt(a.lead().pos.x, 6.0)
	assert_string_starts_with(a.halt_reason, "2 m wall ahead")


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
	assert_string_starts_with(a.halt_reason, "3 m wall ahead", "only a wall stops it")


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
	assert_lt(archer.hp, archer.rules.hit_points, "hit him")
	_run(a, 3.0)
	assert_false(archer.alive(), "slain")
	_run(a, 2.0)
	assert_gt(a.lead().pos.x, 8.0, "marched on")


func test_resting_column_closes_up_to_camp_then_sleeps() -> void:
	var a := _world(["..............................", "##############################", "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"])
	a.spawn(2, 20.5)
	var straggler := a.soldiers[1]
	straggler.pos.x = 12.5
	a.camp_x = 20.5
	a.resting = true
	_run(a, 1.0)
	assert_false(straggler.sleeping, "still walking to camp")
	assert_true(a.lead().sleeping, "the front lies down once it has stopped")
	_run(a, 8.0)
	assert_almost_eq(a.lead().pos.x, 20.5, 0.01, "nobody passes the camp")
	assert_almost_eq(straggler.pos.x, 20.5 - a.rules.camp_spacing, 0.15, "joined the camp")
	assert_true(straggler.sleeping)


func test_waking_stands_everyone_up() -> void:
	var a := _world(["..........", "##########", "BBBBBBBBBB"])
	a.spawn(2, 5.5)
	a.camp_x = 5.5
	a.resting = true
	_run(a, 2.0)
	assert_true(a.soldiers.all(func(s: Soldier) -> bool: return s.sleeping))
	a.resting = false
	assert_false(a.soldiers.any(func(s: Soldier) -> bool: return s.sleeping))


func test_dense_column_spreads_out_into_camp() -> void:
	var a := _world(["..............................", "##############################", "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"])
	a.spawn(4, 20.5)
	a.camp_x = 20.5
	a.resting = true
	_run(a, 8.0)
	for i in a.soldiers.size():
		assert_almost_eq(a.soldiers[i].pos.x, 20.5 - i * a.rules.camp_spacing, 0.1, "soldier %d on its spot" % i)
		assert_true(a.soldiers[i].sleeping)


func test_camp_squeezes_in_when_there_is_no_room_behind() -> void:
	var a := _world(["..........", "##########", "BBBBBBBBBB"])
	a.spawn(6, 3.5)
	a.camp_x = 3.5
	a.resting = true
	_run(a, 6.0)
	var xs := a.soldiers.map(func(s: Soldier) -> float: return s.pos.x)
	for i in range(1, xs.size()):
		assert_gt(xs[i - 1] - xs[i], 0.4, "soldiers %d and %d do not pile up" % [i - 1, i])
	assert_gte(xs[-1], 0.25, "nobody pressed into the edge")


func test_needs_two_metres_of_headroom() -> void:
	var a := _world([
		"..............",
		"......########",
		"..............",
		"##############",
		"BBBBBBBBBBBBBB",
	])
	a.spawn(1, 2.5)
	_run(a, 4.0)
	assert_lt(a.lead().pos.x, 6.0, "a 1 m gap is too low")
	assert_string_starts_with(a.halt_reason, a.rules.low_text)


func test_walks_through_a_two_metre_tunnel() -> void:
	var a := _world([
		"......########",
		"..............",
		"..............",
		"##############",
		"BBBBBBBBBBBBBB",
	])
	a.spawn(1, 2.5)
	_run(a, 4.0)
	assert_gt(a.lead().pos.x, 8.0)


func test_walks_onto_the_finished_part_of_a_bridge_being_built() -> void:
	var a := _world([
		"..................",
		"..................",
		"######......######",
		"######......######",
		"######......######",
		"BBBBBBBBBBBBBBBBBB",
	])
	var b := a.bridge
	var log := preload("res://data/bridge/log.tres")
	var first := b.build(b.snap_point(Vector2(6, 2)), b.snap_point(Vector2(9, 2)), log, true)
	var rest := b.build(b.snap_point(Vector2(9, 2)), b.snap_point(Vector2(12, 2)), log, true)
	b.order_blueprints()
	b.finish(first)
	rest.progress = 0.3
	a.spawn(1, 3.5)
	var furthest := [0.0]
	for i in 240:
		b.step(1.0 / 60.0, a.bridge_loads())
		a.step(1.0 / 60.0)
		if a.lead():
			furthest[0] = maxf(furthest[0], a.lead().pos.x)
	assert_gt(furthest[0], 7.0, "out on the finished piece")


func test_besieges_and_razes_a_tower_in_the_way() -> void:
	var a := _world([
		"....................",
		"..........KKK.......",
		"..........KKK.......",
		"..........KKK.......",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
	])
	a.spawn(1, 2.5)
	_run(a, 6.0)
	assert_eq(a.halt_reason, a.rules.siege_text, "attacking, not just halted")
	assert_gt(a.terrain.siege_progress(Vector2i(10, 3)), 0.0)
	var brick := WorldFixture.type("brick")
	_run(a, brick.raze_time + 1.0)
	assert_null(a.terrain.type_at(Vector2i(10, 2)), "tower razed")
	_run(a, 3.0)
	assert_gt(a.lead().pos.x, 12.5, "marched on")


## Ground at row 5 with a 4 m wall from x = 10, and a 4 m cliff behind the column at x = 5.
const BOXED_IN: Array = [
	"....................",
	"#####.....##########",
	"#####.....##########",
	"#####.....##########",
	"#####.....##########",
	"####################",
	"BBBBBBBBBBBBBBBBBBBB",
]


func test_blocked_soldier_counts_down_then_deserts() -> void:
	var a := _world(BOXED_IN)
	a.spawn(2, 8.5)
	watch_signals(a)
	_run(a, 2.0)
	assert_string_contains(a.halt_reason, "desert", "countdown shown")
	_run(a, a.rules.mutiny_time)
	assert_eq(a.soldiers.size(), 1, "the front soldier deserted")
	assert_eq(a.deserters.size(), 1)
	assert_signal_emitted(a, "count_changed")
	assert_eq(a.deserters[0].facing, -1, "walks back the way it came")


func test_deserter_climbs_a_cliff_on_the_way_out() -> void:
	var a := _world(BOXED_IN)
	a.spawn(1, 8.5)
	_run(a, a.rules.mutiny_time + 2.0)
	var d: Soldier = a.deserters[0]
	_run(a, 4.0)
	assert_lt(d.pos.x, 4.5, "went back over the cliff")
	assert_almost_eq(d.pos.y, 1.0, 0.1, "on top of it")


func test_besieging_does_not_count_toward_mutiny() -> void:
	var a := _world([
		"....................",
		"..........KKK.......",
		"..........KKK.......",
		"..........KKK.......",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
	])
	a.spawn(1, 8.5)
	_run(a, a.rules.mutiny_time + 2.0)
	assert_eq(a.soldiers.size(), 1, "still besieging")
	assert_eq(a.deserters.size(), 0)


func test_fighting_does_not_count_toward_mutiny() -> void:
	var a := _world(["....................", "####################", "BBBBBBBBBBBBBBBBBBBB"])
	var archer := _archer_at(Vector2(6.5, 1))
	a.spawn(1, 5.0)
	a.foes = [archer]
	_run(a, 0.1)
	archer.hp = 1000
	_run(a, a.rules.mutiny_time + 2.0)
	assert_eq(a.soldiers.size(), 1, "still fighting")
	assert_eq(a.deserters.size(), 0)


## Ground at row 4 with a 2 m dip at x 17-18, just behind a camp at x 20.5.
const CAMP_DIP: Array = [
	"..........................",
	"..........................",
	"..........................",
	"..........................",
	"#################..#######",
	"#################..#######",
	"##########################",
	"BBBBBBBBBBBBBBBBBBBBBBBBBB",
]


func test_soldiers_stuck_in_a_dip_do_not_split_the_camp() -> void:
	var a := _world(CAMP_DIP)
	a.spawn(10, 20.5)
	for i in range(1, 8):
		a.soldiers[i].pos = Vector2(18.8 - (i - 1) * 0.25, 6.0)
	a.soldiers[8].pos = Vector2(16.4, 4.0)
	a.soldiers[9].pos = Vector2(15.8, 4.0)
	a.camp_x = 20.5
	a.resting = true
	_run(a, 10.0)
	var xs := a.soldiers.map(func(s: Soldier) -> float: return s.pos.x)
	for i in range(1, xs.size()):
		assert_lte(xs[i - 1] - xs[i], a.rules.camp_spacing + 0.1, "soldier %d camps close behind %d" % [i, i - 1])


func test_deserters_walk_back_down_a_bridge_not_through_it() -> void:
	var a := _world([
		"....................",
		"........############",
		"........############",
		"........############",
		"........############",
		"........############",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
	])
	var b := a.bridge
	b.build(b.snap_point(Vector2(3, 6)), b.snap_point(Vector2(8, 4)), preload("res://data/bridge/log.tres"))
	a.spawn(3, 2.5)
	var sank := [false]
	for i in int((a.rules.mutiny_time + 6.0) * 60):
		b.step(1.0 / 60.0, a.bridge_loads())
		a.step(1.0 / 60.0)
		for d: Soldier in a.deserters:
			if d.pos.x > 3.3 and d.pos.x < 7.7 and d.pos.y > a.surface_at(d.pos.x, 0.0).y + 0.1:
				sank[0] = true
	assert_gt(a.deserters.size() + (3 - a.soldiers.size()), 0, "somebody deserted")
	assert_false(sank[0], "nobody sank through the deck")


func test_deserter_boxed_in_under_a_ceiling_does_not_climb_into_the_rock() -> void:
	var a := _world([
		"....................",
		"####################",
		"#####.....##########",
		"#####.....##########",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
	])
	a.spawn(1, 8.5)
	a.lead().pos.y = 4.0
	var inside := [false]
	for i in int((a.rules.mutiny_time + 4.0) * 60):
		a.step(1.0 / 60.0)
		for d: Soldier in a.deserters:
			inside[0] = inside[0] or a.terrain.is_solid(Grid.cell_of(d.pos - Vector2(0, 0.5)))
	assert_eq(a.soldiers.size(), 0, "deserted")
	assert_false(inside[0], "never inside the rock")
	assert_eq(a.deserters.size(), 0, "slipped away")
