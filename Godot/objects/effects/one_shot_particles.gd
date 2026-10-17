extends CPUParticles2D
## Emits once and frees itself. For explosion flashes and similar effects.


func _ready() -> void:
	one_shot = true
	emitting = true
	finished.connect(queue_free)
