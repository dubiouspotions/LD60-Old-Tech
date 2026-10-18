extends GutTest
## The night colour grade: at night the picture fades into the night LUT, except around lights (camp fire, lamps,
## the cursor lantern), which keep the day colours. The HUD is never graded.

var grade: CanvasLayer


func before_each() -> void:
	grade = load("res://post/night_grade.tscn").instantiate()
	add_child_autofree(grade)


func _light(at: Vector2, energy: float = 1.0) -> PointLight2D:
	var l := PointLight2D.new()
	var tex := GradientTexture2D.new()
	tex.width = 128
	tex.height = 128
	l.texture = tex
	l.texture_scale = 2.0
	l.energy = energy
	l.position = at
	add_child_autofree(l)
	return l


func test_grades_the_world_but_not_the_hud() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	var layer: CanvasLayer = main.get_node("NightGrade")
	assert_gt(layer.layer, 0, "above the world")
	assert_lt(layer.layer, (main.get_node("HUD") as CanvasLayer).layer, "below the HUD")
	var dn: DayNight = main.get_node("DayNight")
	assert_eq(dn.grade, layer.get_node("Grade"))
	assert_eq((dn.grade.lut as Resource).resource_path, "res://post/lut/low_17_blue_out.png")
	main.free()


func test_off_by_day_and_full_at_night() -> void:
	var dn := DayNight.new()
	dn.grade = grade.get_node("Grade")
	add_child_autofree(dn)
	assert_eq(dn.grade.amount, 0.0)
	dn.set_night(true, true)
	assert_eq(dn.grade.amount, 1.0)
	dn.set_night(false, true)
	assert_eq(dn.grade.amount, 0.0)


func test_lights_keep_the_day_colours_around_them() -> void:
	var g: NightGrade = grade.get_node("Grade")
	var l := _light(Vector2(100, 50), 0.9)
	await wait_frames(1)
	var found := g.light_spots()
	assert_eq(found.size(), 1)
	var spot: Vector4 = found[0]
	assert_almost_eq(Vector2(spot.x, spot.y), l.get_global_transform_with_canvas().origin, Vector2.ONE * 0.01)
	assert_almost_eq(spot.z, 128.0 * 2.0 / 2.0 * g.reach, 0.01, "radius: half the texture, scaled, times reach")
	assert_almost_eq(spot.w, clampf(0.9 / g.full_light_energy, 0.0, 1.0), 0.01)


func test_dark_and_hidden_lights_do_not_count() -> void:
	var g: NightGrade = grade.get_node("Grade")
	_light(Vector2(0, 0), 0.0)
	var hidden := _light(Vector2(10, 0), 1.0)
	hidden.visible = false
	await wait_frames(1)
	assert_eq(g.light_spots().size(), 0)


func test_lights_added_later_count_and_freed_ones_go() -> void:
	var g: NightGrade = grade.get_node("Grade")
	await wait_frames(1)
	var l := _light(Vector2(5, 5), 1.0)
	await wait_frames(1)
	assert_eq(g.light_spots().size(), 1, "an engineer's lamp arriving at night")
	l.free()
	await wait_frames(1)
	assert_eq(g.light_spots().size(), 0)
