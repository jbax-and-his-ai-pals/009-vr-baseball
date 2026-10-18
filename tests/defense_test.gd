extends SceneTree
## Fielders should make routine plays, miss ones that are not, and the league-wide share of balls
## in play that fall for hits should look like baseball.
## Run: godot --headless --path . -s res://tests/defense_test.gd

const REL := Vector3(0.0, 2.1, 16.74)
var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _ball(ev_mph: float, launch_deg: float, spray_deg: float, backspin_rpm: float = 1800.0) -> Dictionary:
	var v := ev_mph / PitchPhysics.MPS_TO_MPH
	var la := deg_to_rad(launch_deg)
	var psi := deg_to_rad(spray_deg)
	var vel := Vector3(sin(psi) * cos(la) * v, sin(la) * v, cos(psi) * cos(la) * v)
	var back_axis := Vector3(sin(psi), 0.0, cos(psi)).cross(Vector3.UP).normalized()
	return BattedBall.simulate(Vector3(0.0, 0.9, 0.4), vel, back_axis * (backspin_rpm * PitchPhysics.RPM_TO_RADS))


## Fraction of N trials with each result for a given batted ball.
func _tally(sim: Dictionary, n: int, skill: float = 0.6) -> Dictionary:
	var counts := {}
	for i in n:
		var d := Defense.new(skill)
		d.rng.seed = 1000 + i
		var play := d.resolve(sim, 0.95 + 0.1 * float(i % 5) / 4.0)
		counts[play.result] = counts.get(play.result, 0) + 1
	for k in counts:
		counts[k] = float(counts[k]) / n
	return counts


func _pitch(rng: RandomNumberGenerator, kind: String, target: Vector3) -> Dictionary:
	var def: Dictionary = PitchPhysics.CANNED[kind]
	var spin: Vector3 = (def.rpm as Vector3) * PitchPhysics.RPM_TO_RADS
	var mph: float = float(def.mph) - 18.0 + rng.randf_range(-3.0, 3.0)
	var v := PitchPhysics.solve_aim(REL, mph / PitchPhysics.MPS_TO_MPH, spin, target)
	return {"release": REL, "vel": v, "spin": spin, "flutter_amp": 0.0, "flutter_seed": 0.0,
		"analysis": PitchPhysics.analyze(REL, v, spin)}


func _init() -> void:
	# --- Routine plays.
	var popup := _tally(_ball(55.0, 70.0, 5.0, 3500.0), 200)
	print("pop-up behind the mound: ", popup)
	_check(popup.get("out", 0.0) > 0.93, "a pop-up is almost always caught")

	var grounder_ss := _tally(_ball(78.0, -4.0, 15.0, -800.0), 300)
	print("routine grounder to SS: ", grounder_ss)
	_check(grounder_ss.get("out", 0.0) > 0.80, "a routine grounder at the shortstop is usually an out")

	var grounder_through := _tally(_ball(95.0, 3.0, 28.0, -600.0), 300)   # 5-6 hole, hard
	print("hard grounder down the line side: ", grounder_through)
	_check(grounder_through.get("out", 0.0) < 0.75, "a hard grounder in the hole is less often an out than a routine one")

	# --- Who gets a ball two fielders could both reach: the closer one.
	var by := {}
	var caught := 0
	for sp in [-8.0, -5.0, -2.0, 0.0, 2.0, 5.0, 8.0]:
		for ev in [82.0, 88.0, 94.0]:
			var d := Defense.new(0.6)
			d.rng.seed = 7
			var pl := d.resolve(_ball(ev, 32.0, sp), 1.0)
			if pl.get("caught_in_air", false):
				caught += 1
				by[pl.fielder] = by.get(pl.fielder, 0) + 1
	print("fly balls up the middle caught by: ", by)
	_check(caught > 0 and by.get(8, 0) >= int(0.6 * caught), "the center fielder takes the fly balls hit near him (%d of %d)" % [by.get(8, 0), caught])
	var lf_rf: int = int(by.get(7, 0)) + int(by.get(9, 0))
	_check(lf_rf <= int(0.4 * caught), "...rather than the corner fielders running across (%d)" % lf_rf)

	var fly_cf := _tally(_ball(92.0, 35.0, 0.0), 200)
	print("deep fly to center (~100 m): ", fly_cf)
	_check(fly_cf.get("out", 0.0) > 0.80, "a deep fly straight at the center fielder is usually caught")

	var gap := _tally(_ball(103.0, 17.0, -14.0), 300)
	print("liner to the right-center gap: ", gap)
	_check(gap.get("out", 0.0) < 0.5, "a hard liner in the gap usually falls in")
	_check(gap.get("double", 0.0) + gap.get("triple", 0.0) + gap.get("single", 0.0) > 0.5, "...and becomes an extra-base or single hit")

	var hr := _ball(104.0, 29.0, 4.0, 2300.0)
	var hr_play := Defense.new().resolve(hr)
	print("100+ mph at 29 deg to center: %s (%.0f m)" % [hr_play.result, hr.distance])
	_check(hr.home_run == (hr_play.result == "home_run"), "a ball over the fence is a home run, nothing else")

	var foul_pop := _tally(_ball(50.0, 72.0, 175.0, 3500.0), 200)
	print("pop foul behind the plate: ", foul_pop)
	_check(foul_pop.get("out", 0.0) > 0.7, "a high foul pop behind the plate is usually caught")

	var foul_line := Defense.new().resolve(_ball(85.0, 12.0, 70.0))
	_check(foul_line.result == "foul" or foul_line.result == "out", "a ball far down the foul line is foul (or a foul out)")

	# --- Better defense makes more plays.
	var bad := _tally(_ball(98.0, 8.0, 20.0, 1200.0), 400, 0.0)
	var good := _tally(_ball(98.0, 8.0, 20.0, 1200.0), 400, 1.0)
	print("same hard liner: poor defense %s | great defense %s" % [bad, good])
	_check(good.get("out", 0.0) >= bad.get("out", 0.0), "better defense turns at least as many into outs")

	# --- League sanity: balls in play from real batter profiles.
	for name in ["Contact Hitter", "Slugger", "MVP"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 321
		var ai := BatterAI.new(BatterProfile.by_name(name))
		ai.rng.seed = 654
		var d := Defense.new(0.6)
		d.rng.seed = 987
		var kinds := ["Fastball", "Curveball", "Slider", "Changeup", "Fastball"]
		var bip := 0
		var hits := 0
		var outs := 0
		var hr_n := 0
		var errs := 0
		for i in 2500:
			var tgt := Vector3(rng.randf_range(-0.28, 0.28), rng.randf_range(0.45, 1.25), 0.0)
			var p := _pitch(rng, kinds[i % kinds.size()], tgt)
			if not p.analysis.reached:
				continue
			var r := ai.evaluate(p)
			if r.kind != "hit":
				continue
			var sim := BattedBall.simulate(r.contact_pos, r.vel, r.spin)
			if not sim.fair:
				continue
			var play := d.resolve(sim)
			if play.result == "home_run":
				hr_n += 1
				continue
			bip += 1
			if play.result in ["single", "double", "triple", "inside_park_hr"]:
				hits += 1
			elif play.result == "error":
				errs += 1
			elif play.result == "out":
				outs += 1
		var babip := float(hits) / maxf(bip, 1)
		print("%-15s balls in play %4d | hits %4d (%.3f BABIP) | outs %4d | errors %2d | HR %3d" % [name, bip, hits, babip, outs, errs, hr_n])
		_check(babip > 0.18 and babip < 0.46, "%s: share of balls in play that fall for hits is baseball-like (%.3f)" % [name, babip])
		_check(errs < bip * 0.08, "%s: errors are rare (%d of %d)" % [name, errs, bip])

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
