extends Node2D
## Short-lived visual feedback: debris bursts, floating text, screen shake. Autoload "Effects" (effects.tscn).
## Positions are in pixels.

signal shake_requested(amount: float)
## A floating text was shown (for tests and anything that follows the texts).
signal said(text: String, at_px: Vector2)
## A particle burst was spawned: kind is &"debris", &"sparks", &"rubble", &"dust" or &"splash".
signal burst(kind: StringName, at_px: Vector2, color: Color)

## CPUParticles2D scene used for debris. Its look is edited in the scene; colour and count are set per call.
@export var debris_scene: PackedScene
## CPUParticles2D scene for sparks (metal on stone). Its look, colours included, is edited in the scene.
@export var sparks_scene: PackedScene
## CPUParticles2D scenes for a structure breaking up: heavy chunks of it, and a cloud of its dust.
@export var rubble_scene: PackedScene
@export var dust_scene: PackedScene
## CPUParticles2D scene for drops thrown up where something falls into water, and how much paler (toward white) the
## drops are than the water.
@export var splash_scene: PackedScene
@export_range(0.0, 1.0, 0.05) var splash_pale: float = 0.45
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


## Heavy chunks of color flying out of at_px (a structure breaking up).
func rubble(at_px: Vector2, color: Color, amount: int = 4, speed_px: float = 200.0) -> void:
	if rubble_scene == null or amount <= 0:
		return
	var p: CPUParticles2D = rubble_scene.instantiate()
	p.amount = amount
	p.color = color
	p.initial_velocity_max = speed_px
	p.initial_velocity_min = speed_px * 0.3
	p.position = at_px
	_fire(p)
	burst.emit(&"rubble", at_px, color)


## A cloud of dust of color swelling and drifting up from at_px.
func dust(at_px: Vector2, color: Color, amount: int = 2) -> void:
	if dust_scene == null or amount <= 0:
		return
	var p: CPUParticles2D = dust_scene.instantiate()
	p.amount = amount
	p.color = color
	p.position = at_px
	_fire(p)
	burst.emit(&"dust", at_px, color)


## Drops of color thrown up from at_px (something fell into water there).
func splash(at_px: Vector2, color: Color, amount: int = 10) -> void:
	if splash_scene == null or amount <= 0:
		return
	var p: CPUParticles2D = splash_scene.instantiate()
	p.amount = amount
	p.color = color.lerp(Color.WHITE, splash_pale)
	p.position = at_px
	_fire(p)
	burst.emit(&"splash", at_px, color)


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
