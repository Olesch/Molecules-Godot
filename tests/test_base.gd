extends SceneTree
## Shared harness for unit tests: `extends "res://tests/test_base.gd"`.
## Provides _check(cond, name) and _finish(), which prints the summary and quits
## with exit code 1 on any failure. Run all tests with:
##   godot --headless --path . --script res://tests/run_all.gd

var _failed := 0
var _count := 0


func _check(cond: bool, name: String) -> void:
	_count += 1
	if cond:
		print("ok   ", name)
	else:
		print("FAIL ", name)
		_failed += 1


func _finish(show_count := false) -> void:
	if show_count:
		print("tests: ", _count, " failures: ", _failed)
	else:
		print("failures: ", _failed)
	quit(1 if _failed > 0 else 0)
