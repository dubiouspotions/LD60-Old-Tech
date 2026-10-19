extends GutTest
## The boot scene: readies every sound behind a loading bar, then opens the main menu.

var _had_samples: bool


func before_each() -> void:
	_had_samples = Audio.samples


func after_each() -> void:
	Audio.samples = _had_samples


func _boot() -> Boot:
	var boot: Boot = load("res://menu/boot.tscn").instantiate()
	boot.next_scene = ""
	add_child_autofree(boot)
	return boot


func test_the_game_opens_on_the_boot_scene_which_leads_to_the_main_menu() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://menu/boot.tscn")
	var boot: Boot = load("res://menu/boot.tscn").instantiate()
	assert_eq(boot.next_scene, "res://menu/main_menu.tscn")
	assert_eq(boot.audio_folder, "res://audio")
	boot.free()


## On the web every stream is decoded into a sample before the menu, so no music freezes the game as it starts.
func test_with_sample_playback_it_waits_until_every_stream_is_readied() -> void:
	Audio.samples = true
	for s in Audio.preloaded():
		Audio._unready.append(s)
	var boot := _boot()
	watch_signals(boot)
	assert_lt(boot.progress(), 1.0)
	await wait_for_signal(boot.finished, 5.0)
	assert_signal_emitted(boot, "finished")
	assert_eq(Audio.to_ready(), 0)
	assert_eq(boot.progress(), 1.0)


func test_without_sample_playback_it_moves_straight_on() -> void:
	Audio.samples = false
	Audio._unready.clear()
	var boot := _boot()
	watch_signals(boot)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_signal_emitted(boot, "finished")
