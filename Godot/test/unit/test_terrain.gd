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
