extends SceneTree

var got: Array = []

func _initialize() -> void:
	var m := Menu.new()
	root.add_child(m)
	await process_frame
	m.choose.connect(func(mode: String, addr: String) -> void: got.append([mode, addr]))
	var btns: Array = m.find_children("*", "Button", true, false)
	var by := {}
	for b in btns:
		by[b.text] = b
	by["Solo: turn-based"].pressed.emit()
	by["Solo: time pressure"].pressed.emit()
	by["Host online game"].pressed.emit()
	by["Join game"].pressed.emit()
	m.set_busy(true)
	assert(by["Solo: turn-based"].disabled and by["Solo: time pressure"].disabled and by["Cancel"].visible)
	by["Cancel"].pressed.emit()
	m.set_busy(false)
	assert(not by["Solo: turn-based"].disabled and not by["Solo: time pressure"].disabled and not by["Cancel"].visible)
	m.set_status("hello")
	print(got)
	print(m.get_default_status_for("host"))
	print(m.get_default_status_for("join"))
	var ok: bool = got == [["solo", ""], ["solo_timed", ""], ["host", ""], ["join", "127.0.0.1"], ["cancel", ""]]
	print("OK" if ok else "FAIL")
	quit(0 if ok else 1)
