extends SceneTree
## Calibration between games: what the game learned about your arm is saved per throwing hand and picked up by the
## next game; a warm-up starts from scratch and only saves when it is done; until your arm is known the menu
## starts with the warm-up and puts it in front of anything on the mound. Also: a game started from the menu keeps
## being the game it was (the lesson, the bullpen, the warm-up), which a second set-up used to undo.
## Run: godot --headless --path . -s res://tests/calibration_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _scene(pending: GameConfig = null) -> Node3D:
	Session.pending = pending
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	return bp


func _init() -> void:
	ThrowLogger.override_path = "user://test_throws.jsonl"
	Calibration.override_path = "user://test_calibration_unit.json"
	Calibration.clear()

	# --- The file.
	_check(not Calibration.exists("right") and Calibration.load_for("right").is_empty(), "nothing saved: not calibrated")
	var h := HumanPitcher.new()
	h.aim_mu = Vector2(2.5, -1.0)
	h.aim_sigma = Vector2(3.2, 3.9)
	h.aim_n = 40
	h.wrist.mean_speed = 12.7
	h.wrist.mean_snap = 2.1
	h.wrist.throws_seen = 40
	for v in [11.0, 12.0, 13.0, 14.0, 12.5, 12.2, 13.4, 11.8, 12.9, 15.1]:
		h._remember_speed(v)
	_check(h.is_calibrated(), "forty throws in: calibrated")
	Calibration.save_for("right", h.to_dict())
	var back := HumanPitcher.new()
	back.apply_dict(Calibration.load_for("right"))
	_check(back.aim_mu.is_equal_approx(h.aim_mu) and back.aim_sigma.is_equal_approx(h.aim_sigma) and back.aim_n == 40, "your usual aim and its scatter come back")
	_check(is_equal_approx(back.wrist.mean_speed, 12.7) and is_equal_approx(back.wrist.mean_snap, 2.1) and back.wrist.throws_seen == 40, "and the wrist model's usual throw")
	_check(is_equal_approx(back.top_speed(), h.top_speed()) and back.is_calibrated(), "and your top speed: a saved arm is a known arm")
	_check(not Calibration.exists("left"), "each throwing hand has its own")
	Calibration.save_for("left", HumanPitcher.new().to_dict())
	Calibration.clear("left")
	_check(Calibration.exists("right") and not Calibration.exists("left"), "forgetting one hand keeps the other")
	back.reset_calibration(true)
	_check(back.aim_n == 0 and back.wrist.throws_seen == 0 and back.aim_mu.x < 0.0 and not back.is_calibrated(), "a reset starts over from the prior (mirrored for a left-hander)")
	var w := WristModel.new()
	w.from_dict({"mean_side": 1.25, "throws_seen": 7, "nonsense": 3})
	_check(is_equal_approx(w.mean_side, 1.25) and w.throws_seen == 7 and is_equal_approx(w.mean_snap, 2.67), "the wrist model reads what it knows and keeps defaults for the rest")

	# --- The warm-up as a game.
	var wc := GameConfig.new()
	wc.warmup = true
	wc.mode = "Fielding"
	wc.daily = 99
	var wn := wc.normalized()
	_check(wn.warmup and wn.mode == "Pitching" and wn.activity == "Bullpen" and wn.daily == 0 and not wn.is_scored() and wn.title() == "Warm-up", "the warm-up is an unscored pitching bullpen with its own title")
	_check(GameConfig.from_dict(wn.to_dict()).warmup and not wn.needs_arm(), "it round-trips, and it is the one game that does not need your arm known")
	var pc := GameConfig.new()
	_check(pc.normalized().needs_arm(), "a pitching game needs it")
	var fc := GameConfig.new()
	fc.mode = "Fielding"
	_check(not fc.normalized().needs_arm(), "fielding does not")

	# --- The menu.
	var s := Settings.new()
	var m := MenuModel.new(s)
	m.calibrated = false
	var main_rows := m.items().map(func(r): return r.id)
	_check(main_rows[0] == "warmup", "not calibrated: the main menu starts with the warm-up")
	m.calibrated = true
	_check(not "warmup" in m.items().map(func(r): return r.id), "calibrated: it does not")
	m.calibrated = false
	m.stack = ["main", "play"]
	var prow := m.items().map(func(r): return r.id)
	var ev := m.activate(prow.find("mode:Pitching"))
	ev = m.activate(m.items().map(func(r): return r.id).find("start"))
	_check(ev.get("type", "") == "start" and ev.config.warmup and ev.has("then") and ev.then.mode == "Pitching" and not ev.then.warmup,
		"starting a pitching game first warms you up, then plays the game you chose")
	m.stack = ["main", "play"]
	m.activate(m.items().map(func(r): return r.id).find("mode:Fielding"))
	var fev := m.activate(m.items().map(func(r): return r.id).find("start"))
	_check(fev.get("type", "") == "start" and not fev.config.warmup and not fev.has("then"), "fielding starts straight away")
	m.calibrated = true
	m.stack = ["main", "options"]
	var orow := m.items().map(func(r): return r.id)
	var rev := m.activate(orow.find("recalibrate"))
	_check(rev.get("type", "") == "start" and rev.config.warmup and not rev.has("then"), "Options > Recalibrate pitching starts a warm-up")
	m.stack = ["main", "options"]
	var before := s.pitch_select
	m.activate(m.items().map(func(r): return r.id).find("pitch_select"))
	_check(s.pitch_select != before and Settings.from_dict(s.to_dict()).pitch_select == s.pitch_select, "the pitch choice cycles and is saved")
	_check(Settings.from_dict({"pitch_select": "Telepathy"}).pitch_select == "Grip", "an unknown pitch choice falls back to Grip")

	# --- The scene: a game keeps being the game the menu started.
	var tc := GameConfig.new()
	tc.tutorial = true
	var bp := _scene(tc.normalized())
	await process_frame
	_check(bp.acts.tutorial != null and bp._config.tutorial and bp._config.activity == "Bullpen", "a lesson started from the menu is still the lesson (and the bullpen) after set-up")
	bp.queue_free()
	await process_frame
	for want in [["Pitching", "Bullpen"], ["Fielding", "Drill"], ["Hitting", "Derby"]]:
		var ac := GameConfig.new()
		ac.mode = want[0]
		ac.activity = want[1]
		var ab := _scene(ac.normalized())
		for i in 5:
			await process_frame
		var kept: bool = ab._config.activity == want[1]
		if want[1] == "Drill":
			kept = kept and ab.acts.drill
		if want[1] == "Derby":
			kept = kept and ab.acts.derby
		_check(kept, "%s %s started from the menu is still that after set-up (and runs)" % want)
		ab.queue_free()
		await process_frame

	# --- The scene picks up your saved arm, and a warm-up starts from scratch.
	var bp2 := _scene()
	await process_frame
	_check((bp2._human as HumanPitcher).aim_mu.is_equal_approx(Vector2(2.5, -1.0)) and (bp2._human as HumanPitcher).is_calibrated(), "a new game starts from your saved arm")
	(bp2._human as HumanPitcher).aim_mu = Vector2(1.0, 1.0)
	bp2.remember_arm()
	_check(Vector2(Calibration.load_for("right").aim_mu[0], Calibration.load_for("right").aim_mu[1]).is_equal_approx(Vector2(1.0, 1.0)), "after each pitch it keeps what it learned")
	bp2.queue_free()
	await process_frame
	var bp3 := _scene(wn)
	await process_frame
	_check(bp3.acts.warmup != null and not (bp3._human as HumanPitcher).is_calibrated() and (bp3._human as HumanPitcher).grip == Grips.FOUR_SEAM, "a warm-up starts from scratch, with the four-seamer")
	(bp3._human as HumanPitcher).aim_mu = Vector2(-7.0, -7.0)
	bp3.remember_arm()
	_check(Vector2(Calibration.load_for("right").aim_mu[0], Calibration.load_for("right").aim_mu[1]).is_equal_approx(Vector2(1.0, 1.0)), "a warm-up stopped half way keeps the old calibration")
	bp3.queue_free()
	await process_frame

	Calibration.clear()
	Calibration.override_path = ""
	Session.pending = null
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
