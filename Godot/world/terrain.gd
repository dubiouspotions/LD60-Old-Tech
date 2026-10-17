@tool
class_name Terrain
extends TileMapLayer
## The level ground. Paint it with the TileSet; every tile's behaviour comes from the TerrainType
## in its "terrain" custom data. Cells are metres: cell (x, y) covers x..x+1, y..y+1. Empty cells are air.
## Outside the painted area: above is air, left/right/below is out_of_bounds (bedrock).
## Levels are stitched on with stamp() and dropped behind with unload_before(); min_x is the left edge.

## A fill-type tile fell loose; the level spawns a falling block for it.
signal tile_detached(cell: Vector2i, type: TerrainType)
## Structures with no ground under them fell apart, or a tree lost the ground it stood on.
signal collapsed(found: Supplies, cells: Array[Vector2i])

const CUSTOM_DATA: String = "terrain"

@export var out_of_bounds: TerrainType
@export var collapse_sound: SoundEffect
## How far around a change structures are re-checked for support.
@export_range(4, 100) var structure_search: int = 30

## Right and bottom edge in cells (from the origin).
var size: Vector2i = Vector2i.ZERO
## Left edge: columns before it are out of bounds.
var min_x: int = 0

var _types: Dictionary = {} # Vector2i -> TerrainType
var _tile_for: Dictionary = {} # TerrainType -> [source_id, atlas_coords]
var _dirty_cols: Dictionary = {} # int -> true
var _marks: Dictionary = {} # Vector2i -> dig progress 0..1


func _ready() -> void:
    rebuild()


func _process(_delta: float) -> void:
    if not Engine.is_editor_hint():
        settle()


## Re-reads every painted cell. Call after painting from code.
func rebuild() -> void:
    _types.clear()
    _tile_for.clear()
    _marks.clear()
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


## Changes one cell. null makes it air. Marks the area for settle().
func set_type(cell: Vector2i, type: TerrainType) -> void:
    if type != _types.get(cell):
        _marks.erase(cell)
    if type == null:
        _types.erase(cell)
        erase_cell(cell)
    else:
        if _tile_for.is_empty():
            _index_tileset()
        _types[cell] = type
        var tile: Array = _tile_for.get(type, [])
        if tile.is_empty():
            push_error("Terrain: no tile in the TileSet uses %s" % type.resource_path)
        else:
            set_cell(cell, tile[0], tile[1])
    if cell.x >= size.x or cell.y >= size.y:
        _update_size()
    _dirty_cols[cell.x] = true


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
    for c in _fell_group(cell):
        var t := type_at(c)
        counts[t] = counts.get(t, 0) + 1
        set_type(c, null)
        Effects.debris(cell_center_px(c), t.debris_color, 1, 70.0)
    return TerrainType.bulk_total(counts)


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


## Every tile connected to cell that fells with it.
func _fell_group(cell: Vector2i) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    var stack: Array[Vector2i] = [cell]
    var seen := {}
    while not stack.is_empty():
        var c: Vector2i = stack.pop_back()
        if seen.has(c):
            continue
        seen[c] = true
        var t := type_at(c)
        if t == null or t.dig_action != TerrainType.DigAction.FELL:
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
        var t := _read_cell(to)
        if t:
            _types[to] = t
        size = Vector2i(maxi(size.x, to.x + 1), maxi(size.y, to.y + 1))


## Removes every cell from column x on. The world then ends at x.
func clear_from(x: int) -> void:
    _erase_columns(func(cx: int) -> bool: return cx >= x)
    size.x = maxi(min_x, x)


## Removes every cell left of column x and moves the left edge there.
func unload_before(x: int) -> void:
    _erase_columns(func(cx: int) -> bool: return cx < x)
    min_x = x


func _erase_columns(hit: Callable) -> void:
    for cell in get_used_cells():
        if hit.call(cell.x):
            erase_cell(cell)
            _types.erase(cell)
    for cell: Vector2i in _marks.keys():
        if hit.call(cell.x):
            _marks.erase(cell)
    for x: int in _dirty_cols.keys():
        if hit.call(x):
            _dirty_cols.erase(x)


## Picture of the first tile in the TileSet with this terrain type, for showing it off the map (falling fill).
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
                    _types.erase(cell)
                    erase_cell(cell)
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
                Audio.play(t.dig_sound, cell_center_px(work_cell(cell)))
                collapsed.emit(fell(cell), group)


func _collapse_unsupported(xa: int, xb: int, ca: int, cb: int) -> void:
    var supported := {}
    var queue: Array[Vector2i] = []
    for cell: Vector2i in _types:
        if cell.x < xa or cell.x > xb or not _types[cell].structure:
            continue
        for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP]:
            if is_anchor(cell + d):
                supported[cell] = true
                queue.append(cell)
                break
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
    var counts := {}
    var fallen: Array[Vector2i] = []
    for cell: Vector2i in _types.keys():
        var t: TerrainType = _types[cell]
        if cell.x < ca or cell.x > cb or not t.structure or supported.has(cell):
            continue
        counts[t] = counts.get(t, 0) + 1
        fallen.append(cell)
        _types.erase(cell)
        erase_cell(cell)
        Effects.debris(cell_center_px(cell), t.debris_color, 3, 110.0)
    if fallen.is_empty():
        return
    Audio.play(collapse_sound, cell_center_px(fallen[0]))
    Effects.shake(0.25)
    collapsed.emit(TerrainType.bulk_total(counts), fallen)


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


func _index_tileset() -> void:
    if tile_set == null:
        return
    for i in tile_set.get_source_count():
        var sid := tile_set.get_source_id(i)
        var src := tile_set.get_source(sid) as TileSetAtlasSource
        if src == null:
            continue
        for t in src.get_tiles_count():
            var coords := src.get_tile_id(t)
            var type := src.get_tile_data(coords, 0).get_custom_data(CUSTOM_DATA) as TerrainType
            if type and not _tile_for.has(type):
                _tile_for[type] = [sid, coords]
