extends SceneTree

var fails := 0
var got := ""

func check(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func _on_picked(id: String) -> void:
	got = id

func _init() -> void:
	var ov := CardOverlay.new()
	root.add_child(ov)
	ov.picked.connect(_on_picked)
	var cards: Array[Dictionary] = []
	for n in ["a", "b", "c"]:
		cards.append({"id": n, "name": n, "desc": "d", "rarity": 0, "risky": false, "downside": "", "owned": 0, "max": 1, "versus_only": false})
	var k := InputEventKey.new()
	k.keycode = KEY_2
	k.pressed = true
	check(not ov.handle_input(k, Vector2.ZERO), "closed: not consumed")
	ov.show_offer(cards, 2)
	check(ov.is_open(), "open")
	check(ov.handle_input(k, Vector2.ZERO), "key consumed")
	check(got == "b", "KEY_2 picks b")
	check(not ov.is_open(), "closed after pick")
	got = ""
	ov.show_offer(cards, 2)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	check(ov.handle_input(click, Vector2(2, 2)), "outside consumed")
	check(got == "" and ov.is_open(), "outside no pick")
	var c := ov.card_rect(2).get_center()
	check(ov.handle_input(click, c), "inside consumed")
	check(got == "c" and not ov.is_open(), "click picks c")
	check(not ov.handle_input(click, c), "closed click not consumed")
	print("DONE fails=", fails)
	quit(fails)
