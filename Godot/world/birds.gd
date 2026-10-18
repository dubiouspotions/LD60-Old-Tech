class_name Birds
extends Node
## The World's birds. Some patches of tall grass hide birds: when a soldier or engineer comes within
## flush_distance, they burst out, flying up and away from whoever came (once per patch; a level placed again, a
## retry, has its birds back). A tree coming down sends birds off its top both ways. And now and then, by day, one
## flies across the view. The first swing of the axe at a tree may startle one off it before it falls.

@export var bird_scene: PackedScene
## Metres from a patch of grass at which a soldier or engineer flushes it.
@export_range(0.5, 10.0, 0.1, "suffix:m") var flush_distance: float = 2.0
## Chance that a patch hides birds at all.
@export_range(0.0, 1.0, 0.01) var chance: float = 0.3
## How many birds a patch hides, at least and at most.
@export var per_patch: Vector2i = Vector2i(1, 3)
## How many birds fly off a felled tree, at least and at most.
@export var tree_birds: Vector2i = Vector2i(1, 2)
## How many fly off at the first swing of the axe at a tree, at least and at most.
@export var first_chop_birds: Vector2i = Vector2i(0, 1)
## Seconds between birds flying across the view, picked at random in this range. Not during the night camp.
@export var cross_interval: Vector2 = Vector2(15.0, 40.0)
## How far down the view a crossing bird flies, as a fraction of its height from the top.
@export_range(0.05, 1.0, 0.01) var cross_height: float = 0.4
## Each bird gets one of these colours (the sheet is a white mask).
@export var colors: Array[Color] = [Color("3b2f2a"), Color("5a4a3c"), Color("2b2d33"), Color("7a5236"), Color("6e6a62")]

var _flushed: Dictionary = {} # grass cell -> true
var _rng := RandomNumberGenerator.new()
var _next_cross: float = -1.0
var _chopped: Dictionary = {} # cell being felled -> true, once its first chop has been heard


func _ready() -> void:
	_rng.randomize()


func _physics_process(dt: float) -> void:
	check()
	var cam := get_viewport().get_camera_2d()
	if cam:
		var size := get_viewport().get_visible_rect().size / cam.zoom
		advance_crossing(dt, Rect2(Grid.to_m(cam.get_screen_center_position() - size / 2), Grid.to_m(size)))


## Counts down to the next bird across view (metres) and sends it when it is time. Not during the night camp.
func advance_crossing(dt: float, view: Rect2) -> void:
	var world := World.of(self)
	if world == null or world.camping() or colors.is_empty():
		_next_cross = -1.0
		return
	if _next_cross < 0.0:
		_next_cross = _rng.randf_range(cross_interval.x, cross_interval.y)
	_next_cross -= dt
	if _next_cross > 0.0:
		return
	_next_cross = _rng.randf_range(cross_interval.x, cross_interval.y)
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	var x := view.position.x - 1.0 if dir > 0.0 else view.end.x + 1.0
	var y := view.position.y + _rng.randf_range(0.05, 1.0) * view.size.y * cross_height
	var b: Bird = bird_scene.instantiate()
	b.position = Grid.to_px(Vector2(x, y))
	world.objects.add_child(b)
	b.cruise(dir, _color(), _rng, view.size.x + 3.0)


## Birds fly off the top of a tree that came down (cells: all of it), some each way.
func from_tree(cells: Array[Vector2i]) -> Array[Bird]:
	for c in cells:
		_chopped.erase(c)
	return _off_tree(cells, _rng.randi_range(tree_birds.x, tree_birds.y))


## The first swing of the axe at a tree (cell: the one being felled) may startle a bird off its top.
func chop(cell: Vector2i) -> Array[Bird]:
	var world := World.of(self)
	if world == null or _chopped.has(cell):
		return [] as Array[Bird]
	_chopped[cell] = true
	return _off_tree(world.terrain.tree_cells(cell), _rng.randi_range(first_chop_birds.x, first_chop_birds.y))


## count birds off the top of the tree made of cells, alternating directions.
func _off_tree(cells: Array[Vector2i], count: int) -> Array[Bird]:
	var out: Array[Bird] = []
	var world := World.of(self)
	if world == null or cells.is_empty() or colors.is_empty():
		return out
	var top := cells[0].y
	for c in cells:
		top = mini(top, c.y)
	var xs := cells.filter(func(c: Vector2i) -> bool: return c.y == top).map(func(c: Vector2i) -> int: return c.x)
	var centre := (float(xs.min()) + float(xs.max()) + 1.0) / 2.0
	var first := 1.0 if _rng.randf() < 0.5 else -1.0
	for i in count:
		var b: Bird = bird_scene.instantiate()
		b.position = Grid.to_px(Vector2(centre + _rng.randf_range(-0.6, 0.6), top + 0.3))
		world.objects.add_child(b)
		b.launch(first if i % 2 == 0 else -first, _color(), _rng)
		out.append(b)
	return out


## Flushes every patch a soldier or engineer has come close to.
func check() -> void:
	var world := World.of(self)
	if world == null or world.grass.get_used_cells().is_empty():
		return
	var feet: Array[Vector2] = []
	for s in world.army.soldiers:
		feet.append(s.pos)
	for e in world.crew.engineers:
		feet.append(e.pos)
	var reach := ceili(flush_distance)
	for p in feet:
		var c := Grid.cell_of(p)
		for y in range(c.y - 3, c.y + 1):
			for x in range(c.x - reach - 1, c.x + reach + 1):
				var cell := Vector2i(x, y)
				if _flushed.has(cell) or world.grass.get_cell_source_id(cell) == -1:
					continue
				var dx := maxf(0.0, maxf(cell.x - p.x, p.x - (cell.x + 1)))
				if dx < flush_distance and absf(cell.y + 1 - p.y) <= 1.5:
					flush(cell, p)


## Flushes the patch of grass around cell, away from a visitor at from (metres). Returns the birds that flew.
func flush(cell: Vector2i, from: Vector2) -> Array[Bird]:
	var world := World.of(self)
	var out: Array[Bird] = []
	if _flushed.has(cell) or world.grass.get_cell_source_id(cell) == -1:
		return out
	var patch := _patch(world.grass, cell)
	for c in patch:
		_flushed[c] = true
	if _rng.randf() >= chance or colors.is_empty():
		return out
	for i in _rng.randi_range(per_patch.x, per_patch.y):
		var c: Vector2i = patch[_rng.randi() % patch.size()]
		var b: Bird = bird_scene.instantiate()
		b.position = Grid.to_px(Vector2(c) + Vector2(_rng.randf_range(0.2, 0.8), 0.7))
		world.objects.add_child(b)
		var centre := Vector2(c) + Vector2(0.5, 1.0)
		b.launch(1.0 if centre.x >= from.x else -1.0, _color(), _rng)
		out.append(b)
	return out


## Lets the patches from column x on hide birds again (the level there is placed anew).
func forget_from(x: int) -> void:
	for c: Vector2i in _flushed.keys():
		if c.x >= x:
			_flushed.erase(c)


## Forgets the patches left of column x (unloaded).
func forget_before(x: int) -> void:
	for c: Vector2i in _flushed.keys():
		if c.x < x:
			_flushed.erase(c)


func clear() -> void:
	_flushed.clear()
	_chopped.clear()


func _color() -> Color:
	return colors[_rng.randi() % colors.size()]


## The grass cells joined to cell, diagonals included.
func _patch(grass: TileMapLayer, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [cell]
	var seen := {cell: true}
	var i := 0
	while i < out.size():
		var c := out[i]
		i += 1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := c + Vector2i(dx, dy)
				if not seen.has(n) and grass.get_cell_source_id(n) != -1:
					seen[n] = true
					out.append(n)
	return out
