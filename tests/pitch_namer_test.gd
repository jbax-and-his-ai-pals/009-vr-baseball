extends SceneTree
## Naming a pitch: a low pitch with ordinary backspin still gets a name. (Recorded games had 11% of
## pitches called just "Pitch": the comparison flight without spin lift hit the ground before the plate,
## so the break could not be measured.)
## Run: godot --headless --path . -s res://tests/pitch_namer_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


## A right-hander's pitch from a usual release point to `target`, with `spin` (rad/s, world).
func _analyze(mph: float, spin: Vector3, target: Vector3) -> Dictionary:
	var from := Vector3(0.42, 1.78, 17.6)
	var vel := PitchPhysics.solve_aim(from, mph / PitchPhysics.MPS_TO_MPH, spin, target)
	return PitchPhysics.analyze(from, vel, spin)


func _init() -> void:
	var backspin := Vector3(180.0, 0.0, 0.0)           # ~1700 rpm of plain fastball backspin (axis +X: lift toward +Y)
	for y in [0.15, 0.30, 0.45, 0.85, 1.25]:
		var a := _analyze(62.0, backspin, Vector3(0.0, y, 0.0))
		var name := PitchNamer.name_pitch(a, 62.0, 1.0, false)
		_check(a.reached and a.has("ivb_in") and name != "Pitch", "a fastball at %.2f m high is measured and named (%s, ivb %s)" % [y, name, str(a.get("ivb_in", "-"))])
	var low := _analyze(62.0, backspin, Vector3(0.0, 0.15, 0.0))
	var high := _analyze(62.0, backspin, Vector3(0.0, 1.25, 0.0))
	_check(absf(float(low.get("ivb_in", 0.0)) - float(high.get("ivb_in", 99.0))) < 3.0, "the same spin breaks about the same wherever it is aimed")
	var slow := _analyze(45.0, backspin, Vector3(0.0, 0.30, 0.0))
	_check(slow.has("ivb_in") and PitchNamer.name_pitch(slow, 62.0, 1.0, false) == "Changeup", "a slow low pitch is a changeup, not \"Pitch\"")
	var from := Vector3(0.42, 1.78, 17.6)
	var bounced := PitchPhysics.analyze(from, (Vector3(0.0, -3.0, 0.0) - from).normalized() * 27.7, backspin)
	_check(not bounced.reached and PitchNamer.name_pitch(bounced, 62.0, 1.0, false) == "Pitch", "a ball in the dirt before the plate has no name")
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
