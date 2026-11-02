extends SceneTree
## Command and velocity (docs/GAMEPLAY_NEXT.md A3): a throw's aim is measured against a scatter between your
## own and the reference one, so at Pro a steadier player lands closer and a sloppier one further; wild misses
## are squeezed; the funnel aims at the catcher's glove; overthrowing is judged against your usual speed; the
## velocity band follows your effort and the VEL rating; the radar reads in league miles per hour; most
## pitches at a batter are dodged.
## Run: godot --headless --path . -s res://tests/command_test.gd

class Knobs:
	var velocity_gain := 2.4
	var max_mph := 100.0
	var spin_gain := 6.0
	var aim_assist := 1.0
	var funnel_spread_x := 0.30
	var funnel_spread_y := 0.24
	var aim_learn_rate := 0.08
	var technique_gain := 1.0
	var fastball_backspin_rpm := 1700.0
	var velocity_latency := 0.015
	var spin_latency := 0.04
	var spin_mode := 1
	var aim_mode := 2
	var throwing_hand := &"right_hand"
	var aim_reference := 0.5
	var velocity_mode := 1

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	# --- What a throw's aim is measured against.
	var usual := Vector2.ZERO
	var steady := Vector2(3.0, 3.0)
	var sloppy := Vector2(9.0, 9.0)
	var own_steady := HumanPitcher.miss_z(steady, usual, steady, 0.0)
	var own_sloppy := HumanPitcher.miss_z(sloppy, usual, sloppy, 0.0)
	_check(own_steady.is_equal_approx(own_sloppy) and is_equal_approx(own_steady.x, 1.0), "against your own scatter, a one-sd throw is one sd for everyone (today's Casual)")
	var pro_steady := HumanPitcher.miss_z(steady, usual, steady, 1.0)
	var pro_sloppy := HumanPitcher.miss_z(sloppy, usual, sloppy, 1.0)
	_check(pro_steady.x < 0.6 and pro_sloppy.x > 1.4, "against the reference, the steady player's usual miss is half a sd and the sloppy one's more (%.2f vs %.2f)" % [pro_steady.x, pro_sloppy.x])
	var std_steady := HumanPitcher.miss_z(steady, usual, steady, 0.5)
	_check(std_steady.x > pro_steady.x and std_steady.x < own_steady.x, "Standard is between the two")

	# --- Wild misses are squeezed, not clamped hard.
	_check(is_equal_approx(HumanPitcher.squeeze_miss(1.0), 1.0) and is_equal_approx(HumanPitcher.squeeze_miss(-1.5), -1.5), "a miss within 1.5 sd is untouched")
	_check(is_equal_approx(HumanPitcher.squeeze_miss(3.5), 2.3) and is_equal_approx(HumanPitcher.squeeze_miss(-3.5), -2.3), "beyond 1.5 sd it grows at 0.4 the rate")
	var wild := HumanPitcher.miss_z(Vector2(90.0, -90.0), usual, Vector2(6.0, 5.5), 1.0)
	_check(is_equal_approx(wild.x, 2.5) and is_equal_approx(wild.y, -2.5), "even a throw at the dugout is at most 2.5 sd")

	# --- The funnel aims at the catcher's glove.
	var h := HumanPitcher.new()
	h.knobs = Knobs.new()
	var t0 := 50.0
	for i in 27:
		var k := i / 90.0
		h.detector.add_sample(t0 + k, Vector3(0.0, 2.0, 18.0 - 12.0 * k), Quaternion.IDENTITY, 0.9)
	h.aim_mu = Vector2.ZERO                        # this throw is exactly your usual one
	h.aim_n = 50
	var glove := Vector2(0.22, 0.55)
	var f := h.funnel_target(t0 + 26.0 / 90.0, 0.0, 1.0, glove)
	_check(not f.fallback and (f.target as Vector3).distance_to(Vector3(glove.x, glove.y, 0.0)) < 0.01, "your usual throw goes to the glove (%s)" % str(f.target))
	h.aim_mu = Vector2(-3.0, 0.0)                  # this one is 3 degrees right of usual
	var sigma := h.aim_sigma
	var f2 := h.funnel_target(t0 + 26.0 / 90.0, 0.0, 1.0, glove)
	h.aim_mu = Vector2(-3.0, 0.0)                  # (each throw teaches the usual aim: put it back)
	h.aim_sigma = sigma
	var f3 := h.funnel_target(t0 + 26.0 / 90.0, 0.0, 1.0, glove, 1.25)
	_check((f2.target as Vector3).x > glove.x + 0.05, "a throw right of usual misses right of the glove")
	_check((f3.target as Vector3).x - glove.x > ((f2.target as Vector3).x - glove.x) * 1.2, "overthrowing widens the same miss")
	_check(f2.has("center") and f2.has("reference"), "the funnel says what it aimed at and how it measured")

	# --- Overthrowing.
	_check(HumanPitcher.overthrow(12.0, 12.0, 2.5) == 0.0 and HumanPitcher.overthrow(14.5, 12.0, 2.5) == 0.0, "up to your usual + 1 sd is not overthrowing")
	_check(is_equal_approx(HumanPitcher.overthrow(15.75, 12.0, 2.5), 0.5) and HumanPitcher.overthrow(30.0, 12.0, 2.5) == 1.0, "beyond it grows to 1 at + 2 sd")

	# --- The velocity band.
	var b := HumanPitcher.new()
	b.knobs = Knobs.new()
	b.wrist.mean_speed = 12.0
	b.wrist.sd_speed = 2.0
	_check(is_equal_approx(b.band_mph(12.0), 87.0), "your usual throw is the middle of an average arm's band (87)")
	_check(is_equal_approx(b.band_mph(6.0), 43.5), "a half-speed lob is half the speed")
	_check(absf(b.band_mph(b.top_speed()) - 92.0) < 0.01 and b.band_mph(30.0) <= 95.0 + 0.001, "your top speed is the top of the band (92), and nothing goes past 95")
	var last := 0.0
	var rising := true
	for s in range(4, 25):
		var v := b.band_mph(float(s))
		rising = rising and v >= last
		last = v
	_check(rising, "harder is never slower")
	for s in [12.0, 12.5, 13.0, 13.0, 13.5, 13.5, 14.0, 14.0, 14.5, 18.0]:
		b._remember_speed(s)
	_check(absf(b.top_speed() - 14.5) < 0.01, "after a few throws your top speed is your own 90th percentile (%.2f)" % b.top_speed())
	b.velocity_rating = 62.0
	_check(b.band_mph(12.0) > 89.0, "a higher VEL rating raises the band")
	_check(absf(b.typical_mph() - (78.0 + 0.18 * 62.0) * AIPitcher.GAME_SPEED) < 0.01, "the pitch namer's usual speed is the band's middle, in game miles per hour")
	var p := b.throw(0.0, 0.015, 0.04, Vector3.ZERO, 1.7, 0.0, 1.0, false)
	_check(p.kind == "invalid", "no samples: nothing readable")

	# --- The radar.
	_check(absf(PitchPhysics.radar_mph(68.0) - 91.9) < 0.1, "the radar shows a game 68 as a league 92")

	# --- Most pitches at a batter are dodged.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var hits := 0
	for i in 2000:
		if PitchLocation.hit_by(0.9, 0.9, false, rng.randf()):
			hits += 1
	_check(hits > 560 and hits < 840, "a pitch at his ribs hits him about a third of the time (%d of 2000)" % hits)
	_check(not PitchLocation.hit_by(0.0, 0.9, false, 0.0), "one over the plate never does")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
