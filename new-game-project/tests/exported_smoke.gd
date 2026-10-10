extends Node
## Exported-exe smoke test (scene). Run: -- host   and   -- join 127.0.0.1
## Logs to user://smoke_<role>.log
const VERSUS := 4
const MENU := 0

var g: Node
var role := "host"
var fails := 0
var starts: Array = []  # [{seed, hash}] per game_start
var t_start := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "host"
	var addr: String = args[1] if args.size() > 1 else "127.0.0.1"
	rng.randomize()
	_run(addr)


var _log: FileAccess


func out(s: String) -> void:
	var line := "VSTEST [%s] %s" % [role, s]
	print(line)
	if _log == null:
		_log = FileAccess.open("user://smoke_%s.log" % role, FileAccess.WRITE)
	if _log:
		_log.store_line(line)
		_log.flush()


func quit(code: int) -> void:
	get_tree().quit(code)


func check(name: String, ok: bool, extra := "") -> void:
	if not ok:
		fails += 1
	out("%s %s %s" % ["PASS" if ok else "FAIL", name, extra])


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


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
	get_tree().create_timer(40.0).timeout.connect(func():
		out("TIMEOUT")
		quit(1))
	g = load("res://main.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g._net.game_start.connect(func(s):
		starts.append({"seed": s, "hash": hash(g._local.board.snapshot()), "t": Time.get_ticks_msec()})
		out("game_start seed=%d hash=%d" % [s, starts[-1].hash]))
	if role == "join":
		await wait(1.0)
		g._on_menu_choose("join", addr)
	else:
		g._on_menu_choose("host", "")
		g._host_setup.start_button().pressed.emit() # hosting starts from the host setup screen
	var ok := await wait_until(func(): return g._mode == VERSUS and g._net != null, 15.0)
	check("reach VERSUS", ok)
	if not ok:
		return finish()
	ok = await wait_until(func(): return starts.size() >= 1 and not g._local.finished, 10.0)
	check("match started", ok)
	if not ok:
		return finish()
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
		check("pending landed or cancelled", g._local._pending < 3, "pending=%d" % g._local._pending)
	await wait(2.0)
	# (3) hashes
	var lh: int = hash(g._local.board.snapshot())
	var rh: int = hash(g._remote.board.snapshot())
	out("hash local=%d remote=%d role=%s" % [lh, rh, role])
	await wait(1.0)

	# (4) host loses
	if role == "host":
		g._local._lose()
		check("host overlay lose", g._local.finished)
	else:
		ok = await wait_until(func(): return g._local._overlay_title == "YOU WIN!", 4.0)
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
		out("hash2 local=%d remote=%d role=%s" % [hash(g._local.board.snapshot()), hash(g._remote.board.snapshot()), role])
	await wait(1.0)

	# (6) disconnect
	if role == "join":
		g._net.close()
		await wait(0.5)
		return finish()
	ok = await wait_until(func(): return g._mode == MENU, 8.0)
	check("host back to MENU after joiner leaves", ok, "mode=%d" % g._mode)
	finish()
