extends GutTest
## Stars in the night sky: hidden by day, faded in with the night, twinkling gently, and not dimmed by the sky's
## night tint.

var bg: CanvasLayer
var stars: Stars
var tint: CanvasModulate


func before_each() -> void:
	bg = load("res://world/background/background.tscn").instantiate()
	add_child_autofree(bg)
	stars = bg.get_node("Stars")
	tint = bg.get_node("SkyTint")


func _night() -> DayNight:
	var dn := DayNight.new()
	dn.sky_tint = tint
	dn.stars = stars
	add_child_autofree(dn)
	return dn


func test_drawn_in_front_of_the_sky_and_behind_the_hills() -> void:
	assert_gt(stars.get_index(), bg.get_node("Sky").get_index())
	assert_lt(stars.get_index(), bg.get_node("RidgeFar").get_index())


func test_hidden_by_day_and_shown_at_night() -> void:
	var dn := _night()
	await wait_frames(2)
	assert_eq(stars.amount, 0.0, "no stars by day")
	dn.set_night(true, true)
	await wait_frames(2)
	assert_eq(stars.amount, 1.0)
	dn.set_night(false, true)
	await wait_frames(2)
	assert_eq(stars.amount, 0.0)


func test_the_main_scene_fades_them_with_the_night() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	var dn: DayNight = main.get_node("DayNight")
	assert_eq(dn.stars, main.get_node("Background/Stars"))
	main.free()


func test_a_fixed_starfield_in_the_upper_sky() -> void:
	assert_eq(stars.count(), stars.star_count)
	var size := Vector2(1280, 720)
	var first := stars.star_position(0, size)
	for i in stars.count():
		var p := stars.star_position(i, size)
		assert_between(p.y, 0.0, size.y * stars.sky_height, "star %d in the sky" % i)
	stars.queue_redraw()
	assert_eq(stars.star_position(0, size), first, "same sky every time")


func test_twinkles_gently_and_never_goes_out() -> void:
	stars.amount = 1.0
	var seen := []
	for step in 200:
		var b := stars.brightness(0, step * 0.05)
		assert_between(b, 1.0 - stars.twinkle_depth - 0.001, 1.001)
		seen.append(snappedf(b, 0.05))
	assert_gt(seen.max() - seen.min(), stars.twinkle_depth * 0.5, "it does twinkle")


func test_the_night_tint_does_not_dim_them() -> void:
	tint.color = Color(0.2, 0.23, 0.4)
	stars.amount = 1.0
	var c := stars.draw_color(0, 0.0)
	var shown := Color(c.r * tint.color.r, c.g * tint.color.g, c.b * tint.color.b)
	assert_almost_eq(shown.r, stars.color.r, 0.01)
	assert_almost_eq(shown.g, stars.color.g, 0.01)
	assert_almost_eq(shown.b, stars.color.b, 0.01)


func _advance(seconds: float) -> void:
	for i in int(seconds * 60):
		stars.advance(1.0 / 60.0)


func test_an_occasional_shooting_star_at_night() -> void:
	stars.set_process(false)
	stars.amount = 1.0
	var seen := 0
	for i in int(stars.shooting_interval.y * 2 * 60):
		stars.advance(1.0 / 60.0)
		seen = maxi(seen, stars.shooting())
	assert_gt(seen, 0, "at least one within two of the longest waits")
	_advance(stars.shooting_life.y + 0.1)
	assert_lte(stars.shooting(), 1, "each one burns out")


func test_no_shooting_stars_by_day() -> void:
	stars.set_process(false)
	stars.amount = 0.0
	_advance(stars.shooting_interval.y * 2)
	assert_eq(stars.shooting(), 0)


## The stars drift sideways with the camera at their Parallax share of its travel (less than the hills), and wrap
## round the screen so the sky never runs out of stars.
func test_stars_scroll_with_their_parallax_and_wrap_round() -> void:
	var size := Vector2(1280, 720)
	assert_gt(stars.parallax, 0.0, "the stars move a little")
	assert_lt(stars.parallax, (bg.get_node("Mountains") as Parallax2D).scroll_scale.x, "less than the furthest mountains")
	var still := stars.star_position(0, size, 0.0)
	var moved := stars.star_position(0, size, 100.0)
	var shift := 100.0 * Grid.PX * stars.parallax
	assert_almost_eq(fposmod(still.x - moved.x, size.x), fposmod(shift, size.x), stars.pixel + 0.01, "drifts left as the camera goes right")
	assert_eq(moved.y, still.y, "only sideways")
	for i in stars.count():
		var p := stars.star_position(i, size, 1e5)
		assert_true(p.x >= 0.0 and p.x < size.x, "star %d on screen" % i)
