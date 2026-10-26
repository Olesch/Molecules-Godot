extends SceneTree
## godot --path . --resolution 1100x860 --script res://tests/setup_screen_shot.gd

const OUT := "user://shots/"


func _init() -> void:
	_run()


func _run() -> void:
	var s := SetupScreen.new()
	root.add_child(s)
	var cfg := GameConfig.new()
	cfg.set_value("pressure", GameConfig.PRESSURE_TIMED)
	s.set_config(cfg)
	await _shot("setup_a.png")
	s.queue_free()

	var fake: Array[Dictionary] = []
	for n in 4:
		fake.append({"id": "opt%d" % n, "label": ["Pressure", "Board size", "Atom set", "Starting cards"][n], "default": "b", "choices": [
			{"value": "a", "label": "Small", "help": "A short help line for the first choice."},
			{"value": "b", "label": "Medium", "help": "A longer help line that should wrap onto a second line to prove the label wraps."},
			{"value": "c", "label": "Large", "help": "Third choice help."},
		]})
	var big := SetupScreen.new()
	big.options = fake
	root.add_child(big)
	await _shot("setup_b.png")
	quit()


func _shot(file: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OUT + file)
