@tool
class_name TerrainLook
extends Resource
## How the terrain is drawn. With enabled on, the terrain's own tiles are hidden and a TerrainSkin draws it from
## the v2 sheet instead: grass edges, fillets, water and spikes picked per cell from its neighbours, and rock
## pockets in the dirt on a half-cell dual grid. Materials with no v2 art keep their old tiles.
## Each role below lists atlas coordinates (32 px tiles) in texture. Where a role lists several tiles, each
## cell picks one by a fixed hash of its position, so the variation is stable while digging.

## Off: the old tile look.
@export var enabled: bool = true
@export var texture: Texture2D
## Colour baked into the sheet where the sky shows through; drawn as transparent.
@export var sky_key: Color = Color("64988e")
@export_range(8, 128) var tile_size: int = 32

@export_group("Materials")
## Drawn as dirt with grass where it meets the air.
@export var dirt_types: Array[TerrainType] = []
## Drawn as rock pockets inside the dirt (dual grid). At the surface they get the grass edge like dirt.
@export var rock_types: Array[TerrainType] = []
@export var water_types: Array[TerrainType] = []
@export var spike_types: Array[TerrainType] = []

@export_group("Surface (cells with air above)")
@export var flat_tops: Array[Vector2i] = []
## Air to the left (top-left) or to the right (top-right).
@export var corner_tl: Array[Vector2i] = []
@export var corner_tr: Array[Vector2i] = []

@export_group("Sides (cells with ground above)")
## Air to the left / to the right.
@export var wall_l: Array[Vector2i] = []
@export var wall_r: Array[Vector2i] = []
## Ground above and beside, but air diagonally up-left / up-right (the foot of a fillet).
@export var inner_tl: Array[Vector2i] = []
@export var inner_tr: Array[Vector2i] = []
## Ground all round. Also drawn under every v2 ground cell so nothing shows through.
@export var dirt: Array[Vector2i] = []

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

@export_group("Rock in dirt (dual grid)")
## 16 tiles indexed by which of the four cells around a corner are rock: top-left 1, top-right 2,
## bottom-left 4, bottom-right 8. (-1, -1) falls back to full rock (15). Index 0 uses dirt.
@export var body: Array[Vector2i] = []


## The tile for this cell from tiles, varied by a fixed hash of its position. (-1, -1) if tiles is empty.
static func pick(tiles: Array[Vector2i], cell: Vector2i) -> Vector2i:
	if tiles.is_empty():
		return Vector2i(-1, -1)
	var h := absi((cell.x * 73856093) ^ (cell.y * 19349663))
	return tiles[h % tiles.size()]


## Dual-grid tile for a rock mask (see body).
func body_tile(mask: int, cell: Vector2i) -> Vector2i:
	if mask == 0:
		return pick(dirt, cell)
	var t: Vector2i = body[mask] if mask < body.size() else Vector2i(-1, -1)
	return t if t.x >= 0 else body[15]
