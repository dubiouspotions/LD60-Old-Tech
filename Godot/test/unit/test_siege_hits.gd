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


func test_a_hit_cell_shakes_and_blinks_once_then_settles() -> void:
	var t := world.terrain
	var cell := Vector2i(10, 3)
	t.hit(cell)
	assert_true(t._use_tile_data_runtime_update(cell), "drawn with its hit look")
	assert_false(t._use_tile_data_runtime_update(Vector2i(11, 3)), "only the cell hit")
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
	assert_false(t._use_tile_data_runtime_update(cell), "back to normal")
	assert_eq(t.hit_offset_at(cell), Vector2i.ZERO)


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


## Battlements and anything else painted in the air on the tower (decorations, no material) come down with it.
func test_razing_a_tower_takes_its_battlements_down_too() -> void:
	var t := world.terrain
	var src := t.tile_set.get_source(t.look.classic_source) as TileSetAtlasSource
	var deco := Vector2i(-1, -1)
	for i in src.get_tiles_count():
		var c := src.get_tile_id(i)
		if src.get_tile_data(c, 0).get_custom_data(Terrain.CUSTOM_DATA) == null:
			deco = c
			break
	assert_ne(deco, Vector2i(-1, -1), "the TileSet has a decoration tile")
	for x in range(10, 13):
		t.set_cell(Vector2i(x, 0), t.look.classic_source, deco)
	t.set_cell(Vector2i(3, 3), t.look.classic_source, deco)
	t.besiege(Vector2i(10, 3), WorldFixture.type("brick").raze_time + 1.0)
	assert_null(t.type_at(Vector2i(10, 2)), "razed")
	for x in range(10, 13):
		assert_eq(t.get_cell_source_id(Vector2i(x, 0)), -1, "battlement %d gone with the tower" % x)
	assert_eq(t.get_cell_source_id(Vector2i(3, 3)), t.look.classic_source, "a decoration elsewhere stays")


## The row struck bursts at once; the rows above burst as they come down (see test_tower_collapse).
func test_the_row_struck_bursts_into_rubble_and_dust_at_once() -> void:
	var t := world.terrain
	var bursts := []
	Effects.burst.connect(func(kind: StringName, at_px: Vector2, color: Color) -> void: bursts.append([kind, at_px, color]))
	t.besiege(Vector2i(10, 3), WorldFixture.type("brick").raze_time + 1.0)
	var brick := WorldFixture.type("brick")
	var rubble := bursts.filter(func(b: Array) -> bool: return b[0] == &"rubble")
	var dust := bursts.filter(func(b: Array) -> bool: return b[0] == &"dust")
	assert_eq(rubble.size(), 3, "rubble from every cell of the row struck")
	assert_eq(dust.size(), 3, "and a cloud of dust")
	for b: Array in rubble:
		assert_eq(b[2], brick.debris_color, "chunks of its stone")
		var cell := Grid.cell_of(Grid.to_m(b[1]))
		assert_between(cell.x, 10, 12, "where the tower stood")
		assert_eq(cell.y, 3, "in the row struck")
