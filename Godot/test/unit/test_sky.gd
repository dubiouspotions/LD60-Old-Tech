extends GutTest
## The sky behind the world: the parallax hills and forest, and the sun crossing it from dawn to sunset as the
## column crosses a level.

const VIEW := Vector2(1280, 720)


## The main scene pauses the tree for its intro card.
func after_each() -> void:
	get_tree().paused = false


func _background() -> CanvasLayer:
	var bg: CanvasLayer = load("res://world/background/background.tscn").instantiate()
	add_child_autofree(bg)
	return bg


func test_the_mountains_hills_and_forest_are_the_parallax_art() -> void:
	var bg := _background()
	var mountains: Parallax2D = bg.get_node("Mountains")
	var far: Parallax2D = bg.get_node("RidgeFar")
	var near: Parallax2D = bg.get_node("RidgeNear")
	assert_eq(_art(mountains).texture.resource_path, "res://world/background/paralax_far.png")
	assert_eq(_art(far).texture.resource_path, "res://world/background/paralax_back.png")
	assert_eq(_art(near).texture.resource_path, "res://world/background/paralax_front.png")
	assert_lt(mountains.scroll_scale.x, far.scroll_scale.x, "the mountains move slowest")
	assert_lt(far.scroll_scale.x, near.scroll_scale.x, "the far hills move slower than the forest")
	assert_lt(mountains.get_index(), far.get_index(), "the hills in front of the mountains")
	assert_lt(far.get_index(), near.get_index(), "the forest in front of the hills")
	assert_lt(bg.get_node("SunPixel2").get_index(), mountains.get_index(), "the sun sets behind the mountains")


## Each layer's art stands on the bottom of the screen and is repeated, edge to edge, across all of it however the
## camera has scrolled it.
func test_each_layer_tiles_the_screen_from_the_bottom() -> void:
	var bg := _background()
	for layer_name: String in ["Mountains", "RidgeFar", "RidgeNear"]:
		var layer: Parallax2D = bg.get_node(layer_name)
		var art := _art(layer)
		var size := art.texture.get_size() * art.scale
		assert_false(art.centered, layer_name)
		assert_almost_eq(art.position.y + size.y, VIEW.y, 0.5, "%s stands on the bottom of the screen" % layer_name)
		assert_almost_eq(layer.repeat_size.x, size.x, 0.01, "%s repeats edge to edge" % layer_name)
		assert_eq(layer.repeat_size.y, 0.0, "%s does not repeat upwards" % layer_name)
		# Copies run from -(times / 2) to times - times / 2 widths, and scrolling moves the layer by up to one width.
		var right := (layer.repeat_times - layer.repeat_times / 2) * layer.repeat_size.x
		assert_gte(right, VIEW.x, "%s reaches the right edge" % layer_name)


## The sky gradient stands still and is repeated sideways, so an ultra-wide window shows no edge.
func test_the_sky_tiles_across_the_screen() -> void:
	var bg := _background()
	var sky: Parallax2D = bg.get_node("SkyPixel")
	var art := _art(sky)
	var width := art.texture.get_width() * art.scale.x
	assert_false(art.centered)
	assert_eq(sky.scroll_scale, Vector2.ZERO, "it does not scroll")
	assert_almost_eq(sky.repeat_size.x, width, 0.01, "repeats edge to edge")
	assert_eq(sky.repeat_size.y, 0.0, "does not repeat upwards")
	var left := -(sky.repeat_times / 2) * sky.repeat_size.x + art.position.x
	var right := (sky.repeat_times - sky.repeat_times / 2) * sky.repeat_size.x + art.position.x
	# The stretch aspect is "expand": a wider window adds screen to the right of x = 0.
	assert_lte(left, 0.0, "reaches the left edge")
	assert_gte(right, VIEW.y * 32.0 / 9.0, "reaches the right edge of a 32:9 window")
	assert_lt(sky.get_index(), bg.get_node("Stars").get_index(), "behind the stars")


## On the background CanvasLayer the camera does not move the layers, so each scrolls itself by its Scroll Scale
## share of the camera's travel: sideways, and up and down.
func test_a_layer_scrolls_by_its_share_of_the_camera_travel() -> void:
	var layer: Parallax2D = _background().get_node("RidgeFar")
	assert_false(layer.follow_viewport, "it is drawn on the screen, not in the world")
	layer.screen_offset = Vector2.ZERO
	var start := layer.position
	layer.screen_offset = Vector2(Grid.PX, Grid.PX)
	var step := fposmod(start.x - layer.position.x, layer.repeat_size.x)
	assert_almost_eq(step, Grid.PX * layer.scroll_scale.x, 0.01, "a metre right moves it left by its share")
	assert_almost_eq(start.y - layer.position.y, Grid.PX * layer.scroll_scale.y, 0.01, "a metre down moves it up by its share")


## The camera looking down into a pit lifts the layers, so the front one goes on below its art in the art's bottom
## colour, and no sky shows under the forest.
func test_the_front_layer_goes_on_below_its_art() -> void:
	var near: Parallax2D = _background().get_node("RidgeNear")
	var art := _art(near)
	var fill: ColorRect = near.get_node("Fill")
	var image := art.texture.get_image()
	assert_eq(fill.color.to_html(false), image.get_pixel(0, image.get_height() - 1).to_html(false), "the art's bottom colour")
	assert_lte(fill.position.y, art.position.y + art.texture.get_height() * art.scale.y, "no gap under the art")
	assert_gte(fill.size.y, VIEW.y, "deep enough for any pit")
	assert_almost_eq(fill.position.x, 0.0, 0.01)
	assert_gte(fill.size.x, near.repeat_size.x, "repeated edge to edge with the art")
	assert_eq(fill.mouse_filter, Control.MOUSE_FILTER_IGNORE, "clicks go through to the world")
	assert_gt(fill.get_index(), art.get_index())


func _art(layer: Parallax2D) -> Sprite2D:
	return layer.get_node("Art")


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


## The light follows the sun along a curve we can edit: full day at midday, full night once it is down, and in
## between at dawn and sunset.
func test_the_main_scene_darkens_by_the_sun_along_its_curve() -> void:
	var game: Game = load("res://game/main.tscn").instantiate()
	add_child_autofree(game)
	var dn: DayNight = game.get_node("%DayNight")
	var curve := dn.darkness_by_sun
	assert_not_null(curve, "a graph to edit")
	assert_almost_eq(curve.sample(0.5), 0.0, 0.01, "midday: full day")
	assert_almost_eq(curve.sample(1.0 + game.get_node("%World").sun_below), 1.0, 0.01, "set: full night")
	assert_between(curve.sample(0.0), 0.05, 0.95, "dawn: in between")
	assert_between(curve.sample(1.0), 0.05, 0.95, "sunset: in between")


func test_darkness_sets_the_tints_stars_and_grade() -> void:
	var bg := _background()
	var dn := DayNight.new()
	dn.sky_tint = bg.get_node("SkyTint")
	dn.stars = bg.get_node("Stars")
	dn.world_tint = CanvasModulate.new()
	add_child_autofree(dn.world_tint)
	dn.darkness_by_sun = Curve.new()
	dn.darkness_by_sun.add_point(Vector2(0.0, 0.25))
	dn.darkness_by_sun.add_point(Vector2(1.0, 0.25))
	add_child_autofree(dn)
	dn.set_sun(0.5)
	assert_almost_eq(dn.darkness, 0.25, 0.01, "from the curve")
	assert_almost_eq(dn.stars.amount, 0.25, 0.01)
	assert_eq(dn.world_tint.color, dn.day_color.lerp(dn.night_world_color, 0.25))
	assert_eq(dn.sky_tint.color, dn.day_color.lerp(dn.night_sky_color, 0.25))
	dn.set_night(true)
	await wait_seconds(dn.fade_time + 0.1)
	assert_almost_eq(dn.darkness, 0.25, 0.01, "while it follows the sun, nightfall does not override it")


func test_the_game_lights_the_world_by_the_sun() -> void:
	var game: Game = load("res://game/main.tscn").instantiate()
	add_child_autofree(game)
	game._begin()
	game._process(0.0)
	var dn: DayNight = game.get_node("%DayNight")
	var world: World = game.get_node("%World")
	assert_almost_eq(dn.darkness, clampf(dn.darkness_by_sun.sample(world.sun_progress()), 0.0, 1.0), 0.001)
