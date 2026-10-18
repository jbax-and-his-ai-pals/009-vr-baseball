extends SceneTree
const REL := Vector3(0.0, 2.1, 16.74)

func _run(label: String, aim: Vector3, sigma: float, profile: String, n: int, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var ai := BatterAI.new(BatterProfile.by_name(profile))
	ai.rng.seed = seed_v + 1
	var def: Dictionary = PitchPhysics.CANNED["Fastball"]
	var spin: Vector3 = (def.rpm as Vector3) * PitchPhysics.RPM_TO_RADS
	var mph := 68.0
	var strikes := 0
	var swings := 0
	var contact := 0
	var inplay := 0
	var ev_sum := 0.0
	var hard := 0
	var whiff := 0
	var foul_tip := 0
	for i in n:
		var tgt := Vector3(aim.x + rng.randfn(0.0, sigma), clampf(aim.y + rng.randfn(0.0, sigma * 0.85), 0.05, 2.3), 0.0)
		var v := PitchPhysics.solve_aim(REL, mph / PitchPhysics.MPS_TO_MPH, spin, tgt)
		var a := PitchPhysics.analyze(REL, v, spin)
		var r := ai.evaluate({"release": REL, "vel": v, "spin": spin, "flutter_amp": 0.0, "flutter_seed": 0.0, "analysis": a})
		if a.reached and a.strike:
			strikes += 1
		if r.swing:
			swings += 1
			if r.contact:
				contact += 1
				if r.kind == "hit":
					inplay += 1
					ev_sum += r.ev
					if r.ev >= 95.0:
						hard += 1
				else:
					foul_tip += 1
			else:
				whiff += 1
	var tip := ""
	print("%-34s %-14s  strike %3.0f%% | swing %3.0f%% | contact/swing %3.0f%% | whiff/swing %3.0f%% | in play/pitch %3.0f%% | EV %3.0f | hard %2.0f%%" % [
		label, profile, 100.0 * strikes / n, 100.0 * swings / n, 100.0 * contact / maxf(swings, 1), 100.0 * whiff / maxf(swings, 1),
		100.0 * inplay / n, ev_sum / maxf(inplay, 1), 100.0 * hard / maxf(inplay, 1)])

func _init() -> void:
	var n := 2500
	for prof in ["Rookie", "Contact Hitter", "All-Star"]:
		print("---- ", prof, ": same fastball, aimed at different spots, perfect control")
		for spot in [["heart (0, .85)", Vector3(0.0, 0.85, 0.0)], ["corner in zone (.3, .5)", Vector3(0.3, 0.5, 0.0)],
				["just off the plate (.5, .85)", Vector3(0.5, 0.85, 0.0)], ["well off (.8, .85)", Vector3(0.8, 0.85, 0.0)],
				["high (0, 1.5)", Vector3(0.0, 1.5, 0.0)], ["low (0, .2)", Vector3(0.0, 0.2, 0.0)]]:
			_run(spot[0], spot[1], 0.0, prof, n, 11)
		print("---- ", prof, ": aiming at the heart, increasing wildness (location scatter)")
		for s in [0.05, 0.15, 0.30, 0.45]:
			_run("scatter %.2f m" % s, Vector3(0.0, 0.85, 0.0), s, prof, n, 21)
	quit()
