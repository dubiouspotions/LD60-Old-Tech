extends GutTest
## Fireflies: at night a few drift and blink under the trees, drawn above the night grade so they keep their glow.

const MAP: Array = [
	"..................",
	"..LLL.............",
	"..LLL.............",
	"...T..............",
	"...T..............",
	"##################",
	"BBBBBBBBBBBBBBBBBB",
]

var world: World
var flies: Fireflies


func before_each() -> void:
	GameState.save_path = "user://test_sappers.cfg"
	GameState.new_campaign()
	world = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.terrain.clear()
	world.terrain.rebuild()
	for y in MAP.size():
		for x in MAP[y].length():
			var key: String = WorldFixture.LEGEND[MAP[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	flies = world.fireflies
	flies.set_process(false)


func _run(seconds: float) -> int:
	var most := 0
	for i in int(seconds * 60):
		flies.advance(1.0 / 60.0)
		most = maxi(most, flies.count())
	return most


func test_finds_the_foot_of_each_tree() -> void:
	assert_eq(flies.tree_bases(Rect2i(0, 0, 18, 7)), [Vector2i(3, 4)] as Array[Vector2i])


func test_a_few_come_out_under_the_trees_at_night() -> void:
	flies.amount = 1.0
	var most := _run(flies.spawn_interval.y * flies.max_count + flies.life.x)
	assert_gt(most, 1, "a couple")
	assert_lte(most, flies.max_count)
	for p in flies.positions():
		assert_lt(absf(p.x - 3.5), flies.roam.x + 0.01, "under the tree")
		assert_between(p.y, 5.0 - flies.roam.y - 0.01, 5.0, "above the ground at its foot")


func test_none_by_day() -> void:
	flies.amount = 0.0
	assert_eq(_run(flies.spawn_interval.y * 3), 0)


func test_none_without_trees() -> void:
	world.terrain.set_type(Vector2i(3, 3), null)
	world.terrain.set_type(Vector2i(3, 4), null)
	flies.amount = 1.0
	assert_eq(_run(flies.spawn_interval.y * 3), 0)


func test_each_one_fades_away_after_its_life() -> void:
	flies.amount = 1.0
	_run(flies.spawn_interval.y * 2)
	assert_gt(flies.count(), 0)
	flies.amount = 0.0
	_run(flies.life.y + 0.1)
	assert_eq(flies.count(), 0)


func test_drawn_above_the_night_grade_and_below_the_hud() -> void:
	var layer := flies.get_parent() as CanvasLayer
	assert_not_null(layer)
	assert_true(layer.follow_viewport_enabled, "moves with the world")
	var main: Node = load("res://game/main.tscn").instantiate()
	assert_gt(layer.layer, (main.get_node("NightGrade") as CanvasLayer).layer)
	assert_lt(layer.layer, (main.get_node("HUD") as CanvasLayer).layer)
	var dn: DayNight = main.get_node("DayNight")
	assert_eq(dn.fireflies, main.get_node("LevelHolder/World").get_node("%Fireflies"))
	main.free()


func test_they_fly_about_at_their_speed() -> void:
	flies.amount = 1.0
	_run(flies.spawn_interval.y * 2)
	assert_gt(flies.count(), 0)
	var before := flies.positions()
	flies.amount = 0.0
	_run(0.5)
	var after := flies.positions()
	var moved := 0.0
	for i in mini(before.size(), after.size()):
		moved = maxf(moved, before[i].distance_to(after[i]))
	assert_gt(moved, flies.speed * 0.5 * 0.4, "they get somewhere in half a second")
