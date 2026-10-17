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


func test_dig_rock_refuses() -> void:
	var t := WorldFixture.terrain(self, MAP)
	assert_null(t.dig(Vector2i(8, 6)))
	assert_eq(t.type_at(Vector2i(8, 6)), WorldFixture.type("rock"))


func test_dig_crystal_yields_powder() -> void:
	var t := WorldFixture.terrain(self, MAP)
	assert_eq(t.dig(Vector2i(3, 6)).powder, 1)


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
	assert_eq(found.earth, 3, "9 bricks give 3 earth")


func test_brick_on_ground_stands() -> void:
	var t := WorldFixture.terrain(self, ["..KK.", "..KK.", "#####", "BBBBB"])
	t.settle()
	assert_eq(t.type_at(Vector2i(2, 0)), WorldFixture.type("brick"))


func test_blast_clears_radius_but_not_bedrock() -> void:
	var t := WorldFixture.terrain(self, [
		"..........",
		"..........",
		"##########",
		"##########",
		"RRRRRRRRRR",
		"BBBBBBBBBB",
	])
	var got := t.blast(Vector2(5.5, 3.5), 2.6)
	assert_null(t.type_at(Vector2i(5, 3)))
	assert_null(t.type_at(Vector2i(5, 4)), "rock is blasted")
	assert_eq(t.type_at(Vector2i(5, 5)), WorldFixture.type("bedrock"))
	assert_eq(t.type_at(Vector2i(0, 2)), WorldFixture.type("soil"), "outside radius untouched")
	assert_gt(got.earth, 0)


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
