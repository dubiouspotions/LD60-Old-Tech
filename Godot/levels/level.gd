class_name Level
extends Node2D
## Root of every level scene. Make a new level with Scene > New Inherited Scene > levels/level_base.tscn,
## paint the Terrain, move StartFlag and ExitFlag, and drop objects (archers, ...) under Objects.

signal exit_reached
signal army_lost

@export var display_name: String = ""
@export var music: AudioStream
## Soldiers that join when the column arrives here (not on the first level).
@export_range(0, 50) var reinforcements: int = 3
## Supplies dropped when the column arrives here (not on the first level).
@export var supply_drop: Supplies
## Scene spawned when a fill tile falls loose.
@export var falling_block_scene: PackedScene

@onready var terrain: Terrain = %Terrain
@onready var bridge: Bridge = %Bridge
@onready var army: Army = %Army
@onready var crew: Crew = %Crew
## Falling blocks, charges and arrows are added here.
@onready var objects: Node2D = %Objects
@onready var start_flag: CheckpointFlag = %StartFlag
@onready var exit_flag: CheckpointFlag = %ExitFlag

var _done: bool = false


static func of(node: Node) -> Level:
	while node and not node is Level:
		node = node.get_parent()
	return node as Level


func _ready() -> void:
	bridge.terrain = terrain
	army.terrain = terrain
	army.bridge = bridge
	crew.terrain = terrain
	crew.bridge = bridge
	crew.army = army
	terrain.tile_detached.connect(_on_tile_detached)
	terrain.collapsed.connect(func(found: Supplies, _cells: Array[Vector2i]) -> void: GameState.gain(found))
	bridge.member_broken.connect(_on_member_broken)
	army.count_changed.connect(_on_army_count)
	start_flag.reached = true


## Puts the column at the start flag. level_number is shown on the flags.
func start(soldiers: int, level_number: int) -> void:
	start_flag.label = "L%d" % level_number
	exit_flag.label = "L%d" % (level_number + 1)
	army.spawn(soldiers, start_flag.metres().x)
	crew.spawn(start_flag.metres().x)


func _physics_process(dt: float) -> void:
	if _done:
		return
	bridge.step(dt, army.bridge_loads())
	army.step(dt)
	crew.step(dt)
	var lead := army.lead()
	if lead and lead.pos.x >= exit_flag.metres().x:
		_done = true
		exit_flag.reached = true
		exit_reached.emit()


func _on_army_count(count: int) -> void:
	GameState.set_soldiers(count)
	if count == 0 and not _done:
		_done = true
		army_lost.emit()


func _on_tile_detached(cell: Vector2i, type: TerrainType) -> void:
	if falling_block_scene == null:
		return
	var block: FallingBlock = falling_block_scene.instantiate()
	block.type = type
	block.position = Grid.to_px(Vector2(cell))
	objects.add_child(block)


func _on_member_broken(member: Bridge.Member, text: String) -> void:
	Effects.say(Grid.to_px((member.a.pos + member.b.pos) / 2 - Vector2(0, 0.6)), text, Color("ff6a55"))
