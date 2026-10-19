class_name PauseMenu
extends ColorRect
## The pause menu over the game: Resume, Restart from Checkpoint, Restart, Settings and Quit to Main Menu. It only
## reports the clicks (the Game pauses, restarts and quits); Settings it shows itself, in place of the buttons.

signal resume_pressed
signal restart_checkpoint_pressed
signal restart_pressed
signal quit_pressed

@export var click_sound: SoundEffect


func _ready() -> void:
	%ResumeButton.pressed.connect(resume_pressed.emit)
	%RestartCheckpointButton.pressed.connect(restart_checkpoint_pressed.emit)
	%RestartButton.pressed.connect(restart_pressed.emit)
	%QuitButton.pressed.connect(quit_pressed.emit)
	%SettingsButton.pressed.connect(func() -> void:
		Audio.play(click_sound)
		show_settings(true))
	%SettingsMenu.closed.connect(show_settings.bind(false))
	visibility_changed.connect(func() -> void:
		if visible:
			show_settings(false))


## Shows the settings in place of the buttons, or the buttons again.
func show_settings(on: bool) -> void:
	%Buttons.visible = not on
	%SettingsMenu.visible = on
