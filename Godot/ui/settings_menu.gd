class_name SettingsMenu
extends PanelContainer
## Music and sound volume and full screen. Each change takes effect and is saved at once. Back (or Escape) closes it.

signal closed

## Audio buses behind the Music and Sound sliders.
@export var music_bus: StringName = &"Music"
@export var sound_bus: StringName = &"SFX"
@export var click_sound: SoundEffect


func _ready() -> void:
	%MusicSlider.value_changed.connect(func(v: float) -> void: Audio.set_volume(music_bus, v))
	%SoundSlider.value_changed.connect(func(v: float) -> void: Audio.set_volume(sound_bus, v))
	# A click after moving the sound slider, so the new level can be heard.
	%SoundSlider.drag_ended.connect(func(_changed: bool) -> void: Audio.play(click_sound))
	%FullscreenCheck.toggled.connect(func(on: bool) -> void:
		Audio.play(click_sound)
		Settings.set_fullscreen(on))
	%BackButton.pressed.connect(close)
	visibility_changed.connect(refresh)
	refresh()


## Shows the settings as they are now, without changing them.
func refresh() -> void:
	%MusicSlider.set_value_no_signal(Audio.volume(music_bus))
	%SoundSlider.set_value_no_signal(Audio.volume(sound_bus))
	%FullscreenCheck.set_pressed_no_signal(Settings.fullscreen())


func close() -> void:
	Audio.play(click_sound)
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
