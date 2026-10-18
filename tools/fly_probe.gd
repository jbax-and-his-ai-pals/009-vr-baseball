extends SceneTree
const REL := Vector3(0.0, 2.1, 16.74)
func _init() -> void:
	var team := Team.generate("Home", 55.0, 7)
	var res := {}
	var dist_hist := {}
	var n_fly := 0
	var beyond_of := 0
	var hr := 0
	var wall := 0
	var total_bip := 0
	for g in 20:
		var pitcher := AIPitcher.new(team.player_at(1))
		pitcher.track_fatigue = false
		pitcher.rng.seed = 100 + g
		var defense := Defense.from_team(team)
		defense.rng.seed = 200 + g
		var ai := BatterAI.new()
		ai.rng.seed = 300 + g
		var lineup := Team.generate("Away", 52.0, 14 + g).lineup
		for i in 400:
			var p := pitcher.next_pitch(REL)
			ai.profile = BatterProfile.from_player(lineup[i % 9])
			if not p.analysis.reached:
				continue
			var r := ai.evaluate(p)
			if r.kind != "hit":
				continue
			var sim := BattedBall.simulate(r.contact_pos, r.vel, r.spin)
			total_bip += 1
			var play := defense.resolve(sim, 1.0)
			if sim.apex > 8.0:
				n_fly += 1
				var d: float = sim.distance
				var bucket := int(d / 20.0) * 20
				dist_hist[bucket] = dist_hist.get(bucket, 0) + 1
			if sim.home_run:
				hr += 1
			elif sim.wall:
				wall += 1
			res[play.result] = res.get(play.result, 0) + 1
	print("balls in play: ", total_bip, " fly(apex>8m): ", n_fly, " HR: ", hr, " wall: ", wall)
	print("results: ", res)
	print("fly distance hist (m): ", dist_hist)
	quit()
