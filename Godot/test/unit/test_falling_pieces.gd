extends GutTest
## Towers and trees whose ground is dug away fall as one piece, carrying what stands on them, and break up only
## when they fall further than their Survives Fall.

## A 2 x 3 brick tower on soil, with ground 1 m below the soil it stands on and 5 m below on the right.
const MAP: Array = [
	"....................",
	"....................",
	"......KK............",
	"......KK............",
	"......KK............",
	"....######..........",
	"....######..........",
	"####################",
	"BBBBBBBBBBBBBBBBBBBB",
]

## A tree (trunk and leaves) on soil.
const TREE: Array = [
	"....................",
	".....LLL............",
	".....LTL............",
	"......T.............",
	"......T.............",
	"....####............",
	"....####............",
	"....####............",
	"....####............",
	"####################",
	"BBBBBBBBBBBBBBBBBBBB",
]

const ARCHER := preload("res://objects/archer/archer.tscn")

var world: World


func before_each() -> void:
	GameState.save_path = "user://test_sappers.cfg"
	GameState.new_campaign()
	world = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	world.set_physics_process(false)


func _build(rows: Array) -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	for y in rows.size():
		for x in rows[y].length():
			var key: String = WorldFixture.LEGEND[rows[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	world.terrain.settle()
	world.army.spawn(1, 18.5)
	world.crew.spawn(18.5)


func _run(seconds: float) -> void:
	for i in int(seconds * 60):
		world.terrain.settle()
		world._physics_process(1.0 / 60.0)


func _clear(cells: Array) -> void:
	for c: Vector2i in cells:
		world.terrain.set_type(c, null)


func _bricks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in 12:
		for x in 20:
			var t := world.terrain.type_at(Vector2i(x, y))
			if t and t.structure:
				out.append(Vector2i(x, y))
	return out


func _on_top(scene_or_node: Variant, x: float, y: float) -> Node2D:
	var n: Node2D = scene_or_node.instantiate() if scene_or_node is PackedScene else scene_or_node
	n.position = Grid.to_px(Vector2(x, y))
	world.objects.add_child(n)
	return n


func test_tower_falls_onto_the_ground_below_and_stands_there() -> void:
	_build(MAP)
	var archer: Archer = _on_top(ARCHER, 7.0, 2.0)
	var torch := _on_top(Node2D.new(), 6.5, 2.0)
	_clear([Vector2i(6, 5), Vector2i(7, 5)])
	_run(2.0)
	var expected: Array[Vector2i] = []
	for y in range(3, 6):
		expected.append_array([Vector2i(6, y), Vector2i(7, y)])
	assert_eq(_bricks().size(), 6, "all six bricks")
	for c in expected:
		assert_true(c in _bricks(), "brick at %s" % c)
	assert_almost_eq(archer.position.y, 3.0 * Grid.PX, 0.5, "the archer rode it down")
	assert_almost_eq(torch.position.y, 3.0 * Grid.PX, 0.5, "anything on top rides it down")
	archer._physics_process(1.0 / 60.0)
	assert_true(archer.alive(), "still on its tower")


## Battlements and other tiles painted in the air on top of a tower (decorations, no material) fall with it.
func test_decoration_tiles_on_the_tower_fall_with_it() -> void:
	_build(MAP)
	var t := world.terrain
	var deco := WorldFixture.decorate(t, Vector2i(6, 1))
	assert_ne(deco, Vector2i(-1, -1), "the TileSet has a decoration tile")
	_clear([Vector2i(6, 5), Vector2i(7, 5)])
	_run(2.0)
	assert_eq(t.get_cell_source_id(Vector2i(6, 1)), -1, "not left in the air")
	assert_eq(t.get_cell_atlas_coords(Vector2i(6, 2)), deco, "on the tower where it landed")


## A 2 x 2 tower on a 1 m post, 3 m above deep soil once the post is gone.
const DROP: Array = [
	"....................",
	"......KK............",
	"......KK............",
	"......##............",
	"....................",
	"....................",
	"####################",
	"####################",
	"####################",
	"####################",
	"####################",
	"####################",
	"####################",
	"BBBBBBBBBBBBBBBBBBBB",
]


func test_a_tower_landing_breaks_the_ground_under_it_and_sinks_until_a_short_drop() -> void:
	_build(DROP)
	_clear([Vector2i(6, 3), Vector2i(7, 3)])
	_run(6.0)
	# 3 m onto row 6: breaks rows 6 and 7, sinks 2 m: breaks row 8, sinks 1 m: stops on row 9.
	assert_eq(_bricks().size(), 4, "stands, whole")
	for c in [Vector2i(6, 7), Vector2i(7, 7), Vector2i(6, 8), Vector2i(7, 8)]:
		assert_true(c in _bricks(), "sunk to %s" % c)
	assert_eq(world.terrain.type_at(Vector2i(6, 9)), WorldFixture.type("soil"), "the last 1 m drop broke nothing")
	assert_eq(world.terrain.type_at(Vector2i(5, 7)), WorldFixture.type("soil"), "only the ground under it")


func test_archer_is_not_lost_while_its_tower_falls() -> void:
	_build(MAP)
	var archer: Archer = _on_top(ARCHER, 7.0, 2.0)
	_clear([Vector2i(6, 5), Vector2i(7, 5)])
	world.terrain.settle()
	world._physics_process(1.0 / 60.0)
	archer._physics_process(1.0 / 60.0)
	assert_true(archer.alive(), "carried, not standing on air")


func test_tower_falling_further_than_it_survives_breaks_up() -> void:
	_build(MAP)
	var archer: Archer = _on_top(ARCHER, 7.0, 2.0)
	var torch := _on_top(Node2D.new(), 6.5, 2.0)
	# Move the tower over to the right, where the ground is 5 m below its foot.
	_clear([Vector2i(6, 2), Vector2i(7, 2), Vector2i(6, 3), Vector2i(7, 3), Vector2i(6, 4), Vector2i(7, 4)])
	for y in range(0, 3):
		for x in [13, 14]:
			world.terrain.set_type(Vector2i(x, y), WorldFixture.type("brick"))
	world.terrain.set_type(Vector2i(13, 3), WorldFixture.type("soil"))
	world.terrain.set_type(Vector2i(14, 3), WorldFixture.type("soil"))
	world.terrain.settle()
	archer.position = Grid.to_px(Vector2(14.0, 0.0))
	torch.position = Grid.to_px(Vector2(13.5, 0.0))
	assert_eq(_bricks().size(), 6, "standing")
	_clear([Vector2i(13, 3), Vector2i(14, 3)])
	_run(3.0)
	assert_eq(_bricks().size(), 0, "broke up on landing 4 m down")
	archer._physics_process(1.0 / 60.0)
	assert_false(archer.alive(), "the archer went down with it")
	assert_false(is_instance_valid(torch) and not torch.is_queued_for_deletion(), "so did the rest on top")


func test_falling_tower_crushes_a_soldier_under_it() -> void:
	_build(MAP)
	_clear([Vector2i(6, 5), Vector2i(7, 5)])
	world.terrain.settle()
	world.army.spawn(1, 6.5)
	assert_gt(world.army.lead().pos.y, 5.0, "in the hole under the tower")
	_run(2.0)
	assert_eq(world.army.soldiers.size(), 0, "crushed")


func test_falling_tower_crushes_an_engineer_under_it() -> void:
	_build(MAP)
	_clear([Vector2i(6, 5), Vector2i(7, 5)])
	world.terrain.settle()
	var e: Crew.Engineer = world.crew.engineers[0]
	e.pos = Vector2(6.5, 6.0)
	var before := world.crew.engineers.size()
	_run(1.0)
	assert_eq(world.crew.engineers.size(), before - 1, "crushed")


## Only what Crushes kills: a tree coming down on people leaves them alive.
func test_falling_tree_kills_nobody() -> void:
	assert_false(WorldFixture.type("trunk").crushes)
	assert_false(WorldFixture.type("leaves").crushes)
	assert_true(WorldFixture.type("brick").crushes)
	_build(TREE)
	_clear([Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)])
	world.army.spawn(1, 6.5)
	var e: Crew.Engineer = world.crew.engineers[0]
	e.pos = Vector2(6.5, 6.0)
	var before := world.crew.engineers.size()
	_run(2.0)
	assert_eq(world.terrain.type_at(Vector2i(6, 5)), WorldFixture.type("trunk"), "the tree came down")
	assert_eq(world.army.soldiers.size(), 1, "the soldier lives")
	assert_eq(world.crew.engineers.size(), before, "the engineer lives")


func test_tree_falls_onto_the_ground_below_and_stands_there() -> void:
	_build(TREE)
	_clear([Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)])
	_run(2.0)
	assert_eq(world.terrain.type_at(Vector2i(6, 5)), WorldFixture.type("trunk"), "fell 1 m")
	assert_eq(world.terrain.type_at(Vector2i(6, 2)), WorldFixture.type("leaves"), "in one piece")
	assert_null(world.terrain.type_at(Vector2i(6, 1)))


func test_a_two_metre_fall_fells_a_tree() -> void:
	_build(TREE)
	_clear([Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6)])
	var expected := _tree_logs()
	_run(2.0)
	assert_eq(world.wood.count(), expected, "felled: its logs lie about as wood")
	assert_null(world.terrain.type_at(Vector2i(6, 6)), "no trunk left standing")


func test_tree_falling_further_than_it_survives_is_felled() -> void:
	_build(TREE)
	var logs := GameState.supplies.logs
	var expected := _tree_logs()
	for y in range(5, 9):
		_clear([Vector2i(4, y), Vector2i(5, y), Vector2i(6, y), Vector2i(7, y)])
	_run(3.0)
	for y in 11:
		for x in 20:
			var t := world.terrain.type_at(Vector2i(x, y))
			assert_false(t != null and t.dig_action == TerrainType.DigAction.FELL, "no tree left at %s" % Vector2i(x, y))
	assert_eq(world.wood.count(), expected, "its logs dropped as wood for the crew to pick up")
	assert_eq(GameState.supplies.logs, logs, "none counted before they are picked up")


## Logs the tree in TREE gives when felled.
func _tree_logs() -> int:
	var counts := {}
	for c in world.terrain.tree_cells(Vector2i(6, 4)):
		var t := world.terrain.type_at(c)
		counts[t] = counts.get(t, 0) + 1
	return TerrainType.bulk_total(counts).logs
