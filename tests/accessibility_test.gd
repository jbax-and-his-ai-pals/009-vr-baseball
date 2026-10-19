extends SceneTree
## Accessibility and comfort: the colour-blind zone palette, the umpire's calls as words, seated play,
## and left-handed throwing (the mirror image of a right-handed throw gives the mirror image of the aim).
## Run: godot --headless --path . -s res://tests/accessibility_test.gd

class Knobs:
	var velocity_gain := 2.4
	var max_mph := 100.0
	var spin_gain := 6.0
	var aim_assist := 1.0
	var funnel_spread_x := 0.40
	var funnel_spread_y := 0.30
	var aim_learn_rate := 0.08
	var technique_gain := 1.0
	var fastball_backspin_rpm := 1700.0
	var velocity_latency := 0.015
	var spin_latency := 0.04
	var spin_mode := 1
	var aim_mode := 2
	var throwing_hand := &"right_hand"

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


## Hue-based reading of how red-green confusable two colours are: a deuteranope loses the red-green
## axis, so two colours that differ only along it look alike. We compare in a simplified space with
## that axis removed.
func _cvd_distance(a: Color, b: Color) -> float:
	var pa := Vector2(0.5 * (a.r + a.g) - 0.5 * a.b, a.b - 0.5 * (a.r + a.g) + 0.2)
	var pb := Vector2(0.5 * (b.r + b.g) - 0.5 * b.b, b.b - 0.5 * (b.r + b.g) + 0.2)
	return pa.distance_to(pb) + absf((a.r + a.g + a.b) - (b.r + b.g + b.b)) * 0.15


func _init() -> void:
	# The palette.
	PitchLocation.colorblind = false
	var std := {}
	for kind in PitchLocation.PALETTE:
		std[kind] = PitchLocation.color_of(kind)
	PitchLocation.colorblind = true
	var cb := {}
	for kind in PitchLocation.PALETTE:
		cb[kind] = PitchLocation.color_of(kind)
	_check(std["corner"] == PitchLocation.PALETTE["corner"][0] and cb["corner"] == PitchLocation.PALETTE["corner"][1] and std["corner"] != cb["corner"], "the setting switches the palette")
	_check(PitchLocation.classify(0.0, 0.9).color == cb["middle"] and PitchLocation.classify(0.0, 0.9).kind == "middle", "classify uses it")
	var worst := 99.0
	var worst_pair := ""
	var kinds := cb.keys()
	for i in kinds.size():
		for j in range(i + 1, kinds.size()):
			var d := _cvd_distance(cb[kinds[i]], cb[kinds[j]])
			if d < worst:
				worst = d
				worst_pair = "%s/%s" % [kinds[i], kinds[j]]
	var std_worst := 99.0
	for i in kinds.size():
		for j in range(i + 1, kinds.size()):
			std_worst = minf(std_worst, _cvd_distance(std[kinds[i]], std[kinds[j]]))
	_check(worst > std_worst and worst > 0.12, "the colour-blind set keeps every pair apart without the red-green axis (%.2f vs %.2f for the standard set; closest %s)" % [worst, std_worst, worst_pair])
	_check(cb["corner"].b > cb["corner"].g and cb["corner"].b > cb["corner"].r and cb["ball"].r > cb["ball"].g, "strikes lean blue, balls lean warm")
	PitchLocation.colorblind = false

	# Settings and the menu.
	var s := Settings.new()
	_check(not s.colorblind and s.call_text and not s.seated, "defaults: standard colours, call text on, standing")
	s.colorblind = true
	s.seated = true
	s.call_text = false
	var s2 := Settings.from_dict(s.to_dict())
	_check(s2.colorblind and s2.seated and not s2.call_text, "all three survive saving")
	var m := MenuModel.new(Settings.new())
	m.stack = ["options"]
	for id in ["colorblind", "call_text", "seated"]:
		var idx := -1
		for i in m.items().size():
			if m.items()[i].id == id:
				idx = i
		var before: bool = bool(m.settings.get(id))
		var ev := m.activate(idx)
		_check(idx >= 0 and ev.get("type", "") == "settings" and bool(m.settings.get(id)) != before, "Options toggles %s" % id)

	# Seated height.
	_check(is_equal_approx(Comfort.seated_offset(1.65), 0.0) and is_equal_approx(Comfort.seated_offset(1.2), 0.45), "a head at 1.20 m is lifted 0.45 m; a standing one not at all")
	_check(Comfort.seated_offset(1.9) == 0.0 and Comfort.seated_offset(0.2) == Comfort.MAX_LIFT, "never lowered, never lifted past the limit")

	# Left-handed throwing: the mirror image of a right-handed throw gives the mirror image of the aim.
	var right := HumanPitcher.new()
	right.knobs = Knobs.new()
	var left := HumanPitcher.new()
	var lk := Knobs.new()
	lk.throwing_hand = &"left_hand"
	left.knobs = lk
	left.mirror_aim()
	_check(left.aim_mu.x == -right.aim_mu.x and left.aim_mu.y == right.aim_mu.y, "a left-hander's starting aim is mirrored")
	var tx: Array = []
	for pair in [[right, 1.0], [left, -1.0]]:
		var h: HumanPitcher = pair[0]
		var side: float = pair[1]
		h.detector.clear()
		for i in 27:
			var k := i / 90.0
			h.detector.add_sample(10.0 + k, Vector3(side * 1.2 * k, 2.0 + 0.4 * k, 18.0 - 12.0 * k), Quaternion.IDENTITY, 0.9)
		tx.append(h.funnel_target(10.0 + 26.0 / 90.0, 0.0, 1.0).target)
	_check(absf(tx[0].x + tx[1].x) < 0.001 and absf(tx[0].y - tx[1].y) < 0.001, "the same throw from the left side lands at the mirrored spot (%.2f vs %.2f)" % [tx[0].x, tx[1].x])

	# The umpire's words, in the real scene.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	_check(bp._call_label != null and not bp._call_label.visible, "there is a call label above the plate, hidden at first")
	bp._settings.call_text = true
	bp._sound.umpire_says("ump_strike")
	bp._props.update(0.01)
	_check(bp._call_label.visible and bp._call_label.text.begins_with("STRIKE"), "a called strike shows the word and the count (%s)" % bp._call_label.text)
	bp._sound.umpire_says("ump_safe")
	bp._props.update(0.01)
	_check(bp._call_label.text == "SAFE", "a call at a base shows too")
	for i in 150:
		bp._process(1.0 / 60.0)
	_check(not bp._call_label.visible, "and goes away after a moment")
	bp._settings.call_text = false
	bp._sound.umpire_says("ump_out")
	bp._props.update(0.01)
	_check(not bp._call_label.visible, "nothing is shown with the setting off")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
