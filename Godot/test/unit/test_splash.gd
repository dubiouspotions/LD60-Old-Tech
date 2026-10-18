extends GutTest
## Whatever falls into water splashes at its surface: a sandbag or box, a thrown sandbag, a soldier, an engineer,
## a bridge piece and a falling tower. Ground (soil) does not splash.

## Ground at row 6 with a pool of water at x 4..9, rows 6..8.
const MAP: Array = [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"####~~~~~~##########",
	"####~~~~~~##########",
	"####~~~~~~##########",
	"BBBBBBBBBBBBBBBBBBBB",
]

## The water's surface (y, pixels).
const SURFACE_PX: float = 6 * 32.0

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
	watch_signals(Effects)


func _run(seconds: float) -> void:
	for i in int(seconds * 60):
		world.terrain.settle()
		world._physics_process(1.0 / 60.0)


## Where splashes were shown (pixels).
func _splashes() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in get_signal_emit_count(Effects, "burst"):
		var p: Array = get_signal_parameters(Effects, "burst", i)
		if p[0] == &"splash":
			out.append(p[1])
	return out


## A splash was shown at the water's surface, between x0 and x1 (metres).
func _assert_splashed(x0: float, x1: float, what: String) -> void:
	var at := _splashes()
	assert_false(at.is_empty(), "%s splashed" % what)
	if at.is_empty():
		return
	assert_almost_eq(at[0].y, SURFACE_PX, 1.0, "at the surface")
	assert_between(at[0].x, x0 * 32.0, x1 * 32.0, "where it went in")


func _sandbag_tool() -> ToolDefinition:
	return GameState.campaign.tools.filter(func(t: ToolDefinition) -> bool: return t.kind == ToolDefinition.Kind.FILL)[0]


func test_a_sandbag_falling_into_water_splashes() -> void:
	var bag: FallingBlock = _sandbag_tool().spawn_scene.instantiate()
	bag.position = Grid.to_px(Vector2(6, 1))
	world.objects.add_child(bag)
	_run(2.0)
	_assert_splashed(6.0, 7.0, "a sandbag")
	assert_eq(_splashes().size(), 1, "once, going in")


func test_a_box_falling_into_water_splashes_too() -> void:
	var box: FallingBlock = world.falling_block_scene.instantiate()
	box.type = WorldFixture.type("box")
	box.position = Grid.to_px(Vector2(5, 1))
	world.objects.add_child(box)
	_run(2.0)
	_assert_splashed(5.0, 6.0, "a box")


func test_a_sandbag_thrown_into_water_splashes() -> void:
	var order := world.crew.order_throw(Vector2i(7, 7), _sandbag_tool())
	world.crew.throws.erase(order)
	world.crew.threw.emit(order, Vector2(1.5, 5.0))
	_run(2.0)
	_assert_splashed(5.0, 8.0, "a thrown sandbag")
	assert_eq(_splashes().size(), 1, "once, going in")


func test_a_soldier_falling_into_water_splashes() -> void:
	world.army.spawn(1, 2.5)
	world.army.hold = true
	var s := world.army.soldiers[0]
	s.pos = Vector2(6.5, 2.0)
	s.airborne = true
	s.vy = 0.0
	_run(1.5)
	_assert_splashed(6.0, 7.0, "a soldier")


func test_an_engineer_falling_into_water_splashes() -> void:
	world.army.spawn(1, 2.5)
	world.army.hold = true
	world.crew.spawn(2.5)
	world.crew.engineers[0].pos = Vector2(7.5, 2.0)
	_run(1.5)
	_assert_splashed(7.0, 8.0, "an engineer")


func test_a_bridge_piece_falling_into_water_splashes() -> void:
	var b := world.bridge
	b.build(b.snap_point(Vector2(5.2, 3.0)), b.snap_point(Vector2(8.2, 3.0)), load("res://data/bridge/log.tres"))
	_run(2.0)
	_assert_splashed(4.0, 10.0, "a bridge piece")


func test_a_tower_falling_onto_water_splashes() -> void:
	for y in range(2, 4):
		world.terrain.set_type(Vector2i(6, y), WorldFixture.type("brick"))
	_run(2.0)
	_assert_splashed(6.0, 7.0, "a tower")


func test_falling_onto_ground_does_not_splash() -> void:
	var bag: FallingBlock = _sandbag_tool().spawn_scene.instantiate()
	bag.position = Grid.to_px(Vector2(14, 1))
	world.objects.add_child(bag)
	_run(2.0)
	assert_true(_splashes().is_empty())


func test_walking_into_water_does_not_splash() -> void:
	world.army.spawn(1, 2.5)
	_run(2.0)
	assert_true(_splashes().is_empty(), "only a fall in splashes")
