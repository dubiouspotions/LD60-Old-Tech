extends GutTest
## The v2 terrain look: grass edges and fillets chosen per cell from its neighbours, rock pockets on a half-cell
## dual grid, and the old tiles kept for materials the v2 sheet has no art for.

## A hill with a step, a rock pocket in the dirt, a tower and a water hole.
const MAP: Array = [
	"..............",
	"..........KK..",
	"....###...KK..",
	"..######..KK..",
	"#########.####",
	"####R####~####",
	"#########~####",
	"BBBBBBBBBBBBBB",
]

var terrain: Terrain
var skin: TerrainSkin
var look: TerrainLook


func before_each() -> void:
	terrain = WorldFixture.terrain(self, MAP)
	skin = terrain.get_node("Skin")
	look = skin.look
	look.enabled = true
	skin.refresh()


func after_all() -> void:
	look.enabled = true


func _tile(cell: Vector2i) -> Vector2i:
	return skin.cells_layer().get_cell_atlas_coords(cell)


func _body(corner_tile: Vector2i) -> Vector2i:
	return skin.body_layer().get_cell_atlas_coords(corner_tile)


func test_v2_hides_the_logic_tiles_and_draws_the_skin() -> void:
	assert_false(terrain.enabled, "old tiles hidden")
	assert_ne(skin.cells_layer().get_cell_source_id(Vector2i(5, 2)), -1, "skin drawn")


func test_grass_surface_corners_and_walls() -> void:
	assert_has(look.flat_tops, _tile(Vector2i(5, 2)), "flat top")
	assert_has(look.corner_tl, _tile(Vector2i(4, 2)), "top-left corner")
	assert_has(look.corner_tr, _tile(Vector2i(6, 2)), "top-right corner")
	assert_has(look.wall_r, _tile(Vector2i(8, 5)), "right wall beside the water")
	assert_has(look.wall_l, _tile(Vector2i(10, 5)), "left wall beside the water")
	assert_has(look.inner_tl, _tile(Vector2i(4, 3)), "inner corner under the step")
	assert_has(look.inner_tr, _tile(Vector2i(6, 3)), "inner corner under the step")


func test_fillets_in_the_air_at_the_foot_of_a_step() -> void:
	assert_has(look.fillet_r + look.fillet_r_low, _tile(Vector2i(3, 2)), "air cell left of the step")
	assert_has(look.fillet_l + look.fillet_l_low, _tile(Vector2i(7, 2)), "air cell right of the step")


func test_rock_pocket_is_drawn_on_the_dual_grid() -> void:
	# The rock cell (4, 5) is the bottom-right corner of dual tile (3, 4), bottom-left of (4, 4), and so on.
	assert_eq(_body(Vector2i(3, 4)), look.body[8])
	assert_eq(_body(Vector2i(4, 4)), look.body[4])
	assert_eq(_body(Vector2i(3, 5)), look.body[2])
	assert_eq(_body(Vector2i(4, 5)), look.body[1])
	assert_eq(skin.body_layer().get_cell_source_id(Vector2i(1, 5)), -1, "no body tile away from the rock")
	assert_has(look.dirt, _tile(Vector2i(1, 5)), "the cell layer draws plain dirt there")


func test_no_body_tile_where_a_corner_is_air() -> void:
	assert_eq(skin.body_layer().get_cell_source_id(Vector2i(4, 1)), -1, "touches the sky")


func test_materials_without_v2_art_keep_their_old_tile() -> void:
	var brick := WorldFixture.type("brick")
	assert_eq(_tile(Vector2i(10, 2)), terrain.atlas_tile(brick)[1])


func test_water_surface_and_depth() -> void:
	assert_has(look.water_top, _tile(Vector2i(9, 5)))
	assert_has(look.water, _tile(Vector2i(9, 6)))


func test_digging_updates_the_skin() -> void:
	var before := _tile(Vector2i(5, 2))
	terrain.set_type(Vector2i(5, 2), null)
	skin.refresh()
	assert_ne(_tile(Vector2i(5, 2)), before, "redrawn")
	assert_has(look.flat_tops, _tile(Vector2i(5, 3)), "the cell below is now a grass top")


func test_variation_is_stable() -> void:
	var first := _tile(Vector2i(2, 3))
	terrain.set_type(Vector2i(12, 0), WorldFixture.type("soil"))
	skin.refresh()
	assert_eq(_tile(Vector2i(2, 3)), first, "unrelated change does not reshuffle")


func test_switching_off_restores_the_old_look() -> void:
	look.enabled = false
	skin.refresh()
	assert_true(terrain.enabled, "old tiles back")
	assert_eq(skin.cells_layer().get_used_cells().size(), 0, "skin cleared")


func test_value_tweaks_has_the_switch() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	var tweaks: ValueTweaks = main.get_node("ValueTweaks")
	assert_eq(tweaks.get("art/terrain_v2"), look.enabled)
	main.free()
