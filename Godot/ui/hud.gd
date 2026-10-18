class_name Hud
extends CanvasLayer
## Top bar, tool rack, banners and the intro / lost / victory cards. It only shows state and reports clicks.

signal tool_pressed(index: int)
## A material was picked in the material picker of the chosen build tool.
signal material_picked(material: BridgeMaterial)
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
## Restart the current level from its checkpoint (any time, not only when lost).
signal restart_level_pressed
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

## The lost card: seconds to fade the screen to its overlay, then to slide the card up from below.
@export_range(0.0, 3.0, 0.05, "suffix:s") var card_fade_time: float = 0.5
@export_range(0.0, 3.0, 0.05, "suffix:s") var card_slide_time: float = 0.45

var _tool_buttons: Array[ToolButton] = []
var _tools: Array[ToolDefinition] = []
var _build_buttons: Array[PlanButtons] = []
var _group := ButtonGroup.new()
var _picker_tool: int = -1 # tool whose materials the picker shows, -1 if none
var _colors: Dictionary = {} # supply key -> swatch colour, for the tool buttons' costs
var _lost_tween: Tween
## The lost overlay's colour as set in the scene, faded to by show_lost.
var _lost_color: Color


func _ready() -> void:
	_lost_color = (%Lost as ColorRect).color
	%PauseButton.pressed.connect(_emit.bind(pause_pressed))
	%SpeedButton.pressed.connect(_emit.bind(speed_pressed))
	%FollowButton.toggled.connect(func(on: bool) -> void:
		Audio.play(click_sound)
		follow_toggled.emit(on))
	%MarchButton.pressed.connect(_emit.bind(march_pressed))
	%RecruitButton.pressed.connect(_emit.bind(recruit_pressed))
	%BeginButton.pressed.connect(_emit.bind(begin_pressed))
	%RetryButton.pressed.connect(_emit.bind(retry_pressed))
	%RestartButton.pressed.connect(_emit.bind(restart_level_pressed))
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
	_picker_tool = -1
	_colors = {}
	# Opaque: a readout may hide its swatch (shown by an icon instead), but the cost swatches need the colour.
	for k in Supplies.KEYS:
		_colors[k] = Color(_readout(k).swatch, 1.0)
	for i in tools.size():
		var b: ToolButton = tool_button_scene.instantiate()
		b.button_group = _group
		%Tools.add_child(b)
		b.setup(tools[i], _colors)
		b.pressed.connect(func() -> void:
			Audio.play(click_sound)
			tool_pressed.emit(i))
		_tool_buttons.append(b)
	_refresh_supplies()
	_fit.call_deferred()


## Shows tool index as chosen, building material (for a build tool) if given. A tool with several materials
## gets the material picker above its button.
func set_tool(index: int, material: BridgeMaterial = null) -> void:
	if index >= _tool_buttons.size():
		return
	var b := _tool_buttons[index]
	b.button_pressed = true
	if material and material != b.build_material:
		b.setup(_tools[index], _colors, material)
		_refresh_supplies()
	_show_picker(index, material)


## One button per material of tool index above its button, the one it builds (material) pressed; hidden for tools
## with a single material.
func _show_picker(index: int, material: BridgeMaterial) -> void:
	var picker: Control = %MaterialPicker
	var all := _tools[index].materials()
	picker.visible = all.size() > 1
	if not picker.visible:
		_picker_tool = -1
		return
	var row: HBoxContainer = %Materials
	var chosen := material if material else all[0]
	if _picker_tool == index:
		# Same tool: only the pick moved. The buttons stay (one of them may be emitting this very pick).
		for i in all.size():
			(row.get_child(i) as Button).set_pressed_no_signal(all[i] == chosen)
		return
	_picker_tool = index
	for c in row.get_children():
		c.queue_free()
		row.remove_child(c)
	var group := ButtonGroup.new()
	for m in all:
		var mb := Button.new()
		mb.toggle_mode = true
		mb.button_group = group
		mb.focus_mode = Control.FOCUS_NONE
		mb.text = "%s · %s/m" % [m.display_name, m.cost.describe_cost() if m.cost else ""]
		mb.tooltip_text = m.hint
		mb.button_pressed = m == chosen
		mb.pressed.connect(func() -> void:
			Audio.play(click_sound)
			material_picked.emit(m))
		row.add_child(mb)
	_place_picker.call_deferred(_tool_buttons[index])


## Over the tool button, above the supply bar so it hides no counts.
func _place_picker(over: Control) -> void:
	var picker: Control = %MaterialPicker
	picker.size = picker.get_combined_minimum_size()
	var top := minf(over.global_position.y, $Root/Margin/Column/SupplyBar.global_position.y)
	picker.global_position = Vector2(over.global_position.x + (over.size.x - picker.size.x) / 2.0, top - picker.size.y - 6.0)


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


## Fades the screen to the lost overlay, then slides the card with title and text up from below.
func show_lost(title: String, text: String) -> void:
	%LostTitle.text = title
	%LostText.text = text
	var lost: ColorRect = %Lost
	var center: Control = lost.get_node(^"Center")
	if _lost_tween:
		_lost_tween.kill()
	lost.visible = true
	lost.color = Color(_lost_color, 0.0)
	center.position.y = lost.size.y if lost.size.y > 0.0 else get_viewport().get_visible_rect().size.y
	_lost_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale()
	_lost_tween.tween_property(lost, ^"color", _lost_color, card_fade_time)
	_lost_tween.tween_property(center, ^"position:y", 0.0, card_slide_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func show_victory(text: String) -> void:
	%VictoryText.text = text
	%Victory.visible = true


func hide_cards() -> void:
	%Intro.visible = false
	if _lost_tween:
		_lost_tween.kill()
	%Lost.visible = false
	%Lost.color = _lost_color
	%Lost.get_node(^"Center").position.y = 0.0
	%Victory.visible = false


func any_card_open() -> bool:
	return %Intro.visible or %Lost.visible or %Victory.visible


func _to_screen(world_px: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_px


func _fit() -> void:
	var margin: MarginContainer = $Root/Margin
	var sides := margin.get_theme_constant(&"margin_left") + margin.get_theme_constant(&"margin_right")
	fit_to(margin.get_viewport_rect().size.x - sides)


## The supply bar readout of supply k (the node named after it: earth -> Earth).
func _readout(k: StringName) -> Readout:
	return get_node("%" + String(k).capitalize())


func _refresh_supplies() -> void:
	var s := GameState.supplies
	for k in Supplies.KEYS:
		_readout(k).set_value(str(s.get(k)), true)
	for i in _tool_buttons.size():
		_tool_buttons[i].set_affordable(s.can_afford(_tools[i].price(_tool_buttons[i].build_material)))


func _emit_index(sig: Signal, index: int) -> void:
	Audio.play(click_sound)
	sig.emit(index)


func _emit(sig: Signal) -> void:
	Audio.play(click_sound)
	sig.emit()
