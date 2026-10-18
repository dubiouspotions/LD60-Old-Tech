extends GutTest
## The v2 terrain: v2 tiles live in the terrain itself (paintable, each tagged with its material). Rules re-pick
## only the cells that no longer fit, so painted variants survive, and the rock in the dirt is an overlay drawn
## on a half-cell dual grid.

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
	look = terrain.look
	skin.refresh()


func after_each() -> void:
	look.enabled = true


func _tile(cell: Vector2i) -> Vector2i:
	return terrain.get_cell_atlas_coords(cell)


func _v2(cell: Vector2i) -> bool:
	return terrain.get_cell_source_id(cell) == look.source_id


func _body(corner: Vector2i) -> Vector2i:
	return skin.body_layer().get_cell_atlas_coords(corner)


func _type(key: String) -> TerrainType:
	return WorldFixture.type(key)


func test_tileset_has_a_paintable_v2_source_tagged_with_materials() -> void:
	var src := terrain.tile_set.get_source(look.source_id) as TileSetAtlasSource
	assert_not_null(src, "v2 source in the TileSet")
	for coords in look.flat_tops + look.corner_tl + look.wall_l + look.dirt:
		var found := []
		for i in src.get_alternative_tiles_count(coords):
			var alt := src.get_alternative_tile_id(coords, i)
			found.append(src.get_tile_data(coords, alt).get_custom_data("terrain"))
		for m in look.dirt_types + look.rock_types:
			assert_has(found, m, "%s has a %s version" % [coords, m])
	for coords in look.fillet_r + look.fillet_l:
		assert_null(src.get_tile_data(coords, 0).get_custom_data("terrain"), "fillets are air")


func test_ground_cells_get_v2_tiles_carrying_their_material() -> void:
	assert_true(_v2(Vector2i(5, 2)))
	assert_has(look.flat_tops, _tile(Vector2i(5, 2)))
	assert_eq(terrain.painted_type(Vector2i(5, 2)), _type("soil"))
	assert_has(look.rock, _tile(Vector2i(4, 5)), "rock inside the dirt")
	assert_eq(terrain.painted_type(Vector2i(4, 5)), _type("rock"))
	assert_eq(terrain.painted_type(Vector2i(3, 7)), _type("bedrock"), "bedrock stays bedrock")


func test_rock_at_the_surface_keeps_its_material() -> void:
	terrain.set_type(Vector2i(12, 4), _type("rock"))
	assert_has(look.flat_tops, _tile(Vector2i(12, 4)), "grass edge like dirt")
	assert_eq(terrain.painted_type(Vector2i(12, 4)), _type("rock"))
	assert_eq(terrain.type_at(Vector2i(12, 4)), _type("rock"))


func test_grass_surface_corners_and_walls() -> void:
	assert_has(look.corner_tl, _tile(Vector2i(4, 2)), "top-left corner")
	assert_has(look.corner_tr, _tile(Vector2i(6, 2)), "top-right corner")
	assert_has(look.wall_r, _tile(Vector2i(8, 5)), "right wall beside the water")
	assert_has(look.wall_l, _tile(Vector2i(10, 5)), "left wall beside the water")
	assert_has(look.inner_tl, _tile(Vector2i(4, 3)), "inner corner under the step")
	assert_has(look.inner_tr, _tile(Vector2i(6, 3)), "inner corner under the step")


func test_fillets_are_air_tiles_at_the_foot_of_a_step() -> void:
	assert_has(look.fillet_r + look.fillet_r_low, _tile(Vector2i(3, 2)), "air cell left of the step")
	assert_has(look.fillet_l + look.fillet_l_low, _tile(Vector2i(7, 2)), "air cell right of the step")
	assert_null(terrain.type_at(Vector2i(3, 2)), "still air")
	assert_false(terrain.is_solid(Vector2i(3, 2)))


func test_rock_pocket_overlay_on_the_dual_grid() -> void:
	# The rock cell (4, 5) is the bottom-right corner of dual tile (3, 4), bottom-left of (4, 4), and so on.
	assert_eq(_body(Vector2i(3, 4)), look.body[8])
	assert_eq(_body(Vector2i(4, 4)), look.body[4])
	assert_eq(_body(Vector2i(3, 5)), look.body[2])
	assert_eq(_body(Vector2i(4, 5)), look.body[1])
	assert_eq(skin.body_layer().get_cell_source_id(Vector2i(1, 5)), -1, "no overlay away from the rock")
	assert_eq(skin.body_layer().get_cell_source_id(Vector2i(4, 1)), -1, "no overlay touching the sky")


func test_materials_without_v2_art_keep_their_old_tile() -> void:
	var old := terrain.atlas_tile(_type("brick"))
	assert_eq(terrain.get_cell_source_id(Vector2i(10, 2)), old[0])
	assert_eq(_tile(Vector2i(10, 2)), old[1])


func test_water_surface_and_depth() -> void:
	assert_has(look.water_top, _tile(Vector2i(9, 5)))
	assert_has(look.water, _tile(Vector2i(9, 6)))


func test_digging_repicks_the_neighbours() -> void:
	terrain.set_type(Vector2i(5, 2), null)
	assert_has(look.flat_tops, _tile(Vector2i(5, 3)), "the cell below is now a grass top")


func test_a_painted_variant_is_kept_while_it_still_fits() -> void:
	var other: Vector2i = look.flat_tops.filter(func(c: Vector2i) -> bool: return c != _tile(Vector2i(5, 2)))[0]
	terrain.set_cell(Vector2i(5, 2), look.source_id, other, terrain.get_cell_alternative_tile(Vector2i(5, 2)))
	terrain.set_type(Vector2i(12, 0), _type("soil"))
	terrain.retile_all()
	assert_eq(_tile(Vector2i(5, 2)), other, "designer's pick kept")
	terrain.set_type(Vector2i(4, 2), null)
	assert_has(look.corner_tl, _tile(Vector2i(5, 2)), "re-picked once it no longer fits")


func test_retile_turns_old_material_tiles_into_v2() -> void:
	var old := terrain.atlas_tile(_type("soil"))
	terrain.set_cell(Vector2i(5, 2), old[0], old[1])
	terrain.retile_all()
	assert_true(_v2(Vector2i(5, 2)))
	assert_eq(terrain.painted_type(Vector2i(5, 2)), _type("soil"))


func test_switching_off_draws_the_old_tiles() -> void:
	look.enabled = false
	terrain.retile_all()
	skin.refresh()
	assert_eq(terrain.get_cell_source_id(Vector2i(5, 2)), look.classic_source)
	assert_has(look.classic_grass, _tile(Vector2i(5, 2)), "old grass on top")
	assert_has(look.classic_dirt, _tile(Vector2i(5, 3)), "old dirt below")
	assert_has(look.classic_rock, _tile(Vector2i(4, 5)))
	assert_has(look.classic_water_top, _tile(Vector2i(9, 5)))
	assert_has(look.classic_water, _tile(Vector2i(9, 6)))
	assert_eq(terrain.get_cell_source_id(Vector2i(3, 2)), -1, "no fillets")
	assert_eq(terrain.painted_type(Vector2i(4, 5)), _type("rock"), "materials unchanged")
	assert_eq(skin.body_layer().get_used_cells().size(), 0, "no overlay")


func test_terrain_has_a_retile_button() -> void:
	var names := terrain.get_property_list().map(func(p: Dictionary) -> String: return p.name)
	assert_has(names, "retile")


func test_value_tweaks_has_the_switch() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	var tweaks: ValueTweaks = main.get_node("ValueTweaks")
	assert_eq(tweaks.get("art/terrain_v2"), look.enabled)
	main.free()

