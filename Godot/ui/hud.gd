class_name Hud
extends CanvasLayer
## Top bar, tool rack, banners and the intro / lost / victory cards. It only shows state and reports clicks.

signal tool_pressed(index: int)
signal pause_pressed
signal speed_pressed
signal follow_pressed
signal begin_pressed
signal retry_pressed
signal restart_pressed

enum Mood { NORMAL, HALT, FIRE }

@export var tool_button_scene: PackedScene
@export var halt_color: Color = Color("e9a93b")
@export var fire_color: Color = Color("d9503f")
@export var normal_color: Color = Color("ece4d2")
@export_range(0.5, 10.0, 0.1, "suffix:s") var banner_time: float = 3.0
@export var click_sound: SoundEffect

var _tool_buttons: Array[ToolButton] = []
var _group := ButtonGroup.new()


func _ready() -> void:
	%PauseButton.pressed.connect(_emit.bind(pause_pressed))
	%SpeedButton.pressed.connect(_emit.bind(speed_pressed))
	%FollowButton.pressed.connect(_emit.bind(follow_pressed))
	%BeginButton.pressed.connect(_emit.bind(begin_pressed))
	%RetryButton.pressed.connect(_emit.bind(retry_pressed))
	%NewWorldButton.pressed.connect(_emit.bind(restart_pressed))
	%AgainButton.pressed.connect(_emit.bind(restart_pressed))
	GameState.supplies_changed.connect(_refresh_supplies)
	GameState.soldiers_changed.connect(func(n: int) -> void: %Army.set_value(str(n)))
	GameState.best_changed.connect(func(n: int) -> void: %Best.set_value("L%d" % n))
	%Banner.modulate.a = 0.0
	_refresh_supplies()
	%Best.set_value("L%d" % GameState.best_level)


func build_tools(tools: Array[ToolDefinition]) -> void:
	for b in _tool_buttons:
		b.queue_free()
	_tool_buttons.clear()
	for i in tools.size():
		var b: ToolButton = tool_button_scene.instantiate()
		b.button_group = _group
		%Tools.add_child(b)
		b.setup(tools[i])
		b.pressed.connect(func() -> void:
			Audio.play(click_sound)
			tool_pressed.emit(i))
		_tool_buttons.append(b)


func set_tool(index: int) -> void:
	if index < _tool_buttons.size():
		_tool_buttons[index].button_pressed = true


func set_paused(paused: bool, show_tag: bool) -> void:
	%PauseButton.text = "Resume" if paused else "Pause"
	%PausedTag.visible = paused and show_tag


func set_speed(speed: float) -> void:
	%SpeedButton.text = "Speed %d×" % roundi(speed)


func set_follow(on: bool) -> void:
	%FollowButton.button_pressed = on


func set_level(number: int, marched_m: int) -> void:
	%Level.set_value(str(number))
	%Marched.set_value("%d m" % marched_m)


func set_status(text: String, mood: Mood) -> void:
	%Status.text = text
	var c: Color = [normal_color, halt_color, fire_color][mood]
	%Status.modulate = c
	%StatusPanel.self_modulate = c


func banner(title: String, sub: String) -> void:
	%BannerTitle.text = title
	%BannerSub.text = sub
	var b: Control = %Banner
	var tw := b.create_tween()
	tw.tween_property(b, ^"modulate:a", 1.0, 0.25)
	tw.tween_interval(banner_time - 1.0)
	tw.tween_property(b, ^"modulate:a", 0.0, 0.75)


## Arrow at the screen edge pointing at the column when it is off screen.
func set_lead_marker(visible_on_side: int, screen_y: float) -> void:
	var m: Label = %LeadMarker
	m.visible = visible_on_side != 0
	if visible_on_side == 0:
		return
	m.text = "▶" if visible_on_side > 0 else "◀"
	var vp := m.get_viewport_rect().size
	m.position = Vector2(vp.x - m.size.x - 6.0 if visible_on_side > 0 else 6.0, clampf(screen_y - m.size.y / 2, 60.0, vp.y - 120.0))


func show_intro(on: bool) -> void:
	%Intro.visible = on


func show_lost(text: String) -> void:
	%LostText.text = text
	%Lost.visible = true


func show_victory(text: String) -> void:
	%VictoryText.text = text
	%Victory.visible = true


func hide_cards() -> void:
	%Intro.visible = false
	%Lost.visible = false
	%Victory.visible = false


func any_card_open() -> bool:
	return %Intro.visible or %Lost.visible or %Victory.visible


func _refresh_supplies() -> void:
	var s := GameState.supplies
	%Earth.set_value(str(s.earth), true)
	%Logs.set_value(str(s.logs), true)
	%Rope.set_value(str(s.rope), true)
	%Powder.set_value(str(s.powder), true)


func _emit(sig: Signal) -> void:
	Audio.play(click_sound)
	sig.emit()
