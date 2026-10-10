extends SceneTree
## Run: godot --headless --path new-game-project --script res://tests/test_music_mixer.gd
## Checks the layer logic of MusicMixer: drums wait for one loop, metal follows the board fill.

var _failed := 0


func _check(cond: bool, name: String) -> void:
	if cond:
		print("ok   ", name)
	else:
		print("FAIL ", name)
		_failed += 1


func _init() -> void:
	var mixer := MusicMixer.new()
	root.add_child(mixer)
	await process_frame

	var sync: AudioStreamSynchronized = mixer._sync
	_check(sync != null, "all three layers loaded into a synchronized stream")
	if sync == null:
		quit(1)
		return
	_check(sync.stream_count == 3, "three layers")
	var length := sync.get_sync_stream(0).get_length()
	_check(is_equal_approx(length, sync.get_sync_stream(1).get_length()), "drums same length as theme")
	_check(is_equal_approx(length, sync.get_sync_stream(2).get_length()), "metal same length as theme")

	mixer.restart()
	_check(sync.get_sync_stream_volume(1) <= MusicMixer.SILENT_DB + 1.0, "drums silent at start")
	_check(sync.get_sync_stream_volume(2) <= MusicMixer.SILENT_DB + 1.0, "metal silent at start")

	# Metal: below 60% fill it stays silent, above it fades in gradually.
	mixer.set_fill(0.55)
	for i in 30:
		mixer._process(0.5)
	_check(mixer._metal == 0.0, "metal stays silent below 60% fill")
	mixer.set_fill(0.75)
	mixer._process(1.0)
	_check(mixer._metal > 0.0 and mixer._metal < 0.3, "metal fades in slowly (got %.2f)" % mixer._metal)
	for i in 20:
		mixer._process(1.0)
	_check(is_equal_approx(mixer._metal, 0.5), "metal settles at 50%% for 75%% fill (got %.2f)" % mixer._metal)
	mixer.set_fill(1.0)
	for i in 20:
		mixer._process(1.0)
	_check(is_equal_approx(mixer._metal, 1.0), "metal full at 90%+ fill")
	mixer.set_fill(0.0)
	for i in 20:
		mixer._process(1.0)
	_check(mixer._metal == 0.0, "metal fades out when the board clears")

	# Drums: only after the playback position wraps once.
	mixer.restart()
	for i in 10:
		mixer._process(0.5)
	_check(mixer._drums == 0.0, "drums wait for the first loop")
	mixer._loops_done = 1
	for i in 10:
		mixer._process(0.5)
	_check(is_equal_approx(mixer._drums, 1.0), "drums fade in after one loop")
	mixer.restart()
	_check(mixer._drums == 0.0 and mixer._loops_done == 0, "restart mutes the drums again")

	print("failures: ", _failed)
	quit(1 if _failed > 0 else 0)
