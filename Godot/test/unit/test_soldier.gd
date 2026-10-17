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
	await wait_seconds(soldier.idle_delay + 0.1)
	soldier.sync()
	await wait_process_frames(2)
	assert_false(sprite.is_playing(), "stops once the column has stood still a moment")


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


func test_engineers_animate_while_walking_in_the_crew() -> void:
	GameState.new_campaign()
	var world: World = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	world.set_physics_process(false)
	world.terrain.clear()
	world.terrain.rebuild()
	for x in 40:
		world.terrain.set_type(Vector2i(x, 6), WorldFixture.type("soil"))
		world.terrain.set_type(Vector2i(x, 7), WorldFixture.type("bedrock"))
	world.army.spawn(1, 30.5)
	world.crew.spawn(3.0)
	var walking := 0
	for i in 30:
		world.crew.step(1.0 / 60.0)
		await wait_process_frames(1)
	for e in world.crew.engineers:
		if e.node.moving:
			walking += 1
			assert_true((e.node.get_node("Body/AnimatedSprite2D") as AnimatedSprite2D).is_playing(), "walk cycle plays")
	assert_gt(walking, 0, "someone is walking to the column")


func test_a_moment_standing_does_not_reset_the_walk_cycle() -> void:
	var engineer: Soldier = load("res://objects/engineer/engineer.tscn").instantiate()
	add_child_autofree(engineer)
	var art: AnimatedSprite2D = engineer.get_node("Body/AnimatedSprite2D")
	engineer.moving = true
	engineer.sync()
	await wait_process_frames(3)
	engineer.moving = false
	engineer.sync()
	await wait_process_frames(1)
	assert_true(art.is_playing(), "a one-frame stop keeps walking")
	engineer.moving = true
	engineer.sync()
	await wait_process_frames(1)
	assert_true(art.is_playing())
