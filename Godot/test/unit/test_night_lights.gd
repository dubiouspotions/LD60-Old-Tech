extends GutTest
## Night lights (cursor lantern, engineers' lamps, camp fire) use the Mix blend mode, so where two overlap the
## brighter one wins instead of the two adding up. A Mix light pulls the ground towards energy x colour, so it
## fades from energy 1 in white (exactly daylight) rather than from 0, which would darken the ground around it.


func _night_light(night_energy: float) -> NightLight:
	var l := NightLight.new()
	l.color = Color(1, 0.8, 0.5)
	l.night_energy = night_energy
	l.texture = GradientTexture2D.new()
	add_child_autofree(l)
	return l


func test_every_night_light_blends_by_mix() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	var engineer: Node = load("res://objects/engineer/engineer.tscn").instantiate()
	var camp: Node = load("res://objects/camp/camp.tscn").instantiate()
	for l: PointLight2D in [main.get_node("Lantern"), engineer.get_node("%Lamp"), camp.get_node("%FireLight")]:
		assert_eq(l.blend_mode, Light2D.BLEND_MODE_MIX, "%s" % l.name)
	for n in [main, engineer, camp]:
		n.free()


func test_fades_in_from_daylight_never_from_dark() -> void:
	var l := _night_light(1.2)
	l.fade(false, 0.0)
	l.fade(true, 0.3)
	assert_true(l.visible)
	var lowest := INF
	for i in 30:
		await wait_frames(1)
		lowest = minf(lowest, l.energy)
	assert_gte(lowest, 1.0, "no darker than daylight on the way")
	await wait_seconds(0.35)
	assert_almost_eq(l.energy, 1.2, 0.001)
	assert_eq(l.color, Color(1, 0.8, 0.5), "its own colour at night")


func test_fades_out_to_daylight_then_goes_out() -> void:
	var l := _night_light(1.2)
	l.fade(true, 0.0)
	l.fade(false, 0.2)
	await wait_seconds(0.3)
	assert_false(l.visible)
	assert_almost_eq(l.energy, 1.0, 0.001)
	assert_eq(l.color, Color.WHITE)
	l.fade(true, 0.0)
	assert_eq(l.color, Color(1, 0.8, 0.5), "keeps its colour for the next night")


func test_striking_camp_fades_the_fire_to_daylight() -> void:
	var camp: Camp = load("res://objects/camp/camp.tscn").instantiate()
	add_child(camp)
	var light: PointLight2D = camp.get_node("%FireLight")
	camp.strike()
	var lowest := INF
	while is_instance_valid(light):
		lowest = minf(lowest, light.energy)
		await wait_frames(1)
	assert_gte(lowest, 1.0, "the fire never darkens the ground as it dies")
