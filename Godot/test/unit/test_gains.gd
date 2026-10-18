extends GutTest
## Every time supplies are gained, "+N ..." floats up where they came from.

var world: World


func before_each() -> void:
	GameState.save_path = "user://test_sappers.cfg"
	GameState.new_campaign()
	world = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	world.set_physics_process(false)
	world.set_process(false)
	watch_signals(Effects)


## The texts Effects showed since the test began.
func _said() -> Array:
	var out := []
	for i in get_signal_emit_count(Effects, "said"):
		out.append(get_signal_parameters(Effects, "said", i)[0])
	return out


func _map(rows: Array) -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for y in rows.size():
		for x in rows[y].length():
			var key: String = WorldFixture.LEGEND[rows[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))


func test_digging_soil_says_what_it_gave() -> void:
	_map(["....", "##C#", "BBBB"])
	world._on_dig_finished(Vector2i(0, 1))
	assert_has(_said(), "+1 earth")


func test_digging_gold_says_what_it_gave() -> void:
	_map(["....", "##C#", "BBBB"])
	world._on_dig_finished(Vector2i(2, 1))
	assert_has(_said(), "+1 gold")


func test_a_collapse_says_what_it_gave() -> void:
	_map([".......", "..KKK..", "..KKK..", "..KKK..", "#######", "BBBBBBB"])
	world.terrain.besiege(Vector2i(3, 3), WorldFixture.type("brick").raze_time + 1.0)
	assert_true(_said().any(func(t: String) -> bool: return t.contains("stone")), "+N stone from the razed tower")


func test_the_camp_supply_drop_says_what_it_gave() -> void:
	world.begin(0, 3)
	world.march()
	var c1 := world.place_now(1)
	world.army.spawn(3, c1.start_flag.metres().x + 0.05)
	for i in 6:
		world._physics_process(1.0 / 60.0)
	var drop: Supplies = c1.level.supply_drop if c1.level.supply_drop else GameState.campaign.checkpoint_supplies
	assert_has(_said(), drop.describe())
