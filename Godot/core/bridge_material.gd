@tool
class_name BridgeMaterial
extends Resource
## A bridge member type (log, rope, ...). Physics units are SI: m, kg, N.

@export var display_name: String = "Log"
## Small hint on the tool button while this material is chosen.
@export var hint: String = ""
## What each started metre costs: a 3.2 m piece costs four times this.
@export var cost: Supplies
## Shown when the player can not afford it; %s is what is missing ("3 logs").
@export var no_supply_text: String = "%s missing. Fell a tree"

## Metres of it one engineer builds per second. Taking a built piece apart goes at the same speed.
@export_range(0.05, 10.0, 0.05, "suffix:m/s") var build_speed: float = 1.6
## The Dig tool takes a built piece of it back at once instead of marking it for the crew to take apart (ropes).
@export var dismantle_instantly: bool = false

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
## Soldiers and archers collide with it (and a fast one crushes them). Off: they pass through it, as with
## supports and ropes.
@export var solid_to_bodies: bool = true
## Its whole length (not only its ends) collides with the ground and other pieces, and falling blocks rest on it.
## Off for ropes: a rope is one straight piece, and would lie across a tower like a stiff rod.
@export var solid_along: bool = true

@export_group("Impact")
## Share of a fast hit's energy that does damage (to towers and ground): how hard the material is.
@export_range(0.0, 2.0, 0.05) var ram: float = 0.3
## Energy (J) of one fast hit against something that holds (a tower, rock) that breaks the piece. 0: never.
@export_range(0.0, 100000.0, 10.0, "suffix:J") var impact_strength: float = 1000.0

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
