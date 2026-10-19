extends GutTest
## Birds hide in the tall grass and burst out, once per patch, when a soldier or engineer comes too close. They
## fly up and away from whoever disturbed them. The art is a white-on-black mask tinted per bird by a shader.

const MAP: Array = [
	"..............................",
	"..............................",
	"..............................",
	"..............................",
	"##############################",
	"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
]

var world: World
var birds: Birds


func before_each() -> void:
	GameState.save_path = "user://test_sappers.cfg"
	GameState.new_campaign()
	world = load("res://game/world.tscn").instantiate()
	add_child_autofree(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.terrain.clear()
	world.terrain.rebuild()
	for y in MAP.size():
		for x in MAP[y].length():
			var key: String = WorldFixture.LEGEND[MAP[y][x]]
			if key != "":
				world.terrain.set_type(Vector2i(x, y), WorldFixture.type(key))
	# One patch of three cells at columns 14..16, standing on the ground (row 4).
	for x in range(14, 17):
		world.grass.set_cell(Vector2i(x, 3), 0, Vector2i.ZERO)
	birds = world.birds
	# Its own copy: the default settings are a shared resource.
	birds.settings = birds.settings.duplicate()
	birds.settings.chance = 1.0
	world.army.spawn(1, 2.0)


func _flying() -> Array[Bird]:
	var out: Array[Bird] = []
	for n in world.objects.get_children():
		if n is Bird and not n.is_queued_for_deletion():
			out.append(n)
	return out


func _soldier_at(x: float) -> void:
	world.army.soldiers[0].pos = Vector2(x, 4.0)
	birds.check()


func test_the_sheet_is_a_nine_frame_mask_tinted_by_a_shader() -> void:
	var bird: Bird = birds.bird_scene.instantiate()
	add_child_autofree(bird)
	var sprite: Sprite2D = bird.get_node("Sprite")
	assert_eq(sprite.texture.resource_path, "res://world/bird.png")
	assert_eq(sprite.hframes, 9)
	assert_eq(sprite.texture.get_width() / sprite.hframes * sprite.scale.x, 32.0, "frames drawn 32 px wide, like the tiles")
	assert_eq(((sprite.material as ShaderMaterial).shader as Shader).resource_path, "res://objects/bird/bird_mask.gdshader")


func test_nothing_happens_while_everyone_is_far() -> void:
	_soldier_at(5.0)
	assert_eq(_flying().size(), 0)


func test_a_soldier_coming_close_flushes_the_patch_once() -> void:
	_soldier_at(14.0 - birds.flush_distance + 0.5)
	var out := _flying()
	assert_between(out.size(), birds.settings.per_patch.x, birds.settings.per_patch.y)
	for b in out:
		assert_between(Grid.to_m(b.position).x, 14.0, 17.0, "from the patch")
	_soldier_at(15.0)
	assert_eq(_flying().size(), out.size(), "a patch only hides one flock")


func test_engineers_flush_them_too() -> void:
	world.crew.spawn(15.5)
	birds.check()
	assert_gt(_flying().size(), 0)


func test_they_fly_up_and_away_from_who_came() -> void:
	_soldier_at(13.0)
	var b: Bird = _flying()[0]
	var start := b.position
	for i in 30:
		b._physics_process(1.0 / 60.0)
	assert_gt(b.position.x, start.x, "away from the soldier on the left")
	assert_lt(b.position.y, start.y, "and up")
	assert_false((b.get_node("Sprite") as Sprite2D).flip_h, "the art faces right")
	world.army.soldiers[0].pos = Vector2(18.0, 4.0)
	var left := birds.flush(Vector2i(15, 3), Vector2(18.0, 4.0))
	assert_true(left.is_empty(), "already flushed")
	birds.forget_from(0)
	left = birds.flush(Vector2i(15, 3), Vector2(18.0, 4.0))
	assert_gt(left.size(), 0)
	for lb in left:
		assert_true((lb.get_node("Sprite") as Sprite2D).flip_h, "mirrored flying left")


func test_each_bird_gets_a_colour_from_the_palette() -> void:
	_soldier_at(13.0)
	for b in _flying():
		assert_has(birds.colors, (b.get_node("Sprite") as Sprite2D).self_modulate)


func test_they_are_gone_after_a_while() -> void:
	_soldier_at(13.0)
	var b: Bird = _flying()[0]
	for i in int((b.life + 0.1) * 60):
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			break
		b._physics_process(1.0 / 60.0)
	assert_true(not is_instance_valid(b) or b.is_queued_for_deletion())


func test_a_retried_level_has_its_birds_back() -> void:
	_soldier_at(13.0)
	birds.forget_from(10)
	for b in _flying():
		b.free()
	_soldier_at(13.0)
	assert_gt(_flying().size(), 0)


func test_flaps_start_at_random_frames() -> void:
	var frames := {}
	var rng := RandomNumberGenerator.new()
	for i in 40:
		var b: Bird = birds.bird_scene.instantiate()
		add_child_autofree(b)
		b.launch(1.0, Color.BLACK, rng)
		b._physics_process(1.0 / 60.0)
		frames[(b.get_node("Sprite") as Sprite2D).frame] = true
	assert_gt(frames.size(), 6, "any of the nine frames, so a flock does not flap in step")


func test_few_patches_hide_birds() -> void:
	var fresh: Birds = (load("res://game/world.tscn") as PackedScene).instantiate().get_node("Birds")
	assert_lte(fresh.settings.chance, 0.35, "not every patch")
	fresh.free()


## A tree at column 22: trunk on the ground, leaves on top (rows 0..1).
func _tree() -> void:
	for y in range(2, 4):
		world.terrain.set_type(Vector2i(22, y), WorldFixture.type("trunk"))
	for x in range(21, 24):
		for y in range(0, 2):
			world.terrain.set_type(Vector2i(x, y), WorldFixture.type("leaves"))


func test_felling_a_tree_sends_birds_off_its_top_both_ways() -> void:
	_tree()
	birds.settings.tree_birds = Vector2i(2, 2)
	world.terrain.fell(Vector2i(22, 3))
	var out := _flying()
	assert_between(out.size(), birds.settings.tree_birds.x, birds.settings.tree_birds.y)
	var dirs := {}
	for b in out:
		var p := Grid.to_m(b.position)
		assert_between(p.y, -0.5, 1.5, "from the top of the tree")
		assert_between(p.x, 20.5, 24.5)
		dirs[(b.get_node("Sprite") as Sprite2D).flip_h] = true
	assert_eq(dirs.size(), 2, "off in different directions")


func test_now_and_then_one_flies_across_the_view() -> void:
	var view := Rect2(0, 0, 40, 22)
	var seen: Bird = null
	for i in int(birds.cross_interval.y * 60) + 2:
		birds.advance_crossing(1.0 / 60.0, view)
		var out := _flying()
		if not out.is_empty():
			seen = out[0]
			break
	assert_not_null(seen, "within the longest wait")
	var start := Grid.to_m(seen.position)
	assert_false(view.has_point(start), "comes in from off screen")
	assert_lt(start.y, view.position.y + view.size.y * birds.cross_height + 0.01, "in the sky")
	var crossed := false
	for i in int(seen.life * 60):
		seen._physics_process(1.0 / 60.0)
		var p := Grid.to_m(seen.position)
		if (start.x < view.position.x and p.x > view.end.x) or (start.x > view.end.x and p.x < view.position.x):
			crossed = true
			break
	assert_true(crossed, "all the way across before it is gone")
	assert_almost_eq(Grid.to_m(seen.position).y, start.y, 2.0, "level flight, no climbing away")


func test_none_fly_across_during_the_night_camp() -> void:
	world.begin(0, 3)
	assert_true(world.camping())
	for i in int(birds.cross_interval.y * 60) + 2:
		birds.advance_crossing(1.0 / 60.0, Rect2(0, 0, 40, 22))
	assert_eq(_flying().size(), 0)


func test_a_tree_sends_one_or_two_off_when_felled_and_maybe_one_at_the_first_chop() -> void:
	var fresh: Birds = (load("res://game/world.tscn") as PackedScene).instantiate().get_node("Birds")
	assert_eq(fresh.settings.tree_birds, Vector2i(1, 2))
	assert_eq(fresh.settings.first_chop_birds, Vector2i(0, 1))
	fresh.free()


func test_only_the_first_chop_startles_a_bird() -> void:
	_tree()
	birds.settings.first_chop_birds = Vector2i(1, 1)
	world.crew.chopped.emit(Vector2i(22, 3))
	assert_eq(_flying().size(), 1, "the first swing")
	var b: Bird = _flying()[0]
	assert_between(Grid.to_m(b.position).y, -0.5, 1.5, "off the top of the tree")
	world.crew.chopped.emit(Vector2i(22, 3))
	world.crew.chopped.emit(Vector2i(22, 3))
	assert_eq(_flying().size(), 1, "later swings do not")
	birds.settings.tree_birds = Vector2i(1, 1)
	world.terrain.fell(Vector2i(22, 3))
	assert_eq(_flying().size(), 2, "and the fall sends its own")


func _level_birds(chance: float, per_patch: Vector2i) -> BirdSettings:
	var s := BirdSettings.new()
	s.chance = chance
	s.per_patch = per_patch
	return s


func test_a_level_can_set_its_own_birds() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	world.grass.clear()
	var c := world.place_now(0)
	var cell: Vector2i = world.grass.get_used_cells().filter(func(g: Vector2i) -> bool: return g.x >= c.seam)[0]
	assert_eq(birds.settings_at(cell.x), birds.settings, "none set: the World's default")
	c.level.birds = _level_birds(0.0, Vector2i(3, 3))
	assert_eq(birds.settings_at(cell.x), c.level.birds)
	assert_eq(birds.flush(cell, Vector2(cell.x - 3, cell.y + 1)).size(), 0, "this level hides none")
	birds.forget_from(c.seam)
	c.level.birds = _level_birds(1.0, Vector2i(2, 2))
	assert_eq(birds.flush(cell, Vector2(cell.x - 3, cell.y + 1)).size(), 2, "every patch hides two here")


func test_the_level_that_owns_a_column_decides() -> void:
	world.terrain.clear()
	world.terrain.rebuild()
	world.grass.clear()
	var first := world.place_now(0)
	var second := world.place_now(1)
	first.level.birds = _level_birds(0.1, Vector2i(1, 1))
	second.level.birds = _level_birds(0.9, Vector2i(5, 5))
	assert_eq(birds.settings_at(second.seam - 1), first.level.birds)
	assert_eq(birds.settings_at(second.seam), second.level.birds)


func test_the_default_keeps_the_old_numbers() -> void:
	var d: BirdSettings = load("res://data/bird_settings.tres")
	assert_eq(d.chance, 0.3)
	assert_eq(d.per_patch, Vector2i(1, 3))
	assert_eq(d.tree_birds, Vector2i(1, 2))
	assert_eq(d.first_chop_birds, Vector2i(0, 1))
