extends GutTest
## The pause menu: Escape (or the Menu button) pauses the game under it, and it restarts, opens the settings or
## quits to the main menu.

var game: Game
var hud: Hud
var menu: PauseMenu


func before_each() -> void:
	game = load("res://game/main.tscn").instantiate()
	add_child_autofree(game)
	game._begin()
	hud = game.get_node("%HUD")
	menu = hud.get_node("%PauseMenu")


func after_each() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0


## Presses and releases a key through the whole input pipeline, as the player would.
func _tap(code: Key) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.physical_keycode = code
		k.keycode = code
		k.pressed = pressed
		Input.parse_input_event(k)
		Input.flush_buffered_events()


func _press(button: String) -> void:
	(menu.get_node("%" + button) as Button).pressed.emit()


func test_escape_is_the_pause_menu_key() -> void:
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	assert_true(InputMap.action_has_event(&"pause_menu", esc))


func test_escape_pauses_under_the_menu_and_escape_again_plays_on() -> void:
	assert_false(menu.visible)
	_tap(KEY_ESCAPE)
	assert_true(menu.visible, "the menu shows")
	assert_true(get_tree().paused, "the game is paused under it")
	_tap(KEY_ESCAPE)
	assert_false(menu.visible)
	assert_false(get_tree().paused, "playing again")


func test_resume_plays_on() -> void:
	_tap(KEY_ESCAPE)
	_press("ResumeButton")
	assert_false(menu.visible)
	assert_false(get_tree().paused)


func test_closing_the_menu_keeps_a_pause_the_player_made() -> void:
	game._toggle_pause()
	assert_true(get_tree().paused)
	_tap(KEY_ESCAPE)
	_tap(KEY_ESCAPE)
	assert_false(menu.visible)
	assert_true(get_tree().paused, "still paused, as before the menu")


func test_the_pause_key_does_nothing_under_the_menu() -> void:
	_tap(KEY_ESCAPE)
	game._toggle_pause()
	assert_true(get_tree().paused)
	assert_true(menu.visible)


func test_the_menu_button_opens_the_pause_menu() -> void:
	(hud.get_node("%MenuButton") as Button).pressed.emit()
	assert_true(menu.visible)
	assert_true(get_tree().paused)


func test_escape_first_puts_down_the_plank_in_hand() -> void:
	var tools: ToolController = game.get_node("%ToolController")
	var world: World = game.get_node("%World")
	tools._build_from = world.bridge.snap_point(world.army.lead().pos + Vector2(2, 0))
	assert_not_null(tools.preview_from())
	_tap(KEY_ESCAPE)
	assert_null(tools.preview_from(), "the plank is put down")
	assert_false(menu.visible, "and that is all")
	_tap(KEY_ESCAPE)
	assert_true(menu.visible, "with nothing in hand, the menu")


func test_right_click_does_not_open_the_menu() -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	Input.parse_input_event(click)
	Input.flush_buffered_events()
	assert_false(menu.visible)


func test_restart_from_checkpoint_puts_the_level_back_and_plays_on() -> void:
	var world: World = game.get_node("%World")
	var earth := GameState.supplies.earth
	var b := world.bridge
	var lead := world.army.lead().pos
	b.build(b.snap_point(lead + Vector2(2, 0)), b.snap_point(lead + Vector2(4, 0)), preload("res://data/bridge/log.tres"))
	GameState.supplies.earth = earth + 7
	_tap(KEY_ESCAPE)
	_press("RestartCheckpointButton")
	assert_eq(b.members.size(), 0, "the level's bridge is gone")
	assert_eq(GameState.supplies.earth, earth, "supplies as at the checkpoint")
	assert_false(menu.visible)
	assert_false(get_tree().paused)


func test_restart_starts_the_campaign_over() -> void:
	game._skip_level()
	assert_eq(GameState.level_index, 1)
	_tap(KEY_ESCAPE)
	_press("RestartButton")
	assert_eq(GameState.level_index, 0, "back at the first level")
	assert_eq(GameState.soldiers, GameState.campaign.start_soldiers)
	assert_false(menu.visible)
	assert_false(get_tree().paused)


func test_settings_show_in_place_of_the_buttons_and_escape_brings_them_back() -> void:
	_tap(KEY_ESCAPE)
	var buttons: Control = menu.get_node("%Buttons")
	var settings: SettingsMenu = menu.get_node("%SettingsMenu")
	_press("SettingsButton")
	assert_true(settings.visible)
	assert_false(buttons.visible)
	_tap(KEY_ESCAPE)
	assert_false(settings.visible, "Escape closes the settings...")
	assert_true(buttons.visible)
	assert_true(menu.visible, "...not the menu")
	assert_true(get_tree().paused)


func test_the_menu_opens_on_its_buttons_again() -> void:
	_tap(KEY_ESCAPE)
	_press("SettingsButton")
	_press("ResumeButton")
	_tap(KEY_ESCAPE)
	assert_true(menu.get_node("%Buttons").visible)
	assert_false(menu.get_node("%SettingsMenu").visible)


func test_quit_goes_to_the_main_menu() -> void:
	assert_true(hud.quit_pressed.is_connected(game._to_menu), "the game leaves for the main menu")
	# Not actually left: changing scene would put the main menu in place of the tests for the rest of the run.
	hud.quit_pressed.disconnect(game._to_menu)
	watch_signals(hud)
	_tap(KEY_ESCAPE)
	_press("QuitButton")
	assert_signal_emitted(hud, "quit_pressed")
