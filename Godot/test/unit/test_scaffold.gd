extends GutTest
## Scaffolding is drawn with the tiles of world/scafolding.png: under every scaffolded joint, a column of cells down
## to the ground, each cell taking the tile its place has in the sheet's 2x2 arrangement, so towers side by side
## join up into one lattice.

const MAP: Array = [
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"##########",
	"BBBBBBBBBB",
]

var terrain: Terrain
var bridge: Bridge


func before_each() -> void:
	terrain = WorldFixture.terrain(self, MAP)
	bridge = WorldFixture.bridge(self, terrain)


func _finish(a: Vector2, b: Vector2) -> Bridge.Member:
	var m := bridge.build(bridge.snap_point(a), bridge.snap_point(b), preload("res://data/bridge/log.tres"), true)
	bridge.finish(m)
	return m


func test_drawn_with_the_scaffolding_sheet() -> void:
	var scene: Bridge = load("res://world/bridge.tscn").instantiate()
	assert_eq(scene.scaffold_texture.resource_path, "res://world/scafolding.png")
	scene.free()


func test_a_column_of_cells_under_each_scaffolded_joint_down_to_the_ground() -> void:
	_finish(Vector2(3, 3), Vector2(6, 3))
	var cells := bridge.scaffold_cells()
	for x in [3, 6]:
		for y in range(3, 6):
			assert_true(cells.has(Vector2i(x, y)), "cell %d,%d" % [x, y])
		assert_false(cells.has(Vector2i(x, 6)), "not into the ground")
		assert_false(cells.has(Vector2i(x, 2)), "not above the joint")
	assert_false(cells.has(Vector2i(4, 4)), "only under the joints")


func test_each_cell_takes_its_place_in_the_sheets_2x2_arrangement() -> void:
	_finish(Vector2(3, 3), Vector2(4, 3))
	var cells := bridge.scaffold_cells()
	assert_eq(cells[Vector2i(4, 4)], Vector2i(0, 0), "even column, even row: top-left")
	assert_eq(cells[Vector2i(3, 4)], Vector2i(1, 0), "odd column: right-hand tile")
	assert_eq(cells[Vector2i(4, 3)], Vector2i(0, 1), "odd row: bottom tile")
	assert_eq(cells[Vector2i(3, 5)], Vector2i(1, 1))


func test_gone_once_the_scaffolding_is_struck() -> void:
	_finish(Vector2(3, 3), Vector2(6, 3))
	bridge.strike_scaffolding()
	assert_true(bridge.scaffold_cells().is_empty())
