extends SceneTree

const OUT := "user://shots/"

func _cards() -> Array[Dictionary]:
	return [
		{"id": "scorer", "name": "High Scorer", "desc": "Every cleared molecule scores +10% more points.", "rarity": 0, "risky": false, "downside": "", "owned": 2, "max": 5, "versus_only": false},
		{"id": "glass", "name": "Glass Cannon", "desc": "Strays you send hit twice as hard.", "rarity": 1, "risky": true, "downside": "Strays you receive are doubled too", "owned": 0, "max": 1, "versus_only": true},
		{"id": "big", "name": "Big Game", "desc": "Molecules need 3+ atoms to clear, but score x3", "rarity": 2, "risky": true, "downside": "Two-atom molecules no longer clear and stay on the board", "owned": 0, "max": 1, "versus_only": false},
	]

func _init() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1e2229")
	bg.size = Vector2(1100, 800)
	root.add_child(bg)
	var holder := Node2D.new()
	holder.position = Vector2(200, 100)
	root.add_child(holder)
	var frame := ColorRect.new()
	frame.color = Color("2a3039")
	frame.size = Vector2(576, 576)
	holder.add_child(frame)
	var ov := CardOverlay.new()
	holder.add_child(ov)
	await _shot(ov, _cards(), Vector2(-1, -1), "card_a.png")
	await _shot(ov, _cards(), Vector2(200 + 0, 0) + Vector2(576.0 / 2, 300), "card_b.png")
	await _shot(ov, _cards().slice(0, 2), Vector2(-1, -1), "card_c.png")
	quit()

func _shot(ov: CardOverlay, cards: Array[Dictionary], mouse: Vector2, file: String) -> void:
	ov.show_offer(cards, 4)
	if mouse.x >= 0:
		var m := InputEventMouseMotion.new()
		ov.handle_input(m, Vector2(288, 250))
	await create_timer(0.7).timeout
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OUT + file)
	ov.hide_offer()
