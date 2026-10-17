extends GutTest
## The soldier's look follows what it does.

var soldier: Soldier
var sprite: AnimatedSprite2D


func before_each() -> void:
	soldier = load("res://objects/soldier/soldier.tscn").instantiate()
	add_child_autofree(soldier)
	sprite = soldier.get_node("Body/AnimatedSprite2D")


func _show(moving: bool) -> void:
	soldier.moving = moving
	soldier.sync()
	await wait_process_frames(2)


func test_standing_soldier_does_not_walk_on_the_spot() -> void:
	await _show(false)
	assert_false(sprite.is_playing(), "idle holds still")


func test_walking_soldier_plays_its_walk_cycle() -> void:
	await _show(true)
	assert_true(sprite.is_playing())
	await _show(false)
	assert_false(sprite.is_playing(), "stops when the column halts")


func test_idle_engineer_does_not_walk_on_the_spot() -> void:
	var engineer: Soldier = load("res://objects/engineer/engineer.tscn").instantiate()
	add_child_autofree(engineer)
	var art: AnimatedSprite2D = engineer.get_node("Body/AnimatedSprite2D")
	engineer.moving = false
	engineer.sync()
	await wait_process_frames(2)
	assert_false(art.is_playing(), "idle holds still")
	engineer.moving = true
	engineer.sync()
	await wait_process_frames(2)
	assert_true(art.is_playing(), "walks when moving")
