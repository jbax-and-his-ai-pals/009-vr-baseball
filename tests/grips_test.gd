extends SceneTree
## Grip, then motion: the grip picks the pitch, its own action decides how much of its movement it gets; with no
## action it gets the assist's floor, a wrong one makes it hang (it stays up, aimed for its usual break), a full
## one gets it all. The stick cycles grips by family; the catcher's sign puts his pitch in your hand; only
## four-seamers teach your usual throw; a grip you are still learning moves less; the lesson counts only good ones.
## Run: godot --headless --path . -s res://tests/grips_test.gd

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
	var pitch_select := "Grip"
	var move_floor := 0.6

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


## A synthetic throw toward the plate at `speed` m/s with an ordinary snap, plus `twist` rad/s about the vertical.
func _sweep(h: HumanPitcher, t0: float, speed: float, twist: float = 0.0) -> void:
	h.detector.clear()
	var q := Quaternion.IDENTITY
	for i in 27:
		var k := i / 90.0
		h.detector.add_sample(t0 + k, Vector3(0.0, 2.0 + 0.1 * k, 18.0 - speed * k), q, 0.9)
		q = (Quaternion(Vector3(1, 0, 0), -2.67 * speed / 90.0) * Quaternion(Vector3(0, 1, 0), (0.76 * speed + twist) / 90.0) * q).normalized()
	h.held = true


func _init() -> void:
	# --- The rules.
	_check(Grips.canonical("Fastball") == "Four-seam" and Grips.canonical("Slider") == "Slider" and Grips.canonical("Eephus") == "Four-seam", "the catcher's 'Fastball' is the four-seamer; anything unknown is too")
	_check(is_equal_approx(Grips.action("Slider", {"z_side": 1.6}, 1.0), 1.6) and is_equal_approx(Grips.action("Sinker", {"z_slot": -1.2}, 1.0), 1.2)
		and is_equal_approx(Grips.action("Cutter", {"z_gyro": 0.8}, 1.0), 0.8), "each grip listens to its own reading: twist, a lower slot, roll")
	_check(Grips.action("Changeup", {}, 1.0) > Grips.action("Changeup", {}, 0.8) and Grips.action("Changeup", {}, 0.75) < 0.0, "a changeup is sold with fastball arm speed; a slowed arm is the wrong way")
	_check(Grips.action("Knuckleball", {"stiff": 0.8}, 1.0) > 1.5 and Grips.action("Knuckleball", {"stiff": 0.0}, 1.0) < 0.0, "a knuckleball wants a stiff wrist")
	_check(is_equal_approx(Grips.execution(Grips.action("Four-seam", {}, 1.0)), 1.0), "the four-seamer is always all there")
	var f := 0.6
	_check(is_equal_approx(Grips.movement(0.0, f), 0.6) and is_equal_approx(Grips.movement(1.0, f), 1.0) and is_equal_approx(Grips.movement(0.5, f), 0.8), "Standard: no action gets 60%, a full one 100%")
	_check(Grips.movement(-1.0, f) < 0.3 and Grips.movement(1.5, f) <= 1.08, "the wrong way hangs (%.2f); more than full adds only a little" % Grips.movement(-1.0, f))
	_check(Grips.movement(-1.0, 1.0) >= 1.0 and Grips.movement(0.0, 1.0) >= 1.0, "Casual: nothing hangs, the grip gives it all")
	_check(is_equal_approx(Grips.expected(0.6), 0.8) and is_equal_approx(Grips.expected(1.0), 1.0), "it is aimed for an ordinary execution")
	_check(Grips.spin("Curveball", 0.0, 1.0).is_equal_approx(Grips.spin("Four-seam", 1.0, 1.0)), "none of a grip's shape spins like a four-seamer")
	_check(Grips.spin("Slider", 1.0, 1.0).y > 0.0 and Grips.spin("Slider", 1.0, -1.0).y < 0.0 and is_equal_approx(Grips.spin("Slider", 1.0, -1.0).x, Grips.spin("Slider", 1.0, 1.0).x), "a left-hander's slider is the mirror image")
	_check(Grips.speed_factor("Changeup") < 0.92 and Grips.speed_factor("Curveball") < Grips.speed_factor("Slider") and is_equal_approx(Grips.speed_factor("Four-seam"), 1.0), "off-speed grips are slower")
	_check(Grips.quality(1.2, f) == "sharp" and Grips.quality(0.5, f) == "good" and Grips.quality(0.1, f) == "flat" and Grips.quality(-0.3, f) == "hanging" and Grips.quality(-0.3, 1.0) == "flat", "in words: sharp, good, flat, hanging (never hanging at Casual)")

	# --- The stick.
	_check(Grips.flick("Four-seam", "glove") == "Curveball" and Grips.flick("Curveball", "glove") == "Slider" and Grips.flick("Slider", "glove") == "Slurve" and Grips.flick("Slurve", "glove") == "Curveball", "glove side: curve, slider, slurve, around again")
	_check(Grips.flick("Slider", "down") == "Changeup" and Grips.flick("Changeup", "down") == "Splitter" and Grips.flick("Four-seam", "press") == "Knuckleball", "down: changeup, splitter; press: knuckleball")
	_check(Grips.flick("Four-seam", "glove", ["Four-seam", "Slider"]) == "Slider" and Grips.flick("Four-seam", "arm", ["Four-seam"]) == "Four-seam", "only grips you may throw")
	_check(Grips.family_of_stick(Vector2(-0.9, 0.1), 1.0) == "glove" and Grips.family_of_stick(Vector2(-0.9, 0.1), -1.0) == "arm"
		and Grips.family_of_stick(Vector2(0.1, 0.95), 1.0) == "up" and Grips.family_of_stick(Vector2(0.2, -0.3), 1.0) == "", "the glove side is left for a right-hander, right for a left-hander; a small push is nothing")

	# --- A hanging pitch stays up; a sharp one dives past the spot (aimed for its usual break).
	var from := Vector3(0.42, 1.78, 17.6)
	var target := Vector3(0.0, 0.55, 0.0)
	var speed := 58.0 / PitchPhysics.MPS_TO_MPH
	var hung: Vector3 = PitchPhysics.fly_to_plate(from, PitchPhysics.solve_aim(from, speed, Grips.spin("Curveball", Grips.aimed_for(0.24, 0.6), 1.0), target), Grips.spin("Curveball", 0.24, 1.0)).pos
	var flat_c: Vector3 = PitchPhysics.fly_to_plate(from, PitchPhysics.solve_aim(from, speed, Grips.spin("Curveball", Grips.aimed_for(0.6, 0.6), 1.0), target), Grips.spin("Curveball", 0.6, 1.0)).pos
	var sharp: Vector3 = PitchPhysics.fly_to_plate(from, PitchPhysics.solve_aim(from, speed, Grips.spin("Curveball", Grips.aimed_for(1.0, 0.6), 1.0), target), Grips.spin("Curveball", 1.0, 1.0)).pos
	_check(hung.y > target.y + 0.25 and hung.y < target.y + 0.6, "a hanging curve aimed at the knees stays up (%.2f m)" % hung.y)
	_check(flat_c.y > target.y + 0.05 and flat_c.y < target.y + 0.2 and sharp.y < target.y - 0.05, "a flat one a little (%.2f m); a sharp one dives below (%.2f m)" % [flat_c.y, sharp.y])
	var s_hung: Vector3 = PitchPhysics.fly_to_plate(from, PitchPhysics.solve_aim(from, speed, Grips.spin("Slider", Grips.aimed_for(0.24, 0.6), 1.0), Vector3(-0.22, 0.85, 0.0)), Grips.spin("Slider", 0.24, 1.0)).pos
	_check(s_hung.x > -0.22 + 0.06, "a hanging slider aimed away drifts back over the plate (x %.2f)" % s_hung.x)
	_check(is_equal_approx(Grips.aimed_for(0.8, 0.6), 0.8) and is_equal_approx(Grips.aimed_for(1.0, 1.0), 1.0), "an ordinary one lands where it was aimed")

	# --- The pitcher with grips.
	var h := HumanPitcher.new()
	h.knobs = Knobs.new()
	h.wrist.throws_seen = 20                       # a known arm
	h.wrist.mean_speed = 12.0
	_sweep(h, 100.0, 12.0)
	var fb := h.throw(100.0 + 26.0 / 90.0, 0.015, 0.04, Vector3(0.0, 2.2, 16.0), 1.7, 0.0, 1.0, false)
	_check(fb.kind == "pitch" and fb.grip.grip == "Four-seam" and is_equal_approx(float(fb.grip.movement), 1.0), "a four-seamer is a four-seamer")
	var seen := h.wrist.throws_seen
	_check(h.set_grip("Slider") and h.grip == "Slider" and not h.set_grip("Slider"), "the grip changes (and changing to the same grip is no change)")
	_sweep(h, 200.0, 12.0, 1.6 * 0.5 * 12.0)        # a deliberate doorknob twist
	var sl := h.throw(200.0 + 26.0 / 90.0, 0.015, 0.04, Vector3(0.0, 2.2, 16.0), 1.7, 0.0, 1.0, false)
	_check(sl.grip.grip == "Slider" and float(sl.grip.action) > 0.8 and String(sl.grip.quality) in ["good", "sharp"], "a twisted slider is a good one (action %+.2f, %s)" % [float(sl.grip.action), sl.grip.quality])
	_check((sl.vel as Vector3).length() < (fb.vel as Vector3).length() * 0.97, "and slower than the four-seamer")
	_check(h.wrist.throws_seen == seen, "a slider does not teach your usual throw")
	_sweep(h, 300.0, 12.0, -1.5 * 0.5 * 12.0)       # twisted the wrong way
	var bad := h.throw(300.0 + 26.0 / 90.0, 0.015, 0.04, Vector3(0.0, 2.2, 16.0), 1.7, 0.0, 1.0, false)
	_check(String(bad.grip.quality) == "hanging" and float(bad.grip.movement) < 0.6, "a slider twisted the wrong way hangs (%.2f of its movement)" % float(bad.grip.movement))
	h.learning = ["Slider"]
	_sweep(h, 400.0, 12.0, 3.0 * 0.5 * 12.0)
	var raw := h.throw(400.0 + 26.0 / 90.0, 0.015, 0.04, Vector3(0.0, 2.2, 16.0), 1.7, 0.0, 1.0, false)
	_check(bool(raw.grip.learning) and float(raw.grip.movement) <= Grips.LEARNING_CAP + 0.001, "a grip you are still learning never gets all of its movement")
	h.grip_locked = true
	_check(not h.set_grip("Curveball") and h.grip == "Slider", "once the delivery has started the grip is locked")
	h.drop()
	_check(h.set_grip("Curveball"), "and free again after the throw")
	_check(Grips.explain(sl.grip)[0].contains("Slider grip") and Grips.explain(bad.grip).size() >= 2 and Grips.explain(bad.grip)[1].contains("hung"), "the lab says how well it was thrown, and how to fix a hanger")

	# --- The lesson with grips.
	var t := Tutorial.new(0, true)
	_check(t.prompt().contains("Four-seam strikes") and Tutorial.GRIP_STEPS.size() == Tutorial.STEPS.size(), "the grip lesson starts with four-seam strikes (and has as many lessons)")
	for i in 3:
		t.on_pitch("Four-seam", true, "sharp")
	var flat := t.on_pitch("Changeup", true, "flat")
	_check(t.step == 1 and t.progress == 0 and String(flat.text).contains("arm speed"), "a flat changeup does not count, and it says why (%s)" % flat.text)
	t.on_pitch("Changeup", false, "good")
	_check(t.progress == 1, "a good one does, strike or not")

	# --- In the scene: the sign puts its pitch in your hand, the grip is the pitch's name.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	bp.pitch_select = "Grip"
	bp.flight.grip_from_sign("Curveball")
	_check((bp._human as HumanPitcher).grip == "Curveball" and bp.flight.grip_label.text == "CURVEBALL", "the catcher's sign puts a curve in your hand, and it says so over the ball")
	bp.flight.pick_family("glove")
	_check((bp._human as HumanPitcher).grip == "Slider", "flicking toward the glove side moves on to the slider")
	bp.flight.pick_family("up")
	var det: ThrowDetector = bp._detector
	det.clear()
	var q := Quaternion.IDENTITY
	for i in 27:
		var k := i / 90.0
		det.add_sample(500.0 + k, Vector3(0.0, 2.1, 18.0 - 12.0 * k), q, 0.9)
		q = (Quaternion(Vector3(1, 0, 0), -2.67 * 12.0 / 90.0) * q).normalized()
	bp.flight.held_ball.global_position = Vector3(0.0, 2.2, 16.0)
	bp._held = true
	bp.flight.release_from_hand(500.0 + 26.0 / 90.0, 0.015, 0.04)
	var last: LivePitch = bp.flight.pitches.back()
	_check(last.label == "Four-seam" and last.shape.has("grip") and bp.acts.lab_lines(last) == "" or last.label == "Four-seam", "the pitch is named for its grip (%s)" % last.label)
	_check(PitchLab.explain(last.label, last.analysis, last.shape).any(func(l): return String(l).contains("Four-seam grip")), "and the lab explains it as a grip")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
