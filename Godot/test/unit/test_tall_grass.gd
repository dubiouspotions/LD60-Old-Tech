extends GutTest
## Tall grass: an animated tile painted on its own layer in each level, drawn in front of soldiers and objects.
## It stands in the air on top of the ground and goes when that ground does.

const MAP: Array = [
	"......",
	"......",
	"######",
	"BBBBBB",
]

var terrain: Terrain
var grass: TallGrass


func before_each() -> void:
	terrain = WorldFixture.terrain(self, MAP)
	grass = load("res://world/tall_grass.tscn").instantiate()
	grass.terrain = terrain
	add_child_autofree(grass)


func _has(cell: Vector2i) -> bool:
	return grass.get_cell_source_id(cell) != -1


func _paint(cell: Vector2i) -> void:
	grass.set_cell(cell, 0, Vector2i.ZERO)


## The frames play from a shader, each column of cells a frame behind the one to its left, so the sway rolls
## along like wind. The tile itself is not animated (that would step the frames twice).
func test_frames_roll_along_the_columns() -> void:
	var level: Level = load("res://levels/level_base.tscn").instantiate()
	add_child_autofree(level)
	var src := grass.tile_set.get_source(0) as TileSetAtlasSource
	assert_eq(src.texture.resource_path, "res://world/grass_anim.png")
	assert_eq(src.get_tile_animation_frames_count(Vector2i.ZERO), 1, "no tile animation")
	assert_false(src.use_texture_padding, "the shader reads the other frames from the sheet itself")
	for layer: TileMapLayer in [grass, level.grass()]:
		var mat := layer.material as ShaderMaterial
		assert_not_null(mat, "%s has the grass material" % layer.name)
		assert_eq(mat.shader.resource_path, "res://world/tall_grass.gdshader")
		assert_eq(mat.get_shader_parameter("frame_px"), float(src.texture_region_size.x))
		assert_eq(mat.get_shader_parameter("cell_px"), float(Grid.PX))
		assert_eq(mat.get_shader_parameter("delay_frames"), 1.0, "one frame per column")
		assert_gt(mat.get_shader_parameter("frame_time"), 0.0)


## The art is drawn at 1x and the layer scaled up, so a grass cell covers exactly one ground cell.
func test_grass_cells_line_up_with_ground_cells() -> void:
	var level: Level = load("res://levels/level_base.tscn").instantiate()
	add_child_autofree(level)
	for layer: TileMapLayer in [grass, level.grass()]:
		assert_eq(Vector2(layer.tile_set.tile_size) * layer.scale, Vector2.ONE * Grid.PX)


func test_drawn_in_front_of_soldiers_engineers_and_arrows() -> void:
	var world: World = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	var z := world.grass.z_index
	assert_gt(z, world.army.z_index)
	assert_gt(z, world.crew.z_index)
	assert_gt(z, (load("res://objects/arrow/arrow.tscn") as PackedScene).instantiate().z_index)


func test_every_level_has_a_grass_layer_to_paint() -> void:
	var level: Level = load("res://levels/level_base.tscn").instantiate()
	add_child_autofree(level)
	assert_not_null(level.grass())
	assert_eq(level.grass().tile_set, grass.tile_set)


func test_digging_the_ground_under_it_removes_it() -> void:
	_paint(Vector2i(2, 1))
	_paint(Vector2i(3, 1))
	terrain.set_type(Vector2i(2, 2), null)
	assert_false(_has(Vector2i(2, 1)), "nothing to stand on")
	assert_true(_has(Vector2i(3, 1)), "the patch beside stays")


func test_filling_its_cell_removes_it() -> void:
	_paint(Vector2i(2, 1))
	terrain.set_type(Vector2i(2, 1), WorldFixture.type("box"))
	assert_false(_has(Vector2i(2, 1)))


## Editing a level: grass goes as soon as ground is painted over it or erased under it.
func test_level_grass_follows_the_levels_terrain() -> void:
	var level: Level = load("res://levels/level_base.tscn").instantiate()
	add_child_autofree(level)
	var g := level.grass() as TallGrass
	assert_not_null(g, "the level's Grass is tall grass")
	assert_eq(g.terrain, level.get_node(^"Terrain"))


func test_painting_ground_over_it_removes_it() -> void:
	_paint(Vector2i(2, 1))
	terrain.set_cell(Vector2i(2, 1), terrain.look.source_id, terrain.look.dirt[0], 0)
	terrain.retile_painted([Vector2i(2, 1)])
	assert_false(_has(Vector2i(2, 1)))


func test_erasing_the_ground_under_it_removes_it() -> void:
	_paint(Vector2i(2, 1))
	_paint(Vector2i(3, 1))
	terrain.erase_cell(Vector2i(2, 2))
	terrain.retile_painted([Vector2i(2, 2)])
	assert_false(_has(Vector2i(2, 1)), "nothing to stand on")
	assert_true(_has(Vector2i(3, 1)), "the patch beside stays")


## Open flat soil, a rock stretch, a step and a wall, wide enough for several patches.
const FIELD: Array = [
	"..........................................",
	"..........................................",
	"......................##..........######..",
	"#########RRRRRR#######################....",
	"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
]


func _scatter() -> GrassScatter:
	var s := GrassScatter.new()
	s.grows_on = [WorldFixture.type("soil")]
	s.gap = Vector2i(1, 3)
	s.width = Vector2i(2, 3)
	s.clearance = 0
	return s


func test_scatter_grows_on_open_soil_only() -> void:
	var t := WorldFixture.terrain(self, FIELD)
	var cells := _scatter().cells(t, [], 0)
	assert_gt(cells.size(), 5)
	for c in cells:
		assert_null(t.type_at(c), "%s in the air" % c)
		assert_null(t.type_at(c + Vector2i.UP), "%s open above" % c)
		assert_eq(t.type_at(c + Vector2i.DOWN), WorldFixture.type("soil"), "%s on soil" % c)


func test_scatter_keeps_clear_of_flags_objects_and_the_edges() -> void:
	var t := WorldFixture.terrain(self, FIELD)
	var s := _scatter()
	s.clearance = 3
	for c in s.cells(t, [12], 0):
		assert_true(absi(c.x - 12) >= 3, "%s clear of column 12" % c)
		assert_true(c.x >= 3 and c.x < t.size.x - 3, "%s clear of the edges" % c)


## Patches are placed by the seed alone, so painting one spot never moves the grass elsewhere.
func test_patches_stay_put_when_the_ground_changes_elsewhere() -> void:
	var t := WorldFixture.terrain(self, FIELD)
	var s := _scatter()
	var before := s.cells(t, [], 0).filter(func(c: Vector2i) -> bool: return c.x < 30)
	t.set_type(Vector2i(32, 3), null)
	t.set_type(Vector2i(5, 2), WorldFixture.type("soil"))
	var after := s.cells(t, [], 0).filter(func(c: Vector2i) -> bool: return c.x < 30 and absi(c.x - 5) > 1)
	assert_eq(after, before.filter(func(c: Vector2i) -> bool: return absi(c.x - 5) > 1))
	assert_ne(s.cells(t, [], 0), s.cells(t, [], 1), "varies per level")


func test_level_grows_its_grass_from_its_scatter() -> void:
	var level: Level = load("res://levels/level_base.tscn").instantiate()
	add_child_autofree(level)
	var g := level.grass() as TallGrass
	assert_not_null(g.scatter, "levels scatter their grass by default")
	var t := level.terrain()
	for x in 140:
		t.set_type(Vector2i(x, 30), WorldFixture.type("soil"))
	level.regrow_grass()
	var start := floori(level.start_flag().metres().x)
	assert_gt(g.get_used_cells().size(), 0)
	for c in g.get_used_cells():
		assert_eq(c.y, 29, "on the ground")
		assert_true(absi(c.x - start) >= g.scatter.clearance, "clear of the start flag")


func test_without_a_scatter_grass_is_painted_by_hand() -> void:
	var level: Level = load("res://levels/level_base.tscn").instantiate()
	add_child_autofree(level)
	var g := level.grass() as TallGrass
	g.scatter = null
	g.set_cell(Vector2i(3, 3), 0, Vector2i.ZERO)
	level.regrow_grass()
	assert_eq(g.get_used_cells(), [Vector2i(3, 3)])


func test_stamped_with_the_level_and_dropped_with_it() -> void:
	var src := TileMapLayer.new()
	src.tile_set = grass.tile_set
	add_child_autofree(src)
	src.set_cell(Vector2i(1, 1), 0, Vector2i.ZERO)
	src.set_cell(Vector2i(5, 1), 0, Vector2i.ZERO)
	grass.stamp(src, Vector2i(10, 0), 13)
	assert_false(_has(Vector2i(11, 1)), "left of the seam is the previous level's")
	assert_true(_has(Vector2i(15, 1)))
	grass.clear_from(14)
	assert_false(_has(Vector2i(15, 1)))
	_paint(Vector2i(2, 1))
	grass.unload_before(3)
	assert_false(_has(Vector2i(2, 1)))
