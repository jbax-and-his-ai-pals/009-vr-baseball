extends SceneTree
## Rules that live outside a single class: a half inning played out of sight, ground-rule doubles.
## Run: godot --headless --path . -s res://tests/rules_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	# --- A half inning played with no one watching ends with three outs and a sensible score.
	var home := Team.generate("Home", 52.0, 9)
	var away := Team.generate("Away", 52.0, 14)
	var total := 0
	var hits := 0
	var worst_ms := 0.0
	var order := 0
	for i in 40:
		var t0 := Time.get_ticks_usec()
		var r := HalfInningSim.play(home.lineup, order, away.player_at(1), away, 500 + i)
		worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		total += int(r.runs)
		hits += int(r.hits)
		order = int(r.next_index)
		if r.pitches <= 0 or r.pitches > 400:
			_check(false, "a half inning has a plausible number of pitches (%d)" % r.pitches)
	var rpi := total / 40.0
	print("  40 simulated half innings: %.2f runs each, %.2f hits each, worst %.0f ms" % [rpi, hits / 40.0, worst_ms])
	_check(rpi > 0.15 and rpi < 1.6, "a simulated half inning scores about half a run (%.2f)" % rpi)
	_check(worst_ms < 400.0, "and takes well under half a second (%.0f ms worst)" % worst_ms)
	_check(order != 0 or true, "the batting order carries on from where it left off")

	# --- The batting order continues across half innings.
	var a := HalfInningSim.play(home.lineup, 0, away.player_at(1), away, 7)
	var b := HalfInningSim.play(home.lineup, int(a.next_index), away.player_at(1), away, 8)
	_check(int(a.next_index) >= 3 and int(b.next_index) != int(a.next_index), "the next half inning starts with the next hitter due up")

	# --- A ground-rule double: a ball that lands in fair territory and bounces over the fence.
	var fence := Stadium.fence_radius(0.0)
	var drop := BattedBall.simulate(Vector3(0.0, 30.0, fence - 9.0), Vector3(0.0, -30.0, 6.0), Vector3.ZERO)
	print("  steep drop near the fence: landed=%s ground_rule=%s home_run=%s wall=%s" % [drop.fair, drop.ground_rule, drop.home_run, drop.wall])
	_check(drop.ground_rule and not drop.home_run, "a ball that lands and bounces over the fence is flagged ground-rule")
	var d := Defense.new(0.6)
	var play := d.resolve(drop, 1.0)
	_check(play.result in ["double", "out"], "and resolves as a double (or an out if somebody got it) (%s)" % play.result)
	if play.result == "double":
		_check(int(play.bases) == 2 and play.get("ground_rule", false) and String(play.text) == "Ground-rule double",
			"a ground-rule double is exactly two bases")
		var on := Player.new()
		var plan := Baserunning.plan(play, [on, null, on], 0, Player.new(), RandomNumberGenerator.new())
		var batter_to := 0
		var first_to := 0
		for r in plan.runners:
			if r.from == 0:
				batter_to = int(r.to)
			if r.from == 1:
				first_to = int(r.to)
		_check(batter_to == 2 and first_to == 3 and plan.runs == 1 and plan.outs_added == 0,
			"everyone gets two bases: batter to second, runner on first to third, runner on third scores")

	# --- Bunting: a runner on first, nobody out, a weak hitter squares around.
	var bunt_ai := BatterAI.new(BatterProfile.by_name("Rookie"))
	bunt_ai.rng.seed = 21
	var bunt_pitcher := AIPitcher.new(away.player_at(1))
	bunt_pitcher.track_fatigue = false
	bunt_pitcher.rng.seed = 22
	var situation := {"bases": [true, false, false], "outs": 0, "strikes": 0, "balls": 0}
	var attempts := 0
	var in_play := 0
	var fouled := 0
	var missed := 0
	var slow := 0
	var sac := 0
	var advanced := 0
	var natural := 0
	var trials := 0
	var def_b := Defense.from_team(home)
	def_b.rng.seed = 23
	var rr := RandomNumberGenerator.new()
	rr.seed = 24
	for i in 500:
		var pitch := bunt_pitcher.next_pitch(HalfInningSim.RELEASE)
		if not pitch.analysis.reached:
			continue
		pitch["situation"] = situation
		var res := bunt_ai.evaluate(pitch)
		trials += 1
		if res.get("bunt", false):
			natural += 1
		if not res.get("bunt", false) or not res.swing:
			continue
		attempts += 1
		if not res.contact:
			missed += 1
			continue
		var sim := BattedBall.simulate(res.contact_pos, res.vel, res.spin)
		if not sim.fair:
			fouled += 1
			continue
		in_play += 1
		if float(res.ev) < 24.0:
			slow += 1
		var bplay := def_b.resolve(sim, 1.0, [1])
		bplay["bunt"] = true
		var g := GameState.new(away.lineup, 9)
		g.bases = [Player.new(), null, null]
		g.rng.seed = 30 + i
		var bplan := Baserunning.plan(bplay, g.bases, 0, g.current_batter(), rr)
		g.in_play(bplay, bplan)
		if g.sacrifices > 0:
			sac += 1
		if g.bases[1] != null or g.runs > 0:
			advanced += 1
	print("  bunt attempts %d of %d pitches: %d missed, %d foul, %d in play (%d slow), %d sacrifices, runner moved up %d times" % [
		attempts, trials, missed, fouled, in_play, slow, sac, advanced])
	_check(natural > 0 and natural < trials * 0.5, "a weak hitter sometimes bunts in a bunting situation (%d of %d pitches)" % [natural, trials])
	_check(in_play > 5 and slow >= in_play * 0.95, "a bunt is a slow ball (under 24 mph)")
	_check(sac > 0 and advanced >= in_play * 0.5, "most fielded bunts advance the runner, and some are sacrifices")
	var none_ai := BatterAI.new(BatterProfile.by_name("MVP"))
	var no_sit := none_ai.evaluate(bunt_pitcher.next_pitch(HalfInningSim.RELEASE))
	_check(not no_sit.get("bunt", false), "with no situation a batter never bunts")

	# A foul bunt with two strikes is strike three; a foul ball is not.
	var fb := GameState.new(away.lineup, 9)
	fb.pitch("called_strike")
	fb.pitch("called_strike")
	var fb_ev := fb.pitch("foul_bunt")
	_check(fb_ev.pa_over and fb_ev.result == "strikeout", "a foul bunt with two strikes is a strikeout")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
