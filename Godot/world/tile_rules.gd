class_name TileRules
extends RefCounted
## The v2 tiling rules (see TerrainLook): which role a cell's tile plays, from the cell and its neighbours.
## type_of(cell) -> TerrainType gives each cell's material (the terrain's live types while playing, the painted
## tiles in the editor).

var look: TerrainLook
var type_of: Callable


func _init(p_look: TerrainLook, p_type_of: Callable) -> void:
	look = p_look
	type_of = p_type_of


## The role the cell's tile should play, or &"" for a cell the v2 tiles do not draw (air with no fillet, or a
## material without v2 art).
func role(cell: Vector2i) -> StringName:
	var t: TerrainType = type_of.call(cell)
	if t == null:
		return _fillet(cell)
	if t in look.water_types:
		return &"water" if type_of.call(cell + Vector2i.UP) in look.water_types else &"water_top"
	if t in look.spike_types:
		return &"spikes"
	if not look.is_ground(t):
		return &""
	var r := _ground(cell)
	if t in look.rock_types:
		return &"rock" if r == &"dirt" else StringName("rock_" + r)
	return r


## The grass role of a ground cell, or &"dirt" with ground all round.
func _ground(cell: Vector2i) -> StringName:
	var up := _solid(cell + Vector2i.UP)
	var left := _solid(cell + Vector2i.LEFT)
	var right := _solid(cell + Vector2i.RIGHT)
	if not up:
		if not left and right:
			return &"corner_tl"
		if left and not right:
			return &"corner_tr"
		return &"flat_tops"
	if not _solid(cell + Vector2i.DOWN):
		if not left and right:
			return &"ceiling_l"
		if left and not right:
			return &"ceiling_r"
		return &"ceiling"
	if not left:
		return &"wall_l"
	if not right:
		return &"wall_r"
	if not _solid(cell + Vector2i(-1, -1)):
		return &"inner_tl"
	if not _solid(cell + Vector2i(1, -1)):
		return &"inner_tr"
	if not _solid(cell + Vector2i(-1, 1)):
		return &"inner_bl"
	if not _solid(cell + Vector2i(1, 1)):
		return &"inner_br"
	return &"dirt"


## Rock in the dirt on the dual grid: the tile for the corner where cells corner to corner + (1, 1) meet,
## or (-1, -1) where any of the four is not dirt or rock, or none is rock.
func body(corner: Vector2i) -> Vector2i:
	var mask := 0
	var quad: Array[Vector2i] = [corner, corner + Vector2i.RIGHT, corner + Vector2i.DOWN, corner + Vector2i.ONE]
	for i in 4:
		var t: TerrainType = type_of.call(quad[i])
		if not look.is_ground(t):
			return Vector2i(-1, -1)
		if t in look.rock_types:
			mask |= 1 << i
	return look.body_tile(mask, corner)


## Air at the foot of a step: grass filling the corner (rock's own where the step or the ground below is rock),
## or &"".
func _fillet(cell: Vector2i) -> StringName:
	var below: TerrainType = type_of.call(cell + Vector2i.DOWN)
	if not look.is_ground(below):
		return &""
	var left: TerrainType = type_of.call(cell + Vector2i.LEFT)
	var right: TerrainType = type_of.call(cell + Vector2i.RIGHT)
	var r := &""
	var step: TerrainType = null
	if look.is_ground(right) and not look.is_ground(left):
		# The low fillet meets the rounded top-left corner of the ground below.
		r = &"fillet_r_low" if not _solid(cell + Vector2i(-1, 1)) else &"fillet_r"
		step = right
	elif look.is_ground(left) and not look.is_ground(right):
		r = &"fillet_l_low" if not _solid(cell + Vector2i(1, 1)) else &"fillet_l"
		step = left
	if r != &"" and (step in look.rock_types or below in look.rock_types):
		return StringName("rock_" + r)
	return r


func _solid(cell: Vector2i) -> bool:
	var t: TerrainType = type_of.call(cell)
	return t != null and t.solid
