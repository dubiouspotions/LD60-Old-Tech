extends GutTest
## Fireflies: swarms placed by hand in the levels. At night a few drift and blink around each, drawn above the night
## grade so they keep their glow.

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
	flies = load("res://objects/fireflies/fireflies.tscn").instantiate()
	# By the trunk, low enough that the circle reaches into the ground.
	flies.position = Grid.to_px(Vector2(3.5, 4.5))
	world.fireflies.add_child(flies)
	flies.set_process(false)


func _run(seconds: float) -> int:
	var most := 0
	for i in int(seconds * 60):
		flies.advance(1.0 / 60.0)
		most = maxi(most, flies.count())
	return most


func test_a_few_come_out_around_the_swarm_at_night() -> void:
	world.fireflies.night = 1.0
	var most := _run(flies.spawn_interval.y * flies.amount + flies.life.x)
	assert_gt(most, 1, "a couple")
	assert_lte(most, flies.amount)
	for p in flies.positions():
		assert_lte(p.length(), flies.radius + 0.01, "inside its radius")


func test_they_keep_out_of_the_ground() -> void:
	world.fireflies.night = 1.0
	var seen := 0
	var buried := 0
	for i in 20 * 60:
		flies.advance(1.0 / 60.0)
		for p in flies.positions():
			seen += 1
			if world.terrain.is_solid(Grid.cell_of(Grid.to_m(flies.position) + p)):
				buried += 1
	assert_gt(seen, 0)
	assert_eq(buried, 0, "never inside the ground, the trunk or the leaves")


func test_amount_is_the_most_out_at_once() -> void:
	flies.amount = 5
	world.fireflies.night = 1.0
	assert_eq(_run(flies.spawn_interval.y * 5 + flies.life.x * 0.5), 5)


func _chop_the_tree() -> void:
	world.terrain.fell(Vector2i(3, 4))
	assert_null(world.terrain.type_at(Vector2i(3, 3)), "the whole tree is gone")


func test_none_once_their_tree_is_chopped_down() -> void:
	world.fireflies.night = 1.0
	_run(flies.spawn_interval.y * 2)
	assert_true(flies.plant_stands())
	_chop_the_tree()
	assert_false(flies.plant_stands())
	_run(flies.life.y + 0.1)
	assert_eq(_run(flies.spawn_interval.y * 3), 0)


func test_none_when_the_tree_was_chopped_before_nightfall() -> void:
	flies.advance(1.0 / 60.0)
	_chop_the_tree()
	world.fireflies.night = 1.0
	assert_eq(_run(flies.spawn_interval.y * 3), 0)


func test_they_stay_after_the_tree_when_the_setting_is_off() -> void:
	assert_true(flies.needs_plant, "on by default")
	flies.needs_plant = false
	_chop_the_tree()
	world.fireflies.night = 1.0
	assert_gt(_run(flies.spawn_interval.y * 3), 0)


func test_a_swarm_with_no_plant_in_reach_still_comes_out() -> void:
	flies.position = Grid.to_px(Vector2(14.5, 4.5))
	world.fireflies.night = 1.0
	assert_gt(_run(flies.spawn_interval.y * 3), 0)


func test_none_by_day() -> void:
	world.fireflies.night = 0.0
	assert_eq(_run(flies.spawn_interval.y * 3), 0)


func test_each_one_fades_away_after_its_life() -> void:
	world.fireflies.night = 1.0
	_run(flies.spawn_interval.y * 2)
	assert_gt(flies.count(), 0)
	world.fireflies.night = 0.0
	_run(flies.life.y + 0.1)
	assert_eq(flies.count(), 0)


func test_they_fly_about_at_their_speed() -> void:
	world.fireflies.night = 1.0
	_run(flies.spawn_interval.y * 2)
	assert_gt(flies.count(), 0)
	var before := flies.positions()
	world.fireflies.night = 0.0
	_run(0.5)
	var after := flies.positions()
	var moved := 0.0
	for i in mini(before.size(), after.size()):
		moved = maxf(moved, before[i].distance_to(after[i]))
	assert_gt(moved, flies.speed * 0.5 * 0.4, "they get somewhere in half a second")


func test_the_layer_tells_every_swarm_when_it_is_night() -> void:
	world.fireflies.night = 1.0
	assert_eq(flies.night, 1.0)
	var later: Fireflies = load("res://objects/fireflies/fireflies.tscn").instantiate()
	world.fireflies.add_child(later)
	assert_eq(later.night, 1.0, "one added at night")


func test_a_levels_swarms_move_onto_the_layer() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	world.fireflies.remove_child(flies)
	flies.free()
	var c := world.place_now(0)
	var placed := world.fireflies.get_children().filter(func(n: Node) -> bool: return n is Fireflies)
	assert_gt(placed.size(), 0)
	for f: Fireflies in placed:
		assert_true(f in c.owned, "freed with its level")
	assert_false(world.objects.get_children().any(func(n: Node) -> bool: return n is Fireflies))


func test_drawn_above_the_night_grade_and_below_the_hud() -> void:
	var layer := world.fireflies.get_parent() as CanvasLayer
	assert_not_null(layer)
	assert_true(layer.follow_viewport_enabled, "moves with the world")
	var main: Node = load("res://game/main.tscn").instantiate()
	assert_gt(layer.layer, (main.get_node("NightGrade") as CanvasLayer).layer)
	assert_lt(layer.layer, (main.get_node("HUD") as CanvasLayer).layer)
	var dn: DayNight = main.get_node("DayNight")
	assert_eq(dn.fireflies, main.get_node("LevelHolder/World").get_node("%Fireflies"))
	main.free()
