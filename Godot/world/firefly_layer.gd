class_name FireflyLayer
extends Node2D
## Holds the levels' Fireflies swarms while they are in the World. Sits on a CanvasLayer above the night grade (with
## Follow Viewport on), so they keep their own glow. DayNight sets night, and every swarm here follows it.

## 0 by day, 1 at night. DayNight sets this.
var night: float = 0.0:
	set(v):
		night = v
		for f in get_children():
			if f is Fireflies:
				f.night = v


func _ready() -> void:
	child_entered_tree.connect(func(n: Node) -> void:
		if n is Fireflies:
			n.night = night)
