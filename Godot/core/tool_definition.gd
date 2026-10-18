@tool
class_name ToolDefinition
extends Resource
## One button in the tool rack. The kind decides the behaviour; everything else is tuning.

enum Kind { DIG, FILL, BUILD }

@export var kind: Kind = Kind.DIG
@export var display_name: String = "Dig"
## Small hint under the name on the button.
@export var hint: String = ""
## Input action that selects this tool (see Project Settings > Input Map).
@export var action: StringName = &""
## Text on the button's key cap.
@export var key_label: String = ""
## Seconds between uses while the button is held. 0 = once per click.
@export_range(0.0, 1.0, 0.01, "suffix:s") var repeat_interval: float = 0.0
@export var cost: Supplies
@export var no_supply_text: String = ""
@export var use_sound: SoundEffect

## What one use costs: the material's cost for build tools, else cost. Never null.
func price() -> Supplies:
	var c: Supplies = bridge_material.cost if kind == Kind.BUILD and bridge_material else cost
	return c if c else Supplies.new()


@export_group("Build")
@export var bridge_material: BridgeMaterial

@export_group("Spawn")
## Scene dropped by Fill (falling block).
@export var spawn_scene: PackedScene
