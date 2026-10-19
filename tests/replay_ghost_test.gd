extends SceneTree
## The ghost replay of a big hit: a home run (or a ball over 95 m) is drawn again in half speed with its distance.
## Run: godot --headless --path . -s res://tests/replay_ghost_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	_check(HighlightReplay.worth_replaying({"home_run": true}) and HighlightReplay.worth_replaying({"distance": 101.0}), "a homer or a 100 m ball is a highlight")
	_check(not HighlightReplay.worth_replaying({"distance": 60.0}) and not HighlightReplay.worth_replaying({}), "a single is not")
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	var v := Vector3(0.0, 24.0, 38.0)
	var sim := BattedBall.simulate(Vector3(0.0, 0.9, 0.4), v, Vector3.ZERO)
	var h := LiveHit.new()
	h.points = sim.points
	h.summary = sim
	bp.replay.on_play_announced(h, "HOME RUN", {})
	_check(bp.replay.active == HighlightReplay.worth_replaying(sim), "a big hit starts the replay (%s, %.0f m)" % [str(sim.get("home_run", false)), float(sim.distance)])
	if bp.replay.active:
		var real_time: float = (sim.points.size() - 1) / 120.0
		var spent := 0.0
		while bp.replay.active and spent < 60.0:
			bp._process(1.0 / 60.0)
			spent += 1.0 / 60.0
		_check(spent > real_time * 1.9, "it takes about twice as long as the flight (%.1f s for a %.1f s flight, plus the hold)" % [spent, real_time])
		_check(not bp.replay._ball.visible and not bp.replay._label.visible, "and then it is gone")
	var short := BattedBall.simulate(Vector3(0.0, 0.9, 0.4), Vector3(0.0, 3.0, 20.0), Vector3.ZERO)
	var h2 := LiveHit.new()
	h2.points = short.points
	h2.summary = short
	bp.replay.on_play_announced(h2, "Single", {})
	_check(not bp.replay.active, "a short hit is not replayed")
	bp.queue_free()
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
