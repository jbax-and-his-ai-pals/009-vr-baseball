extends SceneTree
## Headless sanity checks for the flight model and the throw detector.
## Run: godot --headless --path . -s res://tests/physics_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	var rel := Vector3(0.0, PitchPhysics.MOUND_H + 1.85, PitchPhysics.MOUND_Z - 1.7)
	var target := Vector3(0.0, 0.8, 0.0)
	var results := {}
	for key in PitchPhysics.CANNED:
		var def: Dictionary = PitchPhysics.CANNED[key]
		var spin: Vector3 = (def.rpm as Vector3) * PitchPhysics.RPM_TO_RADS
		var v := PitchPhysics.solve_aim(rel, float(def.mph) / PitchPhysics.MPS_TO_MPH, spin, target)
		var a := PitchPhysics.analyze(rel, v, spin)
		results[key] = a
		print("%-10s %.1f mph  %.3fs  IVB %+6.1f in  HB %+6.1f in  plate (%+.3f, %.3f)" % [
			key, a.speed_mph, a.time, a.ivb_in, a.hb_in, a.plate_pos.x, a.plate_pos.y])
		_check((a.plate_pos as Vector3).distance_to(target) < 0.01, "%s aim solver lands on target" % key)

	var fb: Dictionary = results["Fastball"]
	var cb: Dictionary = results["Curveball"]
	var sl: Dictionary = results["Slider"]
	_check(fb.time > 0.38 and fb.time < 0.50, "92 mph fastball plate time is about 0.4-0.5s")
	_check(fb.ivb_in > 5.0 and fb.ivb_in < 22.0, "fastball backspin gives a modest rise vs gravity-only")
	_check(cb.ivb_in < -3.0, "topspin curveball drops more than gravity-only")
	_check(absf(sl.hb_in) > 3.0, "sidespin slider has horizontal break")

	# Backspin lifts, topspin sinks, mirror-image sidespin breaks opposite ways.
	var up := PitchPhysics.acceleration(Vector3(0, 0, -40), Vector3(250, 0, 0))
	var down := PitchPhysics.acceleration(Vector3(0, 0, -40), Vector3(-250, 0, 0))
	_check(up.y > down.y, "backspin lift exceeds topspin lift")
	var left := PitchPhysics.acceleration(Vector3(0, 0, -40), Vector3(0, 250, 0))
	var right := PitchPhysics.acceleration(Vector3(0, 0, -40), Vector3(0, -250, 0))
	_check(left.x < 0.0 and right.x > 0.0, "sidespin sign maps to break direction")

	# Detector: synthetic hand moving at 10 m/s toward -Z, rotating 20 rad/s about +X.
	var det := ThrowDetector.new()
	var q := Quaternion.IDENTITY
	for i in 30:
		var t := i / 90.0
		det.add_sample(t, Vector3(0, 1.5, -10.0 * t), q)
		q = (Quaternion(Vector3(1, 0, 0), 20.0 / 90.0) * q).normalized()
	var est := det.estimate(29.0 / 90.0, 0.0)
	_check(est.valid and (est.velocity as Vector3).distance_to(Vector3(0, 0, -10)) < 0.2, "detector recovers linear velocity")
	_check(est.valid and (est.spin as Vector3).distance_to(Vector3(20, 0, 0)) < 0.5, "detector recovers angular velocity")

	# Auto-release: speed ramps up then drops; peak should be found after the drop.
	var det2 := ThrowDetector.new()
	var x := 0.0
	var speeds := [2, 4, 7, 11, 15, 18, 20, 19, 14, 9, 5, 3]
	for i in speeds.size():
		x += float(speeds[i]) / 90.0
		det2.add_sample(i / 90.0, Vector3(0, 1.5, -x), Quaternion.IDENTITY)
	var tp := det2.find_release_peak(6.0, 0.85, Vector3(0, 0, -1))
	_check(tp > 0.0 and tp < 9.0 / 90.0, "auto-release finds the speed peak (t=%.3f)" % tp)

	# Gravity assist: a flat-pointed 40 mph throw at the zone center. Unassisted it
	# dies short; assisted it reaches the pointed spot, and spin still adds break.
	var hand := Vector3(0.0, 2.1, PitchPhysics.MOUND_Z - 1.0)
	var pointed := Vector3(0.1, 0.8, 0.0)
	var flat_vel := (pointed - hand).normalized() * (40.0 / PitchPhysics.MPS_TO_MPH)
	_check(not PitchPhysics.fly_to_plate(hand, flat_vel, Vector3.ZERO).reached, "unassisted 40 mph flat throw never reaches the plate")
	var assisted := PitchPhysics.assist_velocity(hand, flat_vel, Vector3.ZERO, 1.0)
	var ra := PitchPhysics.fly_to_plate(hand, assisted, Vector3.ZERO)
	_check(ra.reached and (ra.pos as Vector3).distance_to(pointed) < 0.03, "assisted flat throw lands where pointed")
	_check(absf(assisted.length() - flat_vel.length()) < 0.01, "assist preserves throw speed")
	var cspin := Vector3(-1900.0, 0.0, 0.0) * PitchPhysics.RPM_TO_RADS
	var assisted_c := PitchPhysics.assist_velocity(hand, flat_vel, cspin, 1.0)
	var rc := PitchPhysics.fly_to_plate(hand, assisted_c, cspin)
	_check(rc.reached and (rc.pos as Vector3).y < pointed.y - 0.1, "assisted topspin pitch still breaks down off the pointed line")
	var lob := PitchPhysics.assist_velocity(hand, Vector3(0, 12, -3), Vector3.ZERO, 1.0)
	_check(lob == Vector3(0, 12, -3), "assist leaves a mostly-vertical lob alone")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
