class_name Hud
extends CanvasLayer
## Top bar, tool rack, banners and the intro / lost / victory cards. It only shows state and reports clicks.

signal tool_pressed(index: int)
## A material was picked with its icon on a build tool's button.
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
## Soldier bought in the Camp Shoppe.
signal recruit_pressed
## Engineer bought in the Camp Shoppe.
signal hire_pressed
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
## The Camp Shoppe's purchases, on the left of their buttons; the price in gold is on the right, with the gold icon.
@export var soldier_text: String = "Soldier"
## The Camp Shoppe keeps at least this far (pixels) from where the view stops scrolling.
@export_range(0.0, 200.0, 1.0, "suffix:px") var shop_edge_margin: float = 12.0
## Seconds the Camp Shoppe takes to fade in when it opens.
@export_range(0.0, 5.0, 0.05, "suffix:s") var shop_fade_time: float = 0.6
@export var engineer_text: String = "Engineer"

## The lost card: seconds to fade the screen to its overlay, then to slide the card up from below.
@export_range(0.0, 3.0, 0.05, "suffix:s") var card_fade_time: float = 0.5
@export_range(0.0, 3.0, 0.05, "suffix:s") var card_slide_time: float = 0.45

var _tool_buttons: Array[ToolButton] = []
var _tools: Array[ToolDefinition] = []
var _build_buttons: Array[PlanButtons] = []
var _group := ButtonGroup.new()
var _colors: Dictionary = {} # supply key -> swatch colour, for the tool buttons' costs
var _lost_tween: Tween
## The lost overlay's colour as set in the scene, faded to by show_lost.
var _lost_color: Color


func _ready() -> void:
	_lost_color = (%Lost as ColorRect).color
	# Holds the buttons that belong to the world (the plans' Build/Cancel, the camp's Camp Shoppe), which show and
	# hide themselves: never hidden as a whole, even if it was hidden while editing the scene. Moved to the very
	# back, so every other part of the HUD is drawn in front of them and gets the clicks where they meet.
	var world_buttons: Control = %WorldButtons
	world_buttons.visible = true
	world_buttons.reparent(self, false)
	move_child(world_buttons, 0)
	# Out from under Root, so it takes Root's theme along.
	world_buttons.theme = ($Root as Control).theme
	%PauseButton.pressed.connect(_emit.bind(pause_pressed))
	%SpeedButton.pressed.connect(_emit.bind(speed_pressed))
	%FollowButton.toggled.connect(func(on: bool) -> void:
		Audio.play(click_sound)
		follow_toggled.emit(on))
	%MarchButton.pressed.connect(_emit.bind(march_pressed))
	%ShopButton.pressed.connect(func() -> void: %ShopMenu.visible = not %ShopMenu.visible)
	for o: Button in [%ShopSoldier, %ShopEngineer]:
		# The row inside reads like the button's own text, and lights up under the mouse.
		for l: Label in [o.get_node("Row/Name"), o.get_node("Row/Price")]:
			l.add_theme_font_override(&"font", o.get_theme_font(&"font"))
			l.add_theme_font_size_override(&"font_size", o.get_theme_font_size(&"font_size"))
			l.add_theme_color_override(&"font_color", o.get_theme_color(&"font_color"))
		o.mouse_entered.connect(_light_row.bind(o, true))
		o.mouse_exited.connect(_light_row.bind(o, false))
	%ShopSoldier.pressed.connect(_emit.bind(recruit_pressed))
	%ShopEngineer.pressed.connect(_emit.bind(hire_pressed))
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
		b.material_pressed.connect(func(m: BridgeMaterial) -> void:
			Audio.play(click_sound)
			tool_pressed.emit(i)
			material_picked.emit(m))
		_tool_buttons.append(b)
	_refresh_supplies()
	_fit.call_deferred()


## Shows tool index as chosen, building material (for a build tool) if given (pressed among the icons on its button).
func set_tool(index: int, material: BridgeMaterial = null) -> void:
	if index >= _tool_buttons.size():
		return
	var b := _tool_buttons[index]
	b.button_pressed = true
	if material and material != b.build_material:
		b.setup(_tools[index], _colors, material)
		_refresh_supplies()
		# The new pick's hint may be longer or shorter: fold or unfold the rack to fit again.
		_fit.call_deferred()


func set_paused(paused: bool, show_tag: bool) -> void:
	%PauseButton.text = "Resume" if paused else "Pause"
	%PausedTag.visible = paused and show_tag


func set_speed(speed: float) -> void:
	%SpeedButton.text = "Speed %d×" % roundi(speed)


## Shows the March button while the column waits for the king.
func set_march(waiting: bool) -> void:
	if %MarchPanel.visible != waiting:
		%MarchPanel.visible = waiting
		_fit.call_deferred()


## Shows the Camp Shoppe panel hanging under the camp (world pixels) while the column camps. Its button drops
## down, inside the same panel, its purchases: a soldier for soldier_gold and an engineer for engineer_gold, each
## greyed out (letting clicks through to the world behind it) when it can not be bought. reach is the leftmost and
## rightmost x (world pixels) the view can scroll to: the panel keeps shop_edge_margin inside it.
func set_shop(at_camp: bool, soldier_gold: int, can_recruit: bool, engineer_gold: int, can_hire: bool,
		world_px: Vector2, reach: Vector2 = Vector2(-INF, INF)) -> void:
	var panel: PanelContainer = %ShopPanel
	if not at_camp:
		panel.visible = false
		%ShopMenu.visible = false
		return
	if not panel.visible:
		panel.visible = true
		panel.modulate.a = 0.0
		create_tween().tween_property(panel, ^"modulate:a", 1.0, shop_fade_time)
	_offer(%ShopSoldier, soldier_text, soldier_gold, can_recruit)
	_offer(%ShopEngineer, engineer_text, engineer_gold, can_hire)
	# The Camp Shoppe button and its purchases are all as wide as the widest of them.
	var b: Button = %ShopButton
	var items: Array[Button] = [%ShopSoldier, %ShopEngineer]
	b.custom_minimum_size.x = 0
	var w := b.get_combined_minimum_size().x
	for o in items:
		var row: HBoxContainer = o.get_node("Row")
		w = maxf(w, row.get_combined_minimum_size().x + row.offset_left - row.offset_right + SHOP_GAP)
	for o in items:
		o.custom_minimum_size.x = w
	b.custom_minimum_size.x = w
	# Hangs from the spot and grows downward as the list opens.
	panel.size = panel.get_combined_minimum_size()
	var at := _to_screen(world_px) - Vector2(panel.size.x / 2, 0)
	var lo := _to_screen(Vector2(reach.x, 0)).x + shop_edge_margin if is_finite(reach.x) else -INF
	var hi := _to_screen(Vector2(reach.y, 0)).x - shop_edge_margin - panel.size.x if is_finite(reach.y) else INF
	at.x = clampf(at.x, lo, maxf(lo, hi))
	panel.position = at.round()


## Shows a purchase's words in its button's hover colour while the mouse is over it, else in its own colour.
func _light_row(o: Button, lit: bool) -> void:
	var color := o.get_theme_color(&"font_hover_color" if lit else &"font_color")
	for l: Label in [o.get_node("Row/Name"), o.get_node("Row/Price")]:
		l.add_theme_color_override(&"font_color", color)
	(o.get_node("Row/Icon") as TextureRect).modulate = Color(1.25, 1.25, 1.25) if lit else Color.WHITE


## Room left between the longest purchase's name and its price.
const SHOP_GAP: float = 14.0


## One purchase: what on the left, its price in gold on the right; greyed out and letting clicks through when it can
## not be bought.
func _offer(o: Button, what: String, gold: int, can_buy: bool) -> void:
	var row: HBoxContainer = o.get_node("Row")
	(o.get_node("Row/Name") as Label).text = what
	(o.get_node("Row/Price") as Label).text = str(gold)
	o.custom_minimum_size = Vector2(0, row.get_combined_minimum_size().y + 8)
	o.disabled = not can_buy
	o.mouse_filter = Control.MOUSE_FILTER_STOP if can_buy else Control.MOUSE_FILTER_IGNORE
	row.modulate.a = 1.0 if can_buy else 0.45
	if not can_buy:
		# It no longer hears the mouse, so it would stay lit.
		_light_row(o, false)


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


## Arrow at the screen edge pointing at the column when it is off screen. The markers are TextureRects of one
## arrow sprite (pointing right, tinted by their modulate), flipped to point left.
func set_lead_marker(visible_on_side: int, screen_y: float) -> void:
	_set_edge_marker(%LeadMarker, visible_on_side, screen_y)
	_keep_markers_apart()


## Red arrow at the screen edge pointing at the nearest engineer off screen.
func set_crew_marker(visible_on_side: int, screen_y: float) -> void:
	_set_edge_marker(%CrewMarker, visible_on_side, screen_y)
	_keep_markers_apart()


## Moves the red arrow just clear of the blue one when both are on the same edge and would cover each other:
## below it, or above it near the bottom of the screen.
func _keep_markers_apart() -> void:
	var red: TextureRect = %CrewMarker
	var blue: TextureRect = %LeadMarker
	if not (red.visible and blue.visible) or not red.get_rect().intersects(blue.get_rect()):
		return
	var below := blue.position.y + blue.size.y
	var above := blue.position.y - red.size.y
	red.position.y = below if below + red.size.y <= red.get_viewport_rect().size.y else above


## Shows marker at the screen edge on visible_on_side (-1 left, 1 right; 0 hides it), at screen_y, pointing out.
func _set_edge_marker(m: TextureRect, visible_on_side: int, screen_y: float) -> void:
	m.visible = visible_on_side != 0
	if visible_on_side == 0:
		return
	m.flip_h = visible_on_side < 0
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
