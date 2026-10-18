extends GutTest
## Arrows against the world: logs shield the column.

const MAP: Array = [
	"..................",
	"..................",
	"..................",
	"..................",
	"..................",
	"##################",
	"BBBBBBBBBBBBBBBBBB",
]

var world: World


func before_each() -> void:
	GameState.save_path = "user://test_sappers.cfg"
	GameState.new_campaign()
	world = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	world.set_physics_process(false)
	world.terrain.clear()
	world.terrain.rebuild()
	for y in MAP.size():
		for x in MAP[y].length():
			var key: String = WorldFixture.LEGEND[MAP[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(1, 12.5)


func _shoot() -> Arrow:
	var arrow: Arrow = load("res://objects/arrow/arrow.tscn").instantiate()
	arrow.position = Grid.to_px(Vector2(4, 4.5))
	arrow.velocity = Vector2(15, 0)
	arrow.gravity = 0.0
	world.objects.add_child(arrow)
	return arrow


func test_arrow_hits_an_unshielded_soldier() -> void:
	var hp := world.army.lead().hp
	_shoot()
	await wait_physics_frames(60)
	assert_lt(world.army.lead().hp, hp)


func test_log_wall_stops_the_arrow() -> void:
	var b := world.bridge
	b.build(b.snap_point(Vector2(8, 5)), b.snap_point(Vector2(8, 2)), preload("res://data/bridge/log.tres"))
	var hp := world.army.lead().hp
	var arrow := _shoot()
	await wait_physics_frames(60)
	assert_eq(world.army.lead().hp, hp, "the soldier is unhurt")
	assert_true(is_instance_valid(arrow), "stuck in the log")
	assert_almost_eq(Grid.to_m(arrow.position).x, 8.0, 0.3)


func test_archer_can_not_shoot_down_through_its_own_tower() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for x in 18:
		world.terrain.set_type(Vector2i(x, 6), WorldFixture.type("soil"))
		world.terrain.set_type(Vector2i(x, 7), WorldFixture.type("bedrock"))
		if x >= 8 and x <= 10:
			for y in range(2, 6):
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type("brick"))
	world.army.spawn(1, 7.4)
	var archer: Archer = load("res://objects/archer/archer.tscn").instantiate()
	archer.position = Grid.to_px(Vector2(8.5, 2))
	archer.first_shot_delay = 0.0
	archer.aim_error = 0.0
	world.objects.add_child(archer)
	var hp := world.army.lead().hp
	await wait_physics_frames(180)
	assert_eq(world.army.soldiers.size(), 1, "the tower's own wall is in the way")
	if world.army.lead():
		assert_eq(world.army.lead().hp, hp, "not even wounded")


## Archer on a tower at column 14 (feet at y = 2); a wall at column 12 hides the ground just in front of it.
func _tower_and_wall() -> Archer:
	for y in range(2, 5):
		for x in range(13, 16):
			world.terrain.set_type(Vector2i(x, y), WorldFixture.type("brick"))
	for y in range(3, 5):
		world.terrain.set_type(Vector2i(12, y), WorldFixture.type("brick"))
	var archer: Archer = load("res://objects/archer/archer.tscn").instantiate()
	archer.position = Grid.to_px(Vector2(14.5, 2))
	world.objects.add_child(archer)
	return archer


## Puts the column's soldiers at these x positions on the ground (row 5).
func _soldiers_at(xs: Array) -> Array[Soldier]:
	world.army.spawn(xs.size(), 1.0)
	for i in xs.size():
		world.army.soldiers[i].pos = Vector2(xs[i], 5.0)
	return world.army.soldiers


## With its own tower in the way of every shot, the archer walks to the edge of the tower top for a clear one.
func test_archer_walks_to_the_tower_edge_for_a_clear_shot() -> void:
	for y in range(2, 5):
		for x in range(9, 13):
			world.terrain.set_type(Vector2i(x, y), WorldFixture.type("brick"))
	var archer: Archer = load("res://objects/archer/archer.tscn").instantiate()
	archer.position = Grid.to_px(Vector2(9.5, 2))
	archer.first_shot_delay = 0.0
	world.objects.add_child(archer)
	var s := _soldiers_at([15.5])
	assert_false(archer.sees(world, s[0]), "its own tower is in the way from where it stands")
	await wait_physics_frames(240)
	assert_gt(archer.feet_m().x, 11.0, "walked over to the near edge")
	assert_lt(archer.feet_m().x, 13.0, "still on its tower")
	assert_true(world.terrain.is_solid(Grid.cell_of(archer.feet_m() + Vector2(0, 0.5))), "standing on it")
	assert_true(archer.sees(world, s[0]), "a clear shot from there")
	assert_gt(archer.walk_speed, 0.0)


func test_archer_shoots_a_soldier_it_can_see_over_a_nearer_hidden_one() -> void:
	var archer := _tower_and_wall()
	var s := _soldiers_at([11.5, 5.5])
	assert_false(archer.sees(world, s[0]), "behind the wall")
	assert_true(archer.sees(world, s[1]))
	assert_eq(archer.pick_target(world), s[1])


func test_archer_still_shoots_the_nearest_when_none_can_be_seen() -> void:
	var archer := _tower_and_wall()
	var s := _soldiers_at([11.5, 11.2])
	assert_eq(archer.pick_target(world), s[0], "fires anyway")


func test_archer_shoots_the_nearest_of_those_it_can_see() -> void:
	var archer := _tower_and_wall()
	var s := _soldiers_at([11.5, 5.5, 7.5])
	assert_eq(archer.pick_target(world), s[2])


func test_a_log_wall_hides_a_soldier_from_the_archer() -> void:
	var archer := _tower_and_wall()
	var s := _soldiers_at([9.5, 4.5])
	var b := world.bridge
	b.build(b.snap_point(Vector2(10, 5)), b.snap_point(Vector2(10, 3)), preload("res://data/bridge/log.tres"))
	assert_false(archer.sees(world, s[0]), "behind the logs")
	assert_eq(archer.pick_target(world), s[1])


func test_out_of_range_soldiers_are_not_targets() -> void:
	var archer := _tower_and_wall()
	_soldiers_at([0.5])
	archer.shoot_range = 5.0
	assert_null(archer.pick_target(world))
