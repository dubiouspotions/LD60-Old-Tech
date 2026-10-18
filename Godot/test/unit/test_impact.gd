extends GutTest
## Bridge pieces moving fast hurt soldiers and archers and break the ground and towers they hit.

const LOG := preload("res://data/bridge/log.tres")

var world: World


func before_each() -> void:
	GameState.save_path = "user://test_sappers.cfg"
	GameState.new_campaign()
	world = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	world.set_physics_process(false)
	_map([
		"....................",
		"....................",
		"....................",
		"....................",
		"....................",
		"....................",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
	])


func _map(rows: Array) -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for y in rows.size():
		for x in rows[y].length():
			var key: String = WorldFixture.LEGEND[rows[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))


## A loose log held level at height y over x0..x1, let go.
func _drop_log(x0: float, x1: float, y: float) -> void:
	var b := world.bridge
	b.build(b.snap_point(Vector2(x0, y)), b.snap_point(Vector2(x1, y)), LOG)


func _run(seconds: float) -> void:
	for i in int(seconds * 60):
		world._physics_process(1.0 / 60.0)


func test_falling_log_crushes_the_soldiers_it_lands_on() -> void:
	world.army.spawn(3, 5.5)
	world.army.hold = true
	_drop_log(4.0, 6.5, 0.5)
	_run(2.0)
	assert_eq(world.army.soldiers.size(), 0, "all crushed")


func test_soldiers_cross_a_standing_bridge_unhurt() -> void:
	_map([
		"..............",
		"..............",
		"..............",
		"..............",
		"######....####",
		"######....####",
		"BBBBBBBBBBBBBB",
	])
	_drop_log(6, 10, 4)
	world.army.spawn(3, 3.5)
	_run(8.0)
	for s in world.army.soldiers:
		assert_eq(s.hp, s.max_hp, "unhurt")
	assert_eq(world.army.soldiers.size(), 3)


func test_falling_log_hurts_an_archer() -> void:
	var archer: Archer = load("res://objects/archer/archer.tscn").instantiate()
	archer.position = Grid.to_px(Vector2(5.5, 6))
	world.objects.add_child(archer)
	_drop_log(4.5, 6.5, 0.5)
	_run(2.0)
	assert_false(archer.alive(), "crushed")


func test_falling_log_breaks_the_ground_it_hits() -> void:
	_drop_log(4, 6, 0)
	_run(2.0)
	assert_true(world.terrain.type_at(Vector2i(4, 6)) == null or world.terrain.type_at(Vector2i(5, 6)) == null, "a cell broke")


func test_falling_log_batters_a_tower() -> void:
	_map([
		"....................",
		"....................",
		"....................",
		"....KKK.............",
		"....KKK.............",
		"....KKK.............",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
	])
	_drop_log(4.5, 6.5, -3)
	_run(2.0)
	var hit := false
	for x in range(4, 7):
		hit = hit or world.terrain.siege_progress(Vector2i(x, 3)) > 0.0
	assert_true(hit, "tower damaged")


func test_log_laid_gently_on_the_ground_breaks_nothing() -> void:
	_drop_log(4, 6, 6)
	_run(2.0)
	assert_not_null(world.terrain.type_at(Vector2i(4, 6)))
	assert_not_null(world.terrain.type_at(Vector2i(5, 6)))


func test_an_archer_freed_after_a_hit_is_forgotten_cleanly() -> void:
	var archer: Archer = load("res://objects/archer/archer.tscn").instantiate()
	archer.position = Grid.to_px(Vector2(5.5, 6))
	world.objects.add_child(archer)
	_drop_log(4.5, 6.5, 0.5)
	for i in 120:
		world._physics_process(1.0 / 60.0)
		if not archer.alive():
			break
	assert_false(archer.alive(), "crushed")
	archer.free()
	_run(0.2)
	assert_engine_error_count(0, "no freed archer touched")


func test_slow_log_comes_to_rest_on_a_soldier() -> void:
	world.army.spawn(1, 5.5)
	world.army.hold = true
	var s: Soldier = world.army.lead()
	_drop_log(4.5, 6.5, 6.0 - 1.8 - 0.3)
	_run(3.0)
	assert_false(s.dead, "not crushed")
	var b := world.bridge
	var m: Bridge.Member = b.members[0]
	var head := Geometry2D.get_closest_point_to_segment(s.pos - Vector2(0, 0.9), m.a.pos, m.b.pos)
	assert_lt(head.y, s.pos.y - 1.3, "the log lies on the soldier, above the body")


func test_slow_log_comes_to_rest_on_an_archer() -> void:
	var archer: Archer = load("res://objects/archer/archer.tscn").instantiate()
	archer.position = Grid.to_px(Vector2(5.5, 6))
	world.objects.add_child(archer)
	_drop_log(4.5, 6.5, 6.0 - 1.8 - 0.3)
	_run(3.0)
	assert_true(archer.alive(), "not crushed")
	var m: Bridge.Member = world.bridge.members[0]
	assert_lt((m.a.pos.y + m.b.pos.y) / 2.0, 6.0 - 1.3, "resting on the archer")


## A block of fill let go with its top-left at cell.
func _drop_fill(cell: Vector2i) -> FallingBlock:
	var block: FallingBlock = load("res://objects/falling_block/falling_block.tscn").instantiate()
	block.type = WorldFixture.type("fill")
	block.position = Grid.to_px(Vector2(cell))
	world.objects.add_child(block)
	return block


func test_falling_fill_crushes_the_soldier_it_lands_on() -> void:
	world.army.spawn(1, 5.5)
	world.army.hold = true
	_drop_fill(Vector2i(5, 0))
	_run(2.0)
	assert_eq(world.army.soldiers.size(), 0, "crushed")


func test_a_box_let_go_just_above_a_soldier_crushes_him_by_its_weight() -> void:
	world.army.spawn(1, 5.5)
	world.army.hold = true
	_drop_fill(Vector2i(5, 3))
	_run(2.0)
	assert_eq(world.army.soldiers.size(), 0, "600 kg is too much to carry")


## An archer at x 5.5 with n light boxes (kg each) stacked on him, let go gently.
func _stack_on_archer(n: int, kg: float) -> Archer:
	var archer: Archer = load("res://objects/archer/archer.tscn").instantiate()
	archer.position = Grid.to_px(Vector2(5.5, 6))
	world.objects.add_child(archer)
	for k in n:
		var block := _drop_fill(Vector2i(5, 3 - k))
		block.mass = kg
	return archer


func test_a_light_box_rests_on_an_archer() -> void:
	var archer := _stack_on_archer(1, 100.0)
	_run(3.0)
	assert_true(archer.alive(), "100 kg is carried")


func test_a_stack_of_boxes_crushes_an_archer_by_its_weight() -> void:
	var archer := _stack_on_archer(3, 100.0)
	_run(3.0)
	assert_false(archer.alive(), "300 kg through the stack crushes him")


func test_a_box_on_a_log_lying_on_a_soldier_crushes_him() -> void:
	world.army.spawn(1, 5.5)
	world.army.hold = true
	_drop_log(4.5, 6.5, 6.0 - 1.8 - 0.3)
	_run(2.0)
	assert_eq(world.army.soldiers.size(), 1, "the log alone is carried")
	_drop_fill(Vector2i(5, 0))
	_run(3.0)
	assert_eq(world.army.soldiers.size(), 0, "the box's weight comes through the log")


func test_fill_lands_on_a_bridge_instead_of_falling_through() -> void:
	_map([
		"..............",
		"..............",
		"..............",
		"..............",
		"######....####",
		"######....####",
		"BBBBBBBBBBBBBB",
	])
	_drop_log(6, 10, 4)
	var block := _drop_fill(Vector2i(7, 0))
	_run(3.0)
	assert_true(is_instance_valid(block), "still on the deck")
	assert_null(world.terrain.type_at(Vector2i(7, 5)), "did not fall into the pit")
	assert_almost_eq(block.position.y / Grid.PX + 1.0, world.bridge.members[0].a.pos.y, 0.4, "on the deck")


## Siege done to the tower top by a piece of mat dropped from height above it.
func _siege_from(mat: BridgeMaterial, height: float) -> float:
	before_each()
	_map([
		"....................",
		"....................",
		"....................",
		"....................",
		"....KKK.............",
		"....KKK.............",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
	])
	var b := world.bridge
	b.build(b.snap_point(Vector2(4.5, 4 - height)), b.snap_point(Vector2(6.5, 4 - height)), mat)
	var cells := [Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4)]
	var most := 0.0
	for i in 120:
		world._physics_process(1.0 / 60.0)
		for c: Vector2i in cells:
			most = maxf(most, world.terrain.siege_progress(c))
	return most


func test_heavier_pieces_batter_towers_harder() -> void:
	var by_log := _siege_from(LOG, 4.0)
	var by_stone := _siege_from(preload("res://data/bridge/stone.tres"), 4.0)
	assert_gt(by_log, 0.0, "a log dents it")
	assert_gt(by_stone, by_log * 1.4, "stone does far more")
	assert_gt(by_stone, 0.5, "a stone beam takes half a tower cell's strength")


func test_piece_wider_than_a_tower_lands_on_it_not_through_it() -> void:
	_map([
		"....................",
		"....................",
		"....................",
		".....KK.............",
		".....KK.............",
		".....KK.............",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
	])
	_drop_log(4.0, 8.0, 2.5)
	_run(3.0)
	var m: Bridge.Member = world.bridge.members[0]
	var mid := (m.a.pos + m.b.pos) / 2.0
	assert_lt(mid.y, 3.2, "resting on top of the tower")
	assert_not_null(world.terrain.type_at(Vector2i(5, 3)), "tower standing")


const PIT: Array = [
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
	"######....####",
	"######....####",
	"BBBBBBBBBBBBBB",
]


func test_a_loose_piece_lands_on_another_structure() -> void:
	_map(PIT)
	_drop_log(6, 10, 5)
	_drop_log(7, 9, 3.5)
	_run(3.0)
	var loose: Bridge.Member = world.bridge.members[1]
	assert_lt((loose.a.pos.y + loose.b.pos.y) / 2.0, 5.0, "resting on the deck")


func test_crossing_pieces_of_one_structure_leave_each_other_alone() -> void:
	_map(PIT)
	var b := world.bridge
	b.build(b.snap_point(Vector2(6, 5)), b.snap_point(Vector2(10, 3)), LOG)
	b.build(b.snap_point(Vector2(10, 5)), b.snap_point(Vector2(6, 3)), LOG)
	b.build(b.snap_point(Vector2(6, 3)), b.snap_point(Vector2(10, 3)), LOG)
	_run(3.0)
	for n in b.nodes:
		assert_almost_eq(n.pos.y, roundf(n.pos.y), 0.15, "the X brace holds its shape")


func test_a_loose_piece_lands_on_a_block_resting_on_a_deck() -> void:
	_map(PIT)
	_drop_log(6, 10, 5)
	var block := _drop_fill(Vector2i(7, 3))
	_run(1.0)
	_drop_log(6.5, 8.5, 2.0)
	_run(3.0)
	var loose: Bridge.Member = world.bridge.members[1]
	assert_true(is_instance_valid(block), "block still on the deck")
	assert_lt((loose.a.pos.y + loose.b.pos.y) / 2.0, block.position.y / Grid.PX + 0.1, "resting on the block")


## A tower 3 wide and 3 high on the ground, and a piece of mat 3 m long let go height above it.
func _tower_hit_by(mat: BridgeMaterial, height: float) -> Bridge.Member:
	_map([
		"....................",
		"....................",
		"....................",
		"....................",
		"....................",
		"....................",
		"....................",
		"....KKK.............",
		"....KKK.............",
		"....KKK.............",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
	])
	var b := world.bridge
	return b.build(b.snap_point(Vector2(4, 7 - height)), b.snap_point(Vector2(7, 7 - height)), mat)


func test_a_log_rammed_into_a_tower_breaks_and_barely_dents_it() -> void:
	var m := _tower_hit_by(LOG, 6.0)
	_run(2.0)
	assert_true(m.dead, "the log broke on the brick")
	assert_not_null(world.terrain.type_at(Vector2i(5, 7)), "tower standing")


func test_a_stone_beam_dropped_on_a_tower_brings_it_down() -> void:
	var m := _tower_hit_by(preload("res://data/bridge/stone.tres"), 6.0)
	_run(2.0)
	assert_null(world.terrain.type_at(Vector2i(5, 8)), "tower razed")
	assert_false(m.dead, "stone survives it")


func test_a_light_drop_does_not_raze_a_tower_even_of_stone() -> void:
	_tower_hit_by(preload("res://data/bridge/stone.tres"), 1.5)
	_run(2.0)
	assert_not_null(world.terrain.type_at(Vector2i(5, 7)), "tower standing")


func test_a_fast_piece_landing_with_its_end_on_a_tower_edge_batters_it() -> void:
	_map([
		"....................",
		"....................",
		"....................",
		"....................",
		"....................",
		"....................",
		"....................",
		"....KKK.............",
		"....KKK.............",
		"....KKK.............",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
	])
	var b := world.bridge
	var m := b.build(b.snap_point(Vector2(4, 1)), b.snap_point(Vector2(7, 1)), LOG)
	var hit := [0.0]
	_run(2.0)
	for x in range(4, 7):
		hit[0] = maxf(hit[0], world.terrain.siege_progress(Vector2i(x, 7)))
	assert_gt(hit[0], 0.0, "the hit on the tower's edge counted")
	assert_lt(m.a.pos.y, 7.1, "and the piece rests on top")


func test_soldiers_ignore_supports_and_ropes() -> void:
	for mat: BridgeMaterial in [preload("res://data/bridge/support.tres"), preload("res://data/bridge/rope.tres")]:
		before_each()
		# A free-standing A-frame across the column's path, its apex free at chest height.
		var b := world.bridge
		b.build(b.snap_point(Vector2(6, 6)), b.snap_point(Vector2(7.5, 4.5)), mat)
		b.build(b.snap_point(Vector2(9, 6)), b.snap_point(Vector2(7.5, 4.5)), mat)
		_run(1.0)
		var apex: Bridge.Joint = b.members[0].b
		var start := apex.pos
		world.army.spawn(3, 3.5)
		_run(5.0)
		assert_eq(world.army.soldiers.size(), 3, "%s crushes nobody" % mat.display_name)
		assert_gt(world.army.lead().pos.x, 9.5, "the column walked through the %s" % mat.display_name)
		assert_almost_eq(apex.pos, start, Vector2(0.1, 0.1), "the %s was not shoved by them" % mat.display_name)


func test_a_rope_dropped_across_a_tower_does_not_lie_on_it_like_a_rod() -> void:
	_map([
		"....................",
		"....................",
		"....................",
		".....KK.............",
		".....KK.............",
		".....KK.............",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
	])
	var b := world.bridge
	var rope := b.build(b.snap_point(Vector2(2, 1)), b.snap_point(Vector2(10, 1)), preload("res://data/bridge/rope.tres"))
	_run(3.0)
	assert_gt(rope.a.pos.y, 4.0, "its ends fell past the tower top")
	assert_gt(rope.b.pos.y, 4.0)


func test_spikes_destroy_a_box_that_falls_on_them() -> void:
	_map([
		"..............",
		"..............",
		"..............",
		"..............",
		"..............",
		"..............",
		"######^^^^####",
		"BBBBBBBBBBBBBB",
	])
	var block := _drop_fill(Vector2i(7, 0))
	_run(2.0)
	assert_false(is_instance_valid(block) and not block.is_queued_for_deletion(), "the box is gone")
	assert_eq(world.terrain.type_at(Vector2i(7, 6)), WorldFixture.type("spikes"), "the spikes are still there")
	assert_null(world.terrain.type_at(Vector2i(7, 5)), "and no box sits on them")


func test_a_box_that_landed_stops_falling_before_it_is_freed() -> void:
	_drop_fill(Vector2i(7, 0))
	_run(2.0)
	var boxes := 0
	for y in range(0, 8):
		if world.terrain.type_at(Vector2i(7, y)) == WorldFixture.type("fill"):
			boxes += 1
	assert_eq(boxes, 1, "one box, landed once")
	assert_eq(world.terrain.type_at(Vector2i(7, 5)), WorldFixture.type("fill"), "on the ground")


func test_spikes_destroy_a_bridge_piece_that_falls_on_them() -> void:
	_map([
		"..............",
		"..............",
		"..............",
		"..............",
		"..............",
		"..............",
		"######^^^^####",
		"BBBBBBBBBBBBBB",
	])
	_drop_log(6.5, 8.5, 2.0)
	_run(2.0)
	assert_eq(world.bridge.members.size(), 0, "the log is gone")
	assert_eq(world.terrain.type_at(Vector2i(7, 6)), WorldFixture.type("spikes"))


func test_a_piece_bolted_down_in_a_spike_pit_stays() -> void:
	_map([
		"..............",
		"..............",
		"..............",
		"..............",
		"..............",
		"..............",
		"######^^^^####",
		"BBBBBBBBBBBBBB",
	])
	var b := world.bridge
	# A support from the pit's floor (under the spikes, bolted to the bedrock) up to the left rim.
	var m := b.build(b.snap_point(Vector2(7, 7)), b.snap_point(Vector2(6, 6)), preload("res://data/bridge/support.tres"))
	_run(2.0)
	assert_false(m.dead, "built into the spikes on purpose, not landed on them")


func test_a_stone_beam_dropped_a_little_breaks_soil_and_lies_down() -> void:
	var b := world.bridge
	# Tilted, its low end 1.5 m above the soil (top at row 6).
	var m := b.build(b.snap_point(Vector2(5, 4.5)), b.snap_point(Vector2(7, 2.5)), preload("res://data/bridge/stone.tres"))
	var cells_before := 0
	for x in range(3, 10):
		if world.terrain.type_at(Vector2i(x, 6)) != null:
			cells_before += 1
	_run(4.0)
	var cells_after := 0
	for x in range(3, 10):
		if world.terrain.type_at(Vector2i(x, 6)) != null:
			cells_after += 1
	assert_lt(cells_after, cells_before, "the stone broke the soil it hit")
	assert_lt(absf(m.a.pos.y - m.b.pos.y), 0.6, "and lies down instead of standing on end")


func test_a_log_set_down_gently_breaks_no_soil() -> void:
	var b := world.bridge
	b.build(b.snap_point(Vector2(5, 5)), b.snap_point(Vector2(7, 5)), LOG)
	_run(3.0)
	for x in range(3, 10):
		assert_not_null(world.terrain.type_at(Vector2i(x, 6)), "soil at %d" % x)


func test_a_stone_beam_dropped_end_first_a_metre_breaks_the_soil_under_it() -> void:
	var b := world.bridge
	var m := b.build(b.snap_point(Vector2(6.0, 2.0)), b.snap_point(Vector2(6.5, 5.0)), preload("res://data/bridge/stone.tres"))
	_run(0.6)
	assert_null(world.terrain.type_at(Vector2i(6, 6)), "a 90 kg stone hitting at 4.4 m/s breaks soil")
