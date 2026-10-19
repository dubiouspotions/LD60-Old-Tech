extends GutTest
## The main menu: its looping bridge show, its buttons and music, and the settings.

const SETTINGS := "user://test_settings.cfg"
const DT := 1.0 / 60.0

var _campaign: Campaign
var _volumes: Dictionary = {}


func before_each() -> void:
	_campaign = GameState.campaign
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	Audio.settings_path = SETTINGS
	Settings.settings_path = SETTINGS
	for bus: StringName in [&"Music", &"SFX"]:
		_volumes[bus] = Audio.volume(bus)


func after_each() -> void:
	for bus: StringName in _volumes:
		Audio.set_volume(bus, _volumes[bus], false)
	Audio.play_music(null)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	GameState.campaign = _campaign


## The show stepped by hand, so a whole act runs in one test.
func _show() -> MenuShow:
	var show: MenuShow = load("res://menu/menu_show.tscn").instantiate()
	add_child_autofree(show)
	show.set_physics_process(false)
	show.world.set_physics_process(false)
	show.world.birds.set_physics_process(false)
	return show


## Steps the show until done returns true or seconds have passed. Returns the stages it went through.
func _run(show: MenuShow, seconds: float, done: Callable) -> Array:
	var stages: Array = [show.stage]
	for i in roundi(seconds / DT):
		show.world._physics_process(DT)
		show.world.birds._physics_process(DT)
		show._physics_process(DT)
		if stages[-1] != show.stage:
			stages.append(show.stage)
		if done.call():
			break
	return stages


func test_the_game_opens_on_the_main_menu() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://menu/main_menu.tscn")
	assert_eq(Level.GAME_SCENE, "res://game/main.tscn", "a level run on its own still goes straight into the game")


func test_the_show_plays_its_own_level_and_gives_the_campaign_back() -> void:
	var show := _show()
	assert_eq(GameState.campaign.levels, [show.level] as Array[String])
	assert_eq(GameState.campaign.tools, _campaign.tools, "everything else as the campaign has it")
	remove_child(show)
	assert_eq(GameState.campaign, _campaign)


func test_every_act_has_a_bridge_that_gives_way() -> void:
	var show := _show()
	assert_gt(show.acts.size(), 1, "more than one way to fail")
	for act in show.acts:
		assert_gt(act.pieces.size(), 0)
		assert_gt(act.breaks.size(), 0)
		assert_gt(act.give_way_past, 0.5, "the front soldier is on the far half when it gives way")
		for i in act.breaks:
			assert_between(i, 0, act.pieces.size() - 1, "breaks name pieces of the bridge")


func test_an_act_builds_a_bridge_the_column_falls_through() -> void:
	var show := _show()
	assert_eq(show.act_index, 0)
	assert_eq(show.stage, MenuShow.Stage.BUILD)
	var soldiers: int = show.acts[0].soldiers
	assert_eq(show.world.army.soldiers.size(), soldiers)
	assert_false(show.world.army.hold, "the column walks in with the crew...")
	var near_end: float = show.members.map(func(m: Bridge.Member) -> float: return minf(m.a.pos.x, m.b.pos.x)).min()
	var far_end: float = show.members.map(func(m: Bridge.Member) -> float: return maxf(m.a.pos.x, m.b.pos.x)).max()
	assert_lt(show.world.army.stop_x, near_end, "...and waits short of the bridge")
	_run(show, 60.0, func() -> bool: return show.stage != MenuShow.Stage.BUILD)
	assert_eq(show.stage, MenuShow.Stage.CROSS)
	assert_lt(show.world.army.lead().pos.x, near_end, "it has waited at the edge while the bridge went up")
	var stages := _run(show, 60.0, func() -> bool: return show.stage == MenuShow.Stage.GIVE_WAY)
	assert_eq(stages, [MenuShow.Stage.CROSS, MenuShow.Stage.GIVE_WAY])
	assert_gt(show.world.army.lead().pos.x, (near_end + far_end) / 2.0, "the front is on the far half when it gives way")
	_run(show, 5.0, func() -> bool: return show.stage == MenuShow.Stage.FALL)
	assert_true(show.members.any(func(m: Bridge.Member) -> bool: return m.dead), "it gave way")
	_run(show, 60.0, func() -> bool: return show.stage == MenuShow.Stage.REST)
	assert_eq(show.stage, MenuShow.Stage.REST)
	assert_lt(show.world.army.soldiers.size(), soldiers / 2, "most of the column fell")
	assert_true(show.world.bridge.nodes.all(func(j: Bridge.Joint) -> bool: return not j.pinned), "the rest of the bridge drops after them")


func test_birds_burst_from_the_grass_and_cross_the_sky() -> void:
	var show := _show()
	var birds: Array[Bird] = []
	show.world.objects.child_entered_tree.connect(func(n: Node) -> void:
		if n is Bird:
			birds.append(n))
	_run(show, 20.0, func() -> bool: return false)
	var crossing := birds.filter(func(b: Bird) -> bool: return b.lift == 0.0)
	assert_gt(birds.size() - crossing.size(), 0, "the crew and the column flush birds from the grass")
	assert_gt(crossing.size(), 0, "a bird flies across the sky")


func test_the_acts_loop() -> void:
	var show := _show()
	show.act_index = show.acts.size() - 2
	show.next_act()
	assert_eq(show.act_index, show.acts.size() - 1)
	show.next_act()
	assert_eq(show.act_index, 0, "after the last, the first again")
	assert_eq(show.stage, MenuShow.Stage.BUILD)
	assert_eq(show.world.bridge.members.size(), show.acts[0].pieces.size(), "only the new act's bridge")


func test_an_act_that_gets_stuck_is_cut_short() -> void:
	var show := _show()
	show.act_timeout = 10.0
	# No crew: the bridge is never built.
	for e in show.world.crew.engineers:
		e.node.free()
	show.world.crew.engineers.clear()
	_run(show, 11.0, func() -> bool: return show.act_index != 0)
	assert_eq(show.act_index, 1)


func test_the_main_menu_plays_its_music() -> void:
	var menu: Node = load("res://menu/main_menu.tscn").instantiate()
	add_child_autofree(menu)
	assert_not_null(menu.music)
	assert_eq(Audio._music.stream, menu.music)
	assert_true(Audio._music.playing)


func test_settings_take_the_place_of_the_buttons_until_closed() -> void:
	var menu: Node = load("res://menu/main_menu.tscn").instantiate()
	add_child_autofree(menu)
	var buttons: Control = menu.get_node("%Buttons")
	var settings: SettingsMenu = menu.get_node("%SettingsMenu")
	assert_true(buttons.visible)
	assert_false(settings.visible)
	(menu.get_node("%SettingsButton") as Button).pressed.emit()
	assert_false(buttons.visible)
	assert_true(settings.visible)
	(settings.get_node("%BackButton") as Button).pressed.emit()
	assert_true(buttons.visible)
	assert_false(settings.visible)


func test_the_settings_sliders_set_and_save_the_volumes() -> void:
	var settings: SettingsMenu = load("res://ui/settings_menu.tscn").instantiate()
	add_child_autofree(settings)
	(settings.get_node("%MusicSlider") as Range).value = 0.25
	(settings.get_node("%SoundSlider") as Range).value = 0.6
	assert_almost_eq(Audio.volume(&"Music"), 0.25, 0.001)
	assert_almost_eq(Audio.volume(&"SFX"), 0.6, 0.001)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(SETTINGS), OK)
	assert_almost_eq(float(cfg.get_value("volume", "Music")), 0.25, 0.001)


func test_the_settings_show_the_volumes_as_they_are() -> void:
	Audio.set_volume(&"Music", 0.4, false)
	var settings: SettingsMenu = load("res://ui/settings_menu.tscn").instantiate()
	add_child_autofree(settings)
	assert_almost_eq((settings.get_node("%MusicSlider") as Range).value, 0.4, 0.001)


func test_full_screen_is_saved_for_the_next_session() -> void:
	assert_false(Settings.saved_fullscreen())
	Settings.set_fullscreen(true)
	assert_true(Settings.saved_fullscreen())
	Settings.set_fullscreen(false)
	assert_false(Settings.saved_fullscreen())


func test_the_hud_menu_button_asks_for_the_main_menu() -> void:
	var hud: Hud = load("res://ui/hud.tscn").instantiate()
	add_child_autofree(hud)
	watch_signals(hud)
	(hud.get_node("%MenuButton") as Button).pressed.emit()
	assert_signal_emitted(hud, "menu_pressed")
