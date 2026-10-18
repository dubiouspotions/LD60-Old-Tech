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


func test_falling_log_hurts_the_soldier_it_lands_on() -> void:
	world.army.spawn(1, 5.5)
	world.army.hold = true
	var s: Soldier = world.army.lead()
	_drop_log(4.5, 6.5, 0.5)
	_run(2.0)
	assert_true(s.dead or s.hp < s.max_hp, "hit")


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
	var hp := archer.hp
	_run(2.0)
	assert_lt(archer.hp, hp, "hit")


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


func test_a_soldier_freed_after_a_hit_is_forgotten_cleanly() -> void:
	world.army.spawn(2, 5.5)
	world.army.hold = true
	var s: Soldier = world.army.lead()
	_drop_log(4.5, 6.5, 0.5)
	for i in 120:
		world._physics_process(1.0 / 60.0)
		if s.hp < s.max_hp:
			break
	assert_lt(s.hp, s.max_hp, "hit")
	world.army.soldiers.erase(s)
	s.free()
	_run(0.2)
	assert_engine_error_count(0, "no freed soldier touched")
