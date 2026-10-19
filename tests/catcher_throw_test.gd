extends SceneTree
## The catcher's own throw on a steal: fast and straight at the base gets the runner, a lob is too slow, a
## throw at the wrong base is wild, no throw at all is safe; and it goes in the book and your fielding line.
## Run: godot --headless --path . -s res://tests/catcher_throw_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _scene() -> Node3D:
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_mode_name = "Fielding"
	bp.fielding_position = 2
	root.add_child(bp)
	return bp


## A runner going from first, with the throw about to be yours.
func _going(bp: Node3D, run_t: float) -> Player:
	var runner: Player = bp._away.lineup[0]
	bp._game.bases = [runner, null, null]
	var plan := Baserunning.plan_steal(1, runner, run_t)
	bp._aux_play = {"plan": plan, "t": 1.4}
	bp.plays.steal = {"from": 1, "runner": runner, "run_t": run_t, "plan": plan, "await": {"left": 1.5, "a_time": 0.5}}
	return runner


func _finish(bp: Node3D) -> void:
	bp._aux_play.t = float(bp.plays.steal.apply_at) + 0.1
	bp._update_batter_lifecycle(0.0)


func _init() -> void:
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp := _scene()
	await process_frame
	_check(bp.fielding.is_catcher(), "you are the catcher")
	# A hard throw straight at second beats a slow runner.
	_going(bp, 3.6)
	bp.fielding.catcher_release(Vector3(0.0, 4.0, 33.0))
	_check(bp.plays.steal.has("apply_at") and not bp.plays.steal.has("await") and bp.plays.steal.safe == false, "a fast throw at second gets him (ball at %.2f s, he needed 3.6)" % float(bp.plays.steal.apply_at))
	_finish(bp)
	_check(bp._game.caught_stealing == 1 and bp._game.bases[0] == null and int(bp.fielding.fld.assists) == 1, "caught stealing is in the book and is an assist for you")
	# The same throw against a fast runner is too late.
	bp.plays.steal = {}
	bp._aux_play = {}
	_going(bp, 2.0)
	bp.fielding.catcher_release(Vector3(0.0, 4.0, 33.0))
	_check(bp.plays.steal.safe == true, "but a runner who needs 2.0 s is safe")
	_finish(bp)
	_check(bp._game.stolen_bases == 1 and bp._game.bases[1] != null, "stolen base, he is on second")
	# A lob is too slow.
	bp.plays.steal = {}
	bp._aux_play = {}
	bp._game.bases = [null, null, null]
	_going(bp, 3.2)
	bp.fielding.catcher_release(Vector3(0.0, 2.0, 12.0))
	_check(bp.plays.steal.safe == true, "a lob loses to a 3.2 s runner")
	# A throw at third is wild.
	bp.plays.steal = {}
	bp._aux_play = {}
	bp._game.bases = [null, null, null]
	_going(bp, 3.6)
	bp.fielding.catcher_release(Vector3(20.0, 4.0, 20.0))
	_check(bp.plays.steal.safe == true, "a throw at another base is wild")
	# No throw.
	bp.plays.steal = {}
	bp._aux_play = {}
	bp._game.bases = [null, null, null]
	_going(bp, 3.6)
	bp.fielding.catcher_release(Vector3.ZERO)
	_check(bp.plays.steal.safe == true, "no throw, safe, even against a slow runner")
	# The clock: waiting too long is no throw.
	bp.plays.steal = {}
	bp._aux_play = {}
	bp._game.bases = [null, null, null]
	_going(bp, 3.6)
	bp.plays.steal.await.left = 0.01
	bp.fielding.poll_catcher_throw(0.05, 5.0)
	_check(not bp.plays.steal.has("await") and bp.plays.steal.safe == true, "the time running out is no throw")
	# The run ending before you throw settles it too.
	bp.plays.steal = {}
	bp._aux_play = {}
	bp._game.bases = [null, null, null]
	_going(bp, 3.6)
	bp._aux_play = {}
	bp._update_batter_lifecycle(0.0)
	_check(not bp.plays.steal.has("await") and (bp.plays.steal.is_empty() or bp.plays.steal.has("apply_at")), "a run that ends while you hold it is settled")
	# AI catchers are unchanged: a steal with the AI behind the plate resolves at once.
	bp.queue_free()
	await process_frame
	var ai: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	ai.menu_on_start = false
	ai.game_mode_name = "Spectate"
	root.add_child(ai)
	await process_frame
	var r: Player = ai._away.lineup[0]
	ai._game.bases = [r, null, null]
	var plan := Baserunning.plan_steal(1, r, 3.0)
	ai._aux_play = {"plan": plan, "t": 1.0}
	ai.plays.steal = {"from": 1, "runner": r, "run_t": 3.0, "plan": plan}
	ai.plays.resolve_steal({"time": 0.5})
	_check(ai.plays.steal.has("apply_at") and not ai.plays.steal.has("await"), "with an AI catcher the steal is resolved at once")
	ai.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
