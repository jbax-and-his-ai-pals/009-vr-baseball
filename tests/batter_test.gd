extends SceneTree
## Batter profiles should differ in the ways their ratings say, and batted balls should
## fly like baseballs.
## Run: godot --headless --path . -s res://tests/batter_test.gd

var _failures := 0
const REL := Vector3(0.0, 2.1, 16.74)


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _pitch(rng: RandomNumberGenerator, kind: String, target: Vector3) -> Dictionary:
	var def: Dictionary = PitchPhysics.CANNED[kind]
	var spin: Vector3 = (def.rpm as Vector3) * PitchPhysics.RPM_TO_RADS
	var mph: float = float(def.mph) - 18.0 + rng.randf_range(-3.0, 3.0)  # this game's slower pitches
	if kind == "Changeup":
		mph -= 14.0  # a real change of speed, like the slow throws in recorded sessions
	var v := PitchPhysics.solve_aim(REL, mph / PitchPhysics.MPS_TO_MPH, spin, target)
	return {"release": REL, "vel": v, "spin": spin, "flutter_amp": 0.0, "flutter_seed": 0.0,
		"analysis": PitchPhysics.analyze(REL, v, spin)}


func _target(rng: RandomNumberGenerator, in_zone: bool) -> Vector3:
	if in_zone:
		return Vector3(rng.randf_range(-0.24, 0.24), rng.randf_range(0.5, 1.2), 0.0)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	if rng.randf() < 0.5:
		return Vector3(side * rng.randf_range(0.50, 0.95), rng.randf_range(0.3, 1.4), 0.0)
	var y := rng.randf_range(1.50, 1.95) if rng.randf() < 0.5 else rng.randf_range(0.0, 0.25)
	return Vector3(rng.randf_range(-0.3, 0.3), y, 0.0)


func _run(profile: BatterProfile, n: int, sequence: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var ai := BatterAI.new(profile)
	ai.rng.seed = 999
	var zone_pitches := 0
	var zone_swings := 0
	var out_pitches := 0
	var chases := 0
	var swings := 0
	var contacts := 0
	var hits := 0
	var ev_sum := 0.0
	var hr := 0
	var hard := 0
	var la_sum := 0.0
	var by_kind := {}
	for i in n:
		var kind: String = sequence[i % sequence.size()]
		var in_zone := rng.randf() < 0.5
		var p := _pitch(rng, kind, _target(rng, in_zone))
		if not p.analysis.reached:
			continue
		var r := ai.evaluate(p)
		var strike: bool = p.analysis.strike
		if strike:
			zone_pitches += 1
			if r.swing:
				zone_swings += 1
		else:
			out_pitches += 1
			if r.swing:
				chases += 1
		if r.swing:
			swings += 1
			if r.contact:
				contacts += 1
			var k: Dictionary = by_kind.get(kind, {"sw": 0, "ct": 0})
			k.sw += 1
			if r.contact:
				k.ct += 1
			by_kind[kind] = k
		if r.kind == "hit":
			hits += 1
			ev_sum += r.ev
			la_sum += r.la
			var bb := BattedBall.simulate(r.contact_pos, r.vel, r.spin)
			if bb.home_run:
				hr += 1
			if r.ev >= 85.0:
				hard += 1
	return {
		"zone_swing": float(zone_swings) / maxf(zone_pitches, 1),
		"chase": float(chases) / maxf(out_pitches, 1),
		"contact": float(contacts) / maxf(swings, 1),
		"hits": hits, "swings": swings,
		"ev": ev_sum / maxf(hits, 1), "la": la_sum / maxf(hits, 1),
		"hr_share": float(hr) / maxf(hits, 1), "hard_share": float(hard) / maxf(hits, 1), "by_kind": by_kind,
	}


func _backspin(rpm: float) -> Vector3:
	return Vector3(-1.0, 0.0, 0.0) * (rpm * PitchPhysics.RPM_TO_RADS)


func _init() -> void:
	var res := {}
	for prof in BatterProfile.all():
		res[prof.name] = _run(prof, 1500, ["Fastball", "Curveball", "Slider", "Changeup", "Fastball"])
		var r: Dictionary = res[prof.name]
		print("%-15s zone-swing %2.0f%%  chase %2.0f%%  contact %2.0f%%  EV %4.1f mph  LA %4.1f  HR/hit %2.0f%%  (swings %d, hits %d)" % [
			prof.name, r.zone_swing * 100.0, r.chase * 100.0, r.contact * 100.0, r.ev, r.la, r.hr_share * 100.0, r.swings, r.hits])

	var ll: Dictionary = res["Little Leaguer"]
	var rk: Dictionary = res["Rookie"]
	var ch: Dictionary = res["Contact Hitter"]
	var sl: Dictionary = res["Slugger"]
	var allstar: Dictionary = res["All-Star"]
	var mvp: Dictionary = res["MVP"]
	_check(mvp.chase < allstar.chase and allstar.chase < rk.chase and rk.chase < ll.chase, "better eye chases fewer pitches out of the zone")
	_check(mvp.contact > allstar.contact and allstar.contact > rk.contact and rk.contact > ll.contact, "better contact skill makes contact on more swings")
	_check(sl.ev > ch.ev + 2.0, "the slugger hits the ball harder than the contact hitter (%.1f vs %.1f mph)" % [sl.ev, ch.ev])
	_check(ch.contact > sl.contact, "the contact hitter makes contact more often than the slugger")
	_check(mvp.zone_swing > 0.5 and ll.zone_swing > 0.5, "everyone swings at a good share of strikes")
	_check(sl.zone_swing > ch.zone_swing, "the aggressive slugger swings at more strikes")
	_check(mvp.hits > 3 * ll.hits, "an MVP puts far more balls in play than a little leaguer (%d vs %d)" % [mvp.hits, ll.hits])
	_check(sl.hard_share > ch.hard_share, "the slugger hits a bigger share of balls hard (%.0f%% vs %.0f%%)" % [sl.hard_share * 100.0, ch.hard_share * 100.0])

	# Changeup deception: batters who do not read speed changes swing early against slow pitches.
	var seq_fb := _run(BatterProfile.by_name("Rookie"), 1200, ["Fastball"])
	var seq_mix := _run(BatterProfile.by_name("Rookie"), 1200, ["Fastball", "Fastball", "Changeup"])
	var c_fb: float = seq_fb.contact
	var ck: Dictionary = seq_mix.by_kind.get("Changeup", {"sw": 1, "ct": 0})
	var c_ch: float = float(ck.ct) / maxf(ck.sw, 1)
	print("rookie contact vs fastballs only: %.0f%% ; vs changeups mixed in: %.0f%%" % [c_fb * 100.0, c_ch * 100.0])
	_check(c_ch < c_fb - 0.05, "a rookie makes less contact on changeups mixed into fastballs")
	var mvp_mix := _run(BatterProfile.by_name("MVP"), 1200, ["Fastball", "Fastball", "Changeup"])
	var mk: Dictionary = mvp_mix.by_kind.get("Changeup", {"sw": 1, "ct": 0})
	var mvp_ch: float = float(mk.ct) / maxf(mk.sw, 1)
	_check(mvp_ch > c_ch, "an MVP handles the changeup much better than a rookie (%.0f%% vs %.0f%%)" % [mvp_ch * 100.0, c_ch * 100.0])

	# Batted-ball physics.
	var v100 := 44.7
	var fly := BattedBall.simulate(Vector3(0, 1.0, 0), Vector3(0.0, v100 * sin(deg_to_rad(28.0)), v100 * cos(deg_to_rad(28.0))), _backspin(2000.0))
	print("100 mph @ 28 deg, 2000 rpm backspin: lands %.0f m, apex %.1f m, hang %.1f s, home run %s" % [fly.distance, fly.apex, fly.hang_time, fly.home_run])
	_check(fly.distance > 85.0 and fly.distance < 135.0, "a 100 mph, 28 degree drive travels about a hundred meters")
	_check(fly.apex > 18.0 and fly.apex < 40.0 and fly.hang_time > 4.0 and fly.hang_time < 7.5, "apex and hang time are baseball-like")
	var popup := BattedBall.simulate(Vector3(0, 1.0, 0), Vector3(0.0, 27.0 * sin(deg_to_rad(70.0)), 27.0 * cos(deg_to_rad(70.0))), _backspin(3500.0))
	_check(popup.distance < 40.0 and popup.apex > 25.0, "a steep, soft pop-up goes high and not far (%.0f m out, %.0f m up)" % [popup.distance, popup.apex])
	var grounder := BattedBall.simulate(Vector3(0, 0.9, 0), Vector3(0.0, -4.0, 36.0), _backspin(-800.0))
	_check(grounder.bounces >= 1 and grounder.rest_pos.z > 15.0, "a grounder bounces and keeps rolling (%d bounces, rests %.0f m out)" % [grounder.bounces, grounder.rest_pos.z])
	var foul := BattedBall.simulate(Vector3(0, 1.0, 0), Vector3(40.0 * sin(deg_to_rad(60.0)), 12.0, 40.0 * cos(deg_to_rad(60.0))), Vector3.ZERO)
	_check(not foul.fair, "a ball hit 60 degrees off line is foul")
	var v107 := 47.8
	var gap := BattedBall.simulate(Vector3(0, 1.0, 0), Vector3(v107 * cos(deg_to_rad(32.0)) * sin(deg_to_rad(30.0)), v107 * sin(deg_to_rad(32.0)), v107 * cos(deg_to_rad(32.0)) * cos(deg_to_rad(30.0))), _backspin(2400.0))
	var center := BattedBall.simulate(Vector3(0, 1.0, 0), Vector3(0.0, v107 * sin(deg_to_rad(32.0)), v107 * cos(deg_to_rad(32.0))), _backspin(2400.0))
	print("107 mph @ 32 deg: to center %.0f m (HR %s, wall %s); to the left-center gap %.0f m (HR %s, wall %s)" % [center.distance, center.home_run, center.wall, gap.distance, gap.home_run, gap.wall])
	_check(gap.home_run or gap.wall or gap.distance > 100.0, "a crushed ball to the gap clears or reaches the fence")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
