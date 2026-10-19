class_name HalfInningSim
extends RefCounted
## Plays one half inning with no one watching: a pitcher against a lineup, with the real batter
## AI, batted-ball physics, defense and baserunning. It is how the half you do not pitch (the
## other team's turn at bat) gets a score, so the whole game is a real two-sided game.
##
##   var r := HalfInningSim.play(lineup, start_index, pitcher, fielding_team, seed)
##   r.runs, r.hits, r.next_index, r.pitches

const RELEASE := Vector3(0.0, 2.1, 16.74)


static func play(lineup: Array[Player], start_index: int, pitcher: Player, fielding: Team, seed_value: int) -> Dictionary:
	var out := {"runs": 0, "hits": 0, "next_index": start_index, "pitches": 0, "errors": 0}
	if lineup.is_empty():
		return out
	# One inning of a normal game, starting where this lineup left off.
	var game := GameState.new(lineup, 1)
	game.order_index = posmod(start_index, lineup.size())
	game.rng.seed = seed_value
	var ai_pitcher := AIPitcher.new(pitcher)
	ai_pitcher.rng.seed = seed_value + 1
	var defense := Defense.from_team(fielding)
	defense.rng.seed = seed_value + 2
	var batter_ai := BatterAI.new()
	batter_ai.rng.seed = seed_value + 3
	var run_rng := RandomNumberGenerator.new()
	run_rng.seed = seed_value + 4
	var guard := 0
	while not game.over and guard < 400:
		guard += 1
		var p := ai_pitcher.next_pitch(RELEASE)
		var batter := game.current_batter()
		batter_ai.profile = BatterProfile.from_player(batter)
		batter_ai.bats_left = not batter.bats_right
		batter_ai.platoon = BatterAI.platoon_for(batter.bats_right, pitcher.throws_right)
		var a: Dictionary = p.analysis
		if not a.get("reached", false):
			game.pitch("ball")
			continue
		p["situation"] = {"bases": [game.bases[0] != null, game.bases[1] != null, game.bases[2] != null],
			"outs": game.outs, "strikes": game.strikes, "balls": game.balls}
		var r := batter_ai.evaluate(p)
		match String(r.kind):
			"take":
				game.pitch("called_strike" if a.strike else "ball")
			"whiff":
				game.pitch("swinging_strike")
			"foul tip":
				game.pitch("foul_tip")
			_:
				var sim := BattedBall.simulate(r.contact_pos, r.vel, r.spin)
				var play := defense.resolve(sim, batter.run_factor() * run_rng.randf_range(0.97, 1.03))
				if r.get("bunt", false):
					play["bunt"] = true
				if not sim.fair and not sim.home_run and play.result != "out":
					game.pitch("foul")
				else:
					var plan := Baserunning.plan(play, game.bases, game.outs, batter, run_rng)
					game.in_play(play, plan)
	out.runs = game.runs
	out.hits = game.hits
	out.errors = game.errors
	out.pitches = game.pitch_count
	out.next_index = game.order_index
	return out
