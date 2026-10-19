extends GutTest
## Music and sound volume: set per bus, saved, and restored.

const PATH := "user://test_settings.cfg"

var _saved: Dictionary = {}


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	Audio.settings_path = PATH
	for bus: StringName in [&"Music", &"SFX"]:
		_saved[bus] = Audio.volume(bus)


func after_each() -> void:
	for bus: StringName in _saved:
		Audio.set_volume(bus, _saved[bus])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _db(bus: StringName) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))


func test_set_volume_changes_the_bus() -> void:
	Audio.set_volume(&"Music", 0.5)
	assert_almost_eq(Audio.volume(&"Music"), 0.5, 0.001)
	assert_almost_eq(_db(&"Music"), linear_to_db(0.5), 0.01)


func test_zero_mutes() -> void:
	Audio.set_volume(&"SFX", 0.0)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")))
	assert_eq(Audio.volume(&"SFX"), 0.0)
	Audio.set_volume(&"SFX", 0.3)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")))


func test_volumes_are_saved_and_restored() -> void:
	Audio.set_volume(&"Music", 0.25)
	Audio.set_volume(&"SFX", 0.75)
	Audio.set_volume(&"Music", 1.0, false)
	Audio.set_volume(&"SFX", 1.0, false)
	Audio.load_volumes()
	assert_almost_eq(Audio.volume(&"Music"), 0.25, 0.001)
	assert_almost_eq(Audio.volume(&"SFX"), 0.75, 0.001)


func test_hud_sliders_report_volume() -> void:
	var hud: Hud = load("res://ui/hud.tscn").instantiate()
	add_child_autofree(hud)
	watch_signals(hud)
	hud.set_volumes(0.4, 0.6)
	assert_almost_eq(hud.get_node("%MusicSlider").value, 0.4, 0.001)
	hud.get_node("%SoundSlider").value = 0.2
	assert_signal_emitted_with_parameters(hud, "volume_changed", [&"SFX", 0.2])


## Every stream the game plays, gathered from the sounds, the campaign, the levels' music and the camp's crackle.
func _streams_in_use() -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	for f in ResourceLoader.list_directory("res://data/sounds"):
		var sfx := load("res://data/sounds/" + f) as SoundEffect
		if sfx:
			out.append_array(sfx.streams)
	var c := GameState.campaign
	for sfx: SoundEffect in [c.level_up_sound, c.lost_sound, c.victory_sound, c.dawn_sound]:
		out.append_array(sfx.streams)
	out.append(c.camp_music)
	var level: Level = load("res://levels/level_base.tscn").instantiate()
	out.append(level.music)
	level.free()
	var camp: Node = load("res://objects/camp/camp.tscn").instantiate()
	out.append((camp.get_node("%Crackle") as AudioStreamPlayer2D).stream)
	camp.free()
	return out


## Everything under the audio folder is loaded at start, so no sound or music loads the first time it plays.
func test_preloading_the_audio_folder_loads_every_stream_in_use() -> void:
	Audio.preload_folder("res://audio")
	var loaded := Audio.preloaded()
	for s in _streams_in_use():
		assert_true(s in loaded, "%s loaded ahead" % s.resource_path)


## Where sounds play as WebAudio samples (the web build), each stream is registered as one ahead of its first
## play, one stream a frame so the start does not freeze; elsewhere nothing needs registering.
func test_with_sample_playback_every_stream_is_readied_a_frame_at_a_time() -> void:
	var had := Audio.samples
	Audio.samples = true
	Audio.preload_folder("res://audio")
	var waiting := Audio.to_ready()
	if waiting > 1:
		await get_tree().process_frame
		assert_lt(Audio.to_ready(), waiting, "a stream readied a frame")
	for i in waiting + 2:
		await get_tree().process_frame
	assert_eq(Audio.to_ready(), 0, "all readied")
	Audio.samples = false
	Audio.preload_folder("res://audio")
	assert_eq(Audio.to_ready(), 0, "nothing to ready without sample playback")
	Audio.samples = had


## Sounds count as samples wherever the engine plays them as samples: the web build, by its platform override.
func test_samples_follow_the_playback_type_of_this_platform() -> void:
	var key := "audio/general/default_playback_type"
	# The setting counts 0 = Stream, 1 = Sample.
	assert_eq(Audio.samples, ProjectSettings.get_setting_with_override(key) == 1)
	assert_eq(ProjectSettings.get_setting(key + ".web"), 1, "the web build plays samples")


## The game preloads its audio folder (Audio Folder on the Game node) as it starts.
func test_the_game_preloads_its_audio_folder() -> void:
	var game: Game = load("res://game/main.tscn").instantiate()
	assert_eq(game.audio_folder, "res://audio")
	add_child_autofree(game)
	assert_true(GameState.campaign.camp_music in Audio.preloaded(), "the night music is ready before the first camp")
	get_tree().paused = false
