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
	button.button_pressed = true
	assert_true(cam.follow, "marking follows")
	button.button_pressed = false
	assert_false(cam.follow, "unmarking stops following")


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


func test_f2_toggles_the_cheats_instant_work_and_supplies() -> void:
	var rules: CrewRules = game.get_node("%World").crew.rules
	var was := rules.instant_work
	var press := InputEventAction.new()
	press.action = &"cheat_instant_work"
	press.pressed = true
	rules.instant_work = false
	GameState.supplies = Supplies.make(1, 0, 200)
	game._unhandled_input(press)
	assert_true(rules.instant_work, "toggled on")
	for k in Supplies.KEYS:
		assert_gte(GameState.supplies.get(k), 99, "plenty of %s" % k)
	assert_eq(GameState.supplies.rope, 200, "more is kept")
	game._unhandled_input(press)
	assert_false(rules.instant_work, "and off")
	rules.instant_work = was
	assert_true(InputMap.action_has_event(&"cheat_instant_work", _key(KEY_F2)), "on F2")


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	return k


func test_restart_button_restarts_the_level_from_its_checkpoint() -> void:
	game._begin()
	var world: World = game.get_node("%World")
	var earth := GameState.supplies.earth
	var soldiers := world.army.soldiers.size()
	var b := world.bridge
	var lead := world.army.lead().pos
	b.build(b.snap_point(lead + Vector2(2, 0)), b.snap_point(lead + Vector2(4, 0)), preload("res://data/bridge/log.tres"))
	GameState.supplies.earth = earth + 7
	world.army.crush(world.army.lead())
	(game.get_node("%HUD").get_node("%RestartButton") as Button).pressed.emit()
	assert_eq(b.members.size(), 0, "the level's bridge is gone")
	assert_eq(GameState.supplies.earth, earth, "supplies as at the checkpoint")
	assert_eq(world.army.soldiers.size(), soldiers, "the column as at the checkpoint")
	assert_false(get_tree().paused, "playing")
	assert_true(InputMap.action_has_event(&"restart_level", _key(KEY_BACKSPACE)), "also on Backspace")


func test_the_game_starts_with_following_off_and_the_view_on_the_column() -> void:
	game._begin()
	var cam: CameraRig = game.get_node("%Camera")
	var button: Button = game.get_node("%HUD").get_node("%FollowButton")
	assert_false(cam.follow, "not following")
	assert_false(button.button_pressed, "the button says so")
	var lead: Soldier = game.get_node("%World").army.lead()
	var view := Rect2(cam.view_m(), cam.view_size_m())
	assert_true(view.has_point(lead.pos), "the column is in view")


func test_picking_stone_in_the_picker_switches_bridge_to_stone() -> void:
	game._begin()
	var tools: ToolController = game.get_node("%ToolController")
	tools.select(1)
	var row: Node = game.get_node("%HUD").get_node("%Materials")
	(row.get_child(1) as Button).pressed.emit()
	assert_eq(tools.build_material().display_name, "Stone")
	assert_true((row.get_child(1) as Button).button_pressed, "the pick shows")
	assert_engine_error_count(0, "no button freed while it was being pressed")


func test_cancelling_a_plan_says_what_came_back() -> void:
	game._begin()
	var world: World = game.get_node("%World")
	var b := world.bridge
	var lead := world.army.lead().pos
	b.build(b.snap_point(lead + Vector2(2, 0)), b.snap_point(lead + Vector2(4, 0)), preload("res://data/bridge/log.tres"), true)
	game._show_plans()
	watch_signals(Effects)
	game._on_cancel_pressed(0)
	assert_signal_emitted(Effects, "said")
	assert_eq(get_signal_parameters(Effects, "said")[0], "+1 logs")


func test_the_cheat_top_up_says_what_it_gave() -> void:
	game._begin()
	var rules: CrewRules = game.get_node("%World").crew.rules
	rules.instant_work = false
	GameState.supplies = Supplies.new()
	watch_signals(Effects)
	game._toggle_cheats()
	rules.instant_work = false
	var texts := []
	for i in get_signal_emit_count(Effects, "said"):
		texts.append(get_signal_parameters(Effects, "said", i)[0])
	assert_true(texts.any(func(t: String) -> bool: return t.contains("+99 earth")), "the top-up shown")
