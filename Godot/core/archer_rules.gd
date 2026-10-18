@tool
class_name ArcherRules
extends Resource
## Tuning shared by every enemy archer.

## Melee hits an archer takes from soldiers before it falls.
@export_range(1, 50) var hit_points: int = 3
