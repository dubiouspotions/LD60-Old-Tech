extends GutTest
## The game screen as a whole.

var game: Game


func before_each() -> void:
	game = load("res://game/main.tscn").instantiate()
	add_child_autofree(game)


func after_each() -> void:
	get_tree().paused = false


func test_plans_clear_without_errors_once_the_game_is_over() -> void:
	game._over = true
	game._show_plans()
	assert_eq(game._plans.size(), 0)


func test_follow_button_turns_following_off_and_on() -> void:
	var cam: CameraRig = game.get_node("%Camera")
	var button: Button = game.get_node("%HUD").get_node("%FollowButton")
	assert_true(button.button_pressed, "on from the start, like the camera")
	button.button_pressed = false
	assert_false(cam.follow, "unmarking stops following")
	button.button_pressed = true
	assert_true(cam.follow, "marking follows again")


func test_engineers_carry_a_small_light_at_night() -> void:
	var crew: Crew = game.get_node("%World").crew
	crew.spawn(5.0)
	var day_night: DayNight = game.get_node("%DayNight")
	day_night.set_night(true, true)
	for e in crew.engineers:
		var lamp: NightLight = e.node.get_node("%Lamp")
		assert_true(lamp.visible and lamp.energy > 0.0, "lit at night")
		assert_lt(lamp.texture_scale, (game.get_node("Lantern") as PointLight2D).texture_scale, "smaller than the cursor lantern")
	day_night.set_night(false, true)
	for e in crew.engineers:
		assert_false(e.node.get_node("%Lamp").visible, "out by day")


func test_lamps_freed_while_fading_cause_no_errors() -> void:
	get_tree().paused = false
	var crew: Crew = game.get_node("%World").crew
	crew.spawn(5.0)
	var day_night: DayNight = game.get_node("%DayNight")
	day_night.set_night(true, false, 0.2)
	crew.spawn(5.0)
	await wait_seconds(0.4)
	day_night.set_night(false, false, 0.2)
	crew.spawn(5.0)
	await wait_seconds(0.4)
	assert_engine_error_count(0, "no lamp touched after it was freed")


func test_f2_toggles_the_cheats_instant_build_and_supplies() -> void:
	var rules: CrewRules = game.get_node("%World").crew.rules
	var was := rules.instant_build
	var press := InputEventAction.new()
	press.action = &"cheat_instant_build"
	press.pressed = true
	rules.instant_build = false
	GameState.supplies = Supplies.make(1, 0, 200)
	game._unhandled_input(press)
	assert_true(rules.instant_build, "toggled on")
	for k in Supplies.KEYS:
		assert_gte(GameState.supplies.get(k), 99, "plenty of %s" % k)
	assert_eq(GameState.supplies.rope, 200, "more is kept")
	game._unhandled_input(press)
	assert_false(rules.instant_build, "and off")
	rules.instant_build = was
	assert_true(InputMap.action_has_event(&"cheat_instant_build", _key(KEY_F2)), "on F2")


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	return k
