extends Node2D
## Top-level controller: menu, solo or 1v1 session, audio, and wiring between
## the local Playfield, the opponent mirror Playfield and NetSession.

const SFX_NAMES: Array[String] = [
	"place", "rotate", "clear", "lose", "invalid", "explode",
	"attack", "garbage", "win", "warning",
]
const BG_COLOR := Color("1e2229")
const DIM_TEXT := Color("8f98a8")
const GOOD := Color("6ab04c")
const BAD := Color("ff5d5d")
const LOCAL_CELL := 72
const REMOTE_CELL := 40
const MARGIN := 40.0

enum Mode { MENU, SOLO, HOSTING, JOINING, VERSUS }

var _mode := Mode.MENU
var _menu: Menu
var _net: NetSession
var _local: Playfield
var _remote: Playfield
var _sfx := {}
var _music: AudioStreamPlayer
var _sfx_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_sfx_rng.randomize()
	for sfx_name in SFX_NAMES:
		var path := "res://assets/sfx/%s.wav" % sfx_name
		if ResourceLoader.exists(path):
			var player := AudioStreamPlayer.new()
			player.stream = load(path)
			add_child(player)
			_sfx[sfx_name] = player
	_start_music()

	# NetSession needs the same node path on both peers: /root/Game/NetSession.
	_net = NetSession.new()
	_net.name = "NetSession"
	add_child(_net)
	_net.connected.connect(_on_net_connected)
	_net.disconnected.connect(_on_net_disconnected)
	_net.game_start.connect(_on_game_start)
	_net.peer_snapshot.connect(_on_peer_snapshot)
	_net.peer_attack.connect(_on_peer_attack)
	_net.peer_lost.connect(_on_peer_lost)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_menu = Menu.new()
	_menu.choose.connect(_on_menu_choose)
	layer.add_child(_menu)

	get_viewport().size_changed.connect(_layout)
	_layout()
	queue_redraw()


func _start_music() -> void:
	const PATH := "res://assets/music/theme.wav"
	if not ResourceLoader.exists(PATH):
		return
	var stream: AudioStreamWAV = load(PATH).duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	_music.volume_db = -7.0
	add_child(_music)
	_music.play()


func _play(sfx_name: String, pitch := 1.0) -> void:
	if _sfx.has(sfx_name):
		var player: AudioStreamPlayer = _sfx[sfx_name]
		var jitter := _sfx_rng.randf_range(-0.04, 0.04) if sfx_name in ["place", "rotate"] else 0.0
		player.pitch_scale = pitch + jitter
		player.play()


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2(-60, -60), size + Vector2(120, 120)), BG_COLOR)
	if _mode == Mode.SOLO or _mode == Mode.VERSUS:
		draw_string(ThemeDB.fallback_font, Vector2(MARGIN, size.y - 20), "Click: place   R / right-click / wheel: rotate   M: music   Esc: menu", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, DIM_TEXT)


func _layout() -> void:
	var size := get_viewport_rect().size
	if _local:
		var board_w := Playfield.BOARD_W * LOCAL_CELL
		if _mode == Mode.VERSUS:
			_local.home_position = Vector2(MARGIN, Playfield.HEADER)
		else:
			_local.home_position = Vector2((size.x - board_w) / 2.0, Playfield.HEADER)
		_local.position = _local.home_position
	if _remote:
		_remote.home_position = Vector2(size.x - MARGIN - Playfield.BOARD_W * REMOTE_CELL, Playfield.HEADER + 40)
		_remote.position = _remote.home_position
	queue_redraw()


# --- Sessions ---------------------------------------------------------------

func _make_local() -> void:
	_free_playfields()
	_local = Playfield.new()
	_local.cell_size = LOCAL_CELL
	_local.interactive = true
	add_child(_local)
	_local.sfx_requested.connect(_play)
	_local.lost.connect(_on_local_lost)
	_local.restart_requested.connect(_on_restart_requested)


func _free_playfields() -> void:
	for pf in [_local, _remote]:
		if pf:
			pf.queue_free()
	_local = null
	_remote = null


func _start_solo() -> void:
	_mode = Mode.SOLO
	_menu.visible = false
	_make_local()
	_layout()
	_local.start(randi())


func _enter_versus() -> void:
	_mode = Mode.VERSUS
	_menu.visible = false
	_make_local()
	_local.attack.connect(_net.send_attack)
	_local.board_changed.connect(_net.send_snapshot)
	_remote = Playfield.new()
	_remote.cell_size = REMOTE_CELL
	_remote.interactive = false
	_remote.title = "OPPONENT"
	add_child(_remote)
	_layout()
	_local.set_overlay("Connected!", "Starting...", GOOD)
	_net.send_ready()


func _back_to_menu(status := "") -> void:
	_net.close()
	_free_playfields()
	_mode = Mode.MENU
	_menu.visible = true
	_menu.set_busy(false)
	_menu.set_status(status)
	queue_redraw()


# --- Menu / network events --------------------------------------------------

func _on_menu_choose(mode: String, address: String) -> void:
	match mode:
		"solo":
			_start_solo()
		"host":
			var err := _net.host()
			if err != OK:
				_menu.set_status("Could not host (%s). Is the port already in use?" % error_string(err))
				return
			_mode = Mode.HOSTING
			_menu.set_busy(true)
			_menu.set_status(_menu.get_default_status_for("host"))
		"join":
			var err := _net.join(address)
			if err != OK:
				_menu.set_status("Could not connect (%s)." % error_string(err))
				return
			_mode = Mode.JOINING
			_menu.set_busy(true)
			_menu.set_status(_menu.get_default_status_for("join"))
		"cancel":
			_net.close()
			_mode = Mode.MENU
			_menu.set_busy(false)
			_menu.set_status("")


func _on_net_connected() -> void:
	if _mode == Mode.HOSTING or _mode == Mode.JOINING:
		_enter_versus()


func _on_net_disconnected() -> void:
	match _mode:
		Mode.VERSUS:
			_back_to_menu("Opponent disconnected.")
		Mode.JOINING:
			_back_to_menu("Could not connect to the host.")
		_:
			pass # a failed pairing attempt while hosting; keep waiting


func _on_game_start(seed_value: int) -> void:
	if _mode != Mode.VERSUS:
		return
	_local.start(seed_value)
	_remote.start(seed_value)
	_remote.set_overlay("")
	_local.set_overlay("")


func _on_peer_snapshot(cells: PackedInt32Array) -> void:
	if _remote:
		_remote.apply_snapshot(cells)


func _on_peer_attack(amount: int) -> void:
	if _local and _mode == Mode.VERSUS:
		_local.receive_attack(amount)


func _on_peer_lost() -> void:
	if _mode != Mode.VERSUS or _local.finished:
		return
	_local.set_overlay("YOU WIN!", "Press Enter for a rematch", GOOD)
	_remote.set_overlay("DEFEATED", "", BAD)
	_play("win")


# --- Local player events ----------------------------------------------------

func _on_local_lost() -> void:
	if _mode == Mode.VERSUS:
		_net.send_lost()
		_local.set_overlay("BOARD FULL - YOU LOSE", "Press Enter for a rematch", BAD)
	else:
		_local.set_overlay("BOARD FULL - YOU LOSE", "Click or press Enter to restart", BAD)


func _on_restart_requested() -> void:
	if _mode == Mode.VERSUS:
		_local.set_overlay("Waiting for opponent...", "", DIM_TEXT)
		_net.send_ready()
	elif _mode == Mode.SOLO:
		_local.start(randi())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_M:
				if _music:
					_music.stream_paused = not _music.stream_paused
			KEY_ESCAPE:
				if _mode == Mode.SOLO or _mode == Mode.VERSUS:
					_back_to_menu()
