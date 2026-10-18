extends GutTest
## Pollen and seed fluff drifting left to right on the wind by day: a sparse handful on screen, gone at night.

const VIEW := Rect2(100, 10, 40, 22)

var world: World
var pollen: Pollen


func before_each() -> void:
	GameState.save_path = "user://test_sappers.cfg"
	GameState.new_campaign()
	world = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	world.set_physics_process(false)
	world.set_process(false)
	pollen = world.pollen
	pollen.set_process(false)


func _run(seconds: float, view: Rect2 = VIEW) -> void:
	for i in int(seconds * 60):
		pollen.advance(1.0 / 60.0, view)


func test_a_sparse_handful_drifts_over_the_view_by_day() -> void:
	pollen.amount = 1.0
	_run(0.1)
	assert_gt(pollen.count(), 0, "some right away, not only from the left edge")
	_run(VIEW.size.x / pollen.wind.x * 2.0)
	assert_between(pollen.count(), pollen.max_count / 2, pollen.max_count)
	for p in pollen.positions():
		assert_true(VIEW.grow(pollen.margin + 0.01).has_point(p), "%s around the view" % p)


func test_drifts_left_to_right() -> void:
	pollen.amount = 1.0
	_run(1.0)
	assert_gt(pollen.count(), 0)
	for v in pollen.velocities():
		assert_gt(v.x, 0.0, "with the wind")
		assert_lt(absf(v.y), v.x, "mostly sideways, with a flutter")


func test_follows_the_view() -> void:
	pollen.amount = 1.0
	_run(3.0)
	var moved := Rect2(VIEW.position + Vector2(200, 0), VIEW.size)
	_run(VIEW.size.x / pollen.wind.x * 2.0, moved)
	for p in pollen.positions():
		assert_true(moved.grow(pollen.margin + 0.01).has_point(p), "dropped behind or carried along")
	assert_gt(pollen.count(), 0)


func test_none_at_night() -> void:
	pollen.amount = 0.0
	_run(5.0)
	assert_eq(pollen.count(), 0)


func test_the_day_brings_it_and_the_night_takes_it_away() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	var dn: DayNight = main.get_node("DayNight")
	var world_node: World = main.get_node("LevelHolder/World")
	assert_eq(dn.pollen, world_node.get_node("%Pollen"))
	assert_eq(world_node.get_node("%Pollen").get_parent(), world_node.get_node("%Fireflies").get_parent(), "same layer")
	main.free()
	var d := DayNight.new()
	d.pollen = pollen
	add_child_autofree(d)
	d.set_night(true, true)
	assert_eq(pollen.amount, 0.0)
	d.set_night(false, true)
	assert_eq(pollen.amount, 1.0)
