extends SceneTree

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _still(at: Vector3) -> Array:
	var s: Array = []
	for i in 10:
		s.append([i * 0.03, at])
	return s


func _run_pitches(bp: Node3D, glove_dx: float, n: int) -> Dictionary:
	var seen: Array = []
	var done := 0
	for round in n:
		var pitch: LivePitch = null
		for i in 60 * 30:
			bp._process(1.0 / 60.0)
			for q in bp.flight.pitches:
				if not seen.has(q) and not q.landed:
					seen.append(q)
					pitch = q
			if pitch != null:
				break
		if pitch == null:
			break
		var pp: Vector3 = pitch.analysis.plate_pos
		bp.fielding.glove_override = Vector3(pp.x + glove_dx, pp.y, -0.9)
		for i in 60 * 6:
			bp._process(1.0 / 60.0)
			if pitch.landed:
				break
		for i in 60 * 14:
			bp._process(1.0 / 60.0)
			if bp.flow.batter_ready and bp.flow.aux_play.is_empty():
				break
		done += 1
	return {"pitches": done, "frames": int(bp.fielding.fld.frames), "lost": int(bp.fielding.fld.lost), "passed": int(bp.fielding.fld.passed)}


func _init() -> void:
	# The pure part.
	var edge := Vector3(PitchPhysics.ZONE_HALF_W + PitchPhysics.BALL_RADIUS, 0.85, 0.0)
	_check(absf(Framing.edge_distance(edge)) < 0.001, "the edge of the zone is distance zero")
	_check(Framing.edge_distance(Vector3(0.0, 0.85, 0.0)) < -0.25 and Framing.edge_distance(Vector3(0.6, 0.85, 0.0)) > 0.2, "inside is negative, outside positive")
	var perfect := Framing.assess(_still(Vector3(0.0, 0.85, -0.9)), Vector3(0.0, 0.85, 0.0))
	_check(perfect.quality > 0.99 and perfect.cover > 0.99, "a still glove on the ball is a perfect catch")
	var stab: Array = []
	for i in 10:
		stab.append([i * 0.03, Vector3(-0.3 + i * 0.07, 0.85, -0.9)])
	var stabbed := Framing.assess(stab, Vector3(0.0, 0.85, 0.0))
	_check(stabbed.quality < perfect.quality - 0.2 and stabbed.speed > 1.5, "a glove thrashing around is worse (%.2f at %.1f m/s)" % [stabbed.quality, stabbed.speed])
	var far := Framing.assess(_still(Vector3(0.7, 0.2, -0.9)), Vector3(0.0, 0.85, 0.0))
	_check(far.quality < 0.01 and far.cover < 0.01, "a glove nowhere near is nothing")
	_check(Framing.assess([], Vector3.ZERO).quality == 0.0, "no glove at all is nothing")
	var inch := 0.0254
	var just_off := Vector3(PitchPhysics.ZONE_HALF_W + PitchPhysics.BALL_RADIUS + 1.5 * inch, 0.85, 0.0)
	var good := Framing.call_strike(just_off, 1.0, 0.5)
	var neutral := Framing.call_strike(just_off, Framing.NEUTRAL, 0.5)
	var bad := Framing.call_strike(just_off, 0.0, 0.5)
	_check(good.p > 0.9 and good.strike and good.framed, "a great frame gets a pitch an inch and a half off (p %.2f)" % good.p)
	_check(neutral.p < 0.2 and bad.p < 0.001, "an ordinary catch does not (%.2f), a bad one never (%.4f)" % [neutral.p, bad.p])
	var inside := Vector3(0.0, 0.85, 0.0)
	_check(Framing.call_strike(inside, 0.0, 0.5).strike and Framing.call_strike(inside, 0.0, 0.5).p > 0.99, "a pitch down the middle is a strike however you catch it")
	var edge_in := Vector3(PitchPhysics.ZONE_HALF_W + PitchPhysics.BALL_RADIUS - 1.0 * inch, 0.85, 0.0)
	var lost := Framing.call_strike(edge_in, 0.0, 0.5)
	_check(not lost.strike and lost.lost, "a strike on the corner is lost by a poor receiver")
	_check(not Framing.call_strike(Vector3(0.0, 0.05, 0.0), 1.0, 0.0).strike, "a pitch in the dirt is never a strike")
	var rolls := 0
	for i in 100:
		if Framing.call_strike(just_off, 0.8, i / 100.0).strike:
			rolls += 1
	_check(rolls > 20 and rolls < 95, "in between it is a chance (%d of 100)" % rolls)
	_check(is_equal_approx(Framing.gets_away(0.5, 0.0), 0.5) and Framing.gets_away(0.5, 1.0) < 0.06, "a glove on a ball in the dirt stops most of them")

	# Config, menu and score.
	var c := GameConfig.new()
	c.mode = "Fielding"
	c.position = 2
	_check(c.normalized().position == 2 and c.normalized().title() == "Fielding (C) - 9-inning game", "the catcher is a position (%s)" % c.normalized().title())
	var m := MenuModel.new(Settings.new())
	m.stack = ["main", "play"]
	var fi := -1
	for i in m.items().size():
		if m.items()[i].id == "mode:Fielding":
			fi = i
	m.activate(fi)
	m.config.position = 9
	var pi := -1
	for i in m.items().size():
		if m.items()[i].id == "position":
			pi = i
	m.activate(pi)
	_check(m.config.position == 1, "the position row wraps from right field to the pitcher")
	m.activate(pi)
	_check(m.config.position == 2, "and then the catcher")
	var plain := PlayerProfile.fielding_score({"caught": 3})
	var catcher := PlayerProfile.fielding_score({"caught": 3, "frames": 4, "blocks": 2, "lost": 1, "passed": 1})
	_check(catcher == plain + 16 + 4 - 3 - 8, "framing and blocking count in the score (%d vs %d)" % [catcher, plain])

	# In the scene.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_mode_name = "Fielding"
	bp.fielding_position = 2
	bp.spectate_interval = 0.8
	root.add_child(bp)
	await process_frame
	_check(bp.fielding.is_catcher() and not bp._mode.human_pitcher, "you are the catcher")
	_check(not bp._catcher.visible, "his stand-in is out of the way")
	var good_run := _run_pitches(bp, 0.0, 10)
	print("  good glove: %s" % str(good_run))
	_check(good_run.pitches >= 8 and good_run.lost <= 1, "with the glove on every ball you almost never lose a call")
	# The call itself, on a corner strike and a pitch just off the plate, many times over.
	bp.fielding.fld = {"chances": 0, "caught": 0, "missed": 0, "errors": 0, "assists": 0, "frames": 0, "lost": 0, "blocks": 0, "passed": 0}
	bp._spectate_timer = 1e9                      # no more real pitches: only the ones this test makes
	for i in 60 * 8:
		bp._process(1.0 / 60.0)
		if bp.flight.pitches.is_empty() and bp.flow.batter_ready and bp.flow.aux_play.is_empty():
			break
	bp.fielding.fld = {"chances": 0, "caught": 0, "missed": 0, "errors": 0, "assists": 0, "frames": 0, "lost": 0, "blocks": 0, "passed": 0, "covers": 0, "uncovered": 0}
	var corner := Vector3(PitchPhysics.ZONE_HALF_W + PitchPhysics.BALL_RADIUS - 1.0 * inch, 0.85, 0.0)
	var off := Vector3(PitchPhysics.ZONE_HALF_W + PitchPhysics.BALL_RADIUS + 1.5 * inch, 0.85, 0.0)
	var dummy := LivePitch.new()
	bp.fielding.glove_override = Vector3(corner.x, corner.y, -0.9)
	for i in 40:
		bp._process(1.0 / 60.0)
	var kept := 0
	for i in 20:
		if bp.fielding.receive(dummy, corner, "called_strike") == "called_strike":
			kept += 1
	_check(kept == 20 and bp.fielding.fld.lost == 0, "a still glove on a corner strike keeps it every time")
	var stolen := 0
	for i in 20:
		if bp.fielding.receive(dummy, off, "ball") == "called_strike":
			stolen += 1
	_check(stolen >= 12 and bp.fielding.fld.frames == stolen, "and steals the one just off the plate (%d of 20)" % stolen)
	bp.fielding.glove_override = Vector3(1.5, 0.2, -0.9)
	for i in 40:
		bp._process(1.0 / 60.0)
	bp.fielding.fld.lost = 0
	var kept2 := 0
	for i in 20:
		if bp.fielding.receive(dummy, corner, "called_strike") == "called_strike":
			kept2 += 1
	_check(kept2 <= 6 and bp.fielding.fld.lost == 20 - kept2, "a glove that is somewhere else loses it (%d kept)" % kept2)
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
