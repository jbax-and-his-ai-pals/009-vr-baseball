extends SceneTree
## Feeds synthetic throws with known technique differences through WristModel and
## checks the resulting pitches move the way their names say.
## Run: godot --headless --path . -s res://tests/wrist_test.gd

var _failures := 0
const REL := Vector3(0.0, 2.1, 16.74)
const TARGET := Vector3(0.0, 0.8, 0.0)


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


## Controller rotation built from per-unit-speed ratios, like the recorded throws.
func _omega(snap: float, side: float, gyro: float, speed: float, hand_sign: float = 1.0) -> Vector3:
	var t := Vector3(0.0, 0.0, -1.0)
	var right := Vector3(1.0, 0.0, 0.0)
	return right * (-snap * speed) + Vector3.UP * (side * speed * hand_sign) + t * (gyro * speed * hand_sign)


func _run(label: String, m: WristModel, d_snap: float, d_side: float, d_gyro: float, slot: float, mph_scale: float = 1.0, hand_sign: float = 1.0, seed: float = 0.0) -> Dictionary:
	var speed := 10.3 * mph_scale
	var omega := _omega(m.mean_snap + d_snap * m.sd_snap, m.mean_side + d_side * m.sd_side, m.mean_gyro + d_gyro * m.sd_gyro, speed, hand_sign)
	var s := m.shape(omega, Vector3(0.0, 0.0, -speed), slot, hand_sign)
	var spin: Vector3 = s.spin
	var v := PitchPhysics.solve_aim(REL, speed * 2.4, spin, TARGET)
	var a := PitchPhysics.analyze(REL, v, spin, s.flutter, seed)
	var nm := PitchNamer.name_pitch(a, m.typical_mph(2.4), hand_sign, s.knuckle)
	print("%-26s %-11s %5.1f mph %5.0f rpm  IVB %+6.1f  HB(arm+) %+6.1f  z(snap %+.1f side %+.1f gyro %+.1f slot %+.1f) tilt %+.0f stiff %.2f" % [
		label, nm, a.speed_mph, a.spin_rpm, a.ivb_in, a.hb_in * hand_sign, s.z_snap, s.z_side, s.z_gyro, s.z_slot, s.tilt_deg, s.stiff])
	a["name"] = nm
	return a


func _run_omega(label: String, m: WristModel, omega: Vector3, mph_scale: float) -> Dictionary:
	var speed := 10.3 * mph_scale
	var s := m.shape(omega, Vector3(0.0, 0.0, -speed), m.mean_slot, 1.0)
	var spin: Vector3 = s.spin
	var v := PitchPhysics.solve_aim(REL, speed * 2.4, spin, TARGET)
	var a := PitchPhysics.analyze(REL, v, spin, s.flutter, 0.9)
	var nm := PitchNamer.name_pitch(a, m.typical_mph(2.4), 1.0, s.knuckle)
	print("%-26s %-11s %5.1f mph %5.0f rpm  IVB %+6.1f  HB %+6.1f  stiff %.2f" % [label, nm, a.speed_mph, a.spin_rpm, a.ivb_in, a.hb_in, s.stiff])
	a["name"] = nm
	return a


func _init() -> void:
	var m := WristModel.new()
	# Keep the baseline fixed for the table: no calibration phase, no learning.
	m.learn_rate = 0.0
	m.anchored_rate = 0.0
	m.calibration_throws = 0
	var usual_slot := m.mean_slot
	var base := _run("usual throw", m, 0, 0, 0, usual_slot)
	var hard := _run("same technique, +20% speed", m, 0, 0, 0, usual_slot, 1.2)
	var snap2 := _run("snap +1.5 sd", m, 1.5, 0, 0, usual_slot)
	var snap3 := _run("snap +2.5 sd", m, 2.5, 0, 0, usual_slot)
	var lazy := _run("snap -1 sd (lazy wrist)", m, -1.0, 0, 0, usual_slot)
	var twist := _run("twist +2 sd", m, 0, 2.0, 0, usual_slot)
	var screw := _run("twist -2 sd", m, 0, -2.0, 0, usual_slot)
	var gyro := _run("gyro +2 sd (cutter)", m, 0, 0, 2.0, usual_slot)
	var low := _run("arm slot -1.5 sd lower", m, 0, 0, 0, usual_slot - 1.5 * m.sd_slot)
	var low2 := _run("arm slot -2.5 sd lower", m, 0, 0, 0, usual_slot - 2.5 * m.sd_slot)
	var high := _run("arm slot +1.5 sd higher", m, 0, 0, 0, usual_slot + 1.5 * m.sd_slot)
	var slow := _run("60% speed, usual technique", m, 0, 0, 0, usual_slot, 0.6)
	var stiff := _run_omega("stiff wrist (no rotation)", m, Vector3(-0.8, 0.4, 0.2), 0.95)
	var lefty := _run("left-hander, usual throw", m, 0, 0, 0, usual_slot, 1.0, -1.0)
	var lefty_tw := _run("left-hander, twist +2 sd", m, 0, 2.0, 0, usual_slot, 1.0, -1.0)
	var lefty_lo := _run("left-hander, slot -2.5 sd", m, 0, 0, 0, usual_slot - 2.5 * m.sd_slot, 1.0, -1.0)

	_check(base.name in ["Four-seam", "Fastball", "Two-seam"], "usual throw is a plain fastball (got %s)" % base.name)
	_check(base.ivb_in > 5.0, "usual throw has backspin carry")
	_check(absf(hard.ivb_in - base.ivb_in) < 4.0, "throwing harder with the same technique does not change the pitch shape")
	_check(snap3.ivb_in < base.ivb_in - 20.0 and snap3.name in ["Curveball", "Slurve"], "big snap makes a curveball (got %s)" % snap3.name)
	_check(snap2.ivb_in < base.ivb_in - 8.0, "moderate snap loses carry")
	_check(lazy.ivb_in > base.ivb_in, "lazy wrist adds carry")
	_check(twist.hb_in < base.hb_in - 8.0, "positive twist breaks to the glove side (right-hander)")
	_check(screw.hb_in > base.hb_in + 8.0, "opposite twist breaks to the arm side")
	_check(low2.hb_in > base.hb_in + 8.0 and low2.ivb_in < base.ivb_in - 6.0, "low arm slot runs arm-side and sinks (got %s)" % low2.name)
	_check(low.ivb_in < base.ivb_in and high.ivb_in >= base.ivb_in - 1.0, "lower slot loses carry, higher keeps it")
	_check(low2.name == "Sinker", "very low slot is a sinker (got %s)" % low2.name)
	_check(gyro.hb_in < base.hb_in - 3.0 and gyro.hb_in > -12.0, "gyro roll gives a small glove-side cut (HB %.1f)" % gyro.hb_in)
	_check(twist.ivb_in < base.ivb_in - 8.0, "slider gives up carry (IVB %.1f vs %.1f)" % [twist.ivb_in, base.ivb_in])
	_check(slow.name == "Changeup", "much slower throw is a changeup (got %s)" % slow.name)
	_check(stiff.name == "Knuckleball" and stiff.spin_rpm < 150.0, "stiff wrist is a knuckleball with ~no spin (got %s)" % stiff.name)
	_check(absf(lefty.ivb_in - base.ivb_in) < 1.0 and absf(lefty.hb_in) < 1.0 + absf(base.hb_in), "left-hander's usual throw matches the right-hander's shape")
	_check(lefty_tw.hb_in > 8.0 and twist.hb_in < -8.0, "twist breaks glove-side for both hands (mirrored)")
	_check(lefty_lo.hb_in < -8.0, "left-hander low slot runs arm-side (mirrored)")

	# Knuckleball flutter: different seeds give different paths, bounded and not absurd.
	var xs := []
	var ys := []
	for sd in 24:
		var k := _run_silent(m, float(sd) * 0.7)
		xs.append(k.plate_pos.x)
		ys.append(k.plate_pos.y)
	var spread_x := (xs.max() as float) - (xs.min() as float)
	var spread_y := (ys.max() as float) - (ys.min() as float)
	print("knuckleball plate spread over 24 seeds: x %.2f m, y %.2f m" % [spread_x, spread_y])
	_check(spread_x > 0.2 and spread_x < 1.6 and spread_y > 0.2 and spread_y < 1.6, "knuckleball wobbles by a believable amount")
	var k1 := _run_silent(m, 1.3)
	var k2 := _run_silent(m, 1.3)
	_check((k1.plate_pos as Vector3) == (k2.plate_pos as Vector3), "same seed gives the same flutter path")

	# Push = knuckleball. A slow, dead-straight hand path is a push; the same slow speed with
	# a normal arc is a changeup; a straight path at normal speed is just a fastball.
	var mp := WristModel.new()
	mp.learn_rate = 0.0
	mp.anchored_rate = 0.0
	mp.calibration_throws = 0
	var slow_speed := 10.3 * 0.65
	var calm := _omega(2.2, 0.5, 0.3, slow_speed)
	var push_shape := mp.shape(calm, Vector3(0.0, 0.0, -slow_speed), mp.mean_slot, 1.0, {"straight": 0.99})
	var arc_shape := mp.shape(calm, Vector3(0.0, 0.0, -slow_speed), mp.mean_slot, 1.0, {"straight": 0.85})
	var fast_shape := mp.shape(_omega(2.67, 0.76, 0.39, 10.3), Vector3(0.0, 0.0, -10.3), mp.mean_slot, 1.0, {"straight": 0.99})
	_check(push_shape.knuckle and push_shape.push > 0.9, "a slow straight push is a knuckleball (push %.2f)" % push_shape.push)
	_check(not arc_shape.knuckle, "a slow throw with a normal arc is not a knuckleball (push %.2f)" % arc_shape.push)
	_check(not fast_shape.knuckle, "a straight path at normal speed is not a knuckleball (push %.2f)" % fast_shape.push)

	# Calibration: someone whose wrist moves very differently from the prior (mean 0.8,
	# sd 2.2 snap per m/s) should end up with z-scores of ordinary size, not pinned at +-3.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var m2 := WristModel.new()
	var zs := []
	for i in 80:
		var snap := rng.randfn(0.8, 2.2)
		var side := rng.randfn(0.85, 0.9)
		var s2 := m2.shape(_omega(snap, side, 0.05, 10.0), Vector3(0.0, 0.0, -10.0), rng.randfn(-0.28, 0.3), 1.0)
		if i >= 40:
			zs.append(s2.z_snap)
	var zsd := 0.0
	for z in zs:
		zsd += z * z
	zsd = sqrt(zsd / zs.size())
	_check(absf(m2.mean_snap - 0.8) < 0.6 and m2.sd_snap > 1.2, "baseline recalibrates to a very different thrower (mean %.2f sd %.2f)" % [m2.mean_snap, m2.sd_snap])
	_check(zsd > 0.6 and zsd < 1.6, "calibrated z-scores are ordinary size (rms %.2f)" % zsd)

	# After calibration, a run of deliberate curveballs must not redefine normal.
	var m3 := WristModel.new()
	for i in 30:
		m3.shape(_omega(2.67 + rng.randfn(0.0, 0.3), 0.76, 0.39, 10.3), Vector3(0.0, 0.0, -10.3), -0.3, 1.0)
	var settled := m3.mean_snap
	for i in 25:
		m3.shape(_omega(2.67 + 3.0 * 0.46, 0.76, 0.39, 10.3), Vector3(0.0, 0.0, -10.3), -0.3, 1.0)
	_check(absf(m3.mean_snap - settled) < 0.08, "deliberate curveballs after calibration do not move the baseline (%.2f -> %.2f)" % [settled, m3.mean_snap])

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _run_silent(m: WristModel, seed: float) -> Dictionary:
	var speed := 9.5
	var omega := _omega(0.05, 0.05, 0.05, speed)
	var s := m.shape(omega, Vector3(0.0, 0.0, -speed), m.mean_slot, 1.0)
	var v := PitchPhysics.solve_aim(REL, speed * 2.4, s.spin, TARGET)
	return PitchPhysics.analyze(REL, v, s.spin, s.flutter, seed)
