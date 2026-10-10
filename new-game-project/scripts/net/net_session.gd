class_name NetSession extends Node
## 1v1 networking layer (ENet + high-level multiplayer RPC).
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

var is_host := false
## Set by the host before a match: sent to the client with every game start (rematches too).
var match_options := {}
## Number of cells a snapshot must have: the match's board size (the owner updates it when the
## match options are known).
var expected_cells := CELL_COUNT

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


func close() -> void:
	_unhook()
	if multiplayer.multiplayer_peer != null:
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
	if is_peer_connected():
		_rpc_snapshot.rpc_id(_peer_id, cells)


func send_attack(amount: int) -> void:
	if is_peer_connected():
		_rpc_attack.rpc_id(_peer_id, amount)


func send_lost() -> void:
	if is_peer_connected():
		_rpc_lost.rpc_id(_peer_id)


func send_ready() -> void:
	if not is_peer_connected():
		return
	if is_host:
		_host_ready = true
		_check_start()
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
	_rpc_start.rpc_id(_peer_id, s, match_options)
	game_start.emit(s)


# ---- receiving ----

func _from_peer() -> bool:
	return _peer_id != 0 and multiplayer.get_remote_sender_id() == _peer_id


@rpc("any_peer", "call_remote", "reliable")
func _rpc_snapshot(cells: PackedInt32Array) -> void:
	if not _from_peer() or cells.size() != expected_cells:
		return
	peer_snapshot.emit(cells)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_attack(amount: int) -> void:
	if not _from_peer() or amount < 0 or amount > MAX_ATTACK:
		return
	peer_attack.emit(amount)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_lost() -> void:
	if not _from_peer():
		return
	peer_lost.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ready() -> void:
	if not is_host or not _from_peer():
		return
	_client_ready = true
	_check_start()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_start(s: int, options: Dictionary) -> void:
	if is_host or not _from_peer():
		return
	var clean := {}
	for key in options:
		if (key is String or key is StringName) and (options[key] is String):
			clean[String(key)] = String(options[key])
	options_received.emit(clean)
	game_start.emit(s)


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
