@tool
class_name TerrainLook
extends Resource
## How the terrain is drawn. With enabled on, dirt, rock, water and spikes are painted with the v2 tiles: atlas
## source source_id of the terrain TileSet, built from texture by dev/build_tiles_v2.gd. Every v2 tile carries its
## material, so painting one sets the ground too. Where the ground changes (digging, levels stitched on, Retile),
## the Terrain re-picks only the cells whose tile no longer fits its neighbours, using the roles below. The rock in
## the dirt is an overlay drawn by TerrainSkin on a half-cell dual grid (body). Off: every cell gets its material's
## old tile and no overlay is drawn.
## Each role lists atlas coordinates (tile_size px). Where a role lists several tiles, a cell that needs a new one
## picks by a fixed hash of its position. The *_alt lists are valid when painted by hand but never picked.

## Off: the old tile look.
@export var enabled: bool = true
## The v2 sheet as used in the TileSet, sky transparent.
@export var texture: Texture2D
## The artist's sheet. If its sky is a colour (sky_key) rather than transparent, dev/build_tiles_v2.tscn -- art
## writes texture from it with that colour cut out. Same file as texture when the sheet is already transparent.
@export var source_texture: Texture2D
## Colour baked into source_texture where the sky shows through.
@export var sky_key: Color = Color("64988e")
@export_range(8, 128) var tile_size: int = 32
## Atlas source id of the v2 tiles in the terrain TileSet.
@export var source_id: int = 1

@export_group("Materials")
## Drawn as dirt with grass where it meets the air.
@export var dirt_types: Array[TerrainType] = []
## Drawn as rock deep in the ground, with the dual-grid overlay where it meets dirt. At the surface they get the
## grass edge like dirt (the sheet has no bare rock edges).
@export var rock_types: Array[TerrainType] = []
@export var water_types: Array[TerrainType] = []
@export var spike_types: Array[TerrainType] = []

@export_group("Surface (cells with air above)")
@export var flat_tops: Array[Vector2i] = []
## Air to the left (top-left) or to the right (top-right).
@export var corner_tl: Array[Vector2i] = []
@export var corner_tr: Array[Vector2i] = []
## Square corners: valid when painted, never picked.
@export var corner_tl_alt: Array[Vector2i] = []
@export var corner_tr_alt: Array[Vector2i] = []

@export_group("Sides (cells with ground above)")
## Air to the left / to the right.
@export var wall_l: Array[Vector2i] = []
@export var wall_r: Array[Vector2i] = []
## Ground above and beside, but air diagonally up-left / up-right (the foot of a fillet).
@export var inner_tl: Array[Vector2i] = []
@export var inner_tr: Array[Vector2i] = []
## Ground below and beside, but air diagonally down-left / down-right (where a ceiling meets a wall).
@export var inner_bl: Array[Vector2i] = []
@export var inner_br: Array[Vector2i] = []
## Dirt with ground all round.
@export var dirt: Array[Vector2i] = []
## Rock with ground all round.
@export var rock: Array[Vector2i] = []

@export_group("Ceilings (cells with air below)")
@export var ceiling: Array[Vector2i] = []
## Air below and to the left / to the right.
@export var ceiling_l: Array[Vector2i] = []
@export var ceiling_r: Array[Vector2i] = []

@export_group("Fillets (air cells at the foot of a step)")
## Ground below and to the right. The low one is used when the ground below is a top-left corner.
@export var fillet_r: Array[Vector2i] = []
@export var fillet_r_low: Array[Vector2i] = []
## Ground below and to the left. The low one is used when the ground below is a top-right corner.
@export var fillet_l: Array[Vector2i] = []
@export var fillet_l_low: Array[Vector2i] = []

@export_group("Water and spikes")
## Water with air above, and deeper water.
@export var water_top: Array[Vector2i] = []
@export var water: Array[Vector2i] = []
@export var spikes: Array[Vector2i] = []

@export_group("Classic look (when off)")
## Atlas source of the old tiles, and which of them the classic look uses. Soil gets grass where it meets the air.
@export var classic_source: int = 0
@export var classic_dirt: Array[Vector2i] = []
@export var classic_grass: Array[Vector2i] = []
@export var classic_rock: Array[Vector2i] = []
@export var classic_water_top: Array[Vector2i] = []
@export var classic_water: Array[Vector2i] = []

@export_group("Rock in dirt (dual grid)")
## 16 tiles indexed by which of the four cells around a corner are rock: top-left 1, top-right 2,
## bottom-left 4, bottom-right 8. (-1, -1) falls back to full rock (15). 0 (no rock) draws nothing.
@export var body: Array[Vector2i] = []

## Roles with grass/dirt art, painted for any dirt or rock material.
const GROUND_ROLES: Array[StringName] = [&"flat_tops", &"corner_tl", &"corner_tr", &"wall_l", &"wall_r",
	&"inner_tl", &"inner_tr", &"inner_bl", &"inner_br", &"ceiling", &"ceiling_l", &"ceiling_r", &"dirt"]
const FILLET_ROLES: Array[StringName] = [&"fillet_r", &"fillet_r_low", &"fillet_l", &"fillet_l_low"]
## Every cell role: the TileSet source gets one tile per listed coordinate.
const CELL_ROLES: Array[StringName] = [&"flat_tops", &"corner_tl", &"corner_tr", &"corner_tl_alt", &"corner_tr_alt",
	&"wall_l", &"wall_r", &"inner_tl", &"inner_tr", &"inner_bl", &"inner_br", &"ceiling", &"ceiling_l", &"ceiling_r",
	&"dirt", &"rock", &"fillet_r", &"fillet_r_low", &"fillet_l", &"fillet_l_low", &"water_top", &"water", &"spikes"]

var _role_of: Dictionary = {}


## The tile for this cell from tiles, varied by a fixed hash of its position. (-1, -1) if tiles is empty.
static func pick(tiles: Array[Vector2i], cell: Vector2i) -> Vector2i:
	if tiles.is_empty():
		return Vector2i(-1, -1)
	var h := absi((cell.x * 73856093) ^ (cell.y * 19349663))
	return tiles[h % tiles.size()]


## Dual-grid tile for a rock mask (see body) at corner, or (-1, -1) for none. All rock (15) varies over the rock
## tiles, so solid rock is not one repeated tile.
func body_tile(mask: int, corner: Vector2i = Vector2i.ZERO) -> Vector2i:
	if mask == 0:
		return Vector2i(-1, -1)
	if mask == 15 and not rock.is_empty():
		return pick(rock, corner)
	var t: Vector2i = body[mask] if mask < body.size() else Vector2i(-1, -1)
	return t if t.x >= 0 else body_tile(15, corner)


## Tiles a cell of role may be given when it needs a new one.
func tiles(role: StringName) -> Array[Vector2i]:
	return get(role)


## The role a v2 tile plays (an *_alt tile plays its base role), or &"" if it is not a cell tile.
func role_of(coords: Vector2i) -> StringName:
	if _role_of.is_empty():
		for role in CELL_ROLES:
			for c: Vector2i in get(role):
				_role_of[c] = StringName(String(role).trim_suffix("_alt"))
	return _role_of.get(coords, &"")


## Materials a tile of role can be painted as. Fillets are air: [null].
func materials(role: StringName) -> Array:
	var base := StringName(String(role).trim_suffix("_alt"))
	if base in GROUND_ROLES:
		return dirt_types + rock_types
	if base == &"rock":
		return rock_types.duplicate()
	if base in [&"water_top", &"water"]:
		return water_types.duplicate()
	if base == &"spikes":
		return spike_types.duplicate()
	return [null]


## The classic (old) tiles for a cell of material t, or [] to use the material's first old tile.
## exposed: nothing solid above. under_water: water above.
func classic_tiles(t: TerrainType, exposed: bool, under_water: bool) -> Array[Vector2i]:
	if t in dirt_types:
		return classic_grass if exposed else classic_dirt
	if t in rock_types and t == rock_types[0]:
		return classic_rock
	if t in water_types:
		return classic_water if under_water else classic_water_top
	return []


## The look's materials: drawn with v2 tiles.
func draws(type: TerrainType) -> bool:
	return type != null and (type in dirt_types or type in rock_types or type in water_types or type in spike_types)


func is_ground(type: TerrainType) -> bool:
	return type != null and (type in dirt_types or type in rock_types)
