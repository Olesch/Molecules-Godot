extends "res://tests/test_base.gd"
## Run: godot --headless --path . --script res://tests/test_music_mixer.gd
## Checks the layer logic of MusicMixer: drums wait for one loop, metal follows the board fill.


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

	# Metal: below its start fill it stays silent, above it fades in gradually.
	mixer.set_fill(MusicMixer.METAL_START_FILL - 0.05)
	for i in 30:
		mixer._process(0.5)
	_check(mixer._metal == 0.0, "metal stays silent below its start fill")
	var mid_fill := (MusicMixer.METAL_START_FILL + MusicMixer.METAL_FULL_FILL) / 2.0
	mixer.set_fill(mid_fill)
	mixer._process(1.0)
	_check(mixer._metal > 0.0 and mixer._metal < 0.3, "metal fades in slowly (got %.2f)" % mixer._metal)
	for i in 20:
		mixer._process(1.0)
	_check(is_equal_approx(mixer._metal, 0.5), "metal settles halfway at the middle fill (got %.2f)" % mixer._metal)
	var half_theme := sync.get_sync_stream_volume(0)
	_check(half_theme < 0.0 and half_theme > -6.0, "theme starts ducking (got %.1f dB)" % half_theme)
	mixer.set_fill(1.0)
	for i in 20:
		mixer._process(1.0)
	_check(is_equal_approx(mixer._metal, 1.0), "metal full at its full fill")
	var full_theme := sync.get_sync_stream_volume(0)
	_check(is_equal_approx(full_theme, linear_to_db(MusicMixer.THEME_MIN_GAIN)), "theme ducked to 50%% with full metal (got %.1f dB)" % full_theme)
	mixer.set_fill(0.0)
	for i in 20:
		mixer._process(1.0)
	_check(mixer._metal == 0.0, "metal fades out when the board clears")
	_check(is_equal_approx(sync.get_sync_stream_volume(0), 0.0), "theme back to full volume")

	# Drums: only after the playback position wraps once.
	mixer.restart()
	for i in 10:
		mixer._process(0.5)
	_check(mixer._drums == 0.0, "drums wait for the first loop")
	mixer._loops_done = 1
	mixer._process(MusicMixer.DRUM_FADE_SECONDS / 4.0)
	_check(is_equal_approx(mixer._drums, 0.25), "drum fade progresses gradually (got %.2f)" % mixer._drums)
	_check(sync.get_sync_stream_volume(1) < -6.0, "drums still quiet a quarter into the fade")
	mixer._process(MusicMixer.DRUM_FADE_SECONDS)
	_check(is_equal_approx(mixer._drums, 1.0), "drums fade in after one loop")
	mixer.restart()
	_check(mixer._drums == 0.0 and mixer._loops_done == 0, "restart mutes the drums again")

	_finish()
