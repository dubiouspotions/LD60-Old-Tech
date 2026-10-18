extends GutTest
## A thrown sandbag flies its arc and falls where it was thrown, unless it hits anything on the way: then it
## breaks in a cloud of dust, hurting nobody.

## Flat ground at row 8, a wall at x 6 rows 4..7.
const MAP: Array = [
	"....................",
	"....................",
	"....................",
	"....................",
	"......#.............",
	"......#.............",
	"......#.............",
	"......#.............",
	"####################",
	"BBBBBBBBBBBBBBBBBBBB",
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


func _crew(size: int, x: float) -> void:
	world.crew.rules = world.crew.rules.duplicate()
	world.crew.rules.crew_size = size
	world.crew.spawn(x)


func _sandbag_tool() -> ToolDefinition:
	return GameState.campaign.tools.filter(func(t: ToolDefinition) -> bool: return t.kind == ToolDefinition.Kind.FILL)[0]


## Throws a sandbag from from (metres) at cell, as an engineer would, and runs the world a few seconds.
func _throw(from: Vector2, cell: Vector2i) -> void:
	var order := world.crew.order_throw(cell, _sandbag_tool())
	world.crew.throws.erase(order)
	world.crew.threw.emit(order, from)
	for i in 180:
		world.terrain.settle()
		world._physics_process(1.0 / 60.0)


func _sandbags() -> int:
	var n := 0
	for c in world.terrain.get_used_cells():
		if world.terrain.type_at(c) == WorldFixture.type("sandbag"):
			n += 1
	return n


func _bags_flying() -> bool:
	return world.objects.get_children().any(func(o: Node) -> bool: return (o is ThrownBag or o is FallingBlock) and not o.is_queued_for_deletion())


func test_a_clear_throw_lands() -> void:
	_throw(Vector2(9.5, 7.0), Vector2i(13, 3))
	assert_eq(world.terrain.type_at(Vector2i(13, 7)), WorldFixture.type("sandbag"))


func test_a_throw_into_a_wall_breaks_in_a_cloud_of_dust() -> void:
	watch_signals(Effects)
	_throw(Vector2(2.5, 7.0), Vector2i(8, 7))
	assert_eq(_sandbags(), 0, "nothing landed")
	assert_false(_bags_flying(), "gone")
	var kinds: Array = []
	for i in get_signal_emit_count(Effects, "burst"):
		kinds.append(get_signal_parameters(Effects, "burst", i)[0])
	assert_has(kinds, &"dust", "a cloud of dust")
	assert_eq(world.terrain.type_at(Vector2i(6, 6)), WorldFixture.type("soil"), "the wall stands")


func test_a_throw_into_a_bridge_piece_breaks() -> void:
	var b := world.bridge
	b.build(b.snap_point(Vector2(11.0, 4.0)), b.snap_point(Vector2(11.0, 8.0)), load("res://data/bridge/log.tres"))
	_throw(Vector2(8.5, 7.0), Vector2i(14, 7))
	assert_eq(_sandbags(), 0, "nothing landed")
	assert_false(_bags_flying())


func test_a_throw_into_a_soldier_breaks_without_hurting_them() -> void:
	world.army.spawn(1, 11.5)
	world.army.hold = true
	var s := world.army.soldiers[0]
	_throw(Vector2(8.5, 7.0), Vector2i(11, 7))
	assert_eq(_sandbags(), 0, "nothing landed")
	assert_false(s.dead)
	assert_eq(s.hp, s.max_hp, "not hurt")


func test_a_throw_into_another_engineer_breaks_without_hurting_them() -> void:
	_crew(2, 8.5)
	var thrower := world.crew.engineers[0]
	var other := world.crew.engineers[1]
	other.pos = Vector2(11.5, 8.0)
	_throw(thrower.pos - Vector2(0, 1.0), Vector2i(11, 7))
	assert_eq(_sandbags(), 0, "broke on the other engineer")
	assert_true(other in world.crew.engineers, "who is fine")
	assert_true(thrower in world.crew.engineers)


## It leaves the hands inside the thrower, and maybe others standing with it: those it does not hit.
func test_the_thrower_and_those_beside_it_do_not_break_the_throw() -> void:
	_crew(3, 9.5)
	var thrower := world.crew.engineers[0]
	for e in world.crew.engineers:
		e.pos = thrower.pos
	_throw(thrower.pos - Vector2(0, 1.0), Vector2i(14, 3))
	assert_eq(world.terrain.type_at(Vector2i(14, 7)), WorldFixture.type("sandbag"))


## It spins (Spin turns a second) about its own centre, not about a corner.
func test_it_spins_about_its_centre() -> void:
	var bag: ThrownBag = world.thrown_scene.instantiate()
	bag.block = _sandbag_tool().spawn_scene.instantiate()
	world.objects.add_child(bag)
	bag.throw(Vector2(9.5, 7.0), Vector2i(13, 3), world.crew.rules, world.terrain.tile_texture(WorldFixture.type("sandbag")))
	bag.step(0.1, world, [])
	var sprite: Sprite2D = bag.get_node("Sprite")
	assert_ne(sprite.rotation, 0.0, "spinning")
	var middle := sprite.get_global_transform() * (sprite.get_rect().get_center())
	assert_almost_eq(middle, bag.global_position, Vector2(0.01, 0.01), "turned about the picture's middle")
	assert_almost_eq(Grid.to_m(bag.global_position).distance_to(world.crew.rules.throw_point(Vector2(9.5, 7.0), Vector2(13.5, 3.5), 0.1 / world.crew.rules.throw_time(Vector2(9.5, 7.0), Vector2(13.5, 3.5)))), 0.0, 0.01, "which follows the arc")
	bag.block.free()


## Drops a sandbag from high up at column x and runs the world a few seconds.
func _drop_sandbag(x: int) -> void:
	var bag: FallingBlock = _sandbag_tool().spawn_scene.instantiate()
	bag.position = Grid.to_px(Vector2(x, -6))
	world.objects.add_child(bag)
	for i in 180:
		world.terrain.settle()
		world._physics_process(1.0 / 60.0)


func _dust_count() -> int:
	var n := 0
	for i in get_signal_emit_count(Effects, "burst"):
		n += int(get_signal_parameters(Effects, "burst", i)[0] == &"dust")
	return n


func test_a_sandbag_falling_on_a_soldier_breaks_in_dust_without_hurting_them() -> void:
	world.army.spawn(1, 12.5)
	world.army.hold = true
	var s := world.army.soldiers[0]
	watch_signals(Effects)
	_drop_sandbag(12)
	assert_false(s.dead, "not crushed")
	assert_eq(s.hp, s.max_hp, "not hurt")
	assert_eq(_sandbags(), 0, "it broke")
	assert_gt(_dust_count(), 0, "in a cloud of dust")


func test_a_sandbag_falling_on_an_archer_breaks_without_hurting_them() -> void:
	var archer: Archer = load("res://objects/archer/archer.tscn").instantiate()
	archer.position = Grid.to_px(Vector2(15.5, 8))
	world.objects.add_child(archer)
	var hp := archer.hp
	_drop_sandbag(15)
	assert_true(archer.alive())
	assert_eq(archer.hp, hp, "not hurt")
	assert_eq(_sandbags(), 0, "it broke")


func test_a_sandbag_falling_on_an_engineer_breaks_without_hurting_them() -> void:
	_crew(1, 14.0)
	var e := world.crew.engineers[0]
	world.crew.rules.walk_speed = 0.01
	var x := floori(e.pos.x)
	_drop_sandbag(x)
	assert_true(e in world.crew.engineers, "alive")
	assert_eq(_sandbags(), 0, "it broke on them, not landed in their place")
