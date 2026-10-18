extends GutTest

const MAP: Array = [
	"..........",
	"..........",
	"....LLL...",
	"....LTL...",
	"....LTL...",
	".....T....",
	"###C####RR",
	"##########",
	"BBBBBBBBBB",
]


func test_type_at_and_bounds() -> void:
	var t := WorldFixture.terrain(self, MAP)
	assert_null(t.type_at(Vector2i(0, 0)), "air is null")
	assert_eq(t.type_at(Vector2i(0, 6)), WorldFixture.type("soil"))
	assert_eq(t.type_at(Vector2i(-1, 0)), WorldFixture.type("bedrock"), "left of level is bedrock")
	assert_eq(t.type_at(Vector2i(10, 0)), WorldFixture.type("bedrock"), "right of level is bedrock")
	assert_eq(t.type_at(Vector2i(0, 9)), WorldFixture.type("bedrock"), "below level is bedrock")
	assert_null(t.type_at(Vector2i(0, -3)), "above level is air")
	assert_eq(t.size, Vector2i(10, 9))


func test_solid_and_surface() -> void:
	var t := WorldFixture.terrain(self, MAP)
	assert_true(t.is_solid(Vector2i(0, 6)))
	assert_false(t.is_solid(Vector2i(5, 4)), "trunk is not solid")
	assert_eq(t.surface_row(0), 6)
	assert_eq(t.surface_row(5), 6, "surface ignores the tree")


func test_dig_soil_yields_earth() -> void:
	var t := WorldFixture.terrain(self, MAP)
	var got := t.dig(Vector2i(0, 6))
	assert_not_null(got)
	assert_eq(got.earth, 1)
	assert_null(t.type_at(Vector2i(0, 6)))


func test_dig_rock_yields_stone_slowly() -> void:
	var t := WorldFixture.terrain(self, MAP)
	assert_gt(WorldFixture.type("rock").dig_time, WorldFixture.type("soil").dig_time, "slower than soil")
	assert_eq(t.dig(Vector2i(8, 6)).stone, 1)
	assert_null(t.type_at(Vector2i(8, 6)))


func test_dig_bedrock_refuses() -> void:
	var t := WorldFixture.terrain(self, MAP)
	assert_null(t.dig(Vector2i(8, 8)))
	assert_eq(t.type_at(Vector2i(8, 8)), WorldFixture.type("bedrock"))


func test_dig_gold_ore_yields_gold() -> void:
	var t := WorldFixture.terrain(self, MAP)
	assert_eq(t.dig(Vector2i(3, 6)).gold, 1)


func test_dig_tree_fells_whole_tree() -> void:
	var t := WorldFixture.terrain(self, MAP)
	var got := t.dig(Vector2i(5, 5))
	# 3 trunk -> 3 + 2 bonus logs; 7 leaves -> 3 rope
	assert_eq(got.logs, 5)
	assert_eq(got.rope, 3)
	assert_null(t.type_at(Vector2i(4, 2)))
	assert_null(t.type_at(Vector2i(5, 3)))


func test_tree_falls_when_its_ground_is_dug() -> void:
	var t := WorldFixture.terrain(self, MAP)
	watch_signals(t)
	t.dig(Vector2i(5, 6))
	t.settle()
	assert_null(t.type_at(Vector2i(5, 5)), "trunk fell")
	assert_null(t.type_at(Vector2i(4, 2)), "leaves fell")
	assert_signal_emitted(t, "collapsed")
	var found: Supplies = get_signal_parameters(t, "collapsed")[0]
	assert_eq(found.logs, 5, "same as cutting it")
	assert_eq(found.rope, 3)


func test_tree_with_ground_stays() -> void:
	var t := WorldFixture.terrain(self, MAP)
	t.dig(Vector2i(4, 6))
	t.settle()
	assert_eq(t.type_at(Vector2i(5, 5)), WorldFixture.type("trunk"))


func test_unsupported_fill_detaches() -> void:
	var t := WorldFixture.terrain(self, MAP)
	watch_signals(t)
	t.set_type(Vector2i(1, 2), WorldFixture.type("fill"))
	t.settle()
	assert_signal_emit_count(t, "tile_detached", 1)
	assert_null(t.type_at(Vector2i(1, 2)))


func test_supported_fill_stays() -> void:
	var t := WorldFixture.terrain(self, MAP)
	t.set_type(Vector2i(1, 5), WorldFixture.type("fill"))
	t.settle()
	assert_eq(t.type_at(Vector2i(1, 5)), WorldFixture.type("fill"))


func test_brick_collapses_without_ground() -> void:
	var t := WorldFixture.terrain(self, [
		"..KKK.",
		"..KKK.",
		"..KKK.",
		"..###.",
		"BBBBBB",
	])
	watch_signals(t)
	for x in [2, 3, 4]:
		t.set_type(Vector2i(x, 3), null)
	t.settle()
	assert_null(t.type_at(Vector2i(3, 1)), "bricks fell")
	assert_signal_emitted(t, "collapsed")
	var found: Supplies = get_signal_parameters(t, "collapsed")[0]
	assert_eq(found.stone, 3, "9 bricks give 3 stone")


func test_brick_on_ground_stands() -> void:
	var t := WorldFixture.terrain(self, ["..KK.", "..KK.", "#####", "BBBBB"])
	t.settle()
	assert_eq(t.type_at(Vector2i(2, 0)), WorldFixture.type("brick"))


func test_unload_before_turns_left_columns_into_bedrock() -> void:
	var t := WorldFixture.terrain(self, MAP)
	t.unload_before(3)
	assert_eq(t.min_x, 3)
	assert_eq(t.type_at(Vector2i(0, 6)), WorldFixture.type("bedrock"), "unloaded column is a wall")
	assert_null(t.type_at(Vector2i(3, 0)), "air right of the edge stays air")
	assert_eq(t.type_at(Vector2i(3, 6)), WorldFixture.type("crystal"))
	assert_false(t.get_used_cells().any(func(c: Vector2i) -> bool: return c.x < 3), "tiles freed")


func test_stamp_copies_level_right_of_seam_with_offset() -> void:
	var t := WorldFixture.terrain(self, ["....", "####", "BBBB"])
	var src := WorldFixture.terrain(self, ["RR..", "RR##", "BBBB"])
	t.stamp(src, Vector2i(2, 0), 3)
	assert_eq(t.type_at(Vector2i(3, 0)), WorldFixture.type("rock"), "src column 1 lands on world column 3")
	assert_eq(t.type_at(Vector2i(4, 1)), WorldFixture.type("soil"))
	assert_eq(t.type_at(Vector2i(2, 1)), WorldFixture.type("soil"), "left of the seam untouched")
	assert_eq(t.type_at(Vector2i(2, 0)), null)
	assert_eq(t.size.x, 6)


func test_stamp_replaces_everything_right_of_seam() -> void:
	var t := WorldFixture.terrain(self, ["......R", "#######", "BBBBBBB"])
	var src := WorldFixture.terrain(self, ["..", "##", "BB"])
	t.stamp(src, Vector2i(2, 0), 2)
	assert_eq(t.get_cell_source_id(Vector2i(6, 0)), -1, "old tile beyond the seam cleared")
	assert_eq(t.size.x, 4, "level now ends where the stamp ends")


func test_clear_from_makes_right_side_a_wall() -> void:
	var t := WorldFixture.terrain(self, MAP)
	t.mark(Vector2i(8, 6))
	t.clear_from(5)
	assert_eq(t.size.x, 5)
	assert_eq(t.type_at(Vector2i(6, 6)), WorldFixture.type("bedrock"))
	assert_false(t.is_marked(Vector2i(8, 6)), "marks beyond cleared")
	assert_eq(t.type_at(Vector2i(4, 6)), WorldFixture.type("soil"))


## The TileSet editor's paint view labels tiles with this, so it must be short.
func test_terrain_type_prints_its_name() -> void:
	assert_eq(str(WorldFixture.type("soil")), "Soil")
	assert_eq(str(WorldFixture.type("water")), "Water")


## Anything that shows a tile outside the map (falling fill) takes its picture from the TileSet.
func test_tile_texture_comes_from_the_tileset() -> void:
	var t := WorldFixture.terrain(self, MAP)
	var fill := WorldFixture.type("fill")
	t.set_type(Vector2i(0, 0), fill)
	var src := t.tile_set.get_source(t.get_cell_source_id(Vector2i(0, 0))) as TileSetAtlasSource
	var tex := t.tile_texture(fill) as AtlasTexture
	assert_not_null(tex)
	assert_eq(tex.atlas, src.texture)
	assert_eq(tex.region, Rect2(src.get_tile_texture_region(t.get_cell_atlas_coords(Vector2i(0, 0)))))


## A 3 x 3 brick tower on soil: walls the column can only get past by razing it.
const TOWER: Array = [
	"..........",
	"....KKK...",
	"....KKK...",
	"....KKK...",
	"##########",
	"BBBBBBBBBB",
]


func test_besieged_tower_is_razed_whole_after_its_raze_time() -> void:
	var t := WorldFixture.terrain(self, TOWER)
	var brick := WorldFixture.type("brick")
	assert_gt(brick.raze_time, 0.0, "brick can be razed")
	watch_signals(t)
	assert_false(t.besiege(Vector2i(4, 3), brick.raze_time * 0.5), "still standing")
	assert_almost_eq(t.siege_progress(Vector2i(4, 3)), 0.5, 0.01)
	assert_true(t.besiege(Vector2i(4, 3), brick.raze_time * 0.6), "razed")
	for x in range(4, 7):
		for y in range(1, 4):
			assert_null(t.type_at(Vector2i(x, y)), "whole tower down")
	assert_signal_emitted(t, "collapsed")


func test_a_hit_on_a_tower_ripples_through_the_rest_of_it() -> void:
	var t := WorldFixture.terrain(self, TOWER)
	t.hit(Vector2i(4, 3))
	assert_eq(t.ripple_delay(Vector2i(4, 3)), 0.0, "from the tile hit")
	var near := t.ripple_delay(Vector2i(5, 3))
	var far := t.ripple_delay(Vector2i(6, 1))
	assert_gt(near, 0.0, "the next tile a moment later")
	assert_gt(far, near, "the far side of the tower later still")
	assert_eq(t.ripple_delay(Vector2i(4, 4)), -1.0, "not the ground under it")
	t.advance_hits(near + t.ripple_time / 2.0)
	assert_ne(t.ripple_offset_at(Vector2i(5, 3)), Vector2i.ZERO, "lifted as it passes")
	assert_true(t._use_tile_data_runtime_update(Vector2i(6, 1)))
	t.advance_hits(10.0)
	assert_eq(t.ripple_delay(Vector2i(6, 1)), -1.0, "and settles")
	assert_false(t._use_tile_data_runtime_update(Vector2i(6, 1)))


func test_a_hit_on_plain_ground_does_not_ripple() -> void:
	var t := WorldFixture.terrain(self, TOWER)
	t.hit(Vector2i(0, 4))
	assert_eq(t.ripple_delay(Vector2i(1, 4)), -1.0)


func test_a_razed_tower_takes_its_battlements_with_it() -> void:
	var t := WorldFixture.terrain(self, TOWER)
	WorldFixture.decorate(t, Vector2i(4, 0))
	WorldFixture.decorate(t, Vector2i(6, 0))
	t.besiege(Vector2i(4, 3), WorldFixture.type("brick").raze_time + 1.0)
	assert_eq(t.get_cell_source_id(Vector2i(4, 0)), -1, "not left floating")
	assert_eq(t.get_cell_source_id(Vector2i(6, 0)), -1)


func test_a_tower_breaking_up_where_it_stands_takes_its_battlements_with_it() -> void:
	var t := WorldFixture.terrain(self, TOWER)
	WorldFixture.decorate(t, Vector2i(5, 0))
	var cells: Array[Vector2i] = []
	for x in range(4, 7):
		for y in range(1, 4):
			cells.append(Vector2i(x, y))
	t.break_up(cells)
	assert_eq(t.get_cell_source_id(Vector2i(5, 0)), -1)


func test_a_tower_with_ground_only_at_its_side_does_not_stand() -> void:
	var t := WorldFixture.terrain(self, [
		"..........",
		"###KK.....",
		"###KK.....",
		"###KK.....",
		"###.......",
		"##########",
		"BBBBBBBBBB",
	])
	t.settle()
	assert_null(t.type_at(Vector2i(3, 1)), "ground beside it does not hold it up")


func test_a_tower_standing_on_ground_stands_even_beside_a_wall() -> void:
	var t := WorldFixture.terrain(self, [
		"..........",
		"###KK.....",
		"###KK.....",
		"##########",
		"BBBBBBBBBB",
	])
	t.settle()
	assert_eq(t.type_at(Vector2i(3, 1)), WorldFixture.type("brick"))


func test_rock_can_not_be_besieged() -> void:
	var t := WorldFixture.terrain(self, MAP)
	assert_false(t.besiege(Vector2i(8, 6), 1000.0))
	assert_eq(t.type_at(Vector2i(8, 6)), WorldFixture.type("rock"))


func test_razed_tower_yields_stone() -> void:
	var t := WorldFixture.terrain(self, TOWER)
	watch_signals(t)
	t.besiege(Vector2i(4, 3), WorldFixture.type("brick").raze_time + 1.0)
	var got: Supplies = get_signal_parameters(t, "collapsed")[0]
	assert_gt(got.stone, 0)
	assert_eq(got.earth, 0)


