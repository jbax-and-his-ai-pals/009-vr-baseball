extends SceneTree
## Ratings should create real separation: faster runners, stronger fielders, better hitters and
## better AI pitchers must each produce visibly different results, and game modes assign roles.
## Run: godot --headless --path . -s res://tests/players_test.gd

const REL := Vector3(0.0, 2.1, 16.74)
var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _ball(ev_mph: float, launch_deg: float, spray_deg: float) -> Dictionary:
	var v := ev_mph / PitchPhysics.MPS_TO_MPH
	var la := deg_to_rad(launch_deg)
	var psi := deg_to_rad(spray_deg)
	var dir_h := Vector3(sin(psi), 0.0, cos(psi))
	var vel := dir_h * (v * cos(la)) + Vector3.UP * (v * sin(la))
	return BattedBall.simulate(Vector3(0.0, 0.9, 0.4), vel, dir_h.cross(Vector3.UP).normalized() * (1800.0 * PitchPhysics.RPM_TO_RADS))


func _out_rate(team: Team, sim: Dictionary, n: int, run_factor: float = 1.0) -> float:
	var outs := 0
	for i in n:
		var d := Defense.from_team(team)
		d.rng.seed = 5000 + i
		var play := d.resolve(sim, run_factor)
		if play.result == "out":
			outs += 1
	return float(outs) / n


func _team_of(rating: float) -> Team:
	return Team.generate("Flat", rating, 3, 0.0)


func _pitcher(velocity: float, command: float, movement: float) -> Player:
	var p := Player.new()
	p.velocity = velocity
	p.command = command
	p.movement = movement
	return p


func _init() -> void:
	# --- Rosters have positional character and are repeatable.
	var t1 := Team.generate("A", 50.0, 11)
	var t2 := Team.generate("A", 50.0, 11)
	_check(t1.player_at(6).name == t2.player_at(6).name and t1.player_at(6).speed == t2.player_at(6).speed, "the same seed makes the same roster")
	_check(t1.lineup.size() == 9 and t1.alignment.size() == 9, "a team has nine lineup spots and nine defensive positions")
	var ss_range := 0.0
	var first_range := 0.0
	var cf_speed := 0.0
	var c_speed := 0.0
	for seed_value in 30:
		var t := Team.generate("T", 50.0, seed_value)
		ss_range += t.player_at(6).fielding_range
		first_range += t.player_at(3).fielding_range
		cf_speed += t.player_at(8).speed
		c_speed += t.player_at(2).speed
	_check(ss_range > first_range + 30.0 * 10.0, "shortstops have more range than first basemen (%.0f vs %.0f avg)" % [ss_range / 30.0, first_range / 30.0])
	_check(cf_speed > c_speed + 30.0 * 15.0, "center fielders are faster than catchers (%.0f vs %.0f avg)" % [cf_speed / 30.0, c_speed / 30.0])

	# --- Ratings reach the systems that use them.
	var star := Player.new()
	star.eye = 90.0
	star.contact = 80.0
	star.power = 70.0
	var prof := BatterProfile.from_player(star)
	_check(absf(prof.eye - 0.9) < 1e-6 and absf(prof.contact - 0.8) < 1e-6 and absf(prof.power - 0.7) < 1e-6, "a batter profile reads the player's hitting ratings")
	_check(Player.factor(50.0) == 1.0 and Player.factor(90.0) > Player.factor(20.0), "a rating of 50 is the calibrated baseline and more is more")

	# --- Speed: a slow roller to short is closer to a hit for a fast runner.
	var roller := _ball(40.0, 0.0, 20.0)      # a soft dribbler to third: a close play at first
	var avg_team := _team_of(50.0)
	var out_slow := _out_rate(avg_team, roller, 300, Player.factor(15.0, 0.30))
	var out_fast := _out_rate(avg_team, roller, 300, Player.factor(95.0, 0.30))
	print("slow roller to short: out %.0f%% vs a slow runner, %.0f%% vs a fast one" % [out_slow * 100.0, out_fast * 100.0])
	_check(out_slow > out_fast + 0.2, "the same dribbler is an out far more often against a slow runner than a fast one")

	# --- Fielding: elite range/hands/arm turns more balls into outs than poor.
	var gap := _ball(100.0, 15.0, -14.0)
	var hole := _ball(88.0, -2.0, 22.0)       # a hard grounder in the 5-6 hole
	var elite := _team_of(85.0)
	var poor := _team_of(20.0)
	var elite_gap := _out_rate(elite, gap, 300)
	var poor_gap := _out_rate(poor, gap, 300)
	var elite_hole := _out_rate(elite, hole, 300)
	var poor_hole := _out_rate(poor, hole, 300)
	print("gap liner outs: elite D %.0f%% vs poor D %.0f%% | hard grounder in the hole: elite %.0f%% vs poor %.0f%%" % [
		elite_gap * 100.0, poor_gap * 100.0, elite_hole * 100.0, poor_hole * 100.0])
	_check(elite_gap > poor_gap + 0.10, "an elite defense catches more gap liners than a poor one")
	_check(elite_hole > poor_hole + 0.10, "an elite defense gets to more grounders than a poor one")

	# --- AI pitchers: command, velocity and movement are different things.
	var good := AIPitcher.new(_pitcher(85.0, 90.0, 75.0))
	var bad := AIPitcher.new(_pitcher(20.0, 20.0, 25.0))
	good.track_fatigue = false
	bad.track_fatigue = false
	# Same speed, different movement: break must be compared at equal flight times.
	var curvy := AIPitcher.new(_pitcher(50.0, 90.0, 90.0))
	var plain := AIPitcher.new(_pitcher(50.0, 90.0, 10.0))
	curvy.track_fatigue = false
	plain.track_fatigue = false
	curvy.rng.seed = 11
	plain.rng.seed = 11
	good.rng.seed = 11
	bad.rng.seed = 11
	var stats := {}
	for who in [["good", good], ["bad", bad], ["curvy", curvy], ["plain", plain]]:
		var pp: AIPitcher = who[1]
		var miss := 0.0
		var mph := 0.0
		var strikes := 0
		var n := 0
		var move := 0.0
		var spin_sum := 0.0
		for i in 600:
			var r := pp.next_pitch(REL)
			if not r.analysis.reached:
				continue
			n += 1
			spin_sum += r.analysis.spin_rpm
			miss += Vector2(r.actual.x - r.aim.x, r.actual.y - r.aim.y).length()
			mph += r.mph
			if r.analysis.strike:
				strikes += 1
			if r.analysis.has("ivb_in"):
				move += absf(r.analysis.ivb_in) + absf(r.analysis.hb_in)
		stats[who[0]] = {"miss": miss / n, "mph": mph / n, "strike": float(strikes) / n, "move": move / n, "spin": spin_sum / n}
	print("good pitcher: ", stats.good)
	print("bad pitcher:  ", stats.bad)
	_check(stats.good.miss < stats.bad.miss * 0.5, "high command lands the ball much closer to the aim point")
	_check(stats.good.mph > stats.bad.mph + 6.0, "high velocity is faster")
	_check(stats.curvy.spin > stats.plain.spin * 1.35, "high movement is more spin at the same speed (%.0f vs %.0f rpm)" % [stats.curvy.spin, stats.plain.spin])
	_check(stats.curvy.move > stats.plain.move * 1.08, "...and it shows up as more break (%.1f vs %.1f in)" % [stats.curvy.move, stats.plain.move])
	_check(stats.good.strike > stats.bad.strike + 0.04, "a pitcher with command throws more strikes")

	# --- The whole sim, AI vs AI: better stuff is harder to hit.
	var rates := {}
	var cases := [["stuff", _pitcher(92.0, 50.0, 85.0)], ["no_stuff", _pitcher(15.0, 50.0, 15.0)]]
	for who in cases:
		var pitcher_ai := AIPitcher.new(who[1])
		pitcher_ai.track_fatigue = false
		pitcher_ai.rng.seed = 21
		var batter := BatterAI.new(BatterProfile.by_name("Contact Hitter"))
		batter.rng.seed = 22
		var d := Defense.from_team(_team_of(50.0))
		d.rng.seed = 23
		var hits := 0
		var swings := 0
		var contacts := 0
		for i in 1800:
			var r := pitcher_ai.next_pitch(REL)
			if not r.analysis.reached:
				continue
			var e := batter.evaluate(r)
			if e.swing:
				swings += 1
			if e.contact:
				contacts += 1
			if e.kind == "hit":
				var sim := BattedBall.simulate(e.contact_pos, e.vel, e.spin)
				if sim.fair:
					var play := d.resolve(sim, 1.0)
					if play.result in ["single", "double", "triple", "inside_park_hr", "home_run"]:
						hits += 1
		rates[who[0]] = {"hits_per_swing": float(hits) / maxf(swings, 1), "contact_per_swing": float(contacts) / maxf(swings, 1)}
	print("vs Contact Hitter: stuff ", rates.stuff, " | no stuff ", rates.no_stuff)
	_check(rates.stuff.contact_per_swing < rates.no_stuff.contact_per_swing - 0.04, "better stuff gets the batter to miss more")
	_check(rates.stuff.hits_per_swing < rates.no_stuff.hits_per_swing, "better stuff allows fewer hits per swing")

	# --- Modes assign roles.
	var m_p := GameMode.pitching()
	var m_s := GameMode.spectate()
	var m_f := GameMode.fielding(6)
	_check(m_p.human_pitcher and m_p.supported and not m_p.is_all_ai(), "Pitching: you pitch, supported")
	_check(m_s.is_all_ai() and m_s.supported, "Spectate: everyone is AI")
	_check(m_f.supported and not m_f.is_ai_fielder(6) and m_f.is_ai_fielder(8), "Fielding: playable; you take one position, the AI the rest")
	_check(not GameMode.by_name("hitting").supported and GameMode.by_name("nonsense").name == "Pitching", "unbuilt modes are flagged; unknown names fall back to Pitching")

	# --- Fatigue and relievers.
	var arm := Player.new()
	_check(arm.fatigue(30) == 0.0 and arm.fatigue(85) > 0.3 and arm.fatigue(130) >= 0.99, "an arm is fresh early, tired by 85 pitches, spent by 130")
	var iron := Player.new()
	iron.stamina = 85.0
	_check(iron.fatigue(85) < arm.fatigue(85), "more stamina tires later")
	var fresh := AIPitcher.new(arm)
	fresh.pitches_thrown = 0
	var tired := AIPitcher.new(arm)
	tired.pitches_thrown = 140
	var fresh_mph := 0.0
	var tired_mph := 0.0
	var fresh_miss := 0.0
	var tired_miss := 0.0
	for i in 200:
		var a := fresh.next_pitch(Vector3(0.0, 2.1, 16.74))
		fresh.pitches_thrown = 1
		var b := tired.next_pitch(Vector3(0.0, 2.1, 16.74))
		tired.pitches_thrown = 140
		fresh_mph += a.mph
		tired_mph += b.mph
		fresh_miss += Vector2(a.actual.x - a.aim.x, a.actual.y - a.aim.y).length()
		tired_miss += Vector2(b.actual.x - b.aim.x, b.actual.y - b.aim.y).length()
	_check(tired_mph < fresh_mph * 0.97, "a tired pitcher throws slower (%.1f vs %.1f avg mph)" % [tired_mph / 200.0, fresh_mph / 200.0])
	_check(tired_miss > fresh_miss * 1.2, "and misses his spot by more (%.2f vs %.2f m)" % [tired_miss / 200.0, fresh_miss / 200.0])
	var rp := Team.relief_pitcher(55.0, 5)
	_check(rp.position == 1 and rp.repertoire.size() == 3 and rp.velocity > 15.0, "a reliever is a pitcher with a repertoire")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
