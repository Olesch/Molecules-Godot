extends Node2D
## Top-level controller: menu, solo or 1v1 session, audio, and wiring between
## the local Playfield, the opponent mirror Playfield and NetSession.

const SFX_NAMES: Array[String] = [
	"place", "rotate", "clear", "lose", "invalid", "explode",
	"attack", "garbage", "win", "warning",
]
const LOCAL_CELL := 72
const REMOTE_CELL := 40
const MARGIN := 40.0
const SOLO_PROGRESS_PATH := "user://solo_progress.json"

enum Mode { MENU, SOLO, HOSTING, JOINING, VERSUS }

var _mode := Mode.MENU
var _menu: Menu
var _net: NetSession
var _local: Playfield
var _remote: Playfield
var _sfx := {}
var _mixer: MusicMixer
var _sfx_rng := RandomNumberGenerator.new()
var _waiting_for_rematch := false
var _solo_progression: Progression
var solo_progress_path := SOLO_PROGRESS_PATH


func _ready() -> void:
	_sfx_rng.randomize()
	for sfx_name in SFX_NAMES:
		var path := "res://assets/sfx/%s.wav" % sfx_name
		if ResourceLoader.exists(path):
			var player := AudioStreamPlayer.new()
			player.stream = load(path)
			add_child(player)
			_sfx[sfx_name] = player
	_mixer = MusicMixer.new()
	add_child(_mixer)

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


func _play(sfx_name: String, pitch := 1.0) -> void:
	if _sfx.has(sfx_name):
		var player: AudioStreamPlayer = _sfx[sfx_name]
		var jitter := _sfx_rng.randf_range(-0.04, 0.04) if sfx_name in ["place", "rotate"] else 0.0
		player.pitch_scale = pitch + jitter
		player.play()


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2(-60, -60), size + Vector2(120, 120)), Palette.BG)
	if _mode == Mode.SOLO or _mode == Mode.VERSUS:
		draw_string(ThemeDB.fallback_font, Vector2(MARGIN, size.y - 20), Menu.CONTROLS_HINT, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.DIM)


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

func _make_local(progression: Progression, versus: bool, timed := false) -> void:
	_free_playfields()
	_local = Playfield.new()
	_local.cell_size = LOCAL_CELL
	_local.interactive = true
	_local.progression = progression
	_local.versus = versus
	_local.timed = timed
	add_child(_local)
	_local.progression_changed.connect(_on_progression_changed)
	_local.sfx_requested.connect(_play)
	_local.lost.connect(_on_local_lost)
	_local.restart_requested.connect(_on_restart_requested)


func _free_playfields() -> void:
	for pf in [_local, _remote]:
		if pf:
			pf.queue_free()
	_local = null
	_remote = null


func _process(_delta: float) -> void:
	var fill := 0.0
	if _local and not _local.finished:
		fill = _local.board.fill_ratio()
	_mixer.set_fill(fill)


func _start_solo(timed := false) -> void:
	_mode = Mode.SOLO
	_menu.visible = false
	if _solo_progression == null:
		_solo_progression = Progression.load_from(solo_progress_path)
	_make_local(_solo_progression, false, timed)
	_layout()
	_local.start(randi())
	_mixer.restart()


func _enter_versus() -> void:
	_mode = Mode.VERSUS
	_menu.visible = false
	_make_local(Progression.new(), true)
	_local.attack.connect(_net.send_attack)
	_local.board_changed.connect(_net.send_snapshot)
	_remote = Playfield.new()
	_remote.cell_size = REMOTE_CELL
	_remote.interactive = false
	_remote.title = "OPPONENT"
	add_child(_remote)
	_layout()
	_local.set_overlay("Connected!", "Starting...", Palette.GOOD)
	_waiting_for_rematch = true
	_net.send_ready()


func _back_to_menu(status := "") -> void:
	_waiting_for_rematch = false
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
		"solo_timed":
			_start_solo(true)
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
		"reset_progress":
			_solo_progression = Progression.new()
			_solo_progression.save_to(solo_progress_path)
			_menu.set_status("Solo level and cards reset.")
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
	_waiting_for_rematch = false
	_local.progression = Progression.new() # versus levels only last for one match
	_local.start(seed_value)
	_remote.start(seed_value)
	_mixer.restart()
	_remote.set_overlay("")
	_local.set_overlay("")


func _on_peer_snapshot(cells: PackedInt32Array) -> void:
	if _remote:
		_remote.apply_snapshot(cells)


func _on_peer_attack(amount: int) -> void:
	if _local and _mode == Mode.VERSUS:
		_local.receive_attack(amount)


func _on_peer_lost() -> void:
	if _mode != Mode.VERSUS:
		return
	if _local.finished:
		# Both boards filled at about the same time.
		_local.set_overlay("DRAW", "Press Enter for a rematch", Palette.DIM)
		_remote.set_overlay("DRAW", "", Palette.DIM)
		return
	_local.set_overlay("YOU WIN!", "Press Enter for a rematch", Palette.GOOD)
	_remote.set_overlay("DEFEATED", "", Palette.BAD)
	_play("win")


# --- Local player events ----------------------------------------------------

func _on_progression_changed() -> void:
	if _mode == Mode.SOLO and _solo_progression != null:
		_solo_progression.save_to(solo_progress_path)


func _on_local_lost() -> void:
	if _mode == Mode.VERSUS:
		_net.send_lost()
		_local.set_overlay("BOARD FULL - YOU LOSE", "Press Enter for a rematch", Palette.BAD)
	else:
		_local.set_overlay("BOARD FULL - YOU LOSE", "Click or press Enter to restart", Palette.BAD)


func _on_restart_requested() -> void:
	if _mode == Mode.VERSUS:
		if _waiting_for_rematch:
			return
		_waiting_for_rematch = true
		_local.set_overlay("Waiting for opponent...", "", Palette.DIM)
		_net.send_ready()
	elif _mode == Mode.SOLO:
		_local.start(randi())
		_mixer.restart()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_M:
				_mixer.toggle_pause()
			KEY_ESCAPE:
				if _mode == Mode.SOLO or _mode == Mode.VERSUS:
					_back_to_menu()
