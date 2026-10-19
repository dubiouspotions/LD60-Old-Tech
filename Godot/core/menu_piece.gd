@tool
class_name MenuPiece
extends Resource
## One piece of a bridge in the main menu's show (see MenuAct), in metres of the menu level (one tile is one metre,
## y points down). Ends snap to the half metre and join where they meet; an end touching ground is bolted down.

@export var from: Vector2
@export var to: Vector2
@export var material: BridgeMaterial
