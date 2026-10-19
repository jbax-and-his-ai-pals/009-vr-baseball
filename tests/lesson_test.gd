extends SceneTree
## The pitching lesson and the pitch lab: the lesson counts the right pitches, resets a streak, moves on
## by itself and finishes; the lab explains a throw in words; the menu starts the lesson and remembers
## where you were.
## Run: godot --headless --path . -s res://tests/lesson_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	# The lesson.
	var t := Tutorial.new()
	_check(not t.is_done() and t.prompt().begins_with("LESSON 1 of 5 - Your usual throw (0/8)"), "it starts with your usual throw (%s)" % t.prompt())
	for i in 7:
		t.on_pitch("Fastball", true)
	_check(t.step == 0 and t.progress == 7, "seven fastballs is not enough")
	var r := t.on_pitch("Four-seam", true)
	_check(r.advanced and t.step == 1 and t.progress == 0 and String(r.text).begins_with("Done: Your usual throw"), "the eighth (any fastball family) completes it (%s)" % r.text)
	# Three strikes in a row.
	t.on_pitch("Fastball", true)
	t.on_pitch("Fastball", true)
	var broken := t.on_pitch("Fastball", false)
	_check(t.step == 1 and t.progress == 0, "a ball breaks the streak")
	t.on_pitch("Fastball", true)
	t.on_pitch("Fastball", true)
	_check(t.on_pitch("Fastball", true).advanced and t.step == 2, "three in a row moves on")
	# A wrong pitch gets a hint and does not count.
	var wrong := t.on_pitch("Fastball", true)
	_check(not wrong.advanced and t.progress == 0 and String(wrong.text).contains("Changeup"), "a fastball in the changeup lesson says how to throw one (%s)" % wrong.text)
	for i in 3:
		t.on_pitch("Changeup", false)
	_check(t.step == 3, "pitches count by type, not by where they land (the changeup lesson)")
	for i in 3:
		t.on_pitch("Cutter", true)
	_check(t.step == 4, "a cutter counts as a slider")
	var last := {}
	for i in 3:
		last = t.on_pitch("Curveball", true)
	_check(t.is_done() and last.done and String(last.text).contains("complete"), "the last lesson ends it")
	_check(t.on_pitch("Fastball", true).done, "and it stays done")
	_check(Tutorial.new(99).is_done() and Tutorial.new(-5).step == 0 and Tutorial.new(2).step == 2, "a saved step is clamped, and a lesson can resume")

	# The pitch lab.
	var a := {"reached": true, "speed_mph": 84.2, "spin_rpm": 2400.0, "ivb_in": -14.0, "hb_in": 3.0}
	var curve := PitchLab.explain("Curveball", a, {"z_snap": 2.0, "z_side": 0.1, "z_gyro": 0.0, "z_slot": 0.0, "z_wind": 0.0, "stiff": 0.0})
	_check(curve[0].begins_with("Curveball  84 mph") and curve[1].contains("down 14 in") and curve[2].contains("flick") and curve[2].contains("curve"), "a curve is explained by the wrist flick (%s)" % str(curve))
	var slider := PitchLab.explain("Slider", a, {"z_snap": 0.1, "z_side": -1.8, "z_gyro": 0.0, "z_slot": 0.0, "z_wind": 0.0, "stiff": 0.0})
	_check(slider.any(func(x): return String(x).contains("twist") and String(x).contains("slider")), "a slider is explained by the twist")
	var plain := PitchLab.explain("Fastball", a, {"z_snap": 0.1, "z_side": 0.0, "z_gyro": 0.2, "z_slot": 0.0, "z_wind": 0.0, "stiff": 0.0})
	_check(plain.size() == 3 and plain[2].contains("usual throw"), "a plain throw says nothing was added")
	var knuck := PitchLab.explain("Knuckleball", a, {"knuckle": true, "stiff": 0.9})
	_check(knuck.any(func(x): return String(x).contains("knuckleball")), "a knuckleball is a dead wrist")
	var combo := PitchLab.explain("Slurve", a, {"z_snap": 1.5, "z_side": -1.5, "z_gyro": 0.0, "z_slot": -1.4, "z_wind": 1.2, "stiff": 0.0})
	_check(combo.size() >= 5, "several things at once are each named (%d lines)" % combo.size())
	_check(PitchLab.explain("Fastball", {"reached": false}, {})[0].contains("did not reach"), "a pitch that misses the plate says so")
	_check(PitchLab.how_to("Slider").contains("doorknob") and PitchLab.how_to("???").contains("your own way"), "every pitch has a tip, unknown ones a general one")

	# Config, settings and the menu.
	var c := GameConfig.new()
	c.tutorial = true
	c.mode = "Fielding"
	var n := c.normalized()
	_check(n.tutorial and n.mode == "Pitching" and n.activity == "Bullpen" and n.assist == "Casual" and not n.is_scored() and n.title() == "Learn to pitch", "the lesson is an easy pitching bullpen with its own title")
	_check(GameConfig.from_dict(n.to_dict()).tutorial, "and it round-trips")
	var s := Settings.new()
	s.tutorial_step = 3
	_check(Settings.from_dict(s.to_dict()).tutorial_step == 3 and Settings.from_dict({"tutorial_step": -4}).tutorial_step == 0, "your place in the lesson is saved and clamped")
	var m := MenuModel.new(s)
	m.stack = ["main", "play"]
	var rows := m.items().map(func(r): return r.id)
	_check(rows[1] == "tutorial" and String(m.items()[1].value) == "lesson 4 of 5", "Play lists the lesson first and where you are (%s)" % m.items()[1].value)
	var ev := m.activate(1)
	_check(ev.get("type", "") == "start" and ev.config.tutorial and s.last_game.get("tutorial", false), "choosing it starts it")
	s.tutorial_step = 5
	_check(String(m.items()[1].value).begins_with("done"), "after finishing it offers a replay")
	m.activate(1)
	_check(s.tutorial_step == 0, "and a replay starts over")

	# In the scene.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	bp._config = n
	bp._tutorial = Tutorial.new()
	var pitch := LivePitch.new()
	pitch.label = "Fastball"
	pitch.analysis = {"reached": true, "strike": true, "speed_mph": 80.0, "spin_rpm": 2000.0, "ivb_in": 12.0, "hb_in": 0.0}
	pitch.shape = {"z_snap": 0.0, "z_side": 0.0, "z_gyro": 0.0, "z_slot": 0.0, "z_wind": 0.0, "stiff": 0.0}
	_check(bp._lab_lines(pitch).contains("usual throw"), "in the lesson every pitch gets its explanation")
	for i in 8:
		bp._tutorial_pitch(pitch)
	_check(bp._tutorial.step == 1 and bp._settings.tutorial_step == 1, "eight fastballs advance the lesson and save your place")
	bp._config = GameConfig.new()
	_check(bp._lab_lines(pitch) == "", "in a normal game there is no lab text")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
