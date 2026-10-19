extends SceneTree
## Challenges: each sets up its situation, judges the game as it goes and scores stars; they are
## wired into GameConfig and the menu.
## Run: godot --headless --path . -s res://tests/scenario_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _fresh(id: String) -> Array:
	var team := Team.generate("Test", 0.5, 7)
	var g := GameState.new(team.lineup, 9)
	var s := Scenario.by_id(id)
	s.apply(g, team.lineup)
	return [g, s, team]


## Throw `n` pitches of one outcome through the game and the scenario; returns the last state.
func _throw(g: GameState, s: Scenario, outcome: String, n: int) -> String:
	var st := "running"
	for i in n:
		var ev := g.pitch(outcome)
		st = s.update(g, ev)
	return st


func _init() -> void:
	_check(Scenario.ids().size() == 6, "six challenges")
	for sc in Scenario.catalog():
		_check(sc.title != "" and sc.goal != "" and sc.rule != "", "%s has a title, a goal and a rule" % sc.id)

	# Setup.
	var a := _fresh("escape")
	var g: GameState = a[0]
	_check(g.inning == 9 and g.outs == 0 and g.runs == 3 and g.home_score == 4 and g.bases.all(func(b): return b is Player), "escape: bases loaded with real runners, 9th, up by one")
	var pk := _fresh("pickoff")
	var fastest := 0.0
	for p in (pk[2] as Team).lineup:
		fastest = maxf(fastest, float(p.speed))
	_check((pk[0] as GameState).bases[0] is Player and float((pk[0] as GameState).bases[0].speed) == fastest and (pk[0] as GameState).outs == 1, "pickoff: the fastest man is on first with one out")

	# Escape the jam.
	var win := _fresh("escape")
	var st := _throw(win[0], win[1], "swinging_strike", 9)       # three strikeouts, three pitches each
	_check(st == "success" and (win[1] as Scenario).stars == 3, "escape: three strikeouts end it, in 9 pitches that is three stars (%s %d)" % [st, win[1].stars])
	var lose := _fresh("escape")
	st = _throw(lose[0], lose[1], "ball", 4)                     # a walk forces in the tying run
	_check(st == "fail" and (lose[1] as Scenario).stars == 0, "escape: a walk with the bases loaded forces in a run and fails it")
	var slow := _fresh("escape")
	for i in 7:
		(slow[0] as GameState).pitch("ball")                     # work some balls, no walk yet
		(slow[0] as GameState).balls = 0
	(slow[0] as GameState).pitch_count += 0
	st = _throw(slow[0], slow[1], "swinging_strike", 9)
	_check(st == "success" and (slow[1] as Scenario).stars == 2, "escape: more pitches, fewer stars (%d pitches, %d stars)" % [(slow[1] as Scenario).pitches, (slow[1] as Scenario).stars])

	# Strike out the side.
	var ks := _fresh("side")
	st = _throw(ks[0], ks[1], "swinging_strike", 9)
	_check(st == "success" and (ks[1] as Scenario).stars == 3, "side: three strikeouts")
	var ks2 := _fresh("side")
	st = _throw(ks2[0], ks2[1], "ball", 4)
	_check(st == "fail", "side: a walk spoils it")
	var ks3 := _fresh("side")
	(ks3[0] as GameState).in_play({"result": "out", "text": "Groundout", "bases": 0, "fielder": 6})
	st = (ks3[1] as Scenario).update(ks3[0], {})
	_check(st == "fail", "side: an ordinary out spoils it")

	# Pick him off.
	var po := _fresh("pickoff")
	(po[0] as GameState).pickoff(1)
	_check((po[1] as Scenario).update(po[0], {}) == "success" and (po[1] as Scenario).stars == 3, "pickoff: a pickoff wins, with no pitches wasted that is three stars")
	var po2 := _fresh("pickoff")
	(po2[0] as GameState).steal(1, true)
	_check((po2[1] as Scenario).update(po2[0], {}) == "fail", "pickoff: a stolen base fails it")
	var po3 := _fresh("pickoff")
	st = _throw(po3[0], po3[1], "ball", 3)
	for i in 8:
		(po3[0] as GameState).balls = 0
		st = _throw(po3[0], po3[1], "called_strike", 1)
		(po3[0] as GameState).strikes = 0
	_check(st == "fail", "pickoff: out of pitches fails it (%d pitches)" % (po3[1] as Scenario).pitches)
	var po4 := _fresh("pickoff")
	(po4[0] as GameState).caught_stealing += 1
	_check((po4[1] as Scenario).update(po4[0], {}) == "success", "pickoff: catching him stealing counts too")

	# Paint the corners.
	var cn := _fresh("corners")
	for i in 5:
		(cn[1] as Scenario).on_pitch("corner", true)
		(cn[0] as GameState).pitch("called_strike")
		(cn[0] as GameState).strikes = 0
		st = (cn[1] as Scenario).update(cn[0], {})
	_check(st == "success" and (cn[1] as Scenario).stars == 3, "corners: five corner strikes in five pitches (%s, %d stars)" % [st, (cn[1] as Scenario).stars])
	var cn2 := _fresh("corners")
	(cn2[1] as Scenario).on_pitch("middle", true)
	(cn2[1] as Scenario).on_pitch("corner", false)
	for i in 14:
		(cn2[0] as GameState).pitch("ball")
		(cn2[0] as GameState).balls = 0
		st = (cn2[1] as Scenario).update(cn2[0], {})
	_check(st == "fail", "corners: only strikes on a corner count, and out of pitches fails it")

	# Protect the lead.
	var ld := _fresh("lead")
	_check((ld[0] as GameState).outs == 2 and (ld[0] as GameState).bases[2] is Player, "lead: two outs, a runner on third")
	st = _throw(ld[0], ld[1], "swinging_strike", 3)
	_check(st == "success" and (ld[1] as Scenario).stars == 3, "lead: one strikeout ends it (%s)" % st)

	# No-hitter.
	var nh := _fresh("nohit")
	(nh[0] as GameState).in_play({"result": "single", "text": "Single", "bases": 1, "fielder": 6})
	_check((nh[1] as Scenario).update(nh[0], {}) == "fail", "nohit: a hit ends it")
	var nh2 := _fresh("nohit")
	(nh2[0] as GameState).over = true
	_check((nh2[1] as Scenario).update(nh2[0], {}) == "success" and (nh2[1] as Scenario).stars == 3, "nohit: a game with no hits and no walks is three stars")
	var nh3 := _fresh("nohit")
	(nh3[0] as GameState).walks = 2
	(nh3[0] as GameState).over = true
	_check((nh3[1] as Scenario).update(nh3[0], {}) == "success" and (nh3[1] as Scenario).stars == 2, "nohit: walks cost stars")

	# A finished challenge stays finished.
	_check((win[1] as Scenario).update(win[0], {}) == "success" and (win[1] as Scenario).stars == 3, "a finished challenge does not change")

	# Progress text.
	var pr := _fresh("side")
	_check((pr[1] as Scenario).progress_text(pr[0]) == "Strikeouts 0 of 3", "progress reads like a scoreboard (%s)" % (pr[1] as Scenario).progress_text(pr[0]))
	_check(Scenario.stars_text(2) == "**-", "stars read **-")

	# Config and menu.
	var c := GameConfig.new()
	c.scenario = "escape"
	c.mode = "Fielding"
	c.activity = "Practice"
	var n := c.normalized()
	_check(n.mode == "Pitching" and n.activity == "Game" and n.scenario == "escape" and not n.is_scored() and n.leaderboard_key() == "", "a challenge is a pitching game with no leaderboard")
	_check(n.title() == "Challenge - Escape the jam" and GameConfig.from_dict(n.to_dict()).scenario == "escape", "it has a title and survives saving")
	var bad := GameConfig.new()
	bad.scenario = "no_such_thing"
	_check(bad.normalized().scenario == "", "an unknown challenge is dropped")
	var s := Settings.new()
	var m := MenuModel.new(s)
	m.stack = ["play"]
	var idx := -1
	for i in m.items().size():
		if m.items()[i].id == "challenges":
			idx = i
	_check(idx >= 0, "Play has a Challenges row")
	m.activate(idx)
	var rows := m.items()
	_check(m.screen() == "challenges" and rows.size() == 7 and rows[0].value == "---", "the challenge list shows six and Back, no stars yet")
	m.profile.record_challenge("side", 2, 12)
	_check(m.items()[1].value == "**-", "earned stars show")
	var ev := m.activate(1)
	_check(ev.get("type", "") == "start" and ev.config.scenario == "side" and s.last_game.get("scenario", "") == "side", "choosing one starts it (and Continue will replay it)")

	# In the real scene: a challenge starts in its situation, is judged as the game runs, saves its
	# result to the test profile (never the player's) and ends with a way back to the menu.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.acts.scenario_id = "side"
	root.add_child(bp)
	await process_frame
	_check(bp.acts.scenario != null and bp._game.inning == 3 and bp._game.bases[0] == null and bp._profile.save_path == "user://test_profile.json",
		"the scene starts the challenge in its situation, saving to the test profile")
	var throw_timer := 0.0
	for i in 60 * 120:
		bp._process(1.0 / 60.0)
		throw_timer -= 1.0 / 60.0
		if throw_timer <= 0.0 and bp.flow.batter_ready:
			throw_timer = 1.0
			bp.flight.debug_throw()
		if bp.acts.scenario_done:
			break
	_check(bp.acts.scenario_done and bp._profile.challenge("side").attempts == 1, "it was judged and the attempt recorded (%s, stars %d)" % [bp.acts.scenario.state, bp.acts.scenario.stars])
	_check(bp.flow.game_over_timer < 0.0, "a finished challenge does not restart a new game by itself")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
