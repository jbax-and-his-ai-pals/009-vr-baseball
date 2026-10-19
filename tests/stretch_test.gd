extends SceneTree
## Pickoff moves from the stretch (a quick move, a lefty's first-base move, the AI throwing over) and
## backing up bases (who goes where, and the AI ones actually going).
## Run: godot --headless --path . -s res://tests/stretch_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	# The move.
	var runner := Player.new()
	var slow := StealModel.pickoff_chance(3.8, 3.0, 28.0, runner, 1.2, 2, false)
	var normal := StealModel.pickoff_chance(3.8, 3.0, 28.0, runner)
	var snap := StealModel.pickoff_chance(3.8, 3.0, 28.0, runner, 0.4, 2, false)
	_check(slow < normal and normal < snap, "a quicker move gets more (%.3f < %.3f < %.3f)" % [slow, normal, snap])
	var lefty_first := StealModel.pickoff_chance(3.8, 3.0, 28.0, runner, 0.7, 1, true)
	var righty_first := StealModel.pickoff_chance(3.8, 3.0, 28.0, runner, 0.7, 1, false)
	var lefty_third := StealModel.pickoff_chance(3.8, 3.0, 28.0, runner, 0.7, 3, true)
	var righty_third := StealModel.pickoff_chance(3.8, 3.0, 28.0, runner, 0.7, 3, false)
	_check(lefty_first > righty_first * 1.2 and righty_third > lefty_third * 1.2, "a lefty owns first base, a righty third")
	_check(StealModel.pickoff_chance(1.8, 0.0, 30.0, runner, 0.3, 1, true) == 0.0, "nothing on a short lead, however good the move")
	_check(snap <= 0.42 and StealModel.pickoff_chance(6.0, 0.0, 40.0, runner, 0.2, 1, true) <= 0.42, "and a cap")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n_long := 0
	var n_short := 0
	var n_just := 0
	for i in 2000:
		if StealModel.ai_throws_over(5.0, 6, rng):
			n_long += 1
		if StealModel.ai_throws_over(2.4, 6, rng):
			n_short += 1
		if StealModel.ai_throws_over(5.0, 0, rng):
			n_just += 1
	_check(n_long > 400 and n_long < 800 and n_short == 0 and n_just < n_long / 4, "the AI throws over at a long lead (%d of 2000), not a short one, rarely just after a throw (%d)" % [n_long, n_just])
	var hp := HumanPitcher.new()
	_check(hp.has_method("throw"), "the human pitcher reports how quick the move was")

	# Backing up.
	var rf := Backup.assignment(1, 4, Vector3(-8.0, 0.0, 28.0))
	_check(rf.fielder == 9 and rf.spot.x < Defense.FIRST.x and rf.spot.z < Defense.FIRST.z + 1.0, "right field goes behind first, beyond the bag from the throw (%s)" % str(rf.spot))
	_check(Backup.assignment(2, 2, Vector3(0.0, 0.0, -1.0)).fielder == 8 and Backup.assignment(2, 8, Vector3(30.0, 0.0, 90.0)).fielder == 7, "center field behind second, left field if he is the thrower")
	_check(Backup.assignment(3, 6, Vector3(5.0, 0.0, 30.0)).fielder == 7 and Backup.assignment(3, 7, Vector3(40.0, 0.0, 80.0)).fielder == 9, "left field behind third")
	_check(Backup.assignment(4, 8, Vector3(0.0, 0.0, 90.0)).fielder == 1 and Backup.assignment(4, 1, Vector3(0.0, 0.0, 17.0)).fielder == 5, "the pitcher behind home, the third baseman if he threw")
	_check(Backup.assignment(4, 8, Vector3(0.0, 0.0, 90.0)).spot.z > -9.0 and Backup.assignment(4, 8, Vector3(0.0, 0.0, 90.0)).spot.z < 0.0, "home is backed up from behind the plate")
	var far := Backup.reach(Vector3(-40.0, 0.0, 80.0), Vector3(-28.0, 0.0, 17.0), 7.0, 2.0)
	_check(absf(Vector2(far.x + 40.0, far.z - 80.0).length() - 14.0) < 0.01, "he runs as far as he can in the time he has")
	_check(Backup.reach(Vector3(0.0, 0.0, 10.0), Vector3(3.0, 0.0, 5.0), 8.0, 5.0) == Vector3(3.0, 0.0, 5.0), "and gets there if it is close")

	# In the scene.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_mode_name = "Spectate"
	root.add_child(bp)
	await process_frame
	var h := LiveHit.new()
	h.play = {"fielder": 4, "movements": [{"fielder": 4, "from": Vector3(-8.5, 0.0, 32.5), "to": Vector3(-10.0, 0.0, 24.0), "t0": 0.3, "t1": 1.4, "dive": false}]}
	h.plan = {"throws": [{"from": Vector3(-10.0, 1.3, 24.0), "to": Defense.FIRST + Vector3(0.0, 1.0, 0.0), "t0": 1.9, "t1": 2.8, "base": 1}]}
	bp._director.build_throws(h)
	var backed := false
	var spot := Vector3.ZERO
	for m in h.play.movements:
		if int(m.fielder) == 9:
			backed = true
			spot = m.to
	_check(backed, "the right fielder is sent behind first on a throw to first")
	_check(backed and Vector2(spot.x + 40.0, spot.z - 80.0).length() > 5.0, "partway there (he cannot cover 60 m in 2 s)")
	var h2 := LiveHit.new()
	h2.play = {"fielder": 3, "movements": []}
	h2.plan = {"throws": [{"from": Vector3(-17.0, 1.3, 21.0), "to": Defense.FIRST, "t0": 1.0, "t1": 1.2, "base": 1}]}
	bp._director.build_throws(h2)
	var any9 := false
	for m in h2.play.movements:
		if int(m.fielder) == 9:
			any9 = true
	_check(not any9, "nobody is sent for a throw that arrives at once")

	# The AI throws over.
	bp._game.bases[0] = bp._away.lineup[0]
	bp._leads[0] = 5.2
	bp._since_throw = [8, 8, 8]
	var threw := false
	for i in 60 * 80:
		bp._leads[0] = 5.2 if int(bp._since_throw[0]) > 0 else bp._leads[0]
		bp._process(1.0 / 60.0)
		if int(bp._since_throw[0]) == 0:
			threw = true
			break
	_check(threw, "an AI pitcher throws over to hold a runner who is leading far off")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
