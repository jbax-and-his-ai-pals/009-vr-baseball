extends SceneTree
## Rundowns: what a throw over can do, the runner's path back and forth between the bases, the
## book (out, back safe, on to the next base), and the whole thing in the scene.
## Run: godot --headless --path . -s res://tests/rundown_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	# The outcome of a throw over.
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var counts := {}
	for i in 6000:
		var o := StealModel.pickoff_outcome(0.30, 4.0, rng)
		counts[o] = int(counts.get(o, 0)) + 1
	var out_total := int(counts.get("out", 0)) + int(counts.get("rundown_out", 0))
	_check(absf(out_total / 6000.0 - 0.30) < 0.03, "he is out about as often as the chance says (%.3f)" % (out_total / 6000.0))
	_check(int(counts.get("out", 0)) > int(counts.get("rundown_out", 0)) and int(counts.get("rundown_out", 0)) > 400, "most outs are clean, a good share are rundowns (%d clean, %d run down)" % [counts.get("out", 0), counts.get("rundown_out", 0)])
	_check(int(counts.get("rundown_safe_back", 0)) > 0 and int(counts.get("rundown_safe_ahead", 0)) > 0, "a long lead sometimes escapes a rundown, back or ahead")
	var short := {}
	for i in 3000:
		var o2 := StealModel.pickoff_outcome(0.0, 1.8, rng)
		short[o2] = int(short.get(o2, 0)) + 1
	_check(short.size() == 1 and short.has("safe"), "a short lead never gets him in a rundown (%s)" % str(short))

	# The plan.
	var team := Team.generate("T", 50.0, 3)
	var runner: Player = team.lineup[0]
	for outcome in ["rundown_out", "rundown_safe_back", "rundown_safe_ahead"]:
		var plan := Baserunning.plan_rundown(1, runner, outcome)
		var keys: Array = plan.runners[0].keys
		var increasing := true
		for i in range(1, keys.size()):
			increasing = increasing and float(keys[i][0]) >= float(keys[i - 1][0])
		var last_pos: Vector3 = keys[keys.size() - 1][1]
		var first_base: Vector3 = Baserunning.BASE_POS[1]
		var second_base: Vector3 = Baserunning.BASE_POS[2]
		var ok_end := true
		match outcome:
			"rundown_safe_back":
				ok_end = last_pos.distance_to(first_base) < 0.01 and plan.runners[0].out == false
			"rundown_safe_ahead":
				ok_end = last_pos.distance_to(second_base) < 0.01 and plan.runners[0].out == false
			_:
				ok_end = plan.runners[0].out and last_pos.distance_to(first_base) > 2.0 and last_pos.distance_to(second_base) > 2.0
		_check(increasing and keys.size() >= 4 and ok_end and float(plan.end_time) > 2.0 and float(plan.end_time) < 6.0, "%s: back-and-forth path ending where it should (%.1f s, %d turns)" % [outcome, float(plan.end_time), plan.turns.size()])
		_check(plan.outs_added == (1 if outcome == "rundown_out" else 0) and plan.events.size() == 1, "%s: one call at the end" % outcome)
	var out_plan := Baserunning.plan_rundown(1, runner, "rundown_out")
	var back_plan := Baserunning.plan_rundown(1, runner, "rundown_safe_back")
	_check(out_plan.turns.size() == 2 and back_plan.turns.size() == 1, "the runner turns around as often as the ball goes back and forth")

	# The book.
	var g := GameState.new(team.lineup, 9)
	g.bases = [runner, null, null]
	var ev := g.advance_runner(1)
	_check(g.bases[0] == null and g.bases[1] == runner and ev.result == "advance" and g.outs == 0, "beating the rundown puts him on second, no steal credited")
	g.bases = [team.lineup[1], runner, null]
	var ev2 := g.advance_runner(1)
	_check(g.bases[0] != null and g.bases[1] == runner and ev2.result == "", "he cannot take an occupied base")
	g.bases = [null, null, runner]
	var ev3 := g.advance_runner(3)
	_check(g.runs == 1 and ev3.runs == 1 and g.bases[2] == null, "from third he scores")

	# In the scene.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	for outcome in ["rundown_out", "rundown_safe_back", "rundown_safe_ahead", "out", "safe"]:
		bp._game.outs = 0
		bp._game.runs = 0
		var r: Player = bp._away.lineup[2]
		bp._game.bases = [r, null, null]
		bp._aux_play = {}
		bp._steal = {}
		bp._refresh_base_runners()
		bp._pickoff_override = outcome
		bp._do_pickoff(1, Vector3(0.0, 1.5, 16.7), Vector3(-15.0, 2.0, 10.0), 2.0)
		var flights_started: int = bp._flights.size()
		var moved: bool = not bp._aux_play.is_empty()
		for i in 60 * 16:
			bp._process(1.0 / 60.0)
			if bp._aux_play.is_empty() and i > 30:
				break
		var after: Array = bp._game.bases
		var good := false
		match outcome:
			"rundown_out":
				good = after[0] == null and bp._game.outs == 1 and flights_started >= 3
			"rundown_safe_back":
				good = after[0] == r and bp._game.outs == 0 and flights_started >= 2
			"rundown_safe_ahead":
				good = after[0] == null and after[1] == r and bp._game.outs == 0
			"out":
				good = after[0] == null and bp._game.outs == 1
			_:
				good = after[0] == r and bp._game.outs == 0
		_check(good and bp._aux_play.is_empty() and moved, "scene, %s: the book is right and the play finishes (%d throws in the air)" % [outcome, flights_started])
		for i in 120:
			bp._process(1.0 / 60.0)
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
