extends SceneTree
# godot --headless --path . --script res://tests/net_test.gd -- host
# godot --headless --path . --script res://tests/net_test.gd -- join 127.0.0.1

var net: NetSession
var role := "host"
var starts: Array[int] = []
var got_snap := false
var got_attack := false
var got_lost := false
var sent_rematch := false
var finished := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		role = args[0]
	var game := Node.new()
	game.name = "Game"
	root.add_child(game)
	net = NetSession.new()
	net.name = "NetSession"
	game.add_child(net)
	net.connected.connect(_on_connected)
	net.disconnected.connect(_on_disconnected)
	net.game_start.connect(_on_start)
	net.peer_snapshot.connect(_on_snap)
	net.peer_attack.connect(_on_attack)
	net.peer_lost.connect(_on_lost)
	await process_frame
	var err: Error
	if role == "host":
		err = net.host()
	else:
		err = net.join(args[1] if args.size() > 1 else "127.0.0.1")
	print("NETTEST ", role, " start err=", err)
	if err != OK:
		quit(1)
		return
	create_timer(10.0).timeout.connect(_on_timeout)


func _on_timeout() -> void:
	if not finished:
		print("NETTEST TIMEOUT")
		quit(1)


func _on_snap(c: PackedInt32Array) -> void:
	got_snap = c.size() == 64 and c[5] == 7
	print("NETTEST snapshot ", c.size())
	_check()


func _on_attack(a: int) -> void:
	got_attack = a == 3
	print("NETTEST attack ", a)
	_check()


func _on_lost() -> void:
	got_lost = true
	print("NETTEST lost")
	_check()


func _on_connected() -> void:
	print("NETTEST connected is_peer_connected=", net.is_peer_connected())
	net.send_ready()


func _on_start(s: int) -> void:
	starts.append(s)
	print("NETTEST game_start #", starts.size(), " seed=", s)
	if starts.size() == 1:
		var cells := PackedInt32Array()
		cells.resize(64)
		cells[5] = 7
		net.send_attack(3)
		net.send_lost()
		# unreliable snapshot: resend a few times
		for i in 4:
			net.send_snapshot(cells)
			await create_timer(0.2).timeout
	elif starts.size() == 2:
		if starts[0] == starts[1]:
			print("NETTEST FAIL same seed on rematch")
			quit(1)
			return
		if role == "host":
			print("NETTEST waiting for client close")
		else:
			await create_timer(0.5).timeout
			net.close()
			print("NETTEST PASS (client closed)")
			finished = true
			quit(0)


func _check() -> void:
	if got_snap and got_attack and got_lost and not sent_rematch:
		sent_rematch = true
		print("NETTEST all received, requesting rematch")
		net.send_ready()


func _on_disconnected() -> void:
	print("NETTEST disconnected")
	if role == "host" and starts.size() == 2:
		print("NETTEST PASS (host saw disconnect)")
		finished = true
		quit(0)
	elif not finished:
		quit(1)
