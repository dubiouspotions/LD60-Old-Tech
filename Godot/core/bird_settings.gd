@tool
class_name BirdSettings
extends Resource
## How many birds hide in the tall grass and in the trees. The World's Birds node holds the default
## (data/bird_settings.tres); a level can set its own on its root (Birds), used for its own columns.

## Chance that a patch of tall grass hides birds at all.
@export_range(0.0, 1.0, 0.01) var chance: float = 0.3
## How many birds a patch hides, at least and at most.
@export var per_patch: Vector2i = Vector2i(1, 3)
## How many birds fly off a felled tree, at least and at most.
@export var tree_birds: Vector2i = Vector2i(1, 2)
## How many fly off at the first swing of the axe at a tree, at least and at most.
@export var first_chop_birds: Vector2i = Vector2i(0, 1)
