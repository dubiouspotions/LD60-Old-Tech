extends Node2D
## Short-lived visual feedback: debris bursts, floating text, screen shake. Autoload "Effects" (effects.tscn).
## Positions are in pixels.

signal shake_requested(amount: float)
## A floating text was shown (for tests and anything that follows the texts).
signal said(text: String, at_px: Vector2)
## A particle burst was spawned: kind is &"debris" or &"sparks".
signal burst(kind: StringName, at_px: Vector2, color: Color)

## CPUParticles2D scene used for debris. Its look is edited in the scene; colour and count are set per call.
@export var debris_scene: PackedScene
## CPUParticles2D scene for sparks (metal on stone). Its look, colours included, is edited in the scene.
@export var sparks_scene: PackedScene
## Label scene that floats up and fades (see floating_text.gd).
@export var text_scene: PackedScene


func _ready() -> void:
	z_index = 50
	process_mode = Node.PROCESS_MODE_ALWAYS


func debris(at_px: Vector2, color: Color, amount: int = 4, speed_px: float = 90.0) -> void:
	if debris_scene == null or amount <= 0:
		return
	var p: CPUParticles2D = debris_scene.instantiate()
	p.amount = amount
	p.color = color
	p.initial_velocity_min = speed_px * 0.4
	p.initial_velocity_max = speed_px
	p.position = at_px
	_fire(p)
	burst.emit(&"debris", at_px, color)


## A burst of sparks at at_px, flying mostly toward direction.
func sparks(at_px: Vector2, amount: int = 6, direction: Vector2 = Vector2.UP) -> void:
	if sparks_scene == null or amount <= 0:
		return
	var p: CPUParticles2D = sparks_scene.instantiate()
	p.amount = amount
	p.direction = direction
	p.position = at_px
	_fire(p)
	burst.emit(&"sparks", at_px, Color.WHITE)


func _fire(p: CPUParticles2D) -> void:
	p.one_shot = true
	p.emitting = true
	p.finished.connect(p.queue_free)
	add_child(p)


func say(at_px: Vector2, text: String, color: Color = Color("ece4d2")) -> void:
	if text_scene == null or text.is_empty():
		return
	var label: Node2D = text_scene.instantiate()
	label.position = at_px
	add_child(label)
	label.call(&"show_text", text, color)
	said.emit(text, at_px)


func shake(amount: float) -> void:
	shake_requested.emit(amount)


func clear() -> void:
	for c in get_children():
		c.queue_free()
