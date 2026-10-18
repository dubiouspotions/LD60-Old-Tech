@tool
class_name BridgeMaterial
extends Resource
## A bridge member type (log, rope, ...). Physics units are SI: m, kg, N.

@export var display_name: String = "Log"
@export var cost: Supplies
## Shown when the player can not afford it.
@export var no_supply_text: String = "No logs. Fell a tree"

## Metres of it one engineer builds per second.
@export_range(0.05, 10.0, 0.05, "suffix:m/s") var build_speed: float = 1.6

@export_group("Physics")
@export_range(0.5, 30.0, 0.5, "suffix:m") var max_length: float = 5.0
@export_range(0.1, 100.0, 0.1, "suffix:kg/m") var kg_per_m: float = 20.0
## Stretch per newton. Lower is stiffer. Logs ~1e-7, ropes ~2e-6.
@export_range(0.0, 0.0001, 1e-9, "suffix:m/N") var compliance: float = 1e-7
@export_range(100.0, 100000.0, 100.0, "suffix:N") var break_force: float = 16000.0
## Ropes: only pull, never push.
@export var tension_only: bool = false
## New members may start or end anywhere along it, not only at its joints (logs yes, ropes no).
@export var attach_along: bool = true
## Stops arrows once built (bridges do; supports and ropes do not).
@export var blocks_arrows: bool = true
## Soldiers can walk on top of it.
@export var walkable: bool = true
## How far the middle of a 5 m member sinks with one soldier (80 kg) standing at its middle. It grows with the load
## and with the length cubed, like a real beam, so short pieces barely move. Only the look and the walking surface
## bend; the joints and breaking are not affected. 0: rigid. Ropes never flex.
@export_range(0.0, 1.0, 0.01, "suffix:m") var flex: float = 0.08

@export_group("Messages")
@export var snapped_text: String = "Log pulled apart"
## Shown when it fails pushing (only for members that take push).
@export var buckled_text: String = "Log buckled"

@export_group("Look")
@export var color: Color = Color("b07a42")
@export var edge_color: Color = Color("5c3b1c")
@export var hot_color: Color = Color("ff462d")
@export_range(0.02, 0.5, 0.01, "suffix:m") var thickness: float = 0.2
## Members with a lower layer are drawn first, behind the others. Soldiers are always in front.
@export_range(-5, 5) var draw_layer: int = 0
## Ropes sag when slack and draw dashed while being placed.
@export var draw_as_rope: bool = false

@export_group("Sound")
@export var place_sound: SoundEffect
@export var break_sound: SoundEffect
