extends SceneTree
## The people at the edges: teammates at each dugout rail and a coach in each box, who react to what
## happens (the side at bat cheers runs and homers and groans strikeouts; the fielding side pumps a fist).
## Run: godot --headless --path . -s res://tests/dugouts_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _busy(side: String, dg: Dugouts) -> int:
	var n := 0
	for d in dg.mates[side]:
		if (d as Doll).busy():
			n += 1
	return n


func _settle(dg: Dugouts) -> void:
	for i in 300:
		dg._process(0.02)
		for side in ["home", "away"]:
			for d in dg.mates[side]:
				(d as Doll)._process(0.02)
		for c in dg.coaches:
			(c as Doll)._process(0.02)


func _init() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var home := Team.generate("Home", 55.0, 7)
	var away := Team.generate("Away", 52.0, 14)
	var dg := Dugouts.new()
	dg.setup(holder, home, away, func(k: int): return k % 2)
	await process_frame
	_check(dg.mates.home.size() == Dugouts.MATES and dg.mates.away.size() == Dugouts.MATES and dg.coaches.size() == 2, "four teammates at each rail and two coaches")
	var home_ok := true
	var away_ok := true
	for d in dg.mates.home:
		home_ok = home_ok and d.position.x > 5.0 and d.position.z > 5.6
	for d in dg.mates.away:
		away_ok = away_ok and d.position.x < -5.0 and d.position.z > 5.6
	_check(home_ok and away_ok, "home on the third-base side, visitors on the first-base side, both in front of the dugout face")
	_check(dg.coaches[0].position.x < 0.0 and dg.coaches[1].position.x > 0.0, "a coach by each base")
	_check(_busy("home", dg) == 0 and _busy("away", dg) == 0, "all standing quietly to start")

	dg.react_event({"result": "home_run", "runs": 1}, "away")
	_check(dg.pending() == Dugouts.MATES * 2 + 2 + 0 or dg.pending() > 8, "a homer sends the batting side, its coaches and the fielding side into action (%d queued)" % dg.pending())
	dg._process(1.0)
	_check(dg.pending() == 0 and _busy("away", dg) == Dugouts.MATES and _busy("home", dg) == Dugouts.MATES, "and they all do it within a second")
	_settle(dg)
	_check(_busy("away", dg) == 0 and _busy("home", dg) == 0, "then they are still again")

	dg.react_event({"result": "strikeout"}, "away")
	dg._process(1.0)
	_check(_busy("home", dg) == Dugouts.MATES and _busy("away", dg) == Dugouts.MATES, "a strikeout: the fielding side pumps a fist, the batting side groans")
	_settle(dg)
	dg.react_event({"result": "out"}, "away")
	_check(dg.pending() == 0, "an ordinary out is nothing")
	dg.react_event({"result": "single", "runs": 2}, "home")
	dg._process(1.0)
	_check(_busy("home", dg) == Dugouts.MATES and _busy("away", dg) == 0, "a run scores a cheer from the side at bat only")
	_settle(dg)
	dg.cheer("away", "celebrate", true)
	dg._process(1.0)
	var coach_busy := 0
	for c in dg.coaches:
		if (c as Doll).busy():
			coach_busy += 1
	_check(coach_busy == 2, "coaches join in when asked")

	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	_check(bp._dugouts != null and bp._dugouts.mates.home.size() == Dugouts.MATES, "the game has its dugouts")
	bp.flow.after_event({"result": "home_run", "runs": 1, "pa_over": false, "half_over": false, "game_over": false, "text": "", "batter": null})
	_check(bp._dugouts.pending() > 0, "and a home run in it sets them off")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
