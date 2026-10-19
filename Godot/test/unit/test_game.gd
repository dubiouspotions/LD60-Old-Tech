extends GutTest
## The game screen as a whole.

var game: Game


func before_each() -> void:
	game = load("res://game/main.tscn").instantiate()
	add_child_autofree(game)


func after_each() -> void:
	get_tree().paused = false
	GameState.start_level = ""
	GameState.campaign = load("res://data/campaign.tres")


## Run Current Scene on a level: the level hands itself to the game, which starts there.
func test_a_level_run_on_its_own_starts_the_game_at_that_level() -> void:
	var path: String = GameState.campaign.levels[2]
	GameState.start_level = path
	var other: Game = load("res://game/main.tscn").instantiate()
	add_child_autofree(other)
	var world: World = other.get_node("%World")
	assert_eq(world.current, 2, "at that level")
	assert_eq(GameState.level_index, 2)
	assert_false(other.get_node("%HUD").get_node("%Intro").visible, "straight into it, no intro card")
	assert_eq(GameState.start_level, "", "only once")


func test_a_level_not_in_the_campaign_is_played_on_its_own() -> void:
	var path := "res://levels/level_base.tscn"
	assert_false(path in GameState.campaign.levels)
	GameState.start_level = path
	var other: Game = load("res://game/main.tscn").instantiate()
	add_child_autofree(other)
	var world: World = other.get_node("%World")
	assert_eq(GameState.campaign.levels, [path] as Array[String], "a campaign of just that level")
	assert_eq(world.current, 0)
	assert_true(world.current_chunk() != null)


## Waits seconds of real time, also while the game pauses itself (GUT's wait_seconds stops then).
func _real_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


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


## F3 (a testing cheat) ends the level as if it was won: the column is at the next level's camp, with its
## reinforcements and supply drop, and the view on it.
func test_f3_skips_the_level_as_if_it_was_won() -> void:
	game._begin()
	var world: World = game.get_node("%World")
	assert_eq(world.current, 0)
	var soldiers := world.army.soldiers.size()
	var engineers := world.crew.engineers.size()
	var press := InputEventAction.new()
	press.action = &"cheat_skip_level"
	press.pressed = true
	game._unhandled_input(press)
	assert_eq(world.current, 1, "at the next level")
	assert_eq(GameState.level_index, 1, "its checkpoint reached")
	var flag := world.chunk(1).start_flag.metres().x
	assert_true(world.camping(), "camped there")
	assert_eq(world.army.soldiers.size(), soldiers + world.chunk(1).level.reinforcements, "with its reinforcements")
	assert_eq(world.crew.engineers.size(), engineers, "the whole crew")
	for s in world.army.soldiers:
		assert_lt(absf(s.pos.x - flag), 15.0, "the column at its camp")
	var cam: CameraRig = game.get_node("%Camera")
	assert_lt(absf(cam.view_m().x - flag), cam.view_size_m().x, "the view on it")
	assert_true(InputMap.action_has_event(&"cheat_skip_level", _key(KEY_F3)), "on F3")


func test_skipping_the_last_level_wins_the_campaign() -> void:
	game._begin()
	var world: World = game.get_node("%World")
	var last := GameState.campaign.levels.size() - 1
	game._start_at_level(last)
	watch_signals(world)
	world.skip_level()
	assert_signal_emitted(world, "victory")


## A stuck engineer is told on the status line, after whatever else it says.
func test_the_status_line_warns_of_a_stuck_engineer() -> void:
	game._begin()
	var world: World = game.get_node("%World")
	var status: Label = game.get_node("%HUD").get_node("%Status")
	game._process(0.0)
	var before := status.text
	assert_false(status.text.contains(game.stuck_one_text), "nobody stuck")
	world.crew.engineers[0].stuck = true
	game._process(0.0)
	assert_true(status.text.begins_with(before), "what it said before stays")
	assert_true(status.text.contains(game.stuck_one_text), "and the warning follows: %s" % status.text)
	world.crew.hire(world.crew.engineers[0].pos.x).stuck = true
	game._process(0.0)
	assert_true(status.text.contains(game.stuck_many_text % 2), "counted: %s" % status.text)


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


## The red arrow points at the nearest engineer off screen, on its side, and is gone while all are on screen.
func test_the_crew_marker_points_at_the_nearest_engineer_off_screen() -> void:
	game._begin()
	var world: World = game.get_node("%World")
	var marker: Label = game.get_node("%HUD").get_node("%CrewMarker")
	var view := world.get_viewport().get_canvas_transform().affine_inverse()
	var w := world.get_viewport().get_visible_rect().size.x
	var mid_m := Grid.to_m(view * Vector2(w / 2.0, 300.0))
	for e in world.crew.engineers:
		e.pos.x = mid_m.x
	game._process(0.0)
	assert_false(marker.visible, "all on screen")
	var e: Crew.Engineer = world.crew.engineers[0]
	e.pos.x = Grid.to_m(view * Vector2(w + 200.0, 0.0)).x
	game._process(0.0)
	assert_true(marker.visible, "one off screen")
	assert_eq(marker.text, "▶", "on its side")


## Dragging or wheeling the view past its limit leaves it where it is at once, not only on the next frame, so
## nothing pinned to the world (the Camp Shoppe button) jumps about.
func test_the_view_stays_put_against_its_limit_while_dragged() -> void:
	game._begin()
	var cam: CameraRig = game.get_node("%Camera")
	cam.position.x = -1.0e6
	cam._clamp()
	var x0 := cam.position.x
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.position = Vector2(500, 300)
	cam._unhandled_input(press)
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(900, 300)
	cam._unhandled_input(drag)
	assert_eq(cam.position.x, x0, "dragging toward the locked side does not move it")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	cam._unhandled_input(wheel)
	assert_eq(cam.position.x, x0, "nor does the wheel")


## While a pan button is held, the camera takes the mouse's motion and the release before the HUD does and keeps
## them from it (no hovering, no swallowing the drag), so panning stays smooth over its buttons. Input as a whole
## is never switched off: the release still arrives and the next pan works too.
func test_panning_over_the_hud_stays_smooth() -> void:
	game._begin()
	var cam: CameraRig = game.get_node("%Camera")
	cam.position.x = 4000.0
	cam._clamp()
	for pan in 2:
		var x0 := cam.position.x
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_MIDDLE
		press.pressed = true
		press.position = Vector2(500, 300)
		cam._unhandled_input(press)
		assert_false(get_viewport().gui_disable_input, "input stays on")
		var drag := InputEventMouseMotion.new()
		drag.position = Vector2(600, 300)
		cam._input(drag)
		assert_true(get_viewport().is_input_handled(), "the motion is kept from the HUD")
		assert_lt(cam.position.x, x0, "pan %d moves on every motion, even over the HUD (seen before it)" % pan)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_MIDDLE
		release.pressed = false
		release.position = Vector2(600, 300)
		cam._input(release)
		assert_false(cam._dragging, "let go")


## The PAUSED tag says the game is paused; the status line keeps telling what the column is doing (the night timer).
func test_pausing_at_camp_keeps_the_night_timer_in_the_status() -> void:
	game._begin()
	game._hud.get_node("%Intro").visible = false
	get_tree().paused = true
	game._update_status()
	var status: String = (game._hud.get_node("%Status") as Label).text
	assert_false(status.contains("Paused"), "the PAUSED tag says that")
	assert_true(status.contains(str(ceili(game._world.march_left()))), "still the night timer: %s" % status)


func test_the_game_starts_with_following_off_and_the_view_on_the_column() -> void:
	game._begin()
	var cam: CameraRig = game.get_node("%Camera")
	var button: Button = game.get_node("%HUD").get_node("%FollowButton")
	assert_false(cam.follow, "not following")
	assert_false(button.button_pressed, "the button says so")
	var lead: Soldier = game.get_node("%World").army.lead()
	var view := Rect2(cam.view_m(), cam.view_size_m())
	assert_true(view.has_point(lead.pos), "the column is in view")


func test_clicking_the_stone_icon_on_the_bridge_button_builds_stone() -> void:
	game._begin()
	var tools: ToolController = game.get_node("%ToolController")
	tools.select(0)
	var bridge_button: ToolButton = game.get_node("%HUD").get_node("%Tools").get_child(1)
	var row: Node = bridge_button.get_node("%Materials")
	(row.get_child(1) as Button).pressed.emit()
	assert_eq(tools.tool().display_name, "Bridge", "picks the Bridge tool too")
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
	assert_eq(get_signal_parameters(Effects, "said")[0], "+2 logs", "the 2 m plan's price")


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


func test_losing_the_last_engineer_says_so_not_the_army() -> void:
	game._begin()
	var world: World = game.get_node("%World")
	for e: Crew.Engineer in world.crew.engineers.duplicate():
		world.crew._kill(e, "Spiked")
	await _real_seconds(game.lost_delay + 0.2)
	var hud: Node = game.get_node("%HUD")
	assert_true(hud.get_node("%Lost").visible, "the level is lost")
	assert_eq(hud.get_node("%LostTitle").text, game.crew_lost_title)
	assert_string_contains(hud.get_node("%LostText").text, "engineer")


func test_the_status_says_the_engineers_are_lost_not_the_column() -> void:
	game._begin()
	var world: World = game.get_node("%World")
	for e: Crew.Engineer in world.crew.engineers.duplicate():
		world.crew._kill(e, "Spiked")
	await get_tree().process_frame
	game._update_status()
	assert_eq(game.get_node("%HUD").get_node("%Status").text, game.crew_lost_status)
	assert_ne(game.crew_lost_status, game.lost_status)


func test_losing_the_army_still_says_the_army() -> void:
	game._begin()
	var world: World = game.get_node("%World")
	for s: Soldier in world.army.soldiers.duplicate():
		world.army.crush(s)
	await _real_seconds(game.lost_delay + 0.2)
	assert_eq(game.get_node("%HUD").get_node("%LostTitle").text, game.lost_title)


func test_the_lost_card_waits_a_moment_while_the_world_goes_on() -> void:
	game._begin()
	game._march()
	var world: World = game.get_node("%World")
	var hud: Node = game.get_node("%HUD")
	for s: Soldier in world.army.soldiers.duplicate():
		world.army.crush(s)
	await _real_seconds(game.lost_delay * 0.5)
	assert_false(hud.get_node("%Lost").visible, "not yet")
	assert_false(get_tree().paused, "the world goes on meanwhile")
	assert_true(game._over, "but the level is lost")
	await _real_seconds(game.lost_delay * 0.5 + 0.2)
	assert_true(hud.get_node("%Lost").visible, "then the card")
	assert_true(get_tree().paused)


func test_retrying_during_the_wait_keeps_the_lost_card_away() -> void:
	game._begin()
	var world: World = game.get_node("%World")
	for s: Soldier in world.army.soldiers.duplicate():
		world.army.crush(s)
	await get_tree().process_frame
	game._retry()
	await _real_seconds(game.lost_delay + 0.2)
	assert_false(game.get_node("%HUD").get_node("%Lost").visible)
	assert_false(game._over)
