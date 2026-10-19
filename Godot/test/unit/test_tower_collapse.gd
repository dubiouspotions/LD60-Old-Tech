extends GutTest
## A razed tower comes down in a sequence: the row struck is crushed under the weight above, the rest drops
## straight down and each row breaks as it hits the ground, the archer hangs a moment, falls, lies flat and
## vanishes in a blink and a puff of smoke. The column stands back until it is all over.

## A 3 x 4 brick tower (columns 10..12, rows 1..4) on the ground (row 5).
const MAP: Array = [
	"....................",
	"..........KKK.......",
	"..........KKK.......",
	"..........KKK.......",
	"..........KKK.......",
	"####################",
	"BBBBBBBBBBBBBBBBBBBB",
]

const ARCHER := preload("res://objects/archer/archer.tscn")

var world: World
var bursts := []


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
	world.terrain.settle()
	world.army.spawn(1, 9.4)
	bursts.clear()
	Effects.burst.connect(_on_burst)


func after_each() -> void:
	Effects.burst.disconnect(_on_burst)


func _on_burst(kind: StringName, at_px: Vector2, _color: Color) -> void:
	bursts.append([kind, Grid.to_m(at_px)])


func _step() -> void:
	world.terrain.settle()
	world._physics_process(1.0 / 60.0)
	for o in world.objects.get_children():
		if o is Archer and not o.is_queued_for_deletion():
			o._physics_process(1.0 / 60.0)


func _run(seconds: float, until: Callable = func() -> bool: return false) -> void:
	for i in int(seconds * 60):
		_step()
		if until.call():
			return


func _archer() -> Archer:
	var a: Archer = ARCHER.instantiate()
	a.position = Grid.to_px(Vector2(11.5, 1.0))
	a.first_shot_delay = 999.0
	world.objects.add_child(a)
	return a


func _pieces() -> Array:
	return world.objects.get_children().filter(func(o: Node) -> bool: return o is FallingPiece and not o.is_queued_for_deletion())


func _bricks() -> int:
	var n := 0
	for y in MAP.size():
		for x in MAP[0].length():
			if world.terrain.type_at(Vector2i(x, y)) == WorldFixture.type("brick"):
				n += 1
	return n


func _raze() -> void:
	world.terrain.besiege(Vector2i(10, 4), WorldFixture.type("brick").raze_time + 1.0)


func test_the_row_struck_is_crushed_and_the_rest_drops() -> void:
	_raze()
	for x in range(10, 13):
		assert_null(world.terrain.type_at(Vector2i(x, 4)), "crushed")
	assert_eq(_bricks(), 0, "the rest is no longer standing ground")
	var pieces := _pieces()
	assert_eq(pieces.size(), 3, "a column at a time")
	var total := 0
	for p: FallingPiece in pieces:
		assert_true(p.crumble)
		total += p.tiles.size()
	assert_eq(total, 9, "the three rows above")


func test_the_columns_start_falling_left_to_right() -> void:
	_raze()
	var by_x := {}
	for p: FallingPiece in _pieces():
		by_x[(p.tiles.keys()[0] as Vector2i).x] = p
	assert_gt(world.collapse_stagger, 0.0)
	_run(world.collapse_stagger * 1.5)
	assert_gt((by_x[10] as FallingPiece).fallen, 0.0, "the left column is on its way")
	assert_eq((by_x[12] as FallingPiece).fallen, 0.0, "the right one has not started yet")


func test_each_row_breaks_as_it_hits_the_ground() -> void:
	_raze()
	var most := [0]
	_run(6.0, func() -> bool:
		most[0] = maxi(most[0], _pieces().size())
		return _pieces().is_empty())
	assert_true(_pieces().is_empty(), "all of it broke")
	assert_eq(_bricks(), 0, "nothing of it left standing")
	var rubble := bursts.filter(func(b: Array) -> bool: return b[0] == &"rubble")
	assert_eq(rubble.size(), 12, "every tile bursts")
	for b: Array in rubble:
		assert_between((b[1] as Vector2).x, 10.0, 13.0)
		assert_between((b[1] as Vector2).y, 4.0, 5.0, "broken at the ground")


func test_a_fallen_archer_lies_there_for_two_seconds() -> void:
	var a: Archer = ARCHER.instantiate()
	assert_eq(a.lie_time, 2.0)
	a.free()


func test_the_archer_hangs_falls_lies_flat_then_vanishes() -> void:
	var archer := _archer()
	_step()
	_raze()
	var start := archer.position
	_run(archer.topple_hang * 0.8)
	assert_eq(archer.position, start, "hangs in the air a moment")
	assert_false(archer.alive(), "out of the fight")
	_run(3.0, func() -> bool: return archer.lying())
	assert_true(archer.lying(), "landed")
	assert_almost_eq(archer.feet_m().y, 5.0, 0.35, "on the ground")
	assert_almost_eq(absf(archer.rotation), PI / 2, 0.01, "flat")
	_run(archer.lie_time * 0.8)
	assert_true(is_instance_valid(archer) and not archer.is_queued_for_deletion(), "lies there a moment")
	_run(archer.lie_time + 1.0, func() -> bool: return not is_instance_valid(archer) or archer.is_queued_for_deletion())
	assert_true(not is_instance_valid(archer) or archer.is_queued_for_deletion(), "gone")
	assert_true(bursts.any(func(b: Array) -> bool: return b[0] == &"dust" and absf((b[1] as Vector2).y - 4.8) < 1.0), "in a puff of smoke")


func test_the_column_stands_back_until_it_is_all_over() -> void:
	var archer := _archer()
	_step()
	_raze()
	var x0 := world.army.lead().pos.x
	_step()
	assert_eq(world.army.halt_reason, world.army.rules.collapse_text)
	_run(2.0)
	assert_almost_eq(world.army.lead().pos.x, x0, 0.01, "not one step in")
	_run(10.0, func() -> bool: return not is_instance_valid(archer))
	_run(2.0)
	assert_gt(world.army.lead().pos.x, x0 + 1.0, "marches on once it is over")


func test_a_tower_one_row_high_just_breaks() -> void:
	for x in range(10, 13):
		for y in range(1, 4):
			world.terrain.set_type(Vector2i(x, y), null)
	_raze()
	assert_eq(_bricks(), 0)
	assert_true(_pieces().is_empty(), "nothing above to fall")


func test_the_fallen_archer_lies_still_then_blinks_twice() -> void:
	var archer := _archer()
	_step()
	_raze()
	_run(3.0, func() -> bool: return archer.lying())
	assert_true(archer.lying())
	for s in archer.find_children("*", "AnimatedSprite2D", true, false):
		assert_false((s as AnimatedSprite2D).is_playing(), "%s frozen" % s.name)
	var blinks := 0
	var lit := false
	for i in int((archer.lie_time + 2.0) * 60):
		if not is_instance_valid(archer) or archer.is_queued_for_deletion():
			break
		var bright := archer.modulate.r > 1.01
		if bright and not lit:
			blinks += 1
		lit = bright
		_step()
	assert_eq(blinks, 2, "blinks twice")


func test_the_engineers_stand_back_until_it_is_all_over() -> void:
	var archer := _archer()
	world.crew.spawn(3.0)
	_step()
	_raze()
	var xs := world.crew.engineers.map(func(e: Crew.Engineer) -> float: return e.pos.x)
	_run(2.0)
	for i in xs.size():
		assert_almost_eq(world.crew.engineers[i].pos.x, xs[i], 0.01, "not one step on")
	_run(10.0, func() -> bool: return not is_instance_valid(archer))
	_run(2.0)
	assert_gt(world.crew.engineers[0].pos.x, xs[0] + 1.0, "walks on once it is over")
