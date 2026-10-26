class_name NetSession extends Node
## 1v1 networking layer. Two transports: a relay (WebSocket, works in the browser and needs no port
## forwarding: host_relay/join_relay) and ENet with high-level multiplayer RPC (host/join, LAN).
## IMPORTANT: @rpc routing is by node path. The NetSession node must have the
## same name and the same parent path on both peers (e.g. both add it as
## child "NetSession" under an identically named node such as /root/Game).

const DEFAULT_PORT := 24680
const CELL_COUNT := Playfield.BOARD_W * Playfield.BOARD_H ## cells of a default board
const MAX_ATTACK := 64

signal connected()
signal disconnected()
signal peer_snapshot(cells: PackedInt32Array)
signal peer_attack(amount: int)
signal peer_lost()
signal game_start(seed: int)
## The host's match options (e.g. the board shape), emitted on the client just before game_start.
## Values are plain strings; the receiver validates them (see GameConfig.from_dict).
signal options_received(options: Dictionary)
## Relay host: the relay created the room; `code` is what the other player enters.
signal room_ready(code: String)

var is_host := false
## Set by the host before a match: sent to the client with every game start (rematches too).
var match_options := {}
## Number of cells a snapshot must have: the match's board size (the owner updates it when the
## match options are known).
var expected_cells := CELL_COUNT

## Why the last relay connection failed (empty when it did not).
var last_error := ""
var room_code := ""

var _relay: RelayTransport = null
var _peer_id := 0 # remote peer id, 0 when none
var _host_ready := false
var _client_ready := false
var _hooked := false
var _last_seed := -1


func _hook() -> void:
	if _hooked:
		return
	_hooked = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _unhook() -> void:
	if not _hooked:
		return
	_hooked = false
	multiplayer.peer_connected.disconnect(_on_peer_connected)
	multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	multiplayer.connection_failed.disconnect(_on_connection_failed)
	multiplayer.server_disconnected.disconnect(_on_server_disconnected)


func host(port := DEFAULT_PORT) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1)
	if err != OK:
		return err
	is_host = true
	_hook()
	multiplayer.multiplayer_peer = peer
	return OK


func join(address: String, port := DEFAULT_PORT) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	is_host = false
	_hook()
	multiplayer.multiplayer_peer = peer
	return OK


func host_relay(url: String) -> void:
	close()
	is_host = true
	_start_relay()
	_relay.host(url, "host")


func join_relay(url: String, code: String) -> void:
	close()
	is_host = false
	_start_relay()
	_relay.join(url, code, "guest")


func _start_relay() -> void:
	last_error = ""
	room_code = ""
	_relay = RelayTransport.new()
	add_child(_relay)
	_relay.room_ready.connect(_on_relay_room_ready)
	_relay.peer_joined.connect(_on_relay_peer_joined)
	_relay.peer_left.connect(_on_relay_peer_left)
	_relay.host_presence.connect(_on_relay_host_presence)
	_relay.message.connect(_on_relay_message)
	_relay.failed.connect(_on_relay_failed)


func close() -> void:
	if _relay != null:
		_relay.shutdown()
		_relay = null
	_unhook()
	if is_inside_tree() and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_peer_id = 0
	_host_ready = false
	_client_ready = false
	is_host = false


func is_peer_connected() -> bool:
	return _peer_id != 0


# ---- sending ----

func send_snapshot(cells: PackedInt32Array) -> void:
	if not is_peer_connected():
		return
	if _relay != null:
		_relay_send({"k": "snap", "cells": cells})
	else:
		_rpc_snapshot.rpc_id(_peer_id, cells)


func send_attack(amount: int) -> void:
	if not is_peer_connected():
		return
	if _relay != null:
		_relay_send({"k": "attack", "n": amount})
	else:
		_rpc_attack.rpc_id(_peer_id, amount)


func send_lost() -> void:
	if not is_peer_connected():
		return
	if _relay != null:
		_relay_send({"k": "lost"})
	else:
		_rpc_lost.rpc_id(_peer_id)


func send_ready() -> void:
	if not is_peer_connected():
		return
	if is_host:
		_host_ready = true
		_check_start()
	elif _relay != null:
		_relay_send({"k": "ready"})
	else:
		_rpc_ready.rpc_id(_peer_id)


func _check_start() -> void:
	if not (_host_ready and _client_ready and is_peer_connected()):
		return
	_host_ready = false
	_client_ready = false
	var s := randi()
	while s == _last_seed:
		s = randi()
	_last_seed = s
	if _relay != null:
		_relay_send({"k": "start", "seed": s, "options": match_options})
	else:
		_rpc_start.rpc_id(_peer_id, s, match_options)
	game_start.emit(s)


# ---- receiving ----

func _from_peer() -> bool:
	return _peer_id != 0 and multiplayer.get_remote_sender_id() == _peer_id


@rpc("any_peer", "call_remote", "reliable")
func _rpc_snapshot(cells: PackedInt32Array) -> void:
	if _from_peer():
		_got_snapshot(cells)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_attack(amount: int) -> void:
	if _from_peer():
		_got_attack(amount)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_lost() -> void:
	if _from_peer():
		peer_lost.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ready() -> void:
	if _from_peer():
		_got_ready()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_start(s: int, options: Dictionary) -> void:
	if _from_peer():
		_got_start(s, options)


func _got_snapshot(cells: PackedInt32Array) -> void:
	if cells.size() == expected_cells:
		peer_snapshot.emit(cells)


func _got_attack(amount: int) -> void:
	if amount >= 0 and amount <= MAX_ATTACK:
		peer_attack.emit(amount)


func _got_ready() -> void:
	if not is_host:
		return
	_client_ready = true
	_check_start()


func _got_start(s: int, options: Dictionary) -> void:
	if is_host:
		return
	var clean := {}
	for key in options:
		if (key is String or key is StringName) and (options[key] is String):
			clean[String(key)] = String(options[key])
	options_received.emit(clean)
	game_start.emit(s)


# ---- relay ----

func _relay_send(msg: Dictionary) -> void:
	if is_host:
		_relay.send_to(_peer_id, msg)
	else:
		_relay.send_host(msg)


func _on_relay_room_ready(info: Dictionary) -> void:
	if is_host:
		room_code = str(info.get("code", ""))
		room_ready.emit(room_code)
	elif _peer_id == 0:
		_peer_id = 1
		connected.emit()


func _on_relay_peer_joined(peer: int, _name: String, _resumed: bool) -> void:
	if not is_host or _peer_id != 0:
		return
	_peer_id = peer
	_relay.lock(true) # one opponent only
	connected.emit()


func _on_relay_peer_left(peer: int) -> void:
	if not is_host or peer != _peer_id:
		return
	_peer_id = 0
	_host_ready = false
	_client_ready = false
	_relay.lock(false)
	disconnected.emit()


func _on_relay_host_presence(online: bool) -> void:
	if not online and not is_host and _peer_id != 0:
		_peer_id = 0
		disconnected.emit()


func _on_relay_failed(_code: int, reason: String) -> void:
	last_error = reason
	_peer_id = 0
	disconnected.emit()


func _on_relay_message(from: int, data: Variant) -> void:
	if from != _peer_id or not (data is Dictionary):
		return
	match str(data.get("k", "")):
		"snap":
			if data.get("cells") is PackedInt32Array:
				_got_snapshot(data["cells"])
		"attack":
			if data.get("n") is int:
				_got_attack(data["n"])
		"lost":
			peer_lost.emit()
		"ready":
			_got_ready()
		"start":
			if data.get("seed") is int and data.get("options") is Dictionary:
				_got_start(data["seed"], data["options"])


# ---- connection events ----

func _on_peer_connected(id: int) -> void:
	if not is_host:
		return # client learns of the link via connected_to_server
	if _peer_id != 0:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	_peer_id = id
	connected.emit()


func _on_peer_disconnected(id: int) -> void:
	if is_host and id == _peer_id:
		_peer_id = 0
		_host_ready = false
		_client_ready = false
		disconnected.emit()


func _on_connected_to_server() -> void:
	_peer_id = 1
	connected.emit()


func _on_connection_failed() -> void:
	_peer_id = 0
	disconnected.emit()


func _on_server_disconnected() -> void:
	_peer_id = 0
	_host_ready = false
	_client_ready = false
	disconnected.emit()
