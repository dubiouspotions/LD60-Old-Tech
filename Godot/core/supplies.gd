@tool
class_name Supplies
extends Resource
## A bundle of the four engineering supplies.
## Used for starting stock, checkpoint bonuses, tool and member costs, and dig/blast yields.

@export var earth: int = 0
@export var logs: int = 0
@export var rope: int = 0
@export var powder: int = 0

const KEYS: Array[StringName] = [&"earth", &"logs", &"rope", &"powder"]


static func make(p_earth: int = 0, p_logs: int = 0, p_rope: int = 0, p_powder: int = 0) -> Supplies:
	var s := Supplies.new()
	s.earth = p_earth
	s.logs = p_logs
	s.rope = p_rope
	s.powder = p_powder
	return s


func add(other: Supplies, times: int = 1) -> void:
	if other == null:
		return
	for k in KEYS:
		set(k, get(k) + other.get(k) * times)


func can_afford(cost: Supplies) -> bool:
	if cost == null:
		return true
	for k in KEYS:
		if get(k) < cost.get(k):
			return false
	return true


## Removes cost if affordable. Returns false and changes nothing otherwise.
func spend(cost: Supplies) -> bool:
	if not can_afford(cost):
		return false
	add(cost, -1)
	return true


func is_empty() -> bool:
	for k in KEYS:
		if get(k) != 0:
			return false
	return true


## "+2 logs · +1 rope". Empty string when nothing is in the bundle.
func describe() -> String:
	var parts: PackedStringArray = []
	for k in KEYS:
		var v: int = get(k)
		if v != 0:
			parts.append("%+d %s" % [v, k])
	return " · ".join(parts)


func copy() -> Supplies:
	var s := Supplies.new()
	s.add(self)
	return s
