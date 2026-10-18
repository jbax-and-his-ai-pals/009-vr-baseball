extends SceneTree
## Runs synthetic throws through the real release path with the wrist model on, and
## checks the pitch names, spin, and log entries.
## Run: godot --headless --path . -s res://tests/wrist_flow_test.gd

var _t0 := 200.0


## omega_x: controller rotation about the X axis, rad/s (negative = forward snap).
func _throw(bp: Node3D, omega_x: float, omega_y: float = 0.0) -> void:
	var det: ThrowDetector = bp._detector
	det.clear()
	var q := Quaternion.IDENTITY
	for i in 27:
		var k := i / 90.0
		det.add_sample(_t0 + k, Vector3(0.0, 2.0 + 0.1 * k, 18.0 - 12.0 * k), q, 0.9)
		q = (Quaternion(Vector3(1, 0, 0), omega_x / 90.0) * Quaternion(Vector3(0, 1, 0), omega_y / 90.0) * q).normalized()
	bp._held_ball.global_position = Vector3(0.0, 2.2, 16.0)
	bp._held = true
	bp._release_from_hand(_t0 + 26.0 / 90.0, 0.015, 0.04)
	_t0 += 10.0


func _init() -> void:
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	# A usual throw at 12 m/s: snap ratio 2.67, natural twist ratio 0.76 (recorded averages).
	var usual_omega := -2.67 * 12.0
	var usual_twist := 0.76 * 12.0
	_throw(bp, usual_omega, usual_twist)
	_throw(bp, -3.9 * 12.0, usual_twist)                 # big snap
	_throw(bp, usual_omega, usual_twist + 2.0 * 0.5 * 12.0)  # +2 sd of twist
	_throw(bp, -0.2, 0.0)                                # nearly still wrist
	var f := FileAccess.open(bp._logger.path, FileAccess.READ)
	var lines: Array = []
	while not f.eof_reached():
		var l := f.get_line()
		if l != "":
			lines.append(JSON.parse_string(l))
	var fails := 0
	for d in lines:
		print("%-12s tag %-7s spin %5.0f rpm  z_snap %+.2f z_side %+.2f stiff %.2f  baseline snap %.3f  plate %s" % [
			d.pitch_name, d.tag, d.wrist.spin_rpm, d.wrist.z_snap, d.wrist.z_side, d.wrist.stiff, d.wrist.baseline.snap, d.result.plate])
	var checks := {
		"four entries logged": lines.size() == 4,
		"usual throw is a fastball": lines[0].pitch_name in ["Four-seam", "Fastball", "Two-seam"],
		"big snap is a curve": lines[1].pitch_name in ["Curveball", "Slurve", "Splitter"],
		"twist breaks off the line": lines[2].pitch_name in ["Slider", "Cutter", "Slurve"],
		"still wrist is a knuckleball": lines[3].pitch_name == "Knuckleball",
		"wrist data logged": lines[0].has("wrist") and lines[0].spin_mode == "WRIST_MODEL",
		"usual throw barely moves the baseline": absf(lines[0].wrist.baseline.snap - 2.67) < 0.2,
	}
	for k in checks:
		print(("PASS  " if checks[k] else "FAIL  ") + k)
		if not checks[k]:
			fails += 1
	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
