extends Node
## The title screen: New Game, Settings and Quit over the bridge-building show (MenuShow), to the menu music.
## It is the game's main scene; the game (game_scene) comes back here with its Menu button.

@export_file("*.tscn") var game_scene: String = "res://game/main.tscn"
## Loops while the menu is open.
@export var music: AudioStream
@export var click_sound: SoundEffect


func _ready() -> void:
	# Back from a game that was paused or sped up.
	get_tree().paused = false
	Engine.time_scale = 1.0
	Audio.play_music(music)
	%NewGameButton.pressed.connect(new_game)
	%SettingsButton.pressed.connect(func() -> void:
		Audio.play(click_sound)
		show_settings(true))
	%SettingsMenu.closed.connect(show_settings.bind(false))
	%QuitButton.pressed.connect(get_tree().quit)
	# A browser tab can not be quit.
	%QuitButton.visible = not OS.has_feature("web")


func new_game() -> void:
	Audio.play(click_sound)
	get_tree().change_scene_to_file(game_scene)


## Shows the settings in place of the buttons, or the buttons again.
func show_settings(on: bool) -> void:
	%Buttons.visible = not on
	%SettingsMenu.visible = on
