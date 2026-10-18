@tool
class_name Terrain
extends TileMapLayer
## The level ground. Paint it with the TileSet; every tile's behaviour comes from the TerrainType
## in its "terrain" custom data. Cells are metres: cell (x, y) covers x..x+1, y..y+1. Empty cells are air.
## Outside the painted area: above is air, left/right/below is out_of_bounds (bedrock).
## Levels are stitched on with stamp() and dropped behind with unload_before(); min_x is the left edge.
## With the v2 look on, dirt, rock, water and spikes are drawn with v2 tiles (each tagged with its material) and
## the tile of every cell around a change is re-picked if it no longer fits its neighbours (see TerrainLook).

## A tile that falls (a box) lost what held it; the level spawns a falling block for it.
signal tile_detached(cell: Vector2i, type: TerrainType)
## A structure or tree broke up (razed, fell too far, landed on spikes): what it gave and its cells.
signal collapsed(found: Supplies, cells: Array[Vector2i])
## A tree is coming down, whatever brought it down: every cell of it, just before they are cleared, and its yield,
## which fell() then returns. A listener may take some of the yield out (the World drops the logs as wood).
signal felled(cells: Array[Vector2i], found: Supplies)
## A cell's material changed while playing (dug, filled, fell, collapsed).
signal cell_changed(cell: Vector2i)
## A tower or tree lost the ground under it and came out as one piece (see lift()), when drops_loose is on.
signal came_loose(tiles: Dictionary)
## A tower was razed: the row struck and anything below it broke, and the rest (tiles, lifted out as by lift())
## comes down row by row. The World drops it as a crumbling FallingPiece.
signal razed(tiles: Dictionary)

const CUSTOM_DATA: String = "terrain"
## Stands for "no material" (air tiles such as fillets) in lookups: an empty custom data value and a typed null
## are different dictionary keys.
const AIR_KEY: StringName = &"air"

@export var out_of_bounds: TerrainType
@export var collapse_sound: SoundEffect
## How the ground is drawn: v2 tiles or the old ones.
@export var look: TerrainLook
## Re-picks the tile of every cell that does not fit its neighbours, keeping those that do. Paint roughly with any
## tile of the right material, press this, then save the scene.
@export_tool_button("Retile", "Reload") var retile: Callable = retile_all
## How far around a change structures are re-checked for support.
@export_range(4, 100) var structure_search: int = 30

@export_group("Hit effect")
## A tile hit (a soldier's blow on a tower) shakes for this long and blinks once at the start.
@export_range(0.05, 2.0, 0.05, "suffix:s") var hit_time: float = 0.25
## How far it shakes, in pixels, easing off over hit_time.
@export_range(0, 16) var hit_shake: int = 3
## Its colour while it blinks (above white is brighter).
@export var hit_flash: Color = Color(2.2, 2.2, 2.2)
## Share of hit_time the blink lasts.
@export_range(0.05, 1.0, 0.05) var hit_flash_share: float = 0.35
## A hit on a tower also sends a ripple through the rest of it (with its battlements), to show the whole tower
## comes down, not one tile: how far each tile bobs up as it passes, how fast it runs, how long each bob lasts.
@export_range(0, 16) var ripple_lift: int = 2
@export_range(1.0, 100.0, 1.0, "suffix:tiles/s") var ripple_speed: float = 14.0
@export_range(0.05, 2.0, 0.05, "suffix:s") var ripple_time: float = 0.25

@export_group("Collapse effect")
## A structure breaking up (a tower razed or collapsing) throws this many chunks per cell, in its Debris Colour...
@export_range(0, 30) var collapse_rubble: int = 4
@export_range(0.0, 1000.0, 10.0, "suffix:px/s") var collapse_rubble_speed: float = 200.0
## ...and this many puffs of dust per cell, in that colour paled by collapse_dust_pale.
@export_range(0, 30) var collapse_dust: int = 3
@export_range(0.0, 1.0, 0.05) var collapse_dust_pale: float = 0.35

## Right and bottom edge in cells (from the origin).
var size: Vector2i = Vector2i.ZERO
## Left edge: columns before it are out of bounds.
var min_x: int = 0
## Set by the World, which drops towers and trees that lose their ground as FallingPieces (came_loose). Off, they
## break up where they are.
var drops_loose: bool = false

var _types: Dictionary = {} # Vector2i -> TerrainType
var _beneath: Dictionary = {} # Vector2i -> TerrainType that Refills, to come back when the cell empties
var _tile_for: Dictionary = {} # TerrainType -> [source_id, atlas_coords]
var _dirty_cols: Dictionary = {} # int -> true
var _marks: Dictionary = {} # Vector2i -> dig progress 0..1
var _siege: Dictionary = {} # Vector2i -> seconds of attack taken
## Cells changed since the last take_changes(), for anything drawing the terrain its own way (TerrainSkin).
var _changed: Dictionary = {} # Vector2i -> true
var _changed_all: bool = true
var _rules: TileRules
var _alts: Dictionary = {} # v2 atlas coords -> {TerrainType, or AIR_KEY for air: alternative id}
var _hits: Dictionary = {} # Vector2i -> seconds since it was hit
var _ripple: Dictionary = {} # Vector2i -> seconds after the latest tower hit that the ripple reaches it
var _ripple_age: float = 0.0 # seconds since the latest tower hit
var _painted: Dictionary = {} # Vector2i -> true: cells painted in the editor, re-picked around after the paint


func _ready() -> void:
	rebuild()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		settle()
		advance_hits(delta)


## The tile at cell was hit: it shakes and blinks once, and if it is part of a tower a ripple runs from it through
## the rest of the tower (see Hit effect).
func hit(cell: Vector2i) -> void:
	if get_cell_source_id(cell) == -1:
		return
	_hits[cell] = 0.0
	var t := type_at(cell)
	if t and t.structure:
		_start_ripple(cell, t)
	notify_runtime_tile_data_update()


## Seconds after the latest hit on a tower that the ripple reaches cell (0 for the tile hit), or -1 if it does not.
func ripple_delay(cell: Vector2i) -> float:
	return _ripple.get(cell, -1.0)


## Every tile of the tower cell belongs to (structure tiles joined to it and the decorations on them), by how long the
## ripple takes to get there from cell.
func _start_ripple(cell: Vector2i, t: TerrainType) -> void:
	var steps := {cell: 0}
	var queue: Array[Vector2i] = [cell]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP]:
			var n: Vector2i = c + d
			var nt := type_at(n)
			if steps.has(n) or not (_is_decoration(n) or (nt != null and (nt.structure or nt == t) and _inside(n))):
				continue
			steps[n] = steps[c] + 1
			queue.append(n)
	_ripple.clear()
	for c: Vector2i in steps:
		_ripple[c] = steps[c] / ripple_speed
	_ripple_age = 0.0


## Moves the hit tiles' shake and blink on by delta seconds.
func advance_hits(delta: float) -> void:
	if _hits.is_empty() and _ripple.is_empty():
		return
	for c: Vector2i in _hits.keys():
		_hits[c] += delta
		if _hits[c] >= hit_time:
			_hits.erase(c)
	_ripple_age += delta
	if not _ripple.is_empty() and _ripple_age > _ripple.values().max() + ripple_time:
		_ripple.clear()
	notify_runtime_tile_data_update()


## How far the tile at cell is shaken off its place now, in pixels.
func hit_offset_at(cell: Vector2i) -> Vector2i:
	if not _hits.has(cell):
		return Vector2i.ZERO
	var left: float = 1.0 - _hits[cell] / hit_time
	var r := roundi(hit_shake * left)
	return Vector2i(randi_range(-r, r), randi_range(-r, r))


## How far the ripple lifts the tile at cell now, in pixels (the tile hit shakes instead).
func ripple_offset_at(cell: Vector2i) -> Vector2i:
	if not _ripple.has(cell) or _hits.has(cell):
		return Vector2i.ZERO
	var age: float = _ripple_age - _ripple[cell]
	if age < 0.0 or age > ripple_time:
		return Vector2i.ZERO
	return Vector2i(0, -roundi(ripple_lift * sin(PI * age / ripple_time)))


## The tile at cell's colour now: hit_flash while it blinks, else white.
func hit_flash_at(cell: Vector2i) -> Color:
	return hit_flash if _hits.has(cell) and _hits[cell] < hit_time * hit_flash_share else Color.WHITE


## In the editor, the tiles around cells painted by hand are re-picked after the paint (not inside this update:
## cells set here are not drawn).
func _update_cells(coords: Array[Vector2i], _forced_cleanup: bool) -> void:
	if not Engine.is_editor_hint() or coords.is_empty():
		return
	if _painted.is_empty():
		_retile_painted_later.call_deferred()
	for c in coords:
		_painted[c] = true


func _retile_painted_later() -> void:
	var cells := _painted.keys()
	_painted.clear()
	retile_painted(cells)


func _use_tile_data_runtime_update(coords: Vector2i) -> bool:
	return _hits.has(coords) or _ripple.has(coords)


func _tile_data_runtime_update(coords: Vector2i, tile_data: TileData) -> void:
	tile_data.texture_origin -= hit_offset_at(coords) + ripple_offset_at(coords)
	tile_data.modulate = hit_flash_at(coords)


## Re-reads every painted cell. Call after painting from code.
func rebuild() -> void:
	_types.clear()
	_beneath.clear()
	_tile_for.clear()
	_marks.clear()
	_siege.clear()
	_changed.clear()
	_changed_all = true
	_alts.clear()
	_rules = null
	size = Vector2i.ZERO
	min_x = 0
	_index_tileset()
	for cell in get_used_cells():
		var t := _read_cell(cell)
		if t:
			_types[cell] = t
	_update_size()


func type_at(cell: Vector2i) -> TerrainType:
	if cell.y < 0:
		return null
	if cell.x < min_x or cell.x >= size.x or cell.y >= size.y:
		return out_of_bounds
	return _types.get(cell)


func is_solid(cell: Vector2i) -> bool:
	var t := type_at(cell)
	return t != null and t.solid


func is_anchor(cell: Vector2i) -> bool:
	var t := type_at(cell)
	return t != null and t.anchor


## Top-most solid row in column x.
func surface_row(x: int) -> int:
	for y in size.y:
		if is_solid(Vector2i(x, y)):
			return y
	return size.y


## Which way the open cell at the foot of a one-high step slopes up to the step: 1 to the right, -1 to the left,
## 0 if it is no such cell. It is walked as a slope from its floor to the step's top, like its fillet tile.
func ramp_at(cell: Vector2i) -> int:
	var t := type_at(cell)
	if (t != null and (t.solid or t.is_hazard())) or not is_solid(cell + Vector2i.DOWN):
		return 0
	for dir: int in [1, -1]:
		var step := cell + Vector2i(dir, 0)
		if is_solid(step) and not is_solid(step + Vector2i.UP) and not is_solid(cell - Vector2i(dir, 0)):
			return dir
	return 0


## Changes one cell. null makes it air, or what it took the place of if that Refills (water). Re-picks the tiles
## around it and marks the area for settle().
func set_type(cell: Vector2i, type: TerrainType) -> void:
	var old: TerrainType = _types.get(cell)
	if type == null:
		type = _beneath.get(cell)
		_beneath.erase(cell)
	elif type.refills:
		_beneath.erase(cell)
	elif old and old.refills:
		_beneath[cell] = old
	_changed[cell] = true
	if type != _types.get(cell):
		_marks.erase(cell)
		_siege.erase(cell)
	if type == null:
		_types.erase(cell)
	else:
		_types[cell] = type
		size = Vector2i(maxi(size.x, cell.x + 1), maxi(size.y, cell.y + 1))
	_dirty_cols[cell.x] = true
	_retile_around([cell])
	cell_changed.emit(cell)


## The material of the tile painted at cell, read from the tile itself (also right after painting in the editor).
func painted_type(cell: Vector2i) -> TerrainType:
	return _read_cell(cell)


## The tiling rules on this terrain's materials. painted: read them from the painted tiles (the editor) rather
## than the live types.
func rules(painted: bool = false) -> TileRules:
	if look == null:
		return null
	if painted:
		return TileRules.new(look, _painted_rule_type)
	if _rules == null:
		_rules = TileRules.new(look, _rule_type)
	return _rules


## Re-picks the tile of every cell that does not fit its neighbours, keeping those that do. In the editor the
## painted tiles are read first.
func retile_all() -> void:
	if Engine.is_editor_hint():
		rebuild()
	_retile_columns(min_x, size.x)
	if Engine.is_editor_hint():
		var editor := Engine.get_singleton(&"EditorInterface")
		if editor:
			editor.call(&"mark_scene_as_unsaved")


## Reads the painted tiles again and re-picks the tiles around cells, painted by hand (the TileMap editor does
## this as you paint).
func retile_painted(cells: Array) -> void:
	rebuild()
	_retile_around(cells)


func _v2() -> bool:
	return look != null and look.enabled and tile_set != null and tile_set.has_source(look.source_id)


func _retile_around(cells: Array) -> void:
	var todo := {}
	for c: Vector2i in cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				todo[c + Vector2i(dx, dy)] = true
	for c: Vector2i in todo:
		_retile(c)


func _retile_columns(xa: int, xb: int) -> void:
	for x in range(maxi(xa, min_x), mini(xb, size.x)):
		for y in size.y:
			_retile(Vector2i(x, y))


## Gives cell the tile its material and neighbours call for, unless its tile already fits. A tile always carries
## the cell's own material, so drawing never changes what the ground is. Water and spikes painted with any tile of
## their material are kept (they have no edges to match); dirt and rock always get the v2 tile for their place.
## A material with no old tile left in the TileSet keeps its v2 tile even with the look off.
func _retile(cell: Vector2i) -> void:
	if cell.y < 0 or cell.x < min_x or cell.x >= size.x or cell.y >= size.y:
		return
	var t: TerrainType = _types.get(cell)
	var src := get_cell_source_id(cell)
	if _is_decoration(cell):
		return
	var v2 := _v2() or (t != null and look != null and atlas_tile(t).is_empty() and tile_set.has_source(look.source_id))
	var role := rules().role(cell) if v2 and (t != null or _v2()) else &""
	if role != &"":
		if src == look.source_id and look.fits(role, get_cell_atlas_coords(cell)) and _read_cell(cell) == t:
			return
		if src == look.classic_source and _read_cell(cell) == t and not look.is_ground(t):
			return
		var coords := TerrainLook.pick(look.tiles(role), cell)
		var alt := _alt_for(coords, t)
		if alt >= 0:
			set_cell(cell, look.source_id, coords, alt)
			return
	# Air, or a material drawn with its old tile.
	if t == null:
		if src != -1:
			erase_cell(cell)
		return
	var classic: Array[Vector2i] = []
	if look:
		var wanted := look.classic_tiles(t, not is_solid(cell + Vector2i.UP), type_at(cell + Vector2i.UP) in look.water_types)
		classic.assign(wanted.filter(func(c: Vector2i) -> bool: return _old_tile_is(c, t)))
	if not classic.is_empty():
		if src != look.classic_source or not get_cell_atlas_coords(cell) in classic or _read_cell(cell) != t:
			set_cell(cell, look.classic_source, TerrainLook.pick(classic, cell))
	elif src == -1 or (look and src == look.source_id) or _read_cell(cell) != t:
		var old := atlas_tile(t)
		if not old.is_empty():
			set_cell(cell, old[0], old[1])


## Is the classic tile at coords tagged as material t.
func _old_tile_is(coords: Vector2i, t: TerrainType) -> bool:
	var src := tile_set.get_source(look.classic_source) as TileSetAtlasSource
	return src != null and src.has_tile(coords) and src.get_tile_data(coords, 0).get_custom_data(CUSTOM_DATA) == t


## Alternative id of the v2 tile at coords painted as material t, or -1 if there is none.
func _alt_for(coords: Vector2i, t: TerrainType) -> int:
	if _alts.is_empty():
		var src := tile_set.get_source(look.source_id) as TileSetAtlasSource
		for i in src.get_tiles_count():
			var c := src.get_tile_id(i)
			var by_type := {}
			for k in src.get_alternative_tiles_count(c):
				var alt := src.get_alternative_tile_id(c, k)
				var m: Variant = src.get_tile_data(c, alt).get_custom_data(CUSTOM_DATA)
				by_type[m if m != null else AIR_KEY] = alt
			_alts[c] = by_type
	return _alts.get(coords, {}).get(t if t else AIR_KEY, -1)


## The rules see past the left and right edge as more of the edge column, so a level's edges are not drawn as
## cliffs. (In the world they are re-checked when the next level is stamped on.)
func _rule_type(cell: Vector2i) -> TerrainType:
	if size.x > min_x:
		cell.x = clampi(cell.x, min_x, size.x - 1)
	return type_at(cell)


func _painted_rule_type(cell: Vector2i) -> TerrainType:
	var used := get_used_rect()
	if cell.y < 0 or used.size.x == 0:
		return null
	cell.x = clampi(cell.x, used.position.x, used.end.x - 1)
	return out_of_bounds if cell.y >= used.end.y else _read_cell(cell)


func can_dig(cell: Vector2i) -> bool:
	var t := type_at(cell)
	return t != null and t.dig_action != TerrainType.DigAction.NONE and _inside(cell)


## Marks a cell for the engineers to dig. Returns false if it can not be dug.
func mark(cell: Vector2i) -> bool:
	if not can_dig(cell):
		return false
	if not _marks.has(cell):
		_marks[cell] = 0.0
	return true


func unmark(cell: Vector2i) -> void:
	_marks.erase(cell)


func is_marked(cell: Vector2i) -> bool:
	return _marks.has(cell)


func marked_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_marks.keys())
	return out


## Share of a marked cell dug so far, 0..1.
func dig_progress(cell: Vector2i) -> float:
	return _marks.get(cell, 0.0)


func set_dig_progress(cell: Vector2i, progress: float) -> void:
	if _marks.has(cell):
		_marks[cell] = clampf(progress, 0.0, 1.0)


## Digs one cell. Returns what was gained, or null if the tile can not be dug.
func dig(cell: Vector2i) -> Supplies:
	var t := type_at(cell)
	if t == null or t.dig_action == TerrainType.DigAction.NONE or not _inside(cell):
		return null
	Audio.play(t.dig_sound, cell_center_px(cell))
	if t.dig_action == TerrainType.DigAction.FELL:
		return fell(cell)
	set_type(cell, null)
	Effects.debris(cell_center_px(cell), t.debris_color, 3, 90.0)
	var got := t.dig_yield.copy() if t.dig_yield else Supplies.new()
	return got


## Removes every connected tile that fells with this one (a whole tree). Returns the bulk yield.
func fell(cell: Vector2i) -> Supplies:
	var counts := {}
	var group := _fell_group(cell)
	for c in group:
		var t := type_at(c)
		counts[t] = counts.get(t, 0) + 1
	var found := TerrainType.bulk_total(counts)
	felled.emit(group, found)
	for c in group:
		Effects.debris(cell_center_px(c), type_at(c).debris_color, 1, 70.0)
		set_type(c, null)
	return found


## The cell engineers work on to dig this one: the base of the tree for trees, else the cell itself.
func work_cell(cell: Vector2i) -> Vector2i:
	var t := type_at(cell)
	if t == null or t.dig_action != TerrainType.DigAction.FELL:
		return cell
	var base := cell
	for c in _fell_group(cell):
		if c.y > base.y:
			base = c
	return base


## Soldiers attack cell for seconds. Returns true when that razes it: once the cell has taken its type's
## raze_time, the whole connected structure (the tower) falls. Types with raze_time 0 can not be attacked.
func besiege(cell: Vector2i, seconds: float) -> bool:
	var t := type_at(cell)
	if t == null or t.raze_time <= 0.0 or not _inside(cell):
		return false
	_siege[cell] = _siege.get(cell, 0.0) + seconds
	if _siege[cell] < t.raze_time:
		return false
	_raze(cell, _group(cell, func(c: TerrainType) -> bool: return c.structure or c == t))
	return true


## The tower made of cells is razed at cell: its row there, and anything below, is crushed under the weight above,
## and the rest comes down (razed). Without drops_loose, or with nothing above, it all breaks up at once.
func _raze(cell: Vector2i, cells: Array[Vector2i]) -> void:
	var above: Array[Vector2i] = cells.filter(func(c: Vector2i) -> bool: return c.y < cell.y)
	if above.is_empty() or not drops_loose:
		break_up(cells)
		return
	var tiles := lift(above)
	break_up(cells.filter(func(c: Vector2i) -> bool: return c.y >= cell.y))
	razed.emit(tiles)


## Share of a besieged cell's raze_time taken so far, 0..1.
func siege_progress(cell: Vector2i) -> float:
	var t := type_at(cell)
	return clampf(_siege.get(cell, 0.0) / t.raze_time, 0.0, 1.0) if t and t.raze_time > 0.0 else 0.0


func besieged_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_siege.keys())
	return out


## Every tile connected to cell that fells with it.
## Every cell of the tree that cell belongs to (trunk and leaves), or [] if it is not a tree.
func tree_cells(cell: Vector2i) -> Array[Vector2i]:
	var t := type_at(cell)
	if t == null or t.dig_action != TerrainType.DigAction.FELL:
		return []
	return _fell_group(cell)


func _fell_group(cell: Vector2i) -> Array[Vector2i]:
	return _group(cell, func(t: TerrainType) -> bool: return t.dig_action == TerrainType.DigAction.FELL)


## Every tile connected to cell (itself included) whose type passes test.
func _group(cell: Vector2i, test: Callable) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var stack: Array[Vector2i] = [cell]
	var seen := {}
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if seen.has(c):
			continue
		seen[c] = true
		var t := type_at(c)
		if t == null or not _inside(c) or not test.call(t):
			continue
		out.append(c)
		stack.append_array([c + Vector2i.RIGHT, c + Vector2i.LEFT, c + Vector2i.DOWN, c + Vector2i.UP])
	return out


## Detaches unsupported falling tiles and collapses unsupported structures near recent changes.
func settle() -> void:
	if _dirty_cols.is_empty():
		return
	var xs: Array = _dirty_cols.keys()
	xs.sort()
	_dirty_cols.clear()
	_detach_loose(xs)
	_fell_unstanding(xs)
	# group nearby columns so one flood fill covers each cluster
	var a: int = xs[0]
	var b: int = xs[0]
	for i in range(1, xs.size() + 1):
		if i < xs.size() and xs[i] - b <= 20:
			b = xs[i]
			continue
		_collapse_unsupported(a - structure_search, b + structure_search, a - structure_search / 2, b + structure_search / 2)
		if i < xs.size():
			a = xs[i]
			b = xs[i]


## Copies the painted cells of src whose column, moved by offset, is seam or later. Everything from seam on is
## replaced, so the stamped level becomes the right end of the world.
func stamp(src: TileMapLayer, offset: Vector2i, seam: int) -> void:
	clear_from(seam)
	for cell in src.get_used_cells():
		var to := cell + offset
		if to.x < seam:
			continue
		set_cell(to, src.get_cell_source_id(cell), src.get_cell_atlas_coords(cell), src.get_cell_alternative_tile(cell))
		_changed[to] = true
		var t := _read_cell(to)
		if t:
			_types[to] = t
		size = Vector2i(maxi(size.x, to.x + 1), maxi(size.y, to.y + 1))
	_retile_columns(seam - 1, size.x)


## Removes every cell from column x on. The world then ends at x.
func clear_from(x: int) -> void:
	_erase_columns(func(cx: int) -> bool: return cx >= x)
	size.x = maxi(min_x, x)
	_retile_columns(x - 1, x)


## Removes every cell left of column x and moves the left edge there.
func unload_before(x: int) -> void:
	_erase_columns(func(cx: int) -> bool: return cx < x)
	min_x = x
	_retile_columns(x, x + 1)


func _erase_columns(hit: Callable) -> void:
	for cell in get_used_cells():
		if hit.call(cell.x):
			erase_cell(cell)
			_types.erase(cell)
			_beneath.erase(cell)
			_changed[cell] = true
	for cell: Vector2i in _marks.keys():
		if hit.call(cell.x):
			_marks.erase(cell)
	for x: int in _dirty_cols.keys():
		if hit.call(x):
			_dirty_cols.erase(x)


## Cells changed since the last call, and whether everything changed (a rebuild). {all: bool, cells: Array}.
func take_changes() -> Dictionary:
	var out := {all = _changed_all, cells = _changed.keys()}
	_changed.clear()
	_changed_all = false
	return out


## [source_id, atlas_coords] of the first tile in the TileSet with this terrain type, or [] if none.
func atlas_tile(type: TerrainType) -> Array:
	if _tile_for.is_empty():
		_index_tileset()
	return _tile_for.get(type, [])


## Picture of the first tile in the TileSet with this terrain type, for showing it off the map (a falling box).
func tile_texture(type: TerrainType) -> Texture2D:
	if _tile_for.is_empty():
		_index_tileset()
	var tile: Array = _tile_for.get(type, [])
	if tile.is_empty():
		return null
	var src := tile_set.get_source(tile[0]) as TileSetAtlasSource
	var tex := AtlasTexture.new()
	tex.atlas = src.texture
	tex.region = Rect2(src.get_tile_texture_region(tile[1]))
	return tex


func cell_center_px(cell: Vector2i) -> Vector2:
	return Grid.to_px(Vector2(cell) + Vector2(0.5, 0.5))


## Splashes if something whose lowest point moved from a to b (metres), falling at vy m/s, went into a liquid
## (a type with a Splash Amount) from out of it: at the liquid's surface above b, unless slower than Splash Speed.
func splash(a: Vector2, b: Vector2, vy: float) -> void:
	var cell := Grid.cell_of(b)
	var t := type_at(cell)
	if t == null or t.splash_amount <= 0 or vy < t.splash_speed or type_at(Grid.cell_of(a)) == t:
		return
	while cell.y > 0 and type_at(cell + Vector2i.UP) == t:
		cell += Vector2i.UP
	var at := Grid.to_px(Vector2(b.x, cell.y))
	Effects.splash(at, t.debris_color, t.splash_amount)
	Audio.play(t.splash_sound, at)


func _detach_loose(xs: Array) -> void:
	var seen := {}
	for x: int in xs:
		for xx in range(x - 1, x + 2):
			if seen.has(xx):
				continue
			seen[xx] = true
			for y in range(size.y - 2, -1, -1):
				var cell := Vector2i(xx, y)
				var t := type_at(cell)
				if t and t.falls and not is_solid(cell + Vector2i.DOWN) and _inside(cell):
					set_type(cell, null)
					tile_detached.emit(cell, t)


## Fells trees near the changed columns that no longer stand on anything solid. Gives the same yield as cutting.
func _fell_unstanding(xs: Array) -> void:
	var seen := {}
	for x: int in xs:
		for xx in range(x - 1, x + 2):
			for y in size.y:
				var cell := Vector2i(xx, y)
				var t := type_at(cell)
				if seen.has(cell) or t == null or t.dig_action != TerrainType.DigAction.FELL:
					continue
				var group := _fell_group(cell)
				for c in group:
					seen[c] = true
				if group.any(func(c: Vector2i) -> bool: return is_solid(c + Vector2i.DOWN)):
					continue
				_loosen(group)


func _collapse_unsupported(xa: int, xb: int, ca: int, cb: int) -> void:
	var supported := {}
	var queue: Array[Vector2i] = []
	for cell: Vector2i in _types:
		# Only ground under a structure holds it up; ground beside or above it does not.
		if cell.x >= xa and cell.x <= xb and _types[cell].structure and is_anchor(cell + Vector2i.DOWN):
			supported[cell] = true
			queue.append(cell)
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP]:
			var n: Vector2i = cell + d
			if n.x < xa or n.x > xb or supported.has(n):
				continue
			var t: TerrainType = _types.get(n)
			if t and t.structure:
				supported[n] = true
				queue.append(n)
	var loose := {}
	for cell: Vector2i in _types:
		if cell.x >= ca and cell.x <= cb and _types[cell].structure and not supported.has(cell):
			loose[cell] = true
	for cell: Vector2i in loose.keys():
		if not loose.has(cell):
			continue
		var group := _group(cell, func(t: TerrainType) -> bool: return t.structure).filter(
			func(c: Vector2i) -> bool: return loose.has(c))
		for c: Vector2i in group:
			loose.erase(c)
		var piece: Array[Vector2i] = []
		piece.assign(group)
		_loosen(piece)


## Lets a tower or tree that lost its ground fall as one piece (came_loose). One resting on something solid that
## does not hold it, or with nobody to drop it (drops_loose off), breaks up where it is.
func _loosen(cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	var resting := cells.any(func(c: Vector2i) -> bool: return is_solid(c + Vector2i.DOWN) and not c + Vector2i.DOWN in cells)
	if resting or not drops_loose:
		break_up(cells)
	else:
		came_loose.emit(lift(cells))


## Breaks a tower or tree apart: a tree is felled, a structure collapses into debris. Either gives its bulk yield
## (collapsed).
func break_up(cells: Array[Vector2i]) -> void:
	# Its battlements and the like come down with it.
	var decorations := decorations_on(cells)
	for c in decorations:
		erase_cell(c)
	var first := type_at(cells[0])
	if first.dig_action == TerrainType.DigAction.FELL:
		Audio.play(first.dig_sound, cell_center_px(work_cell(cells[0])))
		collapsed.emit(fell(cells[0]), cells)
		return
	var counts := {}
	for cell in cells:
		var t := type_at(cell)
		counts[t] = counts.get(t, 0) + 1
		set_type(cell, null)
		Effects.rubble(cell_center_px(cell), t.debris_color, collapse_rubble, collapse_rubble_speed)
		Effects.dust(cell_center_px(cell), t.debris_color.lerp(Color(0.85, 0.8, 0.72), collapse_dust_pale), collapse_dust)
	for cell in decorations:
		Effects.debris(cell_center_px(cell), first.debris_color, 2, 110.0)
	Audio.play(collapse_sound, cell_center_px(cells[0]))
	Effects.shake(0.25)
	collapsed.emit(TerrainType.bulk_total(counts), cells)


## Takes cells out of the ground with their tiles, dig marks and siege, and the decorations painted on and around
## them (battlements): cell -> {type (null for a decoration), source, coords, alt, mark, siege}. put() sets them back.
func lift(cells: Array[Vector2i]) -> Dictionary:
	var tiles := {}
	for c in cells + decorations_on(cells):
		tiles[c] = {type = type_at(c), source = get_cell_source_id(c), coords = get_cell_atlas_coords(c),
			alt = get_cell_alternative_tile(c), mark = _marks.get(c), siege = _siege.get(c)}
	for c: Vector2i in tiles:
		if tiles[c].type == null:
			erase_cell(c)
		else:
			set_type(c, null)
	return tiles


## The decorations (battlements and other tiles painted in the air) joined to cells, directly or through each other.
func decorations_on(cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {}
	var todo: Array[Vector2i] = cells.duplicate()
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP]:
			var n: Vector2i = c + d
			if not seen.has(n) and _is_decoration(n):
				seen[n] = true
				out.append(n)
				todo.append(n)
	return out


## Sets lifted tiles back down rows lower, each with the very tile it had. Returns the ground cells they now fill
## (not the decorations).
func put(tiles: Dictionary, rows: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in tiles:
		var tile: Dictionary = tiles[c]
		var at := c + Vector2i(0, rows)
		if tile.type == null:
			set_cell(at, tile.source, tile.coords, tile.alt)
			continue
		set_type(at, tile.type)
		if tile.source != -1:
			set_cell(at, tile.source, tile.coords, tile.alt)
		if tile.mark != null:
			_marks[at] = tile.mark
		if tile.siege != null:
			_siege[at] = tile.siege
		out.append(at)
	return out


## An old tile with no material painted in the air: a designer's decoration, never re-picked.
func _is_decoration(cell: Vector2i) -> bool:
	return type_at(cell) == null and look != null and get_cell_source_id(cell) == look.classic_source and _read_cell(cell) == null


func _inside(cell: Vector2i) -> bool:
	return cell.x >= min_x and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func _update_size() -> void:
	# Only grows: digging the last tile of a column must not move the level edge.
	var r := get_used_rect()
	size = Vector2i(maxi(size.x, r.end.x), maxi(size.y, r.end.y))


func _read_cell(cell: Vector2i) -> TerrainType:
	var data := get_cell_tile_data(cell)
	if data == null:
		return null
	return data.get_custom_data(CUSTOM_DATA) as TerrainType


## Indexes each material's old tile: from the classic atlas first, then from any other source (a new material's own
## atlas). Materials the v2 tiles draw are left to them.
func _index_tileset() -> void:
	if tile_set == null:
		return
	var sources: Array[int] = []
	for i in tile_set.get_source_count():
		sources.append(tile_set.get_source_id(i))
	if look:
		sources.erase(look.source_id)
		if sources.has(look.classic_source):
			sources.erase(look.classic_source)
			sources.push_front(look.classic_source)
	var v2_types := _types_in(look.source_id) if look else {}
	for sid in sources:
		var src := tile_set.get_source(sid) as TileSetAtlasSource
		if src == null:
			continue
		for t in src.get_tiles_count():
			var coords := src.get_tile_id(t)
			var type := src.get_tile_data(coords, 0).get_custom_data(CUSTOM_DATA) as TerrainType
			if type and not _tile_for.has(type) and (not v2_types.has(type) or sid == look.classic_source):
				_tile_for[type] = [sid, coords]


## The materials the source's tiles (all alternatives) are tagged with, as a set.
func _types_in(sid: int) -> Dictionary:
	var out := {}
	var src := tile_set.get_source(sid) as TileSetAtlasSource if tile_set.has_source(sid) else null
	if src == null:
		return out
	for t in src.get_tiles_count():
		var coords := src.get_tile_id(t)
		for k in src.get_alternative_tiles_count(coords):
			var type := src.get_tile_data(coords, src.get_alternative_tile_id(coords, k)).get_custom_data(CUSTOM_DATA) as TerrainType
			if type:
				out[type] = true
	return out
