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
