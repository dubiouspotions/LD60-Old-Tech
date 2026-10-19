@tool
class_name MenuAct
extends Resource
## One round of the main menu's show (see MenuShow): a crew walks in and builds a bridge over the ravine, a column
## marches onto it, and the bridge gives way under it.

## Engineers who walk in and build it, and the soldiers who walk in with them and cross once it stands.
@export_range(1, 12) var engineers: int = 3
@export_range(1, 60) var soldiers: int = 14
## The bridge. The crew builds it outward from the ground.
@export var pieces: Array[MenuPiece] = []
## The bridge gives way once this many soldiers are on it, the front one this share of the way across...
@export_range(1, 60) var give_way_at: int = 6
@export_range(0.0, 1.0, 0.05) var give_way_past: float = 0.6
## ...by breaking these pieces (counted from 0 in Pieces), one after another this many seconds apart.
@export var breaks: PackedInt32Array = []
@export_range(0.0, 5.0, 0.05, "suffix:s") var break_stagger: float = 0.3
