extends GutTest
## Each blow a soldier lands on a tower: the tile shakes and blinks once, chips fly in the stone's colour, and the
## metal throws sparks.

const MAP: Array = [
	"....................",
	"..........KKK.......",
	"..........KKK.......",
	"..........KKK.......",
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
	world.set_process(false)
	world.terrain.clear()
	world.terrain.rebuild()
	for y in MAP.size():
		for x in MAP[y].length():
			var key: String = WorldFixture.LEGEND[MAP[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.army.spawn(1, 8.5)


func _march(seconds: float) -> void:
	for i in int(seconds * 60):
		world.army.step(1.0 / 60.0)


func test_each_blow_on_a_tower_is_a_hit_on_one_cell() -> void:
	var blows: Array[Vector2i] = []
	world.army.struck.connect(func(cell: Vector2i, _by: Soldier) -> void: blows.append(cell))
	_march(4.0)
	assert_eq(world.army.halt_reason, world.army.rules.siege_text, "besieging")
	var interval := world.army.rules.attack_interval
	assert_gt(blows.size(), 1)
	for c in blows:
		assert_eq(world.terrain.type_at(c), WorldFixture.type("brick"), "a tower cell")
	var before := blows.size()
	_march(interval * 5.0)
	assert_between(blows.size() - before, 4, 6, "one per attack interval")


func test_a_blow_ripples_through_the_whole_tower() -> void:
	var blows: Array[Vector2i] = []
	world.army.struck.connect(func(cell: Vector2i, _by: Soldier) -> void: blows.append(cell))
	_march(4.0)
	assert_false(blows.is_empty(), "besieging")
	assert_gt(world.terrain.ripple_delay(Vector2i(12, 1)), 0.0, "the far top of the tower ripples too")


func test_a_hit_cell_shakes_and_blinks_once_then_settles() -> void:
	var t := world.terrain
	var cell := Vector2i(10, 3)
	t.hit(cell)
	assert_true(t._use_tile_data_runtime_update(cell), "drawn with its hit look")
	assert_false(t._hits.has(Vector2i(11, 3)), "only the cell hit shakes and blinks (the rest of the tower ripples)")
	assert_eq(t.hit_flash_at(Vector2i(11, 3)), Color.WHITE)
	assert_gt(t.hit_flash_at(cell).r, 1.0, "blinks bright at first")
	var moved := false
	var lit_again := false
	var was_dark := false
	var step := 1.0 / 60.0
	var age := 0.0
	while age < t.hit_time:
		moved = moved or t.hit_offset_at(cell) != Vector2i.ZERO
		var bright: bool = t.hit_flash_at(cell).r > 1.01
		was_dark = was_dark or not bright
		lit_again = lit_again or (was_dark and bright)
		t.advance_hits(step)
		age += step
	assert_true(moved, "shakes")
	assert_false(lit_again, "blinks once per hit")
	assert_eq(t.hit_offset_at(cell), Vector2i.ZERO, "back to normal")
	t.advance_hits(10.0)
	assert_false(t._use_tile_data_runtime_update(cell), "nothing drawn specially once the ripple has passed")


func test_a_blow_throws_stone_chips_and_sparks_at_the_face_hit() -> void:
	var bursts := []
	Effects.burst.connect(func(kind: StringName, at_px: Vector2, color: Color) -> void: bursts.append([kind, at_px, color]))
	world.army.struck.emit(Vector2i(10, 3), world.army.lead())
	var kinds := bursts.map(func(b: Array) -> StringName: return b[0])
	assert_has(kinds, &"debris", "stone chips")
	assert_has(kinds, &"sparks", "sparks off the metal")
	for b: Array in bursts:
		if b[0] == &"debris":
			assert_eq(b[2], WorldFixture.type("brick").debris_color, "in the colour of the tower's stone")
		var m := Grid.to_m(b[1])
		assert_almost_eq(m.x, 10.0, 0.3, "on the face toward the soldier")
		assert_between(m.y, 3.0, 4.0)
	assert_true(world.terrain._use_tile_data_runtime_update(Vector2i(10, 3)), "and the cell shakes")
