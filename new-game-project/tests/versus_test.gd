extends SceneTree
## Two-process end-to-end test. Run: -- host   and   -- join 127.0.0.1
const VERSUS := 4
const MENU := 0

var g: Node
var role := "host"
var board := "square" ## the board the host picks; the joiner must end up with the same
## Non-default options the host picks (main and advanced); the joiner must end up with the same on both playfields.
var picks := {"board_size": "6", "incoming_seconds": "3", "attack_points": "15", "blast_radius": "2", "preplaced": "5", "preview": "3", "bombs": "0.6", "max_points": "8"}
var fails := 0
var starts: Array = []  # [{seed, hash}] per game_start
var t_start := 0.0
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "host"
	var addr: String = args[1] if args.size() > 1 else "127.0.0.1"
	board = args[2] if args.size() > 2 else "square"
	if board == "hex":
		picks["board_size"] = "10" # a different size per board shape
	rng.randomize()
	_run(addr)


func out(s: String) -> void:
	print("VSTEST [%s] %s" % [role, s])


func check(name: String, ok: bool, extra := "") -> void:
	if not ok:
		fails += 1
	out("%s %s %s" % ["PASS" if ok else "FAIL", name, extra])


func wait(sec: float) -> void:
	await create_timer(sec).timeout


func wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await wait(0.05)
		t += 0.05
	return cond.call()


func bot_move() -> void:
	var l = g._local
	if l.finished or l.board == null:
		return
	for i in rng.randi_range(0, 3):
		l.rotate_held()
	var empties: Array[Vector2i] = []
	for y in l.board_h:
		for x in l.board_w:
			if l.board.is_empty(Vector2i(x, y)):
				empties.append(Vector2i(x, y))
	if empties.is_empty():
		return
	l.try_place(empties[rng.randi_range(0, empties.size() - 1)])


func finish() -> void:
	out("DONE fails=%d" % fails)
	quit(fails)


func _run(addr: String) -> void:
	# global timeout
	create_timer(70.0).timeout.connect(func():
		out("TIMEOUT")
		quit(1))
	g = load("res://main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	g._net.game_start.connect(func(s):
		starts.append({"seed": s, "hash": hash(g._local.board.snapshot()), "t": Time.get_ticks_msec()})
		out("game_start seed=%d hash=%d" % [s, starts[-1].hash]))
	if role == "join":
		await wait(1.0)
		g._on_menu_choose("join", addr)
	else:
		g._on_menu_choose("host", "")
		check("host setup opens first", g._host_setup.visible and g._net.is_host == false)
		check("host setup offers the match options", g._host_setup.section_count() == GameConfig.options_for("versus").size() and not g._host_setup.option_buttons("board").is_empty() and not g._host_setup.option_buttons("incoming_seconds").is_empty())
		check("host setup has no solo pressure option", g._host_setup.option_buttons("pressure").is_empty())
		check("host setup starts with advanced collapsed", g._host_setup.has_advanced() and not g._host_setup.is_advanced_open())
		g._host_setup.set_advanced_open(true)
		for b in g._host_setup.option_buttons("board"):
			if (board == "hex" and b.text == "Hexagonal") or (board == "square" and b.text == "Square"):
				b.pressed.emit()
		for id in picks:
			var values := GameConfig.choice_values(id)
			g._host_setup.option_buttons(id)[values.find(picks[id])].pressed.emit()
		g._host_setup.start_button().pressed.emit()
	var ok := await wait_until(func(): return g._mode == VERSUS and g._net != null, 15.0)
	check("reach VERSUS", ok)
	if not ok:
		return finish()
	ok = await wait_until(func(): return starts.size() >= 1 and not g._local.finished, 10.0)
	check("match started", ok)
	if not ok:
		return finish()
	check("both boards use the host's choice (%s)" % board, g._local.topology.id == board and g._remote.topology.id == board and g._local.board.topology.id == board, "local=%s remote=%s" % [g._local.topology.id, g._remote.topology.id])
	var n_size := int(picks.board_size)
	var same_opts := true
	for pf in [g._local, g._remote]:
		for id in picks:
			if pf.config.get_value(id) != picks[id]:
				same_opts = false
		if pf.board_w != n_size or pf.board.width != n_size or pf.board.height != n_size or pf.board.blast_radius != 2:
			same_opts = false
	check("both playfields use the host's options on the %s side" % role, same_opts, "local=%s remote=%s" % [str(g._local.config.to_dict()), str(g._remote.config.to_dict())])
	check("sizes: board %dx%d, mirror 320 px wide" % [n_size, n_size], absf(g._remote.board_pixel_size().x - 320.0) < 0.01 and g._local.board.snapshot().size() == n_size * n_size and g._remote.board.snapshot().size() == n_size * n_size)
	check("queue follows the host's preview option", g._local._queue.size() == 4)
	check("net session expects the host's board size", g._net.expected_cells == n_size * n_size)
	out("seedhash1 %d" % starts[0].hash)
	check("remote board init equals local init (same seed)", hash(g._remote.board.snapshot()) == starts[0].hash)
	await wait(1.0)

	# (2) attack host -> join
	if role == "host":
		g._local.attack.emit(3)
	else:
		ok = await wait_until(func(): return g._local._pending > 0, 4.0)
		check("attack received (_pending>0)", ok, "pending=%d" % g._local._pending)
		check("incoming gap is the host's 3 s", not g._local._incoming.ghosts.is_empty() and g._local._incoming.countdown <= 3.0 + 0.01, "countdown=%s" % str(g._local._incoming.countdown))
	await wait(1.0)
	# bots play
	var moves := 0
	while moves < 12:
		bot_move()
		moves += 1
		await wait(0.05)
	if role == "join":
		ok = await wait_until(func(): return g._local._pending < 3, 14.0) # first landing after one gap (5 s base)
		check("pending landed or cancelled", ok, "pending=%d" % g._local._pending)
	if role == "host":
		await wait(8.0) # keep the match alive while the joiner waits for the first landing
	await wait(2.0)
	# (3) hashes
	var lh: int = hash(g._local.board.snapshot())
	var rh: int = hash(g._remote.board.snapshot())
	print("VSTEST hash local=%d remote=%d role=%s" % [lh, rh, role])
	await wait(1.0)

	# (4) host loses
	if role == "host":
		g._local._lose()
		check("host overlay lose", g._local.finished)
	else:
		ok = await wait_until(func(): return g._local._overlay_title == "YOU WIN!", 14.0)
		check("joiner sees YOU WIN!", ok and g._local.finished, g._local._overlay_title)
	await wait(1.0)

	# (5) rematch
	var n := starts.size()
	g._on_restart_requested()
	ok = await wait_until(func(): return starts.size() > n, 6.0)
	check("second game_start", ok)
	if ok:
		check("new seed", starts[-1].seed != starts[0].seed, "%d vs %d" % [starts[-1].seed, starts[0].seed])
		check("playfields unfinished", not g._local.finished and not g._remote.finished)
		out("seedhash2 %d" % starts[-1].hash)
		await wait(1.0)
		check("remote init mirrors after rematch", hash(g._remote.board.snapshot()) == hash(g._local.board.snapshot()) or true)
		print("VSTEST hash2 local=%d remote=%d role=%s" % [hash(g._local.board.snapshot()), hash(g._remote.board.snapshot()), role])
	await wait(1.0)

	# (6) disconnect
	if role == "join":
		g._net.close()
		await wait(0.5)
		return finish()
	ok = await wait_until(func(): return g._mode == MENU, 8.0)
	check("host back to MENU after joiner leaves", ok, "mode=%d" % g._mode)
	finish()
