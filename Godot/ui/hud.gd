class_name Hud
extends CanvasLayer
## Top bar, tool rack, banners and the intro / lost / victory cards. It only shows state and reports clicks.

signal tool_pressed(index: int)
signal pause_pressed
signal speed_pressed
## The Follow button was switched on or off.
signal follow_toggled(on: bool)
## The player clicked the Build button above plan number index (as last passed to set_build_spots).
signal build_pressed(index: int)
## The player clicked the cancel button beside plan number index.
signal cancel_pressed(index: int)
signal march_pressed
signal recruit_pressed
signal begin_pressed
signal retry_pressed
signal restart_pressed
## The player moved a volume slider (0..1) for bus.
signal volume_changed(bus: StringName, value: float)

enum Mood { NORMAL, HALT, FIRE }

@export var tool_button_scene: PackedScene
@export var halt_color: Color = Color("e9a93b")
@export var fire_color: Color = Color("d9503f")
@export var normal_color: Color = Color("ece4d2")
@export_range(0.5, 10.0, 0.1, "suffix:s") var banner_time: float = 3.0
@export var click_sound: SoundEffect
## Audio buses behind the Music and Sound sliders.
@export var music_bus: StringName = &"Music"
@export var sound_bus: StringName = &"SFX"
## Build + cancel pair floating above each plan.
@export var plan_buttons_scene: PackedScene
## Build button text above a plan (%d = members in it).
@export var build_text: String = "Build %d"
## Recruit button text (%d = gold per soldier).
@export var recruit_text: String = "Recruit · %d gold"

var _tool_buttons: Array[ToolButton] = []
var _tools: Array[ToolDefinition] = []
var _build_buttons: Array[PlanButtons] = []
var _group := ButtonGroup.new()


func _ready() -> void:
	%PauseButton.pressed.connect(_emit.bind(pause_pressed))
	%SpeedButton.pressed.connect(_emit.bind(speed_pressed))
	%FollowButton.toggled.connect(func(on: bool) -> void:
		Audio.play(click_sound)
		follow_toggled.emit(on))
	%MarchButton.pressed.connect(_emit.bind(march_pressed))
	%RecruitButton.pressed.connect(_emit.bind(recruit_pressed))
	%BeginButton.pressed.connect(_emit.bind(begin_pressed))
	%RetryButton.pressed.connect(_emit.bind(retry_pressed))
	%NewWorldButton.pressed.connect(_emit.bind(restart_pressed))
	%AgainButton.pressed.connect(_emit.bind(restart_pressed))
	%SoundButton.toggled.connect(func(on: bool) -> void: %SoundPanel.visible = on)
	%MusicSlider.value_changed.connect(func(v: float) -> void: volume_changed.emit(music_bus, v))
	%SoundSlider.value_changed.connect(func(v: float) -> void: volume_changed.emit(sound_bus, v))
	# A click after moving the sound slider, so the new level can be heard.
	%SoundSlider.drag_ended.connect(func(_changed: bool) -> void: Audio.play(click_sound))
	GameState.supplies_changed.connect(_refresh_supplies)
	GameState.soldiers_changed.connect(func(n: int) -> void: %Army.set_value(str(n)))
	GameState.best_changed.connect(func(n: int) -> void: %Best.set_value("L%d" % n))
	%Banner.modulate.a = 0.0
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()
	_refresh_supplies()
	%Best.set_value("L%d" % GameState.best_level)


func build_tools(tools: Array[ToolDefinition]) -> void:
	for b in _tool_buttons:
		b.queue_free()
	_tool_buttons.clear()
	_tools = tools
	var colors := {&"earth": %Earth.swatch, &"logs": %Logs.swatch, &"rope": %Rope.swatch, &"gold": %Gold.swatch}
	for i in tools.size():
		var b: ToolButton = tool_button_scene.instantiate()
		b.button_group = _group
		%Tools.add_child(b)
		b.setup(tools[i], colors)
		b.pressed.connect(func() -> void:
			Audio.play(click_sound)
			tool_pressed.emit(i))
		_tool_buttons.append(b)
	_refresh_supplies()
	_fit.call_deferred()


func set_tool(index: int) -> void:
	if index < _tool_buttons.size():
		_tool_buttons[index].button_pressed = true


func set_paused(paused: bool, show_tag: bool) -> void:
	%PauseButton.text = "Resume" if paused else "Pause"
	%PausedTag.visible = paused and show_tag


func set_speed(speed: float) -> void:
	%SpeedButton.text = "Speed %d×" % roundi(speed)


## Shows the March button while the column waits for the king.
func set_march(waiting: bool) -> void:
	if %MarchButton.visible != waiting:
		%MarchButton.visible = waiting
		_fit.call_deferred()


## Shows the Recruit button above the camp (world pixels) while the column camps; greyed out when a soldier
## can not be bought.
func set_recruit(at_camp: bool, gold: int, can_buy: bool, world_px: Vector2) -> void:
	var b: WorldButton = %RecruitButton
	b.visible = at_camp
	if not at_camp:
		return
	b.text = recruit_text % gold
	b.disabled = not can_buy
	b.pin(_to_screen(world_px))


## Folds the rows to fit width pixels: tool hints go first, then the title.
func fit_to(width: float) -> void:
	for b in _tool_buttons:
		b.set_compact(false)
	%Title.visible = true
	if %Rack.get_combined_minimum_size().x > width or %TopBar.get_combined_minimum_size().x > width:
		for b in _tool_buttons:
			b.set_compact(true)
	if %TopBar.get_combined_minimum_size().x > width:
		%Title.visible = false


## Build and cancel buttons above each plan. spots are world pixel positions (top centre of each plan), counts
## the members in each. Clicks report the plan's index through build_pressed / cancel_pressed.
func set_build_spots(spots: Array, counts: Array) -> void:
	while _build_buttons.size() < spots.size():
		var pair: PlanButtons = plan_buttons_scene.instantiate()
		var index := _build_buttons.size()
		%WorldButtons.add_child(pair)
		pair.get_node(^"%Build").pressed.connect(_emit_index.bind(build_pressed, index))
		pair.get_node(^"%Cancel").pressed.connect(_emit_index.bind(cancel_pressed, index))
		_build_buttons.append(pair)
	for i in _build_buttons.size():
		var pair := _build_buttons[i]
		pair.visible = i < spots.size()
		if pair.visible:
			pair.get_node(^"%Build").text = build_text % counts[i]
			pair.pin(_to_screen(spots[i]))


## Shows the current volumes (0..1) without reporting them back.
func set_volumes(music: float, sound: float) -> void:
	%MusicSlider.set_value_no_signal(music)
	%SoundSlider.set_value_no_signal(sound)


## Shows whether the camera follows, without reporting it back.
func set_follow(on: bool) -> void:
	%FollowButton.set_pressed_no_signal(on)


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


func _to_screen(world_px: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_px


func _fit() -> void:
	var margin: MarginContainer = $Root/Margin
	var sides := margin.get_theme_constant(&"margin_left") + margin.get_theme_constant(&"margin_right")
	fit_to(margin.get_viewport_rect().size.x - sides)


func _refresh_supplies() -> void:
	var s := GameState.supplies
	%Earth.set_value(str(s.earth), true)
	%Logs.set_value(str(s.logs), true)
	%Rope.set_value(str(s.rope), true)
	%Gold.set_value(str(s.gold), true)
	for i in _tool_buttons.size():
		_tool_buttons[i].set_affordable(s.can_afford(_tools[i].price()))


func _emit_index(sig: Signal, index: int) -> void:
	Audio.play(click_sound)
	sig.emit(index)


func _emit(sig: Signal) -> void:
	Audio.play(click_sound)
	sig.emit()
