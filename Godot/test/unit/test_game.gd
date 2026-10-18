extends GutTest
## The game screen as a whole.

var game: Game


func before_each() -> void:
	game = load("res://game/main.tscn").instantiate()
	add_child_autofree(game)


func after_each() -> void:
	get_tree().paused = false


func test_plans_clear_without_errors_once_the_game_is_over() -> void:
	game._over = true
	game._show_plans()
	assert_eq(game._plans.size(), 0)


func test_follow_button_turns_following_off_and_on() -> void:
	var cam: CameraRig = game.get_node("%Camera")
	var button: Button = game.get_node("%HUD").get_node("%FollowButton")
	assert_true(button.button_pressed, "on from the start, like the camera")
	button.button_pressed = false
	assert_false(cam.follow, "unmarking stops following")
	button.button_pressed = true
	assert_true(cam.follow, "marking follows again")
