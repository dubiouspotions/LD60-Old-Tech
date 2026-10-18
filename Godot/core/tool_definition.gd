@tool
class_name ToolDefinition
extends Resource
## One button in the tool rack. The kind decides the behaviour; everything else is tuning.

enum Kind { DIG, FILL, BUILD }

@export var kind: Kind = Kind.DIG
@export var display_name: String = "Dig"
## Small hint under the name on the button. Build tools show their material's hint instead.
@export var hint: String = ""
## Input action that selects this tool (see Project Settings > Input Map).
@export var action: StringName = &""
## Text on the button's key cap.
@export var key_label: String = ""
## Seconds between uses while the button is held. 0 = once per click.
@export_range(0.0, 1.0, 0.01, "suffix:s") var repeat_interval: float = 0.0
@export var cost: Supplies
## Shown when the player can not afford cost; %s is what is missing ("3 logs").
@export var no_supply_text: String = ""
@export var use_sound: SoundEffect

## What one use costs: the material's cost for build tools (mat, or the first), else cost. Never null.
func price(mat: BridgeMaterial = null) -> Supplies:
	if kind == Kind.BUILD:
		mat = mat if mat else bridge_material
	var c: Supplies = mat.cost if mat else cost
	return c if c else Supplies.new()


## The hint under the button's name: the material's (mat, or the first) for build tools, else hint.
func hint_for(mat: BridgeMaterial = null) -> String:
	if kind == Kind.BUILD:
		mat = mat if mat else bridge_material
		return mat.hint if mat else ""
	return hint


## Every material this tool builds, the first one first.
func materials() -> Array[BridgeMaterial]:
	var out: Array[BridgeMaterial] = []
	if bridge_material:
		out.append(bridge_material)
	out.append_array(other_materials)
	return out


@export_group("Build")
@export var bridge_material: BridgeMaterial
## More materials on the same button, picked in the material picker that shows while the tool is chosen.
@export var other_materials: Array[BridgeMaterial] = []

@export_group("Spawn")
## Scene dropped by Fill (falling block).
@export var spawn_scene: PackedScene
