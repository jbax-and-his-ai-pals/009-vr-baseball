extends SceneTree
## You are the first baseman: when an infielder's throw reaches first your glove has to be there, or it is an error.
## Run: godot --headless --path . -s res://tests/first_base_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _hit(bp: Node3D) -> LiveHit:
	var h := LiveHit.new()
	h.ball = MeshInstance3D.new()
	bp.add_child(h.ball)
	h.play = {"result": "out", "fielder": 6, "fielder_name": "SS", "field_pos": Vector3(8.0, 0.0, 33.0), "field_time": 1.4,
		"movements": [], "run_times": Defense.RUNNER_TIMES, "throw": ThrowPlan.make(Vector3(8.0, 1.3, 33.0), Defense.FIRST, 1.9, 3.4, 1)}
	h.plan = Baserunning.plan(h.play, bp._game.bases, bp._game.outs, bp._batter_player, bp._run_rng)
	h.throw_t = 3.4
	h.throw_spot = Baserunning.RECEIVE_SPOT[1] + Vector3(0.0, 1.15, 0.0)
	h.t = 3.4
	return h


func _init() -> void:
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_mode_name = "Fielding"
	bp.fielding_position = 3
	root.add_child(bp)
	await process_frame
	_check(bp.fielding.human_num() == 3, "you are the first baseman")
	bp.fielding.glove_override = Baserunning.RECEIVE_SPOT[1] + Vector3(0.2, 1.2, 0.0)
	var good := _hit(bp)
	bp.fielding.check_throw_catch(good)
	_check(bp.fielding.fld.caught == 1 and bp.fielding.fld.errors == 0 and good.play.result == "out" and good.throw_t < 0.0, "a glove at the bag catches it and the out stands")
	bp.fielding.glove_override = Vector3(-14.0, 1.2, 22.0)
	var bad := _hit(bp)
	bp.fielding.check_throw_catch(bad)
	_check(bp.fielding.fld.errors == 1 and bad.play.result == "error" and bad.play.text.contains("E3"), "a glove somewhere else misses it: error on the first baseman")
	_check(bad.plan != null and bad.plan.runners[bad.plan.runners.size() - 1].to >= 1 and not bad.plan.runners[bad.plan.runners.size() - 1].out, "and the batter is safe")
	var line: Dictionary = bp.results.fielding_line()
	_check(line.caught == 1 and line.errors == 1, "both are in your line")
	var later := _hit(bp)
	bp.fielding.glove_override = Baserunning.RECEIVE_SPOT[1] + Vector3(0.0, 1.15, 0.5)
	bp.fielding.check_throw_catch(later)
	_check(bp.fielding.fld.caught == 2, "reaching half a meter off the line still counts")
	bp.queue_free()
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
