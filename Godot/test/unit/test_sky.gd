extends GutTest
## The sky behind the world: the parallax hills and forest, and the sun crossing it from dawn to sunset as the
## column crosses a level.

const VIEW := Vector2(1280, 720)


func _background() -> CanvasLayer:
	var bg: CanvasLayer = load("res://world/background/background.tscn").instantiate()
	add_child_autofree(bg)
	return bg


func test_the_hills_and_forest_are_the_new_parallax_art() -> void:
	var bg := _background()
	var far: Ridge = bg.get_node("RidgeFar")
	var near: Ridge = bg.get_node("RidgeNear")
	assert_eq(far.texture.resource_path, "res://world/background/paralax_back.png")
	assert_eq(near.texture.resource_path, "res://world/background/paralax_front.png")
	assert_lt(far.parallax, near.parallax, "the far hills move slower")
	assert_lt(far.get_index(), near.get_index(), "the forest in front of the hills")
	assert_lt(bg.get_node("SunPixel2").get_index(), far.get_index(), "the sun sets behind the hills")


## A textured ridge is tiled across the whole screen, standing on its bottom edge at Texture Height of the screen,
## and scrolls by its parallax share of the camera's travel.
func test_a_textured_ridge_tiles_the_screen_and_scrolls_with_its_parallax() -> void:
	var r: Ridge = _background().get_node("RidgeFar")
	var tiles := r.tiles(VIEW, Vector2.ZERO)
	assert_gt(tiles.size(), 0)
	var h := VIEW.y * r.texture_height
	var lo := INF
	var hi := -INF
	for t in tiles:
		assert_almost_eq(t.size.y, h, 0.5, "as tall as set")
		assert_almost_eq(t.end.y, VIEW.y, 0.5, "standing on the bottom of the screen")
		lo = minf(lo, t.position.x)
		hi = maxf(hi, t.end.x)
	assert_lte(lo, 0.0, "from the left edge")
	assert_gte(hi, VIEW.x, "to the right edge")
	var moved := r.tiles(VIEW, Vector2(1.0, 0.0))
	var step := fposmod(tiles[0].position.x - moved[0].position.x, tiles[0].size.x)
	assert_almost_eq(step, Grid.PX * r.parallax, 0.01, "a metre of camera travel moves it by its parallax share")


func test_the_sun_crosses_the_sky_from_dawn_to_sunset() -> void:
	var sun: Sun = _background().get_node("SunPixel2")
	var view := sun.get_viewport_rect().size
	sun.progress = 0.0
	assert_almost_eq(sun.position, Vector2(view.x * sun.rise_x, view.y * sun.horizon_y), Vector2.ONE, "dawn on the horizon")
	sun.progress = 0.5
	assert_almost_eq(sun.position.y, view.y * sun.peak_y, 1.0, "highest at midday")
	sun.progress = 1.0
	assert_almost_eq(sun.position, Vector2(view.x * sun.set_x, view.y * sun.horizon_y), Vector2.ONE, "sunset on the horizon")
	sun.progress = 1.2
	assert_gt(sun.position.y, view.y * sun.horizon_y, "set: below the horizon")


## The day goes by the leader's way between the level's flags; the sun rises in the morning, sets at dusk and stays
## down all night.
func test_the_day_follows_the_leader_between_the_flags() -> void:
	GameState.save_path = "user://test_sappers.cfg"
	GameState.new_campaign()
	var world: World = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	world.set_physics_process(false)
	world.begin(0, 3)
	var c := world.current_chunk()
	var start := c.start_flag.metres().x
	var exit := c.exit_flag.metres().x
	assert_almost_eq(world.sun_progress(), 1.0, 0.01, "camping at dusk: setting")
	for i in int(world.dusk_time * 60.0) + 2:
		world._physics_process(1.0 / 60.0)
	assert_gt(world.sun_progress(), 1.0, "night: below the horizon")
	world.march()
	assert_lt(world.sun_progress(), 0.0, "breaking camp: not up yet")
	world._set_day()
	for t: float in [0.0, 0.5, 1.0]:
		world.army.lead().pos.x = lerpf(start, exit, t)
		assert_almost_eq(world.sun_progress(), t, 0.01, "at %d%% of the way" % roundi(t * 100))


func test_the_game_moves_the_sun() -> void:
	var game: Game = load("res://game/main.tscn").instantiate()
	add_child_autofree(game)
	game._begin()
	game._process(0.0)
	var sun: Sun = game.get_node("Background/SunPixel2")
	assert_eq(sun.progress, game.get_node("%World").sun_progress())
