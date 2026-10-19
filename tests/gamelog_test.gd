extends SceneTree
## The session log: every line is valid JSON, the important kinds are there, marks carry the
## state around them, and a log of a real game can answer "what happened at this moment".
## Run: godot --headless --path . -s res://tests/gamelog_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	ThrowLogger.override_path = "user://test_throws.jsonl"
	GameLog.override_path = "user://test_events_full.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_innings = 2
	root.add_child(bp)
	await process_frame

	var fast := Player.new()
	fast.speed = 95.0
	fast.aggression = 90.0
	var throw_timer := 0.0
	for i in 60 * 150:
		bp._process(1.0 / 60.0)
		throw_timer -= 1.0 / 60.0
		if throw_timer <= 0.0 and bp._batter_ready and not bp._game.over:
			throw_timer = 1.0
			if i % 7 == 0:
				bp._game.bases = [fast, null, null]
				bp._refresh_base_runners()
			bp.plays.on_delivery_start()
			bp.flight.debug_throw()
		if i == 60 * 40:
			bp.slog.mark_moment()
		if bp._game.over:
			break
	GameLog.close()

	var kinds := {}
	var bad := 0
	var lines := 0
	var f := FileAccess.open("user://test_events_full.jsonl", FileAccess.READ)
	_check(f != null, "the log file exists")
	if f != null:
		while not f.eof_reached():
			var line := f.get_line()
			if line.strip_edges() == "":
				continue
			lines += 1
			var json := JSON.new()
			if json.parse(line) != OK or not (json.data is Dictionary) or not json.data.has("kind") or not json.data.has("t"):
				bad += 1
				continue
			kinds[json.data.kind] = int(kinds.get(json.data.kind, 0)) + 1
	print("  %d lines; kinds: %s" % [lines, str(kinds)])
	_check(lines > 20 and bad == 0, "every line is valid JSON with a time and a kind (%d lines, %d bad)" % [lines, bad])
	for k in ["session", "pitch", "contact", "play_result", "walk_on", "perf", "mark"]:
		_check(kinds.has(k), "the log has '%s' entries" % k)
	_check(kinds.get("pitch", 0) >= 5, "a pitch is logged for each pitch (%d)" % int(kinds.get("pitch", 0)))

	# A mark carries the state and the entries before it.
	var f2 := FileAccess.open("user://test_events_full.jsonl", FileAccess.READ)
	var mark: Dictionary = {}
	while f2 != null and not f2.eof_reached():
		var line2 := f2.get_line()
		if line2.contains("\"kind\":\"mark\""):
			var j2 := JSON.new()
			if j2.parse(line2) == OK:
				mark = j2.data
				break
	_check(not mark.is_empty() and mark.has("state") and mark.state.has("inn") and mark.has("recent") and (mark.recent as Array).size() > 0,
		"a mark includes the full state and the entries just before it")

	# Disabled really means no file.
	GameLog.disabled = true
	GameLog.override_path = "user://should_not_exist.jsonl"
	GameLog.start({"x": 1})
	GameLog.event("nothing", {})
	GameLog.disabled = false
	_check(not FileAccess.file_exists("user://should_not_exist.jsonl"), "with logging off no file is written")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
