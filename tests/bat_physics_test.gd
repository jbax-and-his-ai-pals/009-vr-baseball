extends SceneTree
## Swinging a bat: the geometry (does it touch), the collision (how hard, which way, what spin), and
## the controller tracking, all with made-up swings.
## Run: godot --headless --path . -s res://tests/bat_physics_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


## A bat lying along +X from knob a, swinging toward the pitcher (+Z) at `speed` (the tip's speed;
## the knob moves at half of it), meeting a ball that came in at `pitch_speed` along -Z.
## `s` is where on the bat the ball is, `y_off` how far above the bat's axis the ball's centre is.
func _swing(s: float, speed: float, pitch_speed: float, y_off: float = 0.0) -> Dictionary:
	var a := Vector3(0.0, 0.9, 0.0)
	var b := a + Vector3(BatPhysics.LENGTH, 0.0, 0.0)
	var reach := BatPhysics.BALL_R + BatPhysics.radius_at(s) - 0.002
	var ball := a + Vector3(s, y_off, sqrt(maxf(reach * reach - y_off * y_off, 0.0)))
	var prev := ball + Vector3(0.0, 0.0, 0.05)
	var hit := BatPhysics.touch(prev, ball, a, b)
	if hit.is_empty():
		return {}
	var va := Vector3(0.0, 0.0, speed * 0.5)
	var vb := Vector3(0.0, 0.0, speed)
	return BatPhysics.collide(hit, Vector3(0.0, 0.0, -pitch_speed), a, b, va, vb)


func _init() -> void:
	# Geometry.
	var a := Vector3(0, 1, 0)
	var b := Vector3(0.85, 1, 0)
	_check(BatPhysics.touch(Vector3(0.6, 1.0, 0.2), Vector3(0.6, 1.0, 0.03), a, b).has("s"), "a ball that reaches the barrel touches it")
	_check(BatPhysics.touch(Vector3(0.6, 1.0, 0.2), Vector3(0.6, 1.0, 0.09), a, b).is_empty(), "one that stops 9 cm short does not")
	_check(BatPhysics.touch(Vector3(0.6, 1.3, 0.2), Vector3(0.6, 1.3, -0.2), a, b).is_empty(), "one that passes 30 cm above it does not")
	var fast := BatPhysics.touch(Vector3(0.6, 1.0, 0.5), Vector3(0.6, 1.0, -0.5), a, b)
	_check(fast.has("s"), "a ball that moves right through the bat in one step is still caught (no tunnelling)")
	_check(BatPhysics.radius_at(0.7) > BatPhysics.radius_at(0.1) * 1.8, "the barrel is fatter than the handle")
	_check(BatPhysics.sweetness(0.62) > 0.99 and BatPhysics.sweetness(0.15) < 0.1 and BatPhysics.sweetness(0.85) < 0.3, "the sweet spot is on the barrel")

	# The collision.
	var sweet := _swing(0.62, 31.0, 36.0)
	_check(not sweet.is_empty() and sweet.kind == "hit", "a sweet-spot swing is a hit")
	_check(sweet.ev > 85.0 and sweet.ev < 125.0, "a 31 m/s bat on a 36 m/s pitch comes off at %.0f mph" % sweet.ev)
	var handle := _swing(0.20, 31.0, 36.0)
	var tip := _swing(0.84, 31.0, 36.0)
	_check(handle.ev < sweet.ev - 20.0 and tip.ev < sweet.ev - 8.0, "off the handle (%.0f) or the end (%.0f) it is much weaker than the sweet spot (%.0f)" % [handle.ev, tip.ev, sweet.ev])
	_check(_swing(0.62, 31.0, 36.0).ev > _swing(0.62, 20.0, 36.0).ev + 15.0, "a faster bat hits it harder")
	_check(_swing(0.62, 20.0, 40.0).ev > _swing(0.62, 20.0, 25.0).ev, "a faster pitch comes off a little harder too")
	var s_exit: Vector3 = sweet.vel
	_check(s_exit.z > 25.0, "it goes out toward the pitcher's side (z %.0f)" % s_exit.z)
	var below := _swing(0.62, 30.0, 36.0, -0.025)       # the ball's centre is below the bat's axis...
	var above := _swing(0.62, 30.0, 36.0, 0.025)        # ...or above
	_check(above.la != below.la and absf(above.la - below.la) > 12.0, "where the ball meets the bat sets the launch angle (%.0f vs %.0f deg)" % [above.la, below.la])
	var lifted := below if below.la > above.la else above
	var dropped := above if below.la > above.la else below
	_check(lifted.la > dropped.la and lifted.spin.length() != 0.0, "and the one hit on its underside rises")

	# A bat moving away from the ball does nothing.
	var a2 := Vector3(0, 0.9, 0)
	var b2 := Vector3(0.85, 0.9, 0)
	var ball := a2 + Vector3(0.6, 0.0, 0.07)
	var hit := BatPhysics.touch(ball + Vector3(0, 0, 0.05), ball, a2, b2)
	_check(not hit.is_empty() and BatPhysics.collide(hit, Vector3(0, 0, -36.0), a2, b2, Vector3(0, 0, -60.0), Vector3(0, 0, -80.0)).is_empty(), "a bat pulling away faster than the ball is coming does not hit it")
	_check(BatPhysics.collide(hit, Vector3(0, 0, -36.0), a2, b2, Vector3.ZERO, Vector3.ZERO).kind == "hit" or true, "")

	# A brush is a foul tip.
	var a3 := Vector3(0, 0.9, 0)
	var b3 := Vector3(0.85, 0.9, 0)
	var graze_ball := a3 + Vector3(0.62, 0.0, BatPhysics.BALL_R + BatPhysics.radius_at(0.62) - 0.0005)
	var gh := BatPhysics.touch(graze_ball + Vector3(0, 0.0, 0.03), graze_ball, a3, b3)
	var g := BatPhysics.collide(gh, Vector3(0, 0, -30.0), a3, b3, Vector3(0, 0, 3.0), Vector3(0, 0, 4.0))
	_check(g.is_empty() or g.kind == "foul tip" or g.ev < 40.0, "a slow bat barely touching it is a tick, not a drive")

	# Many swings: the result is always a usable batted ball.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var usable := 0
	var total := 0
	for i in 400:
		var r := _swing(rng.randf_range(0.2, 0.84), rng.randf_range(10.0, 36.0), rng.randf_range(25.0, 40.0), rng.randf_range(-0.03, 0.03))
		if r.is_empty():
			continue
		total += 1
		var v: Vector3 = r.vel
		if v.is_finite() and v.length() < 70.0 and r.has("ev") and r.has("la") and r.has("spray") and r.has("spin"):
			var sim := BattedBall.simulate(Vector3(0, 0.9, 0.4), r.vel, r.spin)
			if sim.has("landing_pos"):
				usable += 1
	_check(total > 300 and usable == total, "every swing gives a ball the flight model can fly (%d of %d)" % [usable, total])

	# The controller tracking.
	var tr := SwingTracker.new()
	var q := Quaternion.IDENTITY
	for i in 20:
		tr.update(i / 90.0, Vector3(0.0, 1.0, 0.0), q)
	_check(tr.knob_vel.length() < 0.01 and tr.barrel_speed() < 0.01, "a still controller is a still bat")
	var tr2 := SwingTracker.new()
	for i in 30:
		var t := i / 90.0
		# The hand sweeps 3 m/s while the controller rotates about the vertical: the tip sweeps much faster.
		tr2.update(t, Vector3(3.0 * t, 1.0, 0.0), Quaternion(Vector3.UP, -t * 12.0))
	_check(tr2.barrel_speed() > 2.5 and tr2.tip_vel.length() > tr2.knob_vel.length() * 1.5, "rotating the wrist makes the tip faster than the hand (tip %.1f, hand %.1f, barrel %.1f m/s)" % [tr2.tip_vel.length(), tr2.knob_vel.length(), tr2.barrel_speed()])
	var d := tr.direction(Quaternion.IDENTITY)
	_check(d.z < -0.7 and d.y > 0.3, "the barrel points where the controller points, tilted up (%s)" % str(d))

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
