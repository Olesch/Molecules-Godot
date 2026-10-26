extends SceneTree
## Two NetSessions (host + guest) through the live relay. Run: godot --headless --path . --script res://tests/relay_net_test.gd
## Needs internet; skipped by run_all.

var host: NetSession
var guest: NetSession
var log: Array = []


func _initialize() -> void:
	_run()


func _mk(n: String) -> NetSession:
	var g := Node.new()
	g.name = n
	root.add_child(g)
	var s := NetSession.new()
	s.name = "NetSession"
	g.add_child(s)
	return s


func _wait(cond: Callable, sec: float) -> bool:
	var t := 0.0
	while t < sec and not cond.call():
		await create_timer(0.05).timeout
		t += 0.05
	return cond.call()


func _check(name: String, ok: bool) -> void:
	print("RELAYTEST %s %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		log.append(name)


func _run() -> void:
	host = _mk("H")
	guest = _mk("G")
	host.expected_cells = 4
	guest.expected_cells = 4
	host.match_options = {"board_shape": "hex"}
	var got := {"snap": null, "attack": -1, "lost": false, "start": [], "opts": {}}
	guest.peer_snapshot.connect(func(c): got["snap"] = c)
	host.peer_attack.connect(func(n): got["attack"] = n)
	host.peer_lost.connect(func(): got["lost"] = true)
	guest.options_received.connect(func(o): got["opts"] = o)
	guest.game_start.connect(func(s): got["start"].append(s))
	host.host_relay(RelayTransport.DEFAULT_URL)
	_check("room code", await _wait(func(): return host.room_code.length() == 6, 10.0))
	guest.join_relay(RelayTransport.DEFAULT_URL, host.room_code)
	_check("paired", await _wait(func(): return host.is_peer_connected() and guest.is_peer_connected(), 10.0))
	host.send_snapshot(PackedInt32Array([1, 2, 3, 4]))
	_check("snapshot", await _wait(func(): return got["snap"] != null, 5.0) and got["snap"] == PackedInt32Array([1, 2, 3, 4]))
	guest.send_attack(3)
	_check("attack", await _wait(func(): return got["attack"] == 3, 5.0))
	guest.send_lost()
	_check("lost", await _wait(func(): return got["lost"], 5.0))
	host.send_ready()
	guest.send_ready()
	_check("start + options", await _wait(func(): return got["start"].size() == 1, 5.0) and got["opts"] == {"board_shape": "hex"})
	guest.close()
	_check("host sees leave", await _wait(func(): return not host.is_peer_connected(), 5.0))
	var g2 := _mk("G2")
	g2.join_relay(RelayTransport.DEFAULT_URL, "ZZZZZZ")
	_check("bad code fails", await _wait(func(): return g2.last_error != "", 10.0))
	host.close()
	await create_timer(0.6).timeout
	quit(1 if not log.is_empty() else 0)
