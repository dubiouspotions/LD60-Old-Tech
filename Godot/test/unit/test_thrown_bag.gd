extends GutTest
## A thrown sandbag flies its arc to the cell it was thrown at through anything on the way (ground, bridge pieces,
## soldiers, engineers), and falls on from there. Only an archer stops it: it breaks on them in a cloud of dust, hurting
## nobody. A soldier or engineer standing in that cell gets it under their feet: they step up onto it.

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


func test_a_throw_through_a_wall_still_lands_where_it_was_thrown() -> void:
	_throw(Vector2(2.5, 7.0), Vector2i(8, 7))
	assert_eq(world.terrain.type_at(Vector2i(8, 7)), WorldFixture.type("sandbag"))
	assert_eq(_sandbags(), 1)
	assert_eq(world.terrain.type_at(Vector2i(6, 6)), WorldFixture.type("soil"), "the wall stands")


func test_a_throw_through_a_bridge_piece_still_lands_where_it_was_thrown() -> void:
	var b := world.bridge
	b.build(b.snap_point(Vector2(11.0, 4.0)), b.snap_point(Vector2(11.0, 8.0)), load("res://data/bridge/log.tres"))
	_throw(Vector2(8.5, 7.0), Vector2i(14, 7))
	assert_eq(world.terrain.type_at(Vector2i(14, 7)), WorldFixture.type("sandbag"))
	assert_eq(_sandbags(), 1)


## The column waits at the edge just short of where the bag is thrown (#48): it flies past them.
func test_a_throw_past_a_soldier_beside_the_cell_still_lands_where_it_was_thrown() -> void:
	world.army.spawn(1, 12.9)
	world.army.hold = true
	var s := world.army.soldiers[0]
	_throw(Vector2(8.5, 7.0), Vector2i(13, 7))
	assert_eq(world.terrain.type_at(Vector2i(13, 7)), WorldFixture.type("sandbag"))
	assert_eq(world.terrain.type_at(Vector2i(12, 7)), null, "not under the soldier")
	assert_false(s.dead)


func test_a_throw_into_an_archer_breaks_in_a_cloud_of_dust() -> void:
	watch_signals(Effects)
	world.terrain.set_type(Vector2i(11, 6), WorldFixture.type("brick"))
	world.terrain.set_type(Vector2i(11, 7), WorldFixture.type("brick"))
	var archer: Archer = load("res://objects/archer/archer.tscn").instantiate()
	archer.position = Grid.to_px(Vector2(11.5, 6))
	world.objects.add_child(archer)
	var hp := archer.hp
	_throw(Vector2(8.5, 7.0), Vector2i(14, 7))
	assert_eq(_sandbags(), 0, "nothing landed")
	assert_false(_bags_flying(), "gone")
	assert_true(archer.alive())
	assert_eq(archer.hp, hp, "not hurt")
	assert_gt(_dust_count(), 0, "a cloud of dust")


func test_a_throw_at_a_soldiers_cell_lands_under_them_and_they_step_up() -> void:
	world.army.spawn(1, 11.5)
	world.army.hold = true
	var s := world.army.soldiers[0]
	_throw(Vector2(8.5, 7.0), Vector2i(11, 7))
	assert_eq(_sandbags(), 1, "it landed")
	assert_eq(world.terrain.type_at(Vector2i(11, 7)), WorldFixture.type("sandbag"), "in the cell the soldier stood in")
	assert_false(s.dead)
	assert_eq(s.hp, s.max_hp, "not hurt")
	assert_almost_eq(s.pos.y, 7.0, 0.01, "standing on it")


func test_a_throw_at_another_engineers_cell_lands_under_them_and_they_step_up() -> void:
	_crew(2, 8.5)
	var thrower := world.crew.engineers[0]
	var other := world.crew.engineers[1]
	other.pos = Vector2(11.5, 8.0)
	world.crew.rules.walk_speed = 0.01
	_throw(thrower.pos - Vector2(0, 1.0), Vector2i(11, 7))
	assert_eq(world.terrain.type_at(Vector2i(11, 7)), WorldFixture.type("sandbag"), "under the other engineer")
	assert_true(other in world.crew.engineers, "who is fine")
	assert_true(thrower in world.crew.engineers)
	assert_almost_eq(other.pos.y, 7.0, 0.01, "standing on it")


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


func test_a_sandbag_falling_on_a_soldier_lands_under_them_and_they_step_up() -> void:
	world.army.spawn(1, 12.5)
	world.army.hold = true
	var s := world.army.soldiers[0]
	_drop_sandbag(12)
	assert_false(s.dead, "not crushed")
	assert_eq(s.hp, s.max_hp, "not hurt")
	assert_eq(world.terrain.type_at(Vector2i(12, 7)), WorldFixture.type("sandbag"), "under their feet")
	assert_eq(_sandbags(), 1)
	assert_almost_eq(s.pos.y, 7.0, 0.01, "standing on it")


## One standing in the next column, reaching into this one, is not under it (#48): it falls past them.
func test_a_sandbag_falls_past_a_soldier_in_the_next_column() -> void:
	world.army.spawn(1, 13.2)
	world.army.hold = true
	var s := world.army.soldiers[0]
	_drop_sandbag(12)
	assert_eq(world.terrain.type_at(Vector2i(12, 7)), WorldFixture.type("sandbag"))
	assert_eq(world.terrain.type_at(Vector2i(13, 7)), null, "not under the soldier")
	assert_false(s.dead)


func test_with_no_room_to_step_up_it_breaks_on_the_soldier() -> void:
	world.army.spawn(1, 12.5)
	world.army.hold = true
	var s := world.army.soldiers[0]
	world.terrain.set_type(Vector2i(12, 5), WorldFixture.type("brick"))
	var bag: FallingBlock = _sandbag_tool().spawn_scene.instantiate()
	assert_false(bag.land_under(world, s), "a ceiling right above their head")
	assert_eq(_sandbags(), 0)
	bag.free()


## Marching soldiers hop up and down steps: one in the air still gets it on the ground under them.
func test_a_soldier_in_the_air_gets_it_on_the_ground_under_them() -> void:
	world.army.spawn(1, 12.5)
	var s := world.army.soldiers[0]
	s.airborne = true
	s.pos.y = 7.6
	var bag: FallingBlock = _sandbag_tool().spawn_scene.instantiate()
	assert_true(bag.land_under(world, s))
	bag.free()
	assert_eq(world.terrain.type_at(Vector2i(12, 7)), WorldFixture.type("sandbag"), "on the ground under them")
	assert_almost_eq(s.pos.y, 7.0, 0.01, "their feet were in that cell: lifted onto it")


func test_one_high_in_the_air_is_not_lifted() -> void:
	world.army.spawn(1, 12.5)
	var s := world.army.soldiers[0]
	s.airborne = true
	s.pos.y = 5.0
	var bag: FallingBlock = _sandbag_tool().spawn_scene.instantiate()
	assert_true(bag.land_under(world, s))
	bag.free()
	assert_eq(world.terrain.type_at(Vector2i(12, 7)), WorldFixture.type("sandbag"))
	assert_almost_eq(s.pos.y, 5.0, 0.01, "left to come down onto it")


func test_everyone_standing_in_the_cell_steps_up() -> void:
	world.army.spawn(1, 12.5)
	world.army.hold = true
	var s := world.army.soldiers[0]
	_crew(1, 12.5)
	var e := world.crew.engineers[0]
	e.pos = Vector2(12.4, 8.0)
	var bag: FallingBlock = _sandbag_tool().spawn_scene.instantiate()
	assert_true(bag.land_under(world, s))
	bag.free()
	assert_almost_eq(s.pos.y, 7.0, 0.01)
	assert_almost_eq(e.pos.y, 7.0, 0.01, "the engineer beside them too")


func test_a_sandbag_falling_on_an_archer_breaks_without_hurting_them() -> void:
	var archer: Archer = load("res://objects/archer/archer.tscn").instantiate()
	archer.position = Grid.to_px(Vector2(15.5, 8))
	world.objects.add_child(archer)
	var hp := archer.hp
	_drop_sandbag(15)
	assert_true(archer.alive())
	assert_eq(archer.hp, hp, "not hurt")
	assert_eq(_sandbags(), 0, "it broke")


func test_a_sandbag_falling_on_an_engineer_lands_under_them_and_they_step_up() -> void:
	_crew(1, 14.0)
	var e := world.crew.engineers[0]
	world.crew.rules.walk_speed = 0.01
	var x := floori(e.pos.x)
	_drop_sandbag(x)
	assert_true(e in world.crew.engineers, "alive")
	assert_eq(world.terrain.type_at(Vector2i(x, 7)), WorldFixture.type("sandbag"), "under their feet")
	assert_almost_eq(e.pos.y, 7.0, 0.01, "standing on it")


func test_an_engineer_up_on_the_bridge_gets_it_on_the_ground_under_them() -> void:
	_crew(1, 14.0)
	var e := world.crew.engineers[0]
	e.at = Bridge.Joint.new()
	e.pos = Vector2(14.5, 5.0)
	var bag: FallingBlock = _sandbag_tool().spawn_scene.instantiate()
	assert_true(bag.land_under(world, e))
	bag.free()
	e.at = null
	assert_eq(world.terrain.type_at(Vector2i(14, 7)), WorldFixture.type("sandbag"))
	assert_almost_eq(e.pos.y, 5.0, 0.01, "still up there")
