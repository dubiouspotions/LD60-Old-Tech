extends Node
## Plays SoundEffect resources and the level music, and keeps the player's bus volumes. Autoload "Audio".

const POOL_SIZE: int = 16
## Buses the player can set the volume of (see default_bus_layout.tres).
const VOLUME_BUSES: Array[StringName] = [&"Music", &"SFX"]

## Where the volumes are kept. Tests point this elsewhere.
var settings_path: String = "user://settings.cfg"

var _pool: Array[AudioStreamPlayer] = []
var _pool_2d: Array[AudioStreamPlayer2D] = []
var _music: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
		var p2 := AudioStreamPlayer2D.new()
		p2.max_distance = 1400.0
		add_child(p2)
		_pool_2d.append(p2)
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	_music.finished.connect(_on_music_finished)
	add_child(_music)
	load_volumes()


## Volume of a bus, 0 (silent) to 1 (as mixed).
func volume(bus: StringName) -> float:
	var i := AudioServer.get_bus_index(bus)
	if i < 0 or AudioServer.is_bus_mute(i):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(i))


## Sets a bus volume, 0 mutes it. Saved for the next session unless save is false.
func set_volume(bus: StringName, linear: float, save: bool = true) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, linear <= 0.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
	if save:
		var cfg := ConfigFile.new()
		cfg.load(settings_path)
		cfg.set_value("volume", bus, linear)
		cfg.save(settings_path)


## Restores the saved volumes. Buses without a saved volume keep the bus layout's.
func load_volumes() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	for bus in VOLUME_BUSES:
		if cfg.has_section_key("volume", bus):
			set_volume(bus, float(cfg.get_value("volume", bus)), false)


## Plays sfx. With a world position (pixels) the sound is panned and fades with distance.
func play(sfx: SoundEffect, world_px: Variant = null) -> void:
	if sfx == null:
		return
	var stream := sfx.pick()
	if stream == null:
		return
	var player: Node = _free_player(_pool_2d if world_px is Vector2 else _pool)
	player.stream = stream
	player.volume_db = sfx.volume_db
	player.pitch_scale = 1.0 + randf_range(-sfx.pitch_variation, sfx.pitch_variation)
	player.bus = sfx.bus
	if world_px is Vector2:
		(player as AudioStreamPlayer2D).global_position = world_px
	player.play()


func play_music(stream: AudioStream) -> void:
	if stream == _music.stream and _music.playing:
		return
	_music.stream = stream
	if stream:
		_music.play()
	else:
		_music.stop()


func _on_music_finished() -> void:
	# Loops any stream, so designers need not set loop flags on imports.
	if _music.stream:
		_music.play()


func _free_player(pool: Array) -> Node:
	for p: Node in pool:
		if not p.playing:
			return p
	return pool[0]
