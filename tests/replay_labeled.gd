extends SceneTree
## Replays a recorded, tagged throw log through the real WristModel / PitchPhysics /
## PitchNamer and prints which pitch each tag produced.
## Run: godot --headless --path . -s res://tests/replay_labeled.gd -- <log.jsonl> [--old]
## --old reproduces the model as it was before baseline anchoring / slot-speed coupling /
## sigma-based knuckleball detection.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var rows: Array = []
	var f := FileAccess.open(args[0], FileAccess.READ)
	while not f.eof_reached():
		var l := f.get_line()
		if l != "":
			rows.append(JSON.parse_string(l))
	var m := WristModel.new()
	if "--old" in args:
		m.anchor_baseline = false
		m.slot_per_speed = 0.0
		m.knuckle_by_sigma = false
		m.push_knuckle = false
		m.sidearm_discount = false
		m.calibration_throws = 15
	var by_tag := {}
	var order: Array = []
	var gain := 2.4
	for r in rows:
		var omega := Vector3(r.raw.spin[0], r.raw.spin[1], r.raw.spin[2])
		var vel := Vector3(r.raw.vel[0], r.raw.vel[1], r.raw.vel[2])
		var slot: float = r.hand_minus_head[1]
		var from := Vector3(r.release_pos[0], r.release_pos[1], r.release_pos[2])
		if vel.length() < 3.5:
			continue
		var det := ThrowDetector.new()
		for smp in r.samples:
			det.add_sample(float(smp.ms) / 1000.0, Vector3(smp.p[0], smp.p[1], smp.p[2]), Quaternion.IDENTITY)
		var extras := {}
		if "--old" not in args:
			extras["straight"] = det.straightness(0.0)
			var peak := det.peak_height(0.0)
			if peak > -100.0:
				extras["wind_peak"] = peak - float(r.head_pos[1])
		var s := m.shape(omega, vel, slot, 1.0, extras)
		var target := Vector3(0.0, 0.8, 0.0)
		if r.has("funnel"):
			target = Vector3(r.funnel.target[0], r.funnel.target[1], 0.0)
		var speed := minf(vel.length() * gain, 100.0 / PitchPhysics.MPS_TO_MPH)
		var v := PitchPhysics.solve_aim(from, maxf(speed, 12.0), s.spin, target)
		var a := PitchPhysics.analyze(from, v, s.spin, s.flutter, 0.9)
		var nm := PitchNamer.name_pitch(a, m.typical_mph(gain), 1.0, s.knuckle)
		var tag: String = r.tag
		if not by_tag.has(tag):
			by_tag[tag] = {}
			order.append(tag)
		by_tag[tag][nm] = by_tag[tag].get(nm, 0) + 1
		if args.size() > 1 and "--verbose" in args:
			print("%2d %-11s %-10s z snap %+.1f side %+.1f gyro %+.1f slot %+.1f wind %+.1f stiff %.2f mph %.0f" % [r.n, tag, nm, s.z_snap, s.z_side, s.z_gyro, s.z_slot, s.z_wind, s.stiff, a.speed_mph])
	for tag in order:
		var parts := []
		var d: Dictionary = by_tag[tag]
		for k in d:
			parts.append("%s %d" % [k, d[k]])
		print("%-12s %s" % [tag, ", ".join(parts)])
	print("final baseline: snap %.2f (sd %.2f) side %.2f (sd %.2f) gyro %.2f mag %.2f (sd %.2f) slot %+.2f speed %.1f" % [
		m.mean_snap, m.sd_snap, m.mean_side, m.sd_side, m.mean_gyro, m.mean_mag, m.sd_mag, m.mean_slot, m.mean_speed])
	quit(0)
