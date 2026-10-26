extends SceneTree
## Runs every self-contained unit test as its own Godot process.
## Run: godot --headless --path . --script res://tests/run_all.gd
## Skipped on purpose: versus_test/net_test (two processes), balance_sim/card_balance
## (simulations), card_overlay_shot (screenshots), exported_smoke (needs an export).

const EXTRA := ["menu_smoke"]
const ERROR_MARKERS := ["SCRIPT ERROR", "Parse Error", "FAIL"]


func _initialize() -> void:
	var names: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_base.gd":
			names.append(f.get_basename())
	names.append_array(EXTRA)
	names.sort()
	var project := ProjectSettings.globalize_path("res://")
	var failed := 0
	for n in names:
		var out: Array = []
		var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", project, "--script", "res://tests/%s.gd" % n], out, true)
		var bad: Array[String] = []
		for line in "".join(out).split("\n"):
			for m in ERROR_MARKERS:
				if line.contains(m):
					bad.append(line.strip_edges())
					break
		if code != 0 or not bad.is_empty():
			failed += 1
			print("FAIL ", n, " (exit ", code, ")")
			for l in bad:
				print("       ", l)
		else:
			print("PASS ", n)
	print("%d of %d test files failed" % [failed, names.size()])
	quit(1 if failed > 0 else 0)
