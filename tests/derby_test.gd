extends SceneTree
## Home run derby: easy pitches, ten outs, homers counted, stars saved, a way back to the menu.
## Run: godot --headless --path . -s res://tests/derby_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _set_bat(bp: Node3D, plate: Vector3, swing_speed: float, dy: float) -> void:
	var t: SwingTracker = bp._tracker
	var through := Vector3(plate.x, plate.y + dy, 0.0)
	t.knob = through - Vector3(BatPhysics.SWEET, 0.0, 0.0)
	t.tip = t.knob + Vector3(BatPhysics.LENGTH, 0.0, 0.0)
	t.knob_vel = Vector3(0.0, 0.0, swing_speed * 0.5)
	t.tip_vel = Vector3(0.0, 0.0, swing_speed)


func _init() -> void:
	var c := GameConfig.new()
	c.mode = "Hitting"
	c.activity = "Derby"
	_check(c.normalized().activity == "Derby" and not c.normalized().is_scored() or c.normalized().activity == "Derby", "Derby is an activity of Hitting")
	_check(c.normalized().title() == "Home run derby", "with a title")
	var p := GameConfig.new()
	p.mode = "Pitching"
	p.activity = "Derby"
	_check(p.normalized().activity == "Game", "only Hitting has one")
	var m := MenuModel.new(Settings.new())
	m.stack = ["main", "play"]
	var idx := -1
	for i in m.items().size():
		if m.items()[i].id == "mode:Hitting":
			idx = i
	m.activate(idx)
	m.config.activity = "Derby"
	var note := ""
	for r in m.items():
		if r.id == "start":
			note = String(r.note)
	_check(note.begins_with("ten outs"), "the Start row explains it (%s)" % note)

	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_mode_name = "Hitting"
	root.add_child(bp)
	await process_frame
	bp.acts.derby = true
	var fake := LivePitch.new()
	fake.bat = {"contact": true}
	bp.acts.derby_tally(fake, true, false)
	bp.acts.derby_tally(fake, false, false)
	_check(bp.acts.derby_hr == 1 and bp.acts.derby_outs == 1, "a homer is counted, any other contact is an out")
	var ball_only := LivePitch.new()
	ball_only.bat = {"swing": false, "contact": false}
	bp.acts.derby_tally(ball_only, false, false)
	_check(bp.acts.derby_outs == 1, "a ball you let go is free")
	bp.acts.derby_hr = 0
	bp.acts.derby_outs = 0
	var seen: Array = []
	var speeds: Array = []
	var in_zone := 0
	var swings := 0
	var hrs_seen := 0
	for round in 40:
		if bp.acts.derby_done:
			break
		var pitch: LivePitch = null
		for i in 60 * 30:
			bp._process(1.0 / 60.0)
			for q in bp._pitches:
				if not seen.has(q) and not q.landed:
					seen.append(q)
					pitch = q
			if pitch != null:
				break
		if pitch == null:
			break
		speeds.append(float(pitch.analysis.speed_mph))
		var pp: Vector3 = pitch.analysis.plate_pos
		if PitchLocation.classify(pp.x, pp.y).strike:
			in_zone += 1
		swings += 1
		# Alternate: a huge swing that goes under the ball (a drive), and one that misses completely.
		var dy := -0.022 if round % 2 == 0 else 0.4
		for i in 60 * 3:
			_set_bat(bp, pp, 40.0, dy)
			bp._process(1.0 / 60.0)
			if pitch.landed:
				break
		if pitch.bat.get("contact", false):
			print("  swing %d: %s %.0f mph la %.0f dist %.0f hr %s" % [round, pitch.bat.kind, pitch.bat.ev, pitch.bat.la, pitch.sim.get("distance", 0.0), pitch.sim.get("home_run", false)])
		if int(bp.acts.derby_hr) > hrs_seen:
			hrs_seen = bp.acts.derby_hr
		for i in 60 * 16:
			bp._process(1.0 / 60.0)
			if bp._batter_ready and bp._aux_play.is_empty() and bp._hits.all(func(h): return h.result_shown):
				break
	_check(speeds.size() >= 6 and speeds.max() < 60.0, "batting practice pitches are slow (%.0f mph at most)" % speeds.max())
	_check(in_zone >= speeds.size() - 1, "and over the plate (%d of %d)" % [in_zone, speeds.size()])
	_check(bp.acts.derby_done and bp.acts.derby_outs >= 10, "ten outs end it (%d outs, %d homers)" % [bp.acts.derby_outs, bp.acts.derby_hr])
	_check(int(bp._profile.challenge("derby").attempts) == 1, "the result is saved")
	_check(bp._props.pending_count() > 0 and not bp.results.game_recorded, "a way back to the menu is scheduled, and it is not a recorded game")
	print("  homers hit in the test: %d" % hrs_seen)
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
