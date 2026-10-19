extends GutTest
## Night lights fade out in dither pixels (DitheredLightTexture, and the night grade around them) instead of a smooth
## gradient. Their settings are one LightDither shared by both, tweakable on ValueTweaks.


func _dither(pixel_size: int, steps: int) -> LightDither:
	var d := LightDither.new()
	d.pixel_size = pixel_size
	d.steps = steps
	return d


func _texture(size: int, pixel_size: int, steps: int, dither: LightDither = null) -> DitheredLightTexture:
	var t := DitheredLightTexture.new()
	t.size = size
	t.dither = dither if dither else _dither(pixel_size, steps)
	t.rebuild()
	return t


## The night grade, running through pauses as it does under the Game.
func _grade() -> NightGrade:
	var grade: CanvasLayer = load("res://post/night_grade.tscn").instantiate()
	grade.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child_autofree(grade)
	return grade.get_node("Grade")


func _alpha(t: DitheredLightTexture, x: int, y: int) -> float:
	return t.get_image().get_pixel(x, y).a


func _alphas(t: DitheredLightTexture) -> PackedFloat32Array:
	var img := t.shown_image()
	var out := PackedFloat32Array()
	for y in img.get_height():
		for x in img.get_width():
			out.append(img.get_pixel(x, y).a)
	return out


func test_full_at_the_centre_and_clear_past_the_edge() -> void:
	var t := _texture(64, 2, 3)
	assert_eq(t.get_width(), 64)
	assert_eq(t.get_height(), 64)
	assert_gte(_alpha(t, 32, 32), 2.0 / 3.0 - 0.01, "at most one step below full next to the centre")
	assert_almost_eq(_alpha(t, 31, 31), 1.0, 0.01, "a full pixel at the centre")
	assert_almost_eq(_alpha(t, 0, 0), 0.0, 0.01)


func test_only_the_step_levels_appear() -> void:
	var t := _texture(64, 1, 3)
	var img := t.get_image()
	for y in 64:
		for x in 64:
			var a := img.get_pixel(x, y).a * 3.0
			assert_almost_eq(a, roundf(a), 0.02, "alpha %s at %d,%d is a step level" % [a / 3.0, x, y])
			if absf(a - roundf(a)) > 0.02:
				return


func test_dither_pixels_are_square_blocks() -> void:
	var t := _texture(64, 4, 1)
	var img := t.get_image()
	for y in range(0, 64, 4):
		for x in range(0, 64, 4):
			var a := img.get_pixel(x, y).a
			assert_eq(img.get_pixel(x + 3, y + 3).a, a, "block at %d,%d is one colour" % [x, y])
			if img.get_pixel(x + 3, y + 3).a != a:
				return


func test_the_fade_mixes_lit_and_dark_pixels() -> void:
	var t := _texture(64, 1, 1)
	var img := t.get_image()
	var lit := 0
	for x in range(40, 48):
		for y in range(28, 36):
			if img.get_pixel(x, y).a > 0.5:
				lit += 1
	assert_between(lit, 1, 63, "halfway out, some pixels lit and some not")


func test_size_snaps_to_whole_dither_pixels_around_the_centre() -> void:
	var t := _texture(230, 4, 3)
	assert_eq(t.get_width() % 8, 0, "an even number of dither pixels each side of the centre")


func test_switched_off_it_fades_smoothly() -> void:
	var d := _dither(4, 1)
	d.enabled = false
	var t := _texture(64, 4, 1, d)
	assert_between(_alpha(t, 46, 32), 0.2, 0.8, "partly lit halfway out, not on or off")
	assert_gt(_alpha(t, 44, 32), _alpha(t, 50, 32), "fading outwards")


func test_no_spread_gives_hard_bands() -> void:
	var d := _dither(1, 2)
	d.spread = 0.0
	var t := _texture(64, 1, 2, d)
	var img := t.get_image()
	# Along a ring every pixel is about the same distance out, so with no dither they share one level.
	var levels := {}
	for i in 16:
		var p := Vector2(32, 32) + Vector2.from_angle(TAU * i / 16.0) * 10.0
		levels[snappedf(img.get_pixel(int(p.x), int(p.y)).a, 0.01)] = true
	assert_lte(levels.size(), 2, "a ring is one band (two where it crosses a band edge)")


func test_every_dither_pattern_keeps_the_average_brightness() -> void:
	for p: int in LightDither.Pattern.values():
		if p == LightDither.Pattern.BANDS:
			continue
		var d := _dither(1, 1)
		d.pattern = p
		var sum := 0.0
		for y in 16:
			for x in 16:
				sum += d.level(0.25, Vector2i(x, y), 0)
		assert_almost_eq(sum / 256.0, 0.25, 0.06, "pattern %d" % p)


func test_bayer_4_is_the_classic_matrix() -> void:
	var d := _dither(1, 1)
	d.pattern = LightDither.Pattern.BAYER_4
	var expected := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	for i in 16:
		assert_almost_eq(d.threshold(Vector2i(i % 4, i / 4), 0), (expected[i] + 0.5) / 16.0, 0.001)


func test_animated_frames_change_the_pattern_but_not_the_reach() -> void:
	var d := _dither(1, 1)
	d.animated = true
	d.frames = 4
	d.frames_per_second = 4.0
	assert_eq(d.frame_at(0), 0)
	assert_eq(d.frame_at(250), 1)
	assert_eq(d.frame_at(1000), 0, "loops")
	var t := _texture(64, 1, 1, d)
	var first := _alphas(t)
	t.show(Vector2i.ZERO, 1)
	assert_ne(_alphas(t), first, "a different frame")
	assert_almost_eq(t.shown_image().get_pixel(0, 0).a, 0.0, 0.01)
	t.show(Vector2i.ZERO, 0)
	assert_eq(_alphas(t), first, "back to the first frame")


func test_not_animated_stays_on_frame_zero() -> void:
	assert_eq(_dither(1, 1).frame_at(12345), 0)


func test_texture_redraws_when_the_dither_changes() -> void:
	var d := _dither(1, 1)
	var t := _texture(64, 1, 1, d)
	d.pixel_size = 4
	await wait_process_frames(1)
	var img := t.get_image()
	assert_eq(img.get_pixel(40, 32).a, img.get_pixel(43, 35).a, "redrawn in 4 px blocks")


func test_night_grade_dithers_with_the_shared_settings() -> void:
	var g := _grade()
	assert_eq((g.dither as Resource).resource_path, "res://data/light_dither.tres")


func test_every_night_light_fades_in_dither_pixels_at_scale_one() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	var engineer: Node = load("res://objects/engineer/engineer.tscn").instantiate()
	var camp: Node = load("res://objects/camp/camp.tscn").instantiate()
	var sign: Node = load("res://objects/sign/sign.tscn").instantiate()
	for l: PointLight2D in [main.get_node("Lantern"), engineer.get_node("%Lamp"), camp.get_node("%FireLight"),
			sign.get_node("%Lamp")]:
		assert_is(l.texture, DitheredLightTexture, "%s" % l.name)
		assert_eq(((l.texture as DitheredLightTexture).dither as Resource).resource_path,
				"res://data/light_dither.tres", "%s shares the dither settings" % l.name)
		assert_eq(l.texture_scale, 1.0, "%s keeps its dither pixels on screen pixels" % l.name)
	for n in [main, engineer, camp, sign]:
		n.free()


func test_value_tweaks_lists_the_dither_settings() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	var tweaks: ValueTweaks = main.get_node("ValueTweaks")
	var props := tweaks.get_property_list()
	var names := props.map(func(p: Dictionary) -> String: return p.name)
	for n in ["art/light_dither/enabled", "art/light_dither/pixel_size", "art/light_dither/steps",
			"art/light_dither/pattern", "art/light_dither/spread", "art/light_dither/animated",
			"art/light_dither/frames_per_second", "art/light_dither/frames", "art/light_dither/world_space"]:
		assert_has(names, n)
	var pattern: Dictionary = props.filter(func(p: Dictionary) -> bool: return p.name == "art/light_dither/pattern")[0]
	assert_eq(pattern.hint, PROPERTY_HINT_ENUM, "the pattern is picked from a list")
	assert_string_contains(pattern.hint_string, "Bands")
	assert_eq(tweaks.get("art/light_dither/pixel_size"), tweaks.light_dither.pixel_size)
	main.free()


func test_night_grade_puts_dithered_lights_on_the_art_pixel_grid() -> void:
	var g := _grade()
	var l := PointLight2D.new()
	l.texture = _texture(64, 4, 3)
	l.position = Vector2(101, -19)
	add_child_autofree(l)
	g.amount = 1.0
	await wait_process_frames(2)
	var centre := l.to_global(l.offset)
	assert_eq(centre, centre.snapped(Vector2(4, 4)), "drawn centred on a whole art pixel")
	assert_lt(centre.distance_to(l.global_position), 4.0, "nudged by less than an art pixel")
	var spot: Vector4 = g.light_spots()[0]
	assert_almost_eq(Vector2(spot.x, spot.y), l.get_global_transform_with_canvas() * l.offset, Vector2.ONE * 0.01,
			"the grade's spot sits where the light is drawn")


func test_bands_round_without_dither() -> void:
	var d := _dither(1, 2)
	d.pattern = LightDither.Pattern.BANDS
	for x in 4:
		for y in 4:
			assert_eq(d.level(0.3, Vector2i(x, y), 0), 0.5, "0.3 rounds to the nearest of 0, 0.5, 1 everywhere")
			assert_eq(d.level(0.2, Vector2i(x, y), 0), 0.0)


func test_world_space_is_the_default() -> void:
	assert_true(LightDither.new().world_space)
	assert_true((load("res://data/light_dither.tres") as LightDither).world_space)


func test_shown_at_a_world_cell_the_pattern_moves_with_it() -> void:
	var t := _texture(64, 1, 1)
	var at_origin := _alphas(t)
	t.show(Vector2i(4, 8), 0)
	assert_eq(_alphas(t), at_origin, "a whole Bayer 4 tile over: the same picture")
	t.show(Vector2i(1, 0), 0)
	assert_ne(_alphas(t), at_origin, "one dither pixel over: the pattern shifts under the light")


func test_world_space_lights_show_the_pattern_at_their_world_cell() -> void:
	var g := _grade()
	g.dither = _dither(4, 1)
	var a := PointLight2D.new()
	var b := PointLight2D.new()
	for l: PointLight2D in [a, b]:
		l.texture = _texture(64, 4, 1, g.dither)
		add_child_autofree(l)
	var centred := (a.texture as DitheredLightTexture).shown_image().get_data()
	a.position = Vector2(100, 40)
	b.position = Vector2(104, 40)
	g.amount = 1.0
	await wait_process_frames(2)
	var ta := (a.texture as DitheredLightTexture).shown_image().get_data()
	var tb := (b.texture as DitheredLightTexture).shown_image().get_data()
	assert_ne(ta, tb, "one dither pixel apart: the pattern sits differently under each")
	g.dither.world_space = false
	await wait_process_frames(2)
	assert_eq((b.texture as DitheredLightTexture).shown_image().get_data(), centred,
			"in light space every light shows the pattern from its centre")


func test_lights_do_not_share_their_texture() -> void:
	var one: Node = load("res://objects/engineer/engineer.tscn").instantiate()
	var two: Node = load("res://objects/engineer/engineer.tscn").instantiate()
	assert_ne(one.get_node("%Lamp").texture, two.get_node("%Lamp").texture, "each lamp its own, for its own pattern")
	for path in ["res://objects/camp/camp.tscn", "res://objects/sign/sign.tscn", "res://game/main.tscn"]:
		var scene: Node = load(path).instantiate()
		for l: Node in scene.find_children("*", "PointLight2D"):
			assert_true((l as PointLight2D).texture.resource_local_to_scene, "%s %s" % [path, l.name])
		scene.free()
	one.free()
	two.free()



func test_thresholds_in_bulk_match_one_by_one() -> void:
	for p: int in LightDither.Pattern.values():
		var d := _dither(1, 1)
		d.pattern = p
		d.spread = 0.8
		d.animated = true
		var bulk := d.thresholds(Vector2i(-5, 3), 7, 4, 2)
		for i in bulk.size():
			assert_almost_eq(bulk[i], d.threshold(Vector2i(-5 + i % 7, 3 + i / 7), 2), 0.0001, "pattern %d at %d" % [p, i])
