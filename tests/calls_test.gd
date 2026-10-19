extends SceneTree
## Handedness and play calls: a left-hander's hit is the mirror of a right-hander's, opposite-handed
## pitchers are easier to hit, the squeeze and hit-and-run are called in the right situations and
## change what the batter does, a runner can score or be out from third, and it plays in the scene.
## Run: godot --headless --path . -s res://tests/calls_test.gd

var _failures := 0
const REL := Vector3(0.0, 2.1, 16.74)


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _pitch(rng: RandomNumberGenerator, call := "") -> Dictionary:
	var def: Dictionary = PitchPhysics.CANNED["Fastball"]
	var spin: Vector3 = (def.rpm as Vector3) * PitchPhysics.RPM_TO_RADS
	var target := Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.55, 1.15), 0.0)
	var v := PitchPhysics.solve_aim(REL, (float(def.mph) - 18.0) / PitchPhysics.MPS_TO_MPH, spin, target)
	return {"release": REL, "vel": v, "spin": spin, "flutter_amp": 0.0, "flutter_seed": 0.0,
		"analysis": PitchPhysics.analyze(REL, v, spin),
		"situation": {"bases": [false, false, true], "outs": 0, "strikes": 0, "balls": 0, "call": call}}


func _init() -> void:
	# Platoon: the same batter, the same pitches, opposite hands vs the same hand.
	var rates := {}
	for plat in [1.0, -1.0]:
		var ai := BatterAI.new(BatterProfile.by_name("Journeyman"))
		ai.rng.seed = 99
		ai.force_no_bunt = true
		ai.platoon = plat
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var contact := 0
		var swings := 0
		for i in 3000:
			var r := ai.evaluate(_pitch(rng))
			if r.swing:
				swings += 1
				if r.contact:
					contact += 1
		rates[plat] = float(contact) / maxf(swings, 1)
	_check(rates[1.0] > rates[-1.0] + 0.01, "a batter makes more contact against a pitcher of the other hand (%.3f vs %.3f)" % [rates[1.0], rates[-1.0]])
	_check(BatterAI.platoon_for(true, false) == 1.0 and BatterAI.platoon_for(true, true) == -1.0 and BatterAI.platoon_for(false, true) == 1.0, "platoon_for: opposite hands help the batter")

	# Mirror: with the same random numbers a left-hander's batted ball is the right-hander's, reflected.
	var mirrored_ok := true
	var n := 0
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	for i in 300:
		var p := _pitch(rng2)
		var a := BatterAI.new(BatterProfile.by_name("Contact Hitter"))
		a.rng.seed = i + 1000
		a.force_no_bunt = true
		var b := BatterAI.new(BatterProfile.by_name("Contact Hitter"))
		b.rng.seed = i + 1000
		b.force_no_bunt = true
		b.bats_left = true
		var ra := a.evaluate(p)
		var rb := b.evaluate(p)
		if ra.get("contact", false) and ra.kind == "hit":
			n += 1
			var va: Vector3 = ra.vel
			var vb: Vector3 = rb.vel
			if absf(va.x + vb.x) > 0.001 or absf(va.y - vb.y) > 0.001 or absf(va.z - vb.z) > 0.001 or absf(float(ra.spray) + float(rb.spray)) > 0.001:
				mirrored_ok = false
	_check(n > 50 and mirrored_ok, "a left-hander's hit is the mirror image of a right-hander's (%d hits)" % n)

	# The batter's side of a call.
	var sq_bunts := 0
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 3
	var swing_plain := 0
	var swing_hr := 0
	for i in 600:
		var p := _pitch(rng3)
		var s := BatterAI.new(BatterProfile.by_name("Slugger"))
		s.rng.seed = i
		p["situation"]["call"] = "squeeze"
		if s.evaluate(p).bunt:
			sq_bunts += 1
		var a := BatterAI.new(BatterProfile.by_name("Contact Hitter"))
		a.rng.seed = i
		a.force_no_bunt = true
		var b := BatterAI.new(BatterProfile.by_name("Contact Hitter"))
		b.rng.seed = i
		b.force_no_bunt = true
		p["situation"]["call"] = ""
		if a.evaluate(p).swing:
			swing_plain += 1
		p["situation"]["call"] = "hit_and_run"
		if b.evaluate(p).swing:
			swing_hr += 1
	_check(sq_bunts == 600, "when a squeeze is on even a slugger bunts (%d of 600)" % sq_bunts)
	_check(swing_hr >= swing_plain, "on a hit-and-run he protects the runner (%d swings vs %d)" % [swing_hr, swing_plain])

	# Calling the play.
	var contact_hitter := BatterProfile.by_name("Contact Hitter")
	var slugger := BatterProfile.by_name("Slugger")
	var rng4 := RandomNumberGenerator.new()
	rng4.seed = 11
	var third := [null, null, true]
	var first := [true, null, null]
	var counts := {"late": 0, "early": 0, "slugger": 0, "blowout": 0, "hr_first": 0, "hr_loaded": 0, "hr_slugger": 0}
	for i in 4000:
		if StealModel.play_call(third, 0, 0, 8, 0, contact_hitter, rng4) == "squeeze":
			counts.late += 1
		if StealModel.play_call(third, 0, 0, 2, 0, contact_hitter, rng4) == "squeeze":
			counts.early += 1
		if StealModel.play_call(third, 0, 0, 8, 0, slugger, rng4) == "squeeze":
			counts.slugger += 1
		if StealModel.play_call(third, 0, 0, 8, -6, contact_hitter, rng4) == "squeeze":
			counts.blowout += 1
		if StealModel.play_call(first, 0, 0, 5, 0, contact_hitter, rng4) == "hit_and_run":
			counts.hr_first += 1
		if StealModel.play_call([true, true, true], 0, 0, 5, 0, contact_hitter, rng4) == "hit_and_run":
			counts.hr_loaded += 1
		if StealModel.play_call(first, 0, 0, 5, 0, slugger, rng4) == "hit_and_run":
			counts.hr_slugger += 1
	_check(counts.late > 100 and counts.late < 700, "a late close game with a man on third sometimes calls the squeeze (%d of 4000)" % counts.late)
	_check(counts.early == 0 and counts.blowout == 0 and counts.slugger == 0, "never early, in a blowout, or for a slugger (%s)" % str(counts))
	_check(counts.hr_first > 50 and counts.hr_loaded == 0 and counts.hr_slugger == 0, "hit-and-run: a contact hitter with a man alone on first (%d); not with the bases loaded or a slugger" % counts.hr_first)
	_check(StealModel.play_call(third, 2, 0, 8, 0, contact_hitter, rng4) == "" and StealModel.play_call(third, 0, 2, 8, 0, contact_hitter, rng4) == "", "no call with two outs or two strikes")

	# The book: a runner going from third.
	var team := Team.generate("T", 50.0, 3)
	var g := GameState.new(team.lineup, 9)
	g.bases = [null, null, team.lineup[0]]
	var ev := g.steal(3, true)
	_check(g.runs == 1 and g.bases[2] == null and ev.result == "stolen_base" and ev.runs == 1, "safe from third scores a run")
	g.bases = [null, null, team.lineup[1]]
	g.outs = 0
	var ev2 := g.steal(3, false)
	_check(g.outs == 1 and g.bases[2] == null and ev2.result == "caught_stealing" and ev2.text.contains("home"), "out from third is caught stealing home")

	# In the scene: a squeeze is called, played, and everything settles afterwards.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	var called := 0
	var finished := 0
	for attempt in 40:
		bp._game.inning = 8
		bp._game.outs = 0
		bp._game.strikes = 0
		bp._game.balls = 0
		bp._game.runs = 2
		bp._game.home_score = 2
		bp._game.bases = [null, null, bp._away.lineup[0]]
		bp._batter_ai.profile = BatterProfile.by_name("Contact Hitter")
		bp._batter_ready = true
		bp._steal = {}
		bp._aux_play = {}
		bp._refresh_base_runners()
		var tries := 0
		while bp._steal.is_empty() and tries < 200:
			bp._on_delivery_start()
			tries += 1
		if bp._steal.is_empty():
			continue
		called += 1
		if called == 1:
			_check(bp._steal.call == "squeeze" and int(bp._steal.from) == 3 and bp._bat_call == "squeeze", "a squeeze breaks the runner from third")
		bp._debug_throw()
		for i in 60 * 12:
			bp._process(1.0 / 60.0)
			if bp._steal.is_empty() and bp._aux_play.is_empty() and bp._hits.all(func(h): return h.result_shown):
				break
		if bp._steal.is_empty() and bp._bat_call == "":
			finished += 1
		if called >= 6:
			break
	_check(called >= 3 and finished == called, "squeezes were called and every one played out cleanly (%d called, %d finished)" % [called, finished])
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
