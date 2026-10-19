extends SceneTree
## The pitcher as a fielding position: the scorebook says 3-1 when the first baseman flips to him, the
## defense marks that play as his duty, and in the scene you are either on the bag in time or he is safe.
## Run: godot --headless --path . -s res://tests/pitcher_position_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	# The defense.
	var team := Team.generate("Home", 55.0, 7)
	var d := Defense.from_team(team)
	var sim := {"ev_mph": 70.0, "kind": "Ground ball", "fair": true, "landing_time": 0.0, "points": PackedVector3Array()}
	var wide := d._throw_play(d.fielder_by_num(3), Vector3(-13.0, 0.0, 24.0), 1.4, sim, Defense.RUNNER_TIMES, [])
	var tries := 0
	while wide.result != "out" and tries < 40:
		wide = d._throw_play(d.fielder_by_num(3), Vector3(-13.0, 0.0, 24.0), 1.4, sim, Defense.RUNNER_TIMES, [])
		tries += 1
	_check(wide.result == "out" and wide.cover_pitcher and wide.text == "Groundout 3-1", "a first baseman pulled off the bag throws to the pitcher (%s)" % wide.text)
	var at_bag := d._throw_play(d.fielder_by_num(3), Vector3(-19.0, 0.0, 20.0), 1.2, sim, Defense.RUNNER_TIMES, [])
	tries = 0
	while at_bag.result != "out" and tries < 40:
		at_bag = d._throw_play(d.fielder_by_num(3), Vector3(-19.0, 0.0, 20.0), 1.2, sim, Defense.RUNNER_TIMES, [])
		tries += 1
	_check(at_bag.text == "Groundout 3U" and not at_bag.cover_pitcher, "a first baseman at the bag makes it himself")
	var second := d._throw_play(d.fielder_by_num(4), Vector3(-6.0, 0.0, 30.0), 1.3, sim, Defense.RUNNER_TIMES, [])
	tries = 0
	while second.result != "out" and tries < 40:
		second = d._throw_play(d.fielder_by_num(4), Vector3(-6.0, 0.0, 30.0), 1.3, sim, Defense.RUNNER_TIMES, [])
		tries += 1
	_check(second.text == "Groundout 4-3" and not second.cover_pitcher, "and a second baseman's play is the usual 4-3")

	# Config and score.
	var c := GameConfig.new()
	c.mode = "Fielding"
	c.position = 1
	_check(c.normalized().position == 1 and c.normalized().title() == "Fielding (P) - 9-inning game", "the pitcher is a position (%s)" % c.normalized().title())
	var plain := PlayerProfile.fielding_score({"caught": 2})
	_check(PlayerProfile.fielding_score({"caught": 2, "covers": 2, "uncovered": 1}) == plain + 10 - 8, "covering first counts, leaving the bag empty costs")

	# In the scene.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_mode_name = "Fielding"
	bp.fielding_position = 1
	root.add_child(bp)
	await process_frame
	_check(bp._mode.human_fielders.has(1) and not bp._mode.human_pitcher and bp._human_num() == 1, "you are the pitcher, not pitching")
	var spot: Vector3 = Defense.FIRST + Vector3(0.8, 0.0, -0.4)

	var h1 := _hit(bp, wide)
	bp._camera.global_position = Vector3(spot.x + 0.5, 1.7, spot.z)
	bp._check_cover(h1)
	_check(bp._fld.covers == 1 and bp._fld.uncovered == 0 and h1.play.result == "out", "on the bag when he arrives: the out stands")

	var h2 := _hit(bp, wide)
	bp._camera.global_position = Vector3(0.0, 1.7, 17.4)
	bp._check_cover(h2)
	_check(bp._fld.uncovered == 1 and h2.play.result == "single" and h2.play.text.contains("nobody covered"), "still on the mound: he is safe")
	_check(h2.plan.has("runners") and not h2.plan.runners.is_empty(), "and the runners are replanned")
	_check(h2.cover_t < 0.0, "the duty is settled once")
	var line: Dictionary = bp._fielding_line()
	_check(line.covers == 1 and line.uncovered == 1, "both are in your line")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _hit(bp: Node3D, play: Dictionary) -> LiveHit:
	var h := LiveHit.new()
	h.ball = MeshInstance3D.new()
	bp.add_child(h.ball)
	h.play = play.duplicate(true)
	h.cover_t = float((play.run_times as Array)[0]) - 0.12
	h.cover_spot = play.cover_spot
	h.points = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, 1.0)])
	h.summary = {"landing_pos": Vector3.ZERO, "fair": true, "wall": false, "apex": 0.2, "home_run": false, "landing_time": 0.5}
	h.t = h.cover_t - 0.02
	return h
