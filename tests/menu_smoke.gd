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
	by["Solo"].pressed.emit()
	by["Host online game"].pressed.emit()
	by["Join game"].pressed.emit() # no code yet: refused
	(m.find_children("*", "LineEdit", true, false)[0] as LineEdit).text = "k7qx2m"
	by["Join game"].pressed.emit()
	m.set_busy(true)
	assert(by["Solo"].disabled and by["Cancel"].visible)
	by["Cancel"].pressed.emit()
	m.set_busy(false)
	assert(not by["Solo"].disabled and not by["Cancel"].visible)
	m.set_status("hello")
	print(got)
	print(m.get_default_status_for("host"))
	print(m.get_default_status_for("join"))
	var ok: bool = got == [["solo", ""], ["host", ""], ["join", "K7QX2M"], ["cancel", ""]]
	print("OK" if ok else "FAIL")
	quit(0 if ok else 1)
