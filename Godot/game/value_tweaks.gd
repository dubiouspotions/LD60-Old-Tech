@tool
class_name ValueTweaks
extends Node
## One Inspector panel for balancing the game. Select this node in the main scene and tweak the values listed
## under it: prices, yields, starting and checkpoint supplies, army and crew size, health, mutiny time.
## Nothing is stored here. Every value is a live view of the resource that owns it (the campaign, the army,
## crew and archer rules, the tools and the terrain types): editing it here changes and saves that resource,
## and editing the resource directly shows up here. There is no undo for edits made here.
## A new tool or terrain type that has a cost or a yield shows up on its own.

## Where starting supplies, checkpoint supplies, the army rules and the tools come from.
@export var campaign: Campaign:
	set(v):
		campaign = v
		notify_property_list_changed()
@export var crew_rules: CrewRules:
	set(v):
		crew_rules = v
		notify_property_list_changed()
@export var archer_rules: ArcherRules:
	set(v):
		archer_rules = v
		notify_property_list_changed()
## Terrain types whose dig and fell yields are listed.
@export var terrain_types: Array[TerrainType] = []:
	set(v):
		terrain_types = v
		notify_property_list_changed()


## One tweakable value: where it lives and which resource file to save when it changes.
class Entry:
	var target: Object
	var property: StringName
	## Resource saved after an edit in the editor (the target, or the resource that holds it).
	var owner: Resource
	var hint: String

	func _init(p_target: Object, p_property: StringName, p_owner: Resource, p_hint: String) -> void:
		target = p_target
		property = p_property
		owner = p_owner
		hint = p_hint


const COUNT_HINT: String = "0,999,1,or_greater"


func _get_property_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var entries := _entries()
	for n: String in entries:
		var e: Entry = entries[n]
		var value: Variant = e.target.get(e.property)
		out.append({
			name = n,
			type = typeof(value),
			hint = PROPERTY_HINT_RANGE,
			hint_string = e.hint,
			usage = PROPERTY_USAGE_EDITOR,
		})
	return out


func _get(property: StringName) -> Variant:
	var e: Entry = _entries().get(String(property))
	return e.target.get(e.property) if e else null


func _set(property: StringName, value: Variant) -> bool:
	var e: Entry = _entries().get(String(property))
	if e == null:
		return false
	e.target.set(e.property, value)
	if Engine.is_editor_hint() and not e.owner.resource_path.is_empty():
		ResourceSaver.save(e.owner)
	return true


## path -> Entry, in Inspector order.
func _entries() -> Dictionary:
	var out := {}
	if campaign:
		var army := campaign.army_rules
		out["army/start_soldiers"] = Entry.new(campaign, &"start_soldiers", campaign, "1,200,1")
		if army:
			out["army/soldier_hit_points"] = Entry.new(army, &"hit_points", army, "1,10,1")
			out["army/mutiny_time"] = Entry.new(army, &"mutiny_time", army, "0,60,0.5,suffix:s")
			_supplies(out, "army/recruit_cost", army, &"recruit_cost", army)
	if crew_rules:
		out["crew/engineers"] = Entry.new(crew_rules, &"crew_size", crew_rules, "1,12,1")
	if archer_rules:
		out["enemies/archer_hit_points"] = Entry.new(archer_rules, &"hit_points", archer_rules, "1,50,1")
	if campaign:
		_supplies(out, "supplies/start", campaign, &"start_supplies", campaign)
		_supplies(out, "supplies/checkpoint", campaign, &"checkpoint_supplies", campaign)
		for t: ToolDefinition in campaign.tools:
			var mat := t.bridge_material if t.kind == ToolDefinition.Kind.BUILD else null
			if mat:
				_supplies(out, "prices/" + _slug(t.display_name), mat, &"cost", mat)
			elif t.cost:
				_supplies(out, "prices/" + _slug(t.display_name), t, &"cost", t)
	for tt: TerrainType in terrain_types:
		if tt == null:
			continue
		var base := "yields/" + _slug(tt.display_name)
		match tt.dig_action:
			TerrainType.DigAction.REMOVE:
				_supplies(out, base + "/dig", tt, &"dig_yield", tt)
			TerrainType.DigAction.FELL:
				_supplies(out, base + "/fell", tt, &"bulk_yield", tt)
				_supplies(out, base + "/fell_bonus", tt, &"bulk_bonus", tt)
	return out


## One entry per supply (earth, logs, ...) of the Supplies in holder.property. A missing bundle is created
## so it can be tweaked.
func _supplies(out: Dictionary, path: String, holder: Object, property: StringName, owner: Resource) -> void:
	var s: Supplies = holder.get(property)
	if s == null:
		s = Supplies.new()
		holder.set(property, s)
	for k in Supplies.KEYS:
		out["%s/%s" % [path, k]] = Entry.new(s, k, owner, COUNT_HINT)


static func _slug(display_name: String) -> String:
	return display_name.to_lower().replace(" ", "_")
