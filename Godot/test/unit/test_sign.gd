extends GutTest
## Signs: a board on a post that shows a tutorial text in the level, with a lamp so it can be read at night.


func _sign(text: String = "") -> Sign:
	var s: Sign = load("res://objects/sign/sign.tscn").instantiate()
	s.text = text
	add_child_autofree(s)
	return s


func test_shows_its_text() -> void:
	var s := _sign("Dig with 1.")
	assert_eq(s.get_node("%Text").text, "Dig with 1.")
	s.text = "Build with 2."
	assert_eq(s.get_node("%Text").text, "Build with 2.", "changes show at once")


## The sign's origin is the bottom of the board, centred on the post.
func test_board_sits_on_its_origin() -> void:
	var s := _sign("A longer text that has to wrap over a few lines on the board.")
	await wait_process_frames(2)
	var board: Control = s.get_node("%Board")
	assert_almost_eq(board.position.y + board.size.y, 0.0, 1.0, "board bottom at the origin")
	assert_almost_eq(board.position.x + board.size.x / 2.0, 0.0, 1.0, "centred on the post")


func test_no_post_unless_asked_for() -> void:
	var s := _sign("x")
	assert_false(s.post, "off by default")
	assert_false(s.get_node("%Post").visible)
	s.post = true
	assert_true(s.get_node("%Post").visible)


## In a level, the post runs down from the board to the first solid ground below, and follows it.
func test_post_reaches_the_ground() -> void:
	var level: Level = load("res://levels/level_base.tscn").instantiate()
	add_child_autofree(level)
	var t := level.terrain()
	for x in 10:
		t.set_type(Vector2i(x, 20), WorldFixture.type("soil"))
		t.set_type(Vector2i(x, 21), WorldFixture.type("soil"))
	var s: Sign = load("res://objects/sign/sign.tscn").instantiate()
	s.text = "x"
	s.post = true
	s.position = Vector2(5.5, 17.25) * Grid.PX
	level.objects().add_child(s)
	var post: Control = s.get_node("%Post")
	assert_almost_eq(post.position.y, 0.0, 0.5, "from the board")
	assert_almost_eq(post.size.y, 2.75 * Grid.PX, 0.5, "down to the ground")
	t.set_type(Vector2i(5, 20), null)
	assert_almost_eq(post.size.y, 3.75 * Grid.PX, 0.5, "follows the ground dug away")
	s.position.y -= Grid.PX
	await wait_process_frames(1)
	assert_almost_eq(post.size.y, 4.75 * Grid.PX, 0.5, "follows the sign moved")


## The board is as big as its text plus the padding, and wraps past max_width.
func test_board_fits_its_text_and_padding() -> void:
	var s := _sign("A longer text that has to wrap over a few lines on the board.")
	await wait_process_frames(2)
	var board: Control = s.get_node("%Board")
	var text: Label = s.get_node("%Text")
	assert_gt(text.get_line_count(), 1, "wrapped")
	assert_lt(board.size.x, s.max_width + 2 * s.padding.x + 40.0, "no wider than the wrap width allows")
	assert_lt(board.size.y, text.get_line_count() * text.get_line_height() + 2 * s.padding.y + 40.0, "only as tall as its lines")
	var tall := board.size
	s.text = "Short."
	await wait_process_frames(2)
	assert_lt(board.size.x, tall.x, "shrinks to a short text")
	assert_lt(board.size.y, tall.y)
	var short := board.size
	s.padding += Vector2i(5, 5)
	await wait_process_frames(2)
	assert_almost_eq(board.size, short + Vector2(10, 10), Vector2.ONE, "padding adds on both sides")


func test_uses_the_games_font() -> void:
	assert_eq(_sign("x").get_node("%Text").get_theme_font(&"font").resource_path, "res://ui/fonts/alagard.ttf")


func test_lit_at_night_by_a_mix_lamp() -> void:
	var lamp: NightLight = _sign("x").get_node("%Lamp")
	assert_eq(lamp.blend_mode, Light2D.BLEND_MODE_MIX)
	assert_gt(lamp.night_energy, 0.0)


func test_level_one_teaches_with_signs() -> void:
	var level: Level = load(GameState.campaign.levels[0]).instantiate()
	add_child_autofree(level)
	var signs := level.objects().get_children().filter(func(o: Node) -> bool: return o is Sign)
	assert_gt(signs.size(), 0)
	for s: Sign in signs:
		assert_false(s.text.strip_edges().is_empty(), "%s has a text" % s.name)
