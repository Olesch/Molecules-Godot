class_name RelayTransport
extends Node
## Online transport through the relay (the Cloudflare Worker of the TTA project, relay/ there): every player, the host too, only opens an
## outgoing WebSocket, so nobody needs port forwarding. The relay forwards messages between the host (peer 1) and
## the clients (peers 2, 3, ...) of a room; the protocol is described in TTA's relay/README.md.
##
## This class only moves messages: game payloads are any Godot value, sent as
## var_to_bytes, zstd-compressed and base64-encoded (JSON would turn every integer into a float).
## A dropped connection is re-established with the token the relay handed out, so a seat survives network hiccups.

## Emitted once the relay confirmed the room: host {code, token, peers: [{peer, name, online}]},
## client {code, peer, token, host_name, host_online}. Emitted again (with resumed = true) after a reconnect.
signal room_ready(info: Dictionary)
## Host: a client joined (resumed = it reconnected with its token).
signal peer_joined(peer: int, peer_name: String, resumed: bool)
## Host: a client's connection dropped (its peer id stays reserved for a reconnect).
signal peer_left(peer: int)
## A game message from `from` (1 = host).
signal message(from: int, data: Variant)
## Client: the host dropped (false) or came back (true).
signal host_presence(online: bool)
## Connection state for the UI: "connecting", "online", "reconnecting", "closed".
signal link_changed(state: String)
## Fatal: the room is gone, the seat was taken over, the request was refused, or reconnecting gave up.
signal failed(code: int, reason: String)

const PROTOCOL := 1
## Address of the deployed relay shared with the TTA project; it knows nothing about the game.
const DEFAULT_URL := "wss://pixieworld-relay.olesch.workers.dev"
const PING_EVERY := 25.0
const RECONNECT_DELAYS := [1.0, 2.0, 4.0, 8.0, 15.0]
const RECONNECT_GIVE_UP := 600.0       # seconds without a connection before giving up
const MAX_PAYLOAD := 900 * 1024        # the relay (Cloudflare) refuses WebSocket messages above 1 MiB
const MAX_UNPACKED := 32 * 1024 * 1024
## Close codes of the relay after which reconnecting makes no sense.
const FATAL_CODES := [4000, 4001, 4003, 4004, 4005, 4006, 4007, 4008, 4010]

var role := ""            # "host" / "client" / "" (not connected)
var url := ""
var code := ""
var token := ""
var peer := 0
var player_name := ""
var link := "closed"

var _ws: WebSocketPeer = null
var _open := false
var _ready_once := false   # the room was confirmed at least once (reconnects only make sense after that)
var _ping_left := PING_EVERY
var _retry_left := -1.0
var _retry_n := 0
var _down_since := 0.0
var _last_error := ""
var _closing := false
var _close_deadline := 0
var _close_at := 0
var _free_when_closed := false


func _init() -> void:
	set_process(false)


## Open a new room as its host.
func host(relay_url: String, name_: String) -> void:
	role = "host"
	url = relay_url.strip_edges().trim_suffix("/")
	player_name = name_
	code = ""
	token = ""
	_connect()


## Join the room `room_code` as a new player.
func join(relay_url: String, room_code: String, name_: String) -> void:
	role = "client"
	url = relay_url.strip_edges().trim_suffix("/")
	player_name = name_
	code = room_code.strip_edges().to_upper()
	token = ""
	_connect()


## Go back into a room with a token received earlier (after a restart of the game).
func resume(relay_url: String, room_code: String, token_: String, as_host: bool) -> void:
	role = "host" if as_host else "client"
	url = relay_url.strip_edges().trim_suffix("/")
	code = room_code.strip_edges().to_upper()
	token = token_
	_ready_once = true
	_connect()


## Host: send `data` to one client (peer id), several (Array) or all (0).
func send_to(to, data: Variant) -> bool:
	return _send_msg({"t": "msg", "to": to, "data": _pack(data)})


## Client: send `data` to the host.
func send_host(data: Variant) -> bool:
	return _send_msg({"t": "msg", "data": _pack(data)})


func is_online() -> bool:
	return link == "online"


## Host: refuse (true) or allow (false) new players; reconnects always work.
func lock(on: bool) -> void:
	_send_raw({"t": "lock", "on": on})


## Host: remove a client from the room (its token becomes invalid).
func kick(p: int, reason: String) -> void:
	_send_raw({"t": "kick", "peer": p, "reason": reason})


## Leave the room (the host closes it for everyone). The close handshake finishes in the background.
func close() -> void:
	if _closing:
		return
	_closing = true
	_close_at = Time.get_ticks_msec()
	if _ws != null and _open and role == "host":
		_send_raw({"t": "close", "reason": "the host left the game"})
		_close_at += 300       # let the room close reach the relay before the socket goes
	if _ws != null:
		_close_deadline = _close_at + 2000
		set_process(true)
	else:
		set_process(false)
	_open = false
	_retry_left = -1.0
	role = ""
	_set_link("closed")


## close() and free this node once the connection is closed (it keeps polling for up to 2 s, so messages already
## sent - like the host's room close - still go out). Keep it in the tree until then.
func shutdown() -> void:
	close()
	_free_when_closed = true
	if _ws == null:
		queue_free()


## Not on _exit_tree: NetSession keeps the transport, which must keep the connection.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _ws != null:
		_ws.close(1000, "bye")
		_ws.poll()


# ------------------------------------------------------------------ connection

func _connect() -> void:
	_closing = false
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 4 * 1024 * 1024
	_ws.outbound_buffer_size = 4 * 1024 * 1024
	_ws.max_queued_packets = 8192
	var q := "v=%d" % PROTOCOL
	var path := ""
	if role == "host":
		path = "/host"
		if token != "":
			q += "&code=%s&token=%s" % [code.uri_encode(), token.uri_encode()]
		else:
			q += "&name=%s" % player_name.uri_encode()
	else:
		path = "/join/" + code.uri_encode()
		q += ("&token=%s" % token.uri_encode()) if token != "" else ("&name=%s" % player_name.uri_encode())
	var err := _ws.connect_to_url(url + path + "?" + q)
	_open = false
	_set_link("reconnecting" if _ready_once else "connecting")
	set_process(true)
	if err != OK:
		_ws = null
		_on_closed(0, "cannot connect to %s (%s)" % [url, error_string(err)])


func _process(delta: float) -> void:
	if _closing:
		if _ws != null:
			if _close_at > 0 and Time.get_ticks_msec() >= _close_at:
				_close_at = 0
				_ws.close(1000, "bye")
			_ws.poll()
			if _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED or Time.get_ticks_msec() > _close_deadline:
				_ws = null
		if _ws == null:
			set_process(false)
			if _free_when_closed:
				queue_free()
		return
	if _ws == null:
		if _retry_left >= 0.0:
			_retry_left -= delta
			if _retry_left < 0.0:
				_connect()
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _open:
		_open = true
		_ping_left = PING_EVERY
	while _ws != null and _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		if _ws.was_string_packet():
			_on_text(pkt.get_string_from_utf8())
	if _ws == null:
		return
	if st == WebSocketPeer.STATE_OPEN:
		_ping_left -= delta
		if _ping_left <= 0.0:
			_ping_left = PING_EVERY
			_ws.send_text("ping")
	elif st == WebSocketPeer.STATE_CLOSED:
		var c := _ws.get_close_code()
		var r := _ws.get_close_reason()
		_ws = null
		_open = false
		_on_closed(c, r)


func _on_closed(close_code: int, reason: String) -> void:
	if _closing or role == "":
		return
	if reason == "" and _last_error != "":
		reason = _last_error
	if close_code in FATAL_CODES or not _ready_once:
		var why := reason if reason != "" else ("could not reach the relay at %s" % url)
		role = ""
		_set_link("closed")
		set_process(false)
		failed.emit(close_code, why)
		return
	# Unexpected drop: try again with the token.
	var now := Time.get_ticks_msec() / 1000.0
	if link == "online":
		_down_since = now
		_retry_n = 0
	if now - _down_since > RECONNECT_GIVE_UP:
		role = ""
		_set_link("closed")
		set_process(false)
		failed.emit(close_code, "the connection to the relay was lost")
		return
	_set_link("reconnecting")
	_retry_left = RECONNECT_DELAYS[mini(_retry_n, RECONNECT_DELAYS.size() - 1)]
	_retry_n += 1


func _on_text(text: String) -> void:
	if text == "pong":
		return
	var m = JSON.parse_string(text)
	if not (m is Dictionary):
		return
	match str(m.get("t", "")):
		"room", "joined":
			code = str(m.get("code", code))
			token = str(m.get("token", token))
			peer = int(m.get("peer", 0))
			_ready_once = true
			_retry_n = 0
			_last_error = ""
			_set_link("online")
			room_ready.emit(m)
		"join":
			peer_joined.emit(int(m.get("peer", 0)), str(m.get("name", "")), bool(m.get("resumed", false)))
		"leave":
			peer_left.emit(int(m.get("peer", 0)))
		"host_left":
			host_presence.emit(false)
		"host_back":
			host_presence.emit(true)
		"msg":
			var d = _unpack(m.get("data"))
			if d != null:
				message.emit(int(m.get("from", 0)), d)
		"error":
			_last_error = str(m.get("reason", ""))
			if int(m.get("code", 0)) == 0:
				push_warning("Relay: " + _last_error)


func _set_link(s: String) -> void:
	if s != link:
		link = s
		link_changed.emit(s)


func _send_raw(obj: Dictionary) -> bool:
	if _ws == null or not _open or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	return _ws.send_text(JSON.stringify(obj)) == OK


func _send_msg(obj: Dictionary) -> bool:
	if obj["data"] == null:
		return false
	return _send_raw(obj)


# ------------------------------------------------------------------ payload encoding

static func _pack(v: Variant) -> Variant:
	var raw := var_to_bytes(v)
	var z := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var b64 := Marshalls.raw_to_base64(z)
	if b64.length() > MAX_PAYLOAD:
		push_error("RelayTransport: message too large (%d bytes encoded)" % b64.length())
		return null
	return {"n": raw.size(), "z": b64}


static func _unpack(d: Variant) -> Variant:
	if not (d is Dictionary) or not d.has("z") or not d.has("n"):
		return null
	var n := int(d["n"])
	if n <= 0 or n > MAX_UNPACKED:
		return null
	var z := Marshalls.base64_to_raw(str(d["z"]))
	var raw := z.decompress(n, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != n:
		return null
	return bytes_to_var(raw)   # never decodes objects (bytes_to_var_with_objects would)
