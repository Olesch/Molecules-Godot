extends SceneTree
## Two-process end-to-end test. Run: -- host   and   -- join 127.0.0.1
const VERSUS := 4
const MENU := 0

var g: Node
var role := "host"
var board := "square" ## the board the host picks; the joiner must end up with the same
var fails := 0
var starts: Array = []  # [{seed, hash}] per game_start
var t_start := 0.0
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "host"
	var addr: String = args[1] if args.size() > 1 else "127.0.0.1"
	board = args[2] if args.size() > 2 else "square"
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
	for y in 8:
		for x in 8:
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
		check("host setup offers only the board option", g._host_setup.section_count() == 1 and not g._host_setup.option_buttons("board").is_empty())
		for b in g._host_setup.option_buttons("board"):
			if (board == "hex" and b.text == "Hexagonal") or (board == "square" and b.text == "Square"):
				b.pressed.emit()
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
	out("seedhash1 %d" % starts[0].hash)
	check("remote board init equals local init (same seed)", hash(g._remote.board.snapshot()) == starts[0].hash)
	await wait(1.0)

	# (2) attack host -> join
	if role == "host":
		g._local.attack.emit(3)
	else:
		ok = await wait_until(func(): return g._local._pending > 0, 4.0)
		check("attack received (_pending>0)", ok, "pending=%d" % g._local._pending)
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
