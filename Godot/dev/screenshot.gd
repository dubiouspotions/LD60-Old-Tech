extends Node
## Starts the game, presses Begin, plays for a while and saves a screenshot. For checking the build by eye.
##   godot res://dev/screenshot.tscn -- out=<png path> [seconds=4] [level=1]

func _ready() -> void:
	var out := "user://screenshot.png"
	var seconds := 4.0
	var level := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("seconds="):
			seconds = float(a.get_slice("=", 1))
		elif a.begins_with("level="):
			level = int(a.get_slice("=", 1))
	var game: Game = load("res://game/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	if level > 1:
		game.call(&"_load_level", level - 1, false)
	game.call(&"_begin")
	await get_tree().create_timer(seconds, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
