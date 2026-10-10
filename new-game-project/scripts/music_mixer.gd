class_name MusicMixer
extends Node
## Layered background music. The theme always plays. Drums fade in after the theme
## has looped once, and the metal riff fades in slowly as the board fills up while
## the theme ducks down to THEME_MIN_GAIN.
## All layers have the same length and tempo and are kept in sync by an
## AudioStreamSynchronized, so they can be mixed freely.

const THEME := "res://assets/music/theme.wav"
const DRUMS := "res://assets/music/drums.wav"
const METAL := "res://assets/music/metal.wav"

const BASE_DB := -7.0
const SILENT_DB := -80.0
const DRUM_FADE_SECONDS := 8.0
const METAL_START_FILL := 0.50 ## board fill where the metal starts to creep in
const METAL_FULL_FILL := 0.85 ## board fill where it is at full volume
const METAL_FADE_SPEED := 0.15 ## fade progress per second, so a full fade takes ~7 s
const THEME_MIN_GAIN := 0.5 ## linear gain of the theme once the metal is at full volume

var _player: AudioStreamPlayer
var _sync: AudioStreamSynchronized
var _loops_done := 0
var _last_position := 0.0
var _drums := 0.0
var _metal := 0.0
var _fill := 0.0


func _ready() -> void:
	var theme := _load_loop(THEME)
	if theme == null:
		return
	_player = AudioStreamPlayer.new()
	_player.volume_db = BASE_DB
	add_child(_player)

	var drums := _load_loop(DRUMS)
	var metal := _load_loop(METAL)
	if drums == null or metal == null:
		_player.stream = theme # layers missing: just the theme
	else:
		_sync = AudioStreamSynchronized.new()
		_sync.stream_count = 3
		_sync.set_sync_stream(0, theme)
		_sync.set_sync_stream(1, drums)
		_sync.set_sync_stream(2, metal)
		_apply_volumes()
		_player.stream = _sync
	_player.play()


## Starts the music over from the top with the drums and metal muted again.
func restart() -> void:
	_loops_done = 0
	_last_position = 0.0
	_drums = 0.0
	_metal = 0.0
	_apply_volumes()
	if _player:
		_player.play(0.0)


## How full the player's board is, 0..1; drives the metal layer.
func set_fill(ratio: float) -> void:
	_fill = clampf(ratio, 0.0, 1.0)


func toggle_pause() -> void:
	if _player:
		_player.stream_paused = not _player.stream_paused


func _process(delta: float) -> void:
	if _player == null or _player.stream_paused or not _player.playing:
		return
	# A drop in playback position means the loop wrapped around.
	var position := _player.get_playback_position()
	if position < _last_position - 1.0:
		_loops_done += 1
	_last_position = position

	var drum_target := 1.0 if _loops_done >= 1 else 0.0
	_drums = move_toward(_drums, drum_target, delta / DRUM_FADE_SECONDS)
	var metal_target := clampf(inverse_lerp(METAL_START_FILL, METAL_FULL_FILL, _fill), 0.0, 1.0)
	_metal = move_toward(_metal, metal_target, delta * METAL_FADE_SPEED)
	_apply_volumes()


func _apply_volumes() -> void:
	if _sync == null:
		return
	# _drums and _metal are fade progress (0..1); smoothstep gives a gentle start and end.
	var metal_gain := smoothstep(0.0, 1.0, _metal)
	_sync.set_sync_stream_volume(0, _to_db(lerpf(1.0, THEME_MIN_GAIN, metal_gain)))
	_sync.set_sync_stream_volume(1, _to_db(smoothstep(0.0, 1.0, _drums)))
	_sync.set_sync_stream_volume(2, _to_db(metal_gain))


static func _to_db(linear: float) -> float:
	return SILENT_DB if linear <= 0.001 else linear_to_db(linear)


static func _load_loop(path: String) -> AudioStreamWAV:
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStreamWAV = load(path).duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream
