extends Node
## Starts the game, presses Begin, plays for a while and saves a screenshot. For checking the build by eye.
##   godot res://dev/screenshot.tscn -- out=<png path> [seconds=4] [level=1] [march] [look=<x metres>]
## march orders the march at once (skips the night camp); look parks the camera with its left edge at x.

func _ready() -> void:
	var out := "user://screenshot.png"
	var seconds := 4.0
	var level := 1
	var march := false
	var look := NAN
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("seconds="):
			seconds = float(a.get_slice("=", 1))
		elif a.begins_with("level="):
			level = int(a.get_slice("=", 1))
		elif a == "march":
			march = true
		elif a.begins_with("look="):
			look = float(a.get_slice("=", 1))
	var game: Game = load("res://game/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	if level > 1:
		game.call(&"_start_at_level", level - 1)
	game.call(&"_begin")
	if march:
		game.call(&"_march")
	var camera: CameraRig = game.get_node(^"%Camera")
	var left := Time.get_ticks_msec() + seconds * 1000.0
	while Time.get_ticks_msec() < left:
		if not is_nan(look):
			camera.follow = false
			camera.position.x = look * Grid.PX
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
