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


## A tunnel dug under the ground: its roof gets the ceiling tiles, and the inside corners where it meets the walls.
func test_tunnel_ceiling_and_its_inner_corners() -> void:
	terrain.set_type(Vector2i(2, 6), null)
	terrain.set_type(Vector2i(3, 6), null)
	assert_has(look.ceiling, _tile(Vector2i(2, 5)), "ceiling")
	assert_eq(terrain.painted_type(Vector2i(2, 5)), _type("soil"))
	assert_has(look.inner_br, _tile(Vector2i(1, 5)), "inner corner where the roof meets the left wall")
	assert_has(look.inner_bl, _tile(Vector2i(4, 5)), "inner corner on the other side")
	assert_eq(terrain.painted_type(Vector2i(4, 5)), _type("rock"), "rock keeps its material")


func test_ceiling_with_air_beside_gets_a_corner() -> void:
	terrain.set_type(Vector2i(2, 6), null)
	terrain.set_type(Vector2i(3, 6), null)
	terrain.set_type(Vector2i(1, 6), null)
	terrain.set_type(Vector2i(1, 5), null)
	terrain.set_type(Vector2i(0, 5), _type("soil"))
	assert_has(look.ceiling_l, _tile(Vector2i(2, 5)), "air below and to the left")


## An untagged (no material) old tile painted in the air is a decoration: re-tiling and digging nearby keep it.
func test_decorations_in_the_air_survive() -> void:
	var src := terrain.tile_set.get_source(look.classic_source) as TileSetAtlasSource
	var deco := Vector2i(-1, -1)
	for i in src.get_tiles_count():
		var c := src.get_tile_id(i)
		if src.get_tile_data(c, 0).get_custom_data("terrain") == null:
			deco = c
			break
	if deco.x < 0:
		pass_test("no decoration tiles in the old atlas")
		return
	terrain.set_cell(Vector2i(3, 2), look.classic_source, deco)
	terrain.retile_all()
	terrain.set_type(Vector2i(3, 3), null)
	assert_eq(terrain.get_cell_source_id(Vector2i(3, 2)), look.classic_source, "decoration kept")
	assert_eq(_tile(Vector2i(3, 2)), deco)
	assert_null(terrain.type_at(Vector2i(3, 2)), "still air")


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


## Solid rock varies over the Rock tiles; the overlay must hold every one of them, or most corners draw nothing.
func test_overlay_has_every_tile_it_draws() -> void:
	for y in range(4, 7):
		for x in range(1, 4):
			terrain.set_type(Vector2i(x, y), _type("rock"))
	skin.refresh()
	var body := skin.body_layer()
	assert_gt(body.get_used_cells().size(), 0)
	for c in body.get_used_cells():
		assert_not_null(body.get_cell_tile_data(c), "overlay tile at %s exists" % c)


func test_materials_without_v2_art_keep_their_old_tile() -> void:
	var old := terrain.atlas_tile(_type("brick"))
	assert_eq(terrain.get_cell_source_id(Vector2i(10, 2)), old[0])
	assert_eq(_tile(Vector2i(10, 2)), old[1])


## The v2 sheet has no water art, so water uses the old tiles: surface and depth.
func test_water_surface_and_depth() -> void:
	if not look.water_top.is_empty():
		assert_has(look.water_top, _tile(Vector2i(9, 5)))
		return
	assert_eq(terrain.get_cell_source_id(Vector2i(9, 5)), look.classic_source)
	assert_has(look.classic_water_top, _tile(Vector2i(9, 5)))
	assert_has(look.classic_water, _tile(Vector2i(9, 6)))


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


func test_painted_water_and_spikes_keep_their_old_art() -> void:
	var old := terrain.atlas_tile(_type("water"))
	terrain.set_cell(Vector2i(9, 6), old[0], old[1])
	terrain.retile_all()
	assert_eq(terrain.get_cell_source_id(Vector2i(9, 6)), old[0], "designer's water kept")
	assert_eq(terrain.painted_type(Vector2i(9, 6)), _type("water"))


func test_new_water_gets_a_water_tile() -> void:
	terrain.set_type(Vector2i(9, 4), _type("water"))
	assert_eq(terrain.painted_type(Vector2i(9, 4)), _type("water"))


func test_switching_off_draws_old_tiles_where_old_art_exists() -> void:
	look.enabled = false
	terrain.retile_all()
	skin.refresh()
	assert_eq(terrain.get_cell_source_id(Vector2i(9, 5)), look.classic_source, "water has old art")
	assert_has(look.classic_water_top, _tile(Vector2i(9, 5)))
	assert_has(look.classic_water, _tile(Vector2i(9, 6)))
	assert_eq(terrain.get_cell_source_id(Vector2i(3, 2)), -1, "no fillets")
	assert_eq(skin.body_layer().get_used_cells().size(), 0, "no overlay")


func test_a_material_without_old_art_keeps_its_v2_tile_when_switched_off() -> void:
	look.enabled = false
	terrain.retile_all()
	if terrain.atlas_tile(_type("soil")).is_empty():
		assert_true(_v2(Vector2i(5, 2)), "soil has no old art left, so it stays v2")


## Whatever the look, a cell's tile always carries the cell's material: drawing never changes what the ground is.
func test_tiles_always_carry_their_cells_material() -> void:
	for on in [true, false]:
		look.enabled = on
		terrain.retile_all()
		for cell in terrain.get_used_cells():
			assert_eq(terrain.painted_type(cell), terrain.type_at(cell), "%s with the look %s" % [cell, "on" if on else "off"])


func test_terrain_has_a_retile_button() -> void:
	var names := terrain.get_property_list().map(func(p: Dictionary) -> String: return p.name)
	assert_has(names, "retile")


func test_value_tweaks_has_the_switch() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	var tweaks: ValueTweaks = main.get_node("ValueTweaks")
	assert_eq(tweaks.get("art/terrain_v2"), look.enabled)
	main.free()

