extends SceneTree
## The warm-up: ten easy throws, then three harder ones; it says what it learned in words (usual and top speed,
## how steady your aim is, a suggested assist) and saves your arm. In the scene the batter only watches, the grip
## stays a four-seamer, and the thirteenth throw saves the calibration.
## Run: godot --headless --path . -s res://tests/warmup_test.gd

var _failures := 0
var _t0 := 300.0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


## A throw through the real release path: the hand sweeps forward at `speed` m/s with an ordinary wrist snap.
func _throw(bp: Node3D, speed: float, drift: float) -> void:
	var det: ThrowDetector = bp._detector
	det.clear()
	var q := Quaternion.IDENTITY
	for i in 27:
		var k := i / 90.0
		det.add_sample(_t0 + k, Vector3(drift * k, 2.0 + 0.1 * k, 18.0 - speed * k), q, 0.9)
		q = (Quaternion(Vector3(1, 0, 0), -2.67 * speed / 90.0) * Quaternion(Vector3(0, 1, 0), 0.76 * speed / 90.0) * q).normalized()
	bp.flight.held_ball.global_position = Vector3(0.0, 2.2, 16.0)
	bp._held = true
	bp.flight.release_from_hand(_t0 + 26.0 / 90.0, 0.015, 0.04)
	_t0 += 10.0


func _init() -> void:
	# --- The flow on its own.
	var w := Warmup.new()
	_check(w.prompt().begins_with("WARM-UP 1 of 2 - Easy throws (0/10)") and w.prompt().contains("room"), "it starts with easy throws and a word about space (%s)" % w.prompt().left(60))
	for i in 9:
		_check(not w.on_throw(84.0).advanced, "") if i == 0 else w.on_throw(84.0)
	var r := w.on_throw(85.0)
	_check(r.advanced and not r.done and w.step == 1 and w.prompt().contains("A little harder (0/3)") and w.prompt().contains("hurts"), "ten easy throws, then three harder ones")
	w.on_throw(90.0)
	w.on_throw(91.0)
	var last := w.on_throw(92.0)
	_check(last.done and w.is_done() and w.easy_mph.size() == 10 and w.hard_mph.size() == 3, "thirteen throws and it is done")
	_check(not w.on_throw(80.0).advanced and w.hard_mph.size() == 3, "after that it counts nothing")
	_check(Warmup.steadiness(Vector2(2.5, 2.8)) == "very steady" and Warmup.steadiness(Vector2(4.0, 4.4)) == "steady"
		and Warmup.steadiness(Vector2(6.0, 5.0)) == "about average" and Warmup.steadiness(Vector2(9.0, 7.0)) == "still settling", "steadiness in words, from the wider of the two scatters")
	_check(Warmup.suggested_assist(Vector2(2.5, 2.8)) == "Pro" and Warmup.suggested_assist(Vector2(5.0, 5.0)) == "Standard" and Warmup.suggested_assist(Vector2(10.0, 8.0)) == "Casual", "and an assist to match")
	var card := w.summary(87.0, 92.0, Vector2(3.6, 4.1))
	_check(card.size() == 4 and card[1].contains("87 mph") and card[1].contains("92 mph") and card[2].contains("steady") and card[3].contains("Recalibrate"), "the closing card says what it learned and where to redo it")

	# --- In the scene.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	Calibration.override_path = "user://test_calibration_warmup.json"
	Calibration.clear()
	var wc := GameConfig.new()
	wc.warmup = true
	Session.pending = wc.normalized()
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	bp.pitch_select = "Grip"
	_check(bp.acts.warmup != null and bp.acts.warmup.step == 0, "the warm-up is running")
	bp.flight.pick_family("glove")
	_check((bp._human as HumanPitcher).grip == Grips.FOUR_SEAM, "no grip changes in the warm-up: four-seamers only")
	for i in 10:
		_throw(bp, 12.0 + 0.3 * sin(i * 1.7), 0.15 * sin(i * 2.3))
	_check(bp.acts.warmup.step == 1 and not Calibration.exists("right"), "ten easy throws in: on to the harder ones, nothing saved yet")
	bp.hud.refresh_hud()
	_check(" ".join(bp.hud.pitch_board.lines).contains("WARM-UP 2 of 2 - A little harder (0/3)"), "the board says what to do next (%s)" % " | ".join(bp.hud.pitch_board.lines))
	for i in 3:
		_throw(bp, 15.0 + 0.2 * i, 0.0)
	_check(bp.acts.warmup.is_done() and Calibration.exists("right"), "the thirteenth throw finishes it and saves your arm")
	var saved := Calibration.load_for("right")
	_check((saved.speeds as Array).size() == 13 and float(saved.wrist.mean_speed) > 11.0 and float(saved.wrist.mean_speed) < 13.0, "it learned your usual hand speed from the easy throws (%.2f m/s)" % float(saved.wrist.mean_speed))
	_check((bp._human as HumanPitcher).top_speed() >= 14.9, "and your top speed from the hard ones (%.2f)" % (bp._human as HumanPitcher).top_speed())
	_check(bp.acts.warmup_card.size() == 4 and bp.acts.warmup_card[1].contains("hand speed"), "the board shows what it learned (%s)" % " | ".join(bp.acts.warmup_card))
	_check(bp.flight.swings == 0, "the batter only watched")
	bp.hud.refresh_hud()
	_check(" ".join(bp.hud.pitch_board.lines).contains("WARM-UP DONE") and " ".join(bp.hud.pitch_board.lines).contains("Suggested assist"), "and then the card")

	Calibration.clear()
	Calibration.override_path = ""
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
