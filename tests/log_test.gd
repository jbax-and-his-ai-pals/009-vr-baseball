extends SceneTree
## Drives synthetic throws through the real release path and checks the funnel aim
## and the log line.
## Run: godot --headless --path . -s res://tests/log_test.gd

var _t0 := 100.0


func _throw(bp: Node3D, rise_per_sec: float) -> void:
	var det: ThrowDetector = bp._detector
	det.clear()
	# Hand sweeping forward at 12 m/s for 0.3 s, rising or falling at rise_per_sec.
	for i in 27:
		var t := _t0 + i / 90.0
		var k := i / 90.0
		det.add_sample(t, Vector3(0.0, 2.0 + rise_per_sec * k, 18.0 - 12.0 * k), Quaternion.IDENTITY, 0.9)
	bp._held_ball.global_position = Vector3(0.0, 2.2, 16.0)
	bp._held = true
	bp._release_from_hand(_t0 + 26.0 / 90.0, 0.015, 0.04)
	_t0 += 10.0


func _throw_soft(bp: Node3D) -> void:
	var det: ThrowDetector = bp._detector
	det.clear()
	for i in 27:
		var k := i / 90.0
		det.add_sample(_t0 + k, Vector3(0.0, 2.0, 18.0 - 0.5 * k), Quaternion.IDENTITY, 0.9)
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
	bp.spin_mode = 0  # RAW: synthetic hand has no rotation, which would read as a stiff-wrist knuckleball
	var bias_start: Vector2 = bp._aim_mu
	_throw(bp, 1.5)
	_throw(bp, -1.5)
	_throw(bp, 0.0)
	# A soft release is a drop, not a pitch: nothing logged, nothing counted.
	var before: int = bp.slog.logger.count
	_throw_soft(bp)
	var drop_ok: bool = bp.slog.logger.count == before

	var path: String = bp.slog.logger.path
	print("log path: ", ProjectSettings.globalize_path(path))
	var f := FileAccess.open(path, FileAccess.READ)
	var lines: Array = []
	while not f.eof_reached():
		var l := f.get_line()
		if l != "":
			lines.append(JSON.parse_string(l))
	var ok := lines.size() == 3
	var up: Dictionary = lines[0]
	var down: Dictionary = lines[1]
	var shape_ok: bool = up.has("raw") and up.has("series") and up.samples.size() > 10 and up.has("funnel") and up.result.has("strike")
	var ty_up: float = up.funnel.target[1]
	var ty_dn: float = down.funnel.target[1]
	print("funnel target y: rising hand %.3f | falling hand %.3f | usual aim %s -> %s" % [ty_up, ty_dn, bias_start, bp._aim_mu])
	var order_ok := ty_up > ty_dn
	var bounded := absf(ty_up - 0.85) < 1.0 and absf(ty_dn - 0.85) < 1.0
	var lands_ok := true
	for d in lines:
		var plate = d.result.plate
		var tgt: Array = d.funnel.target
		if plate == null or absf(plate[0] - tgt[0]) > 0.02 or absf(plate[1] - tgt[1]) > 0.02:
			lands_ok = false
	var bias_moved: bool = bp._aim_mu != bias_start
	print("shape %s | higher hand -> higher pitch %s | bounded near zone %s | lands on target %s | bias adapts %s" % [shape_ok, order_ok, bounded, lands_ok, bias_moved])
	print("soft release ignored %s" % drop_ok)
	ok = ok and shape_ok and order_ok and bounded and lands_ok and bias_moved and drop_ok
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
