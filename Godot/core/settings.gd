extends Node
## The player's display settings, kept for the next session (the volumes are kept by Audio). Autoload "Settings".

## Where they are kept, beside the volumes. Tests point this elsewhere.
var settings_path: String = "user://settings.cfg"


func _ready() -> void:
	# A browser only goes full screen on a click, so the web build always starts in the page.
	if saved_fullscreen() and not OS.has_feature("web"):
		set_fullscreen(true, false)


## The game fills the screen (or, on the web, the browser's screen).
func fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Fills the screen, or goes back to a window. Saved for the next session unless save is false.
func set_fullscreen(on: bool, save: bool = true) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if save:
		var cfg := ConfigFile.new()
		cfg.load(settings_path)
		cfg.set_value("display", "fullscreen", on)
		cfg.save(settings_path)


## Was the game left full screen.
func saved_fullscreen() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(settings_path) == OK and bool(cfg.get_value("display", "fullscreen", false))
