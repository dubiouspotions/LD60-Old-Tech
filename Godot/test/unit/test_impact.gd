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


func test_fill_let_go_just_above_a_soldier_rests_on_him() -> void:
	world.army.spawn(1, 5.5)
	world.army.hold = true
	var block := _drop_fill(Vector2i(5, 3))
	_run(2.0)
	assert_eq(world.army.soldiers.size(), 1, "not crushed")
	assert_true(is_instance_valid(block), "still a block, resting")
	assert_null(world.terrain.type_at(Vector2i(5, 5)), "not in the soldier's cell")


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
