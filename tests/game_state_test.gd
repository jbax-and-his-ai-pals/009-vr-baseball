extends SceneTree
## The scorebook's rules, and a whole simulated game from pitch to final out.
## Run: godot --headless --path . -s res://tests/game_state_test.gd

const REL := Vector3(0.0, 2.1, 16.74)
var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _state(innings: int = 9) -> GameState:
	var g := GameState.new(Team.generate("Away", 50.0, 5).lineup, innings)
	g.rng.seed = 42
	return g


func _init() -> void:
	# --- The count.
	var g := _state()
	g.pitch("ball"); g.pitch("ball"); g.pitch("ball")
	var ev := g.pitch("ball")
	_check(ev.pa_over and ev.result == "walk" and g.walks == 1 and g.balls == 0, "four balls is a walk and the count resets")
	_check(g.bases[0] != null and g.order_index == 1, "a walk puts the batter on first and sends up the next hitter")

	g = _state()
	g.pitch("called_strike"); g.pitch("swinging_strike")
	ev = g.pitch("swinging_strike")
	_check(ev.result == "strikeout" and g.outs == 1 and g.strikeouts == 1, "three strikes is a strikeout and an out")

	g = _state()
	g.pitch("called_strike"); g.pitch("called_strike")
	for i in 5:
		ev = g.pitch("foul")
	_check(g.strikes == 2 and not ev.pa_over and g.outs == 0, "a foul with two strikes is never strike three")
	ev = g.pitch("foul_tip")
	_check(not ev.pa_over and g.strikes == 2 and g.outs == 0, "a foul tip with two strikes is NOT strike three")
	g = _state()
	g.pitch("called_strike")
	ev = g.pitch("foul_tip")
	_check(g.strikes == 2 and not ev.pa_over, "a foul tip with fewer than two strikes is a strike")

	# --- Forces.
	g = _state()
	g.bases = [true, true, true]
	g.balls = 3
	ev = g.pitch("ball")
	_check(ev.runs == 1 and g.runs == 1 and g.bases[0] != null and g.bases[1] != null and g.bases[2] != null, "a bases-loaded walk forces in a run")
	g = _state()
	g.bases = [null, true, null]
	g.balls = 3
	g.pitch("ball")
	_check(g.bases[0] != null and g.bases[1] != null and g.bases[2] == null, "a walk with a runner only on second does not move him")

	# --- Balls in play.
	g = _state()
	g.bases = [true, true, true]
	ev = g.in_play({"result": "home_run"})
	_check(ev.runs == 4 and g.runs == 4 and g.bases == [null, null, null], "a grand slam scores four and clears the bases")
	g = _state()
	g.bases = [null, null, true]
	ev = g.in_play({"result": "single", "bases": 1})
	_check(g.runs == 1 and g.bases[0] != null, "a single scores the runner from third and puts the batter on first")
	g = _state()
	g.bases = [true, null, null]
	g.in_play({"result": "double", "bases": 2})
	_check(g.bases[1] != null and g.bases[2] != null and g.runs == 0, "a double puts the batter on second and moves the runner from first to third")
	g = _state()
	ev = g.in_play({"result": "out", "text": "Groundout 6-3", "caught_in_air": false})
	_check(g.outs == 1 and ev.outs_added == 1 and g.hits == 0, "a groundout with nobody on is one out")

	# --- Three outs end the inning and clear the bases.
	g = _state()
	g.bases = [true, null, null]
	g.outs = 2
	ev = g.in_play({"result": "out", "text": "Flyout to LF", "caught_in_air": true})
	_check(ev.half_over and g.inning == 2 and g.outs == 0 and g.bases == [null, null, null], "the third out ends the inning and clears the bases")

	# --- Double plays and sacrifice flies happen, and never when they should not.
	var dps := 0
	var sac := 0
	var no_dp_two_outs := true
	for i in 400:
		var t := _state()
		t.rng.seed = 100 + i
		t.bases = [true, null, null]
		var e := t.in_play({"result": "out", "text": "Groundout 6-4-3", "caught_in_air": false})
		if e.outs_added == 2:
			dps += 1
		var u := _state()
		u.rng.seed = 900 + i
		u.outs = 2
		u.bases = [true, null, null]
		if u.in_play({"result": "out", "text": "Groundout", "caught_in_air": false}).outs_added == 2:
			no_dp_two_outs = false
		var s := _state()
		s.rng.seed = 1700 + i
		s.bases = [null, null, true]
		s.in_play({"result": "out", "text": "Flyout to CF", "caught_in_air": true, "field_pos": Vector3(0, 0, 95)})
		if s.runs == 1:
			sac += 1
	print("double plays on 400 grounders with a runner on first: %d | sacrifice flies on 400 deep flies: %d" % [dps, sac])
	_check(dps > 120 and dps < 240, "about 45%% of grounders with a runner on first are double plays")
	_check(no_dp_two_outs, "no double play with two outs")
	_check(sac > 250, "a deep fly with a runner on third usually scores him")

	# --- Hit by pitch: first base, forced runners move, no walk is charged.
	g = _state()
	g.bases = [true, true, true]
	var hbp := g.pitch("hit_by_pitch")
	_check(hbp.pa_over and hbp.result == "hit_by_pitch" and hbp.runs == 1 and g.walks == 0 and g.hit_by_pitches == 1
		and g.bases[0] != null and g.bases[1] != null and g.bases[2] != null,
		"a hit batter takes first, forces the runners up, and a bases-loaded one scores a run")
	g = _state()
	g.bases = [null, true, null]
	g.pitch("hit_by_pitch")
	_check(g.bases[0] != null and g.bases[1] != null and g.bases[2] == null, "a hit batter with a man on second does not move him")
	_check(g.outs == 0 and g.balls == 0 and g.strikes == 0, "and the count is reset with no out")

	# --- A wild pitch or passed ball: every runner moves up one, a runner on third scores.
	g = _state()
	g.bases = [true, null, true]
	var wp := g.wild_pitch()
	_check(wp.runs == 1 and g.bases[0] == null and g.bases[1] != null and g.bases[2] == null and g.wild_pitches == 1,
		"a wild pitch moves everyone up and scores the man on third")
	g = _state()
	var none := g.wild_pitch()
	_check(none.get("result", "") == "" and g.wild_pitches == 0, "a wild pitch with the bases empty does nothing")

	# --- Two-sided games: the bottom half is played at the third out, ties go to extra innings.
	var calls := []
	g = _state(3)
	g.allow_extra = true
	g.bottom_sim = func(inning: int) -> Dictionary:
		calls.append(inning)
		return {"runs": 1 if inning == 2 else 0, "hits": 1}
	for inning_i in 3:
		for k in 3:
			g.pitch("called_strike"); g.pitch("called_strike"); g.pitch("called_strike")
	# Home leads 1-0 after two innings, so it does not need to bat in the bottom of the third.
	_check(calls == [1, 2] and g.home_score == 1 and g.over and g.home_inning_runs == [0, 1],
		"each third out plays the bottom half (%s) and a lead after the top of the last inning ends it" % str(calls))
	_check(g.final_text().begins_with("FINAL: Away 0, Home 1"), "the final line says who won (%s)" % g.final_text())

	var ex := _state(2)
	ex.allow_extra = true
	ex.max_extra = 2
	ex.bottom_sim = func(_i: int) -> Dictionary: return {"runs": 0, "hits": 0}
	var safety := 0
	while not ex.over and safety < 100:
		safety += 1
		ex.pitch("called_strike"); ex.pitch("called_strike"); ex.pitch("called_strike")
	_check(ex.over and ex.inning >= 3 and ex.inning <= 4, "a tie goes to extra innings and is called after the cap (inning %d)" % ex.inning)

	# The home team ahead after the top of the last inning does not bat.
	var no_bottom := _state(1)
	no_bottom.allow_extra = true
	no_bottom.home_score = 2
	no_bottom.bottom_sim = func(_i: int) -> Dictionary: return {"runs": 9, "hits": 9}
	no_bottom.pitch("called_strike"); no_bottom.pitch("called_strike"); no_bottom.pitch("called_strike")
	for k in 2:
		no_bottom.pitch("called_strike"); no_bottom.pitch("called_strike"); no_bottom.pitch("called_strike")
	_check(no_bottom.over and no_bottom.home_score == 2, "a home team that leads after the top of the last inning does not bat")

	# A walk-off: the home team takes the lead in the bottom of the last inning.
	var wo := _state(1)
	wo.allow_extra = true
	wo.bottom_sim = func(_i: int) -> Dictionary: return {"runs": 3, "hits": 3}
	for k in 3:
		wo.pitch("called_strike"); wo.pitch("called_strike"); wo.pitch("called_strike")
	_check(wo.over and wo.walk_off and wo.final_text().contains("walk-off"), "winning in the last bottom half is a walk-off")

	# --- An intentional walk: no pitch, a walk, forced runners advance.
	g = _state()
	g.bases = [true, true, null]
	var ibb := g.intentional_walk()
	_check(ibb.pa_over and g.intentional_walks == 1 and g.walks == 1 and g.pitch_count == 0 and g.bases[2] != null,
		"an intentional walk is a walk with no pitches")

	# --- A dropped third strike: the batter can run.
	g = _state()
	g.pitch("called_strike"); g.pitch("called_strike")
	var d3 := g.dropped_third_strike(true)
	_check(d3.result == "strikeout" and d3.batter_reached and g.outs == 0 and g.bases[0] != null and g.strikeouts == 1,
		"a dropped third strike that he beats out is a strikeout with no out and a runner on first")
	g = _state()
	g.pitch("called_strike"); g.pitch("called_strike")
	var d4 := g.dropped_third_strike(false)
	_check(d4.result == "strikeout" and g.outs == 1 and g.bases[0] == null, "thrown out at first it is an ordinary strikeout")
	g = _state()
	g.bases = [true, null, null]
	g.pitch("called_strike"); g.pitch("called_strike")
	var d5 := g.dropped_third_strike(true)
	_check(g.bases[0] != null and g.bases[1] != null, "with a runner on first he forces him to second")

	# --- A whole game: AI pitcher vs the lineup, through the real batter and defense.
	var team := Team.generate("Home", 52.0, 9)
	var lineup := Team.generate("Away", 52.0, 14).lineup
	var game := GameState.new(lineup, 9)
	game.rng.seed = 77
	var pitcher := AIPitcher.new(team.player_at(1))
	pitcher.rng.seed = 78
	var defense := Defense.from_team(team)
	defense.rng.seed = 79
	var batter_ai := BatterAI.new(BatterProfile.from_player(game.current_batter()))
	batter_ai.rng.seed = 80
	var guard := 0
	var pa_pitches := 0
	while not game.over and guard < 4000:
		guard += 1
		var p := pitcher.next_pitch(REL)
		var cur := game.current_batter()
		batter_ai.profile = BatterProfile.from_player(cur)
		var a: Dictionary = p.analysis
		var e: Dictionary
		if not a.reached:
			e = game.pitch("ball")
		else:
			var r := batter_ai.evaluate(p)
			match r.kind:
				"take":
					e = game.pitch("called_strike" if a.strike else "ball")
				"whiff":
					e = game.pitch("swinging_strike")
				"foul tip":
					e = game.pitch("foul_tip")
				_:
					var sim := BattedBall.simulate(r.contact_pos, r.vel, r.spin)
					if not sim.fair and not sim.home_run:
						var play := defense.resolve(sim, cur.run_factor())
						if play.result == "out":
							e = game.in_play(play)
						else:
							e = game.pitch("foul")
					else:
						e = game.in_play(defense.resolve(sim, cur.run_factor()))
	print("simulated game: %d pitches, %d batters faced | %s | line: %s" % [game.pitch_count, game.batters_faced, game.situation_text(), game.line_text()])
	_check(game.over and guard < 4000, "a nine-inning game finishes (%d pitches)" % game.pitch_count)
	_check(game.outs_recorded == 27, "27 outs were recorded (%d)" % game.outs_recorded)
	var k_rate := float(game.strikeouts) / maxf(game.batters_faced, 1)
	var bb_rate := float(game.walks) / maxf(game.batters_faced, 1)
	var per_pa := float(game.pitch_count) / maxf(game.batters_faced, 1)
	print("K%% %.0f | BB%% %.0f | pitches per batter %.1f | runs %d | hits %d | HR %d" % [k_rate * 100.0, bb_rate * 100.0, per_pa, game.runs, game.hits, game.home_runs])
	_check(per_pa > 2.5 and per_pa < 6.5, "pitches per batter is baseball-like (%.1f)" % per_pa)
	_check(game.batters_faced >= 27, "at least 27 batters came up (%d)" % game.batters_faced)

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
