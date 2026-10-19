extends SceneTree
## New pitches from use: a career pitcher who throws a pitch the lab recognises often enough, for strikes,
## learns it (and a little movement); it is saved and shown.
## Run: godot --headless --path . -s res://tests/arsenal_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _line(kind: String, n: int, strikes: int) -> Dictionary:
	return {"pitches": n, "strikes": strikes, "k": 3, "bb": 1, "h": 2, "r": 1, "outs": 9, "types": {kind: {"n": n, "strikes": strikes, "whiffs": 1, "swings": 4, "mph_sum": 70.0 * n, "mph_max": 74.0}}}


func _init() -> void:
	var c := Career.create("Cal Reyes", "Balanced", 6, 3, 9)
	c.save_path = "user://test_arsenal.json"
	_check(c.repertoire == ["Fastball", "Curveball", "Slider", "Changeup"] and c.pitcher_player().repertoire == c.repertoire, "you start with four pitches")
	_check(Career.family("Four-seam") == "Fastball" and Career.family("Cutter") == "Cutter", "a four-seam is a fastball")
	var move_before := float(c.ratings.movement)
	_check(c.learn_from(_line("Cutter", 10, 8)).is_empty() and c.arsenal.Cutter.n == 10, "ten cutters is not enough")
	var learned := c.learn_from(_line("Cutter", 8, 6))
	_check(learned == ["Cutter"] and c.repertoire.has("Cutter") and float(c.ratings.movement) == move_before + Career.LEARN_BONUS, "eighteen, mostly strikes: learned, with a bonus (%s)" % str(learned))
	_check(c.learn_from(_line("Cutter", 20, 15)).is_empty(), "and only once")
	var wild := c.learn_from(_line("Splitter", 30, 6))
	_check(wild.is_empty() and not c.repertoire.has("Splitter"), "thirty splitters that are all balls teach nothing")
	_check(c.learn_from(_line("Fastball", 50, 40)).is_empty() and not c.arsenal.has("Four-seam"), "the four you have are not 'learned' again")
	_check(c.learn_from({"types": "nonsense"}).is_empty() and c.learn_from({}).is_empty(), "a bad line is ignored")
	var also := c.learn_from(_line("Sinker", 16, 10))
	_check(also == ["Sinker"] and c.pitcher_player().repertoire.size() == 6, "a second new pitch, and your pitcher knows six")
	# The season moves on and tells you.
	var res := c.finish_start(_line("Knuckleball", 20, 12), 2, 1)
	_check(res.learned == ["Knuckleball"], "finishing a start reports what you learned")
	# Saved.
	c.save()
	var back := Career.load_from("user://test_arsenal.json")
	_check(back != null and back.repertoire == c.repertoire and int(back.arsenal.Cutter.n) == int(c.arsenal.Cutter.n), "it is saved with the career")
	var odd := Career.from_dict({"repertoire": ["Cutter", "Eephus", "Cutter"], "arsenal": {"Cutter": {"n": 3, "strikes": 2}, "x": 5}})
	_check(odd.repertoire.count("Cutter") == 1 and not odd.repertoire.has("Eephus") and odd.arsenal.has("Cutter") and not odd.arsenal.has("x"), "a damaged file cannot teach you a made-up pitch")
	var m := MenuModel.new(Settings.new())
	m.career = c
	m.stack = ["main", "career"]
	var shown := false
	for r in m.items():
		if r.id == "info" and String(r.label) == "Pitches" and String(r.value).contains("Cutter"):
			shown = true
	_check(shown, "the career screen lists your pitches")
	DirAccess.remove_absolute("user://test_arsenal.json")
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
