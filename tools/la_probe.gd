extends SceneTree
const REL := Vector3(0.0, 2.1, 16.74)
func _init() -> void:
	var team := Team.generate("Home", 55.0, 7)
	var las := []
	var evs := []
	var hist := {}
	var cats := {"gb": 0, "ld": 0, "fb": 0, "pu": 0}
	for g in 30:
		var pitcher := AIPitcher.new(team.player_at(1))
		pitcher.track_fatigue = false
		pitcher.rng.seed = 100 + g
		var ai := BatterAI.new()
		ai.rng.seed = 300 + g
		var lineup := Team.generate("Away", 52.0, 14 + g).lineup
		for i in 300:
			var p := pitcher.next_pitch(REL)
			ai.profile = BatterProfile.from_player(lineup[i % 9])
			if not p.analysis.reached:
				continue
			var r := ai.evaluate(p)
			if r.kind != "hit":
				continue
			var la: float = r.la
			las.append(la)
			evs.append(r.ev)
			var b := int(floor(la / 10.0)) * 10
			hist[b] = hist.get(b, 0) + 1
			if la < 10.0:
				cats.gb += 1
			elif la < 25.0:
				cats.ld += 1
			elif la < 50.0:
				cats.fb += 1
			else:
				cats.pu += 1
	las.sort()
	evs.sort()
	var n := las.size()
	print("n=%d  LA median %.1f  p10 %.1f p90 %.1f | EV median %.1f p10 %.1f p90 %.1f" % [n, las[n / 2], las[n / 10], las[n * 9 / 10], evs[n / 2], evs[n / 10], evs[n * 9 / 10]])
	var keys := hist.keys()
	keys.sort()
	var line := ""
	for k in keys:
		line += "%d:%d(%.0f%%) " % [k, hist[k], 100.0 * hist[k] / n]
	print("LA hist: ", line)
	print("GB %.0f%% LD %.0f%% FB %.0f%% PU %.0f%%" % [100.0 * cats.gb / n, 100.0 * cats.ld / n, 100.0 * cats.fb / n, 100.0 * cats.pu / n])
	quit()
