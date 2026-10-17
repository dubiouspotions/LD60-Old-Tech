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
