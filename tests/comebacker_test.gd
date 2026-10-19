extends SceneTree
## A ball hit back through the mound is yours to field when you pitch: the glove, the catch, the
## throw to first, and what happens if you miss.
## Run: godot --headless --path . -s res://tests/comebacker_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _fresh() -> Node3D:
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_innings = 3
	root.add_child(bp)
	return bp


func _init() -> void:
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp := _fresh()
	await process_frame
	_check(bp._human_num() == 1, "when you pitch, your fielding position is the mound")
	bp._auto_field = true                      # debug: the glove finds the ball when the pitcher would have reached it

	var specs := [[70.0, -4.0, 0.0], [78.0, -2.0, 3.0], [85.0, 0.0, -3.0], [90.0, 2.0, 0.0], [66.0, -6.0, 2.0], [95.0, 4.0, -1.0], [75.0, -1.0, 0.0], [82.0, 3.0, 1.0]]
	var found := false
	var spec_used := []
	for spec in specs:
		bp._debug_hit(spec[0], spec[1], spec[2])
		var h: LiveHit = bp._hits[bp._hits.size() - 1]
		if h.human_chance:
			found = true
			spec_used = spec
			break
		# Not a comebacker: let it play out and try another.
		for i in 60 * 14:
			bp._process(1.0 / 60.0)
			if h.result_shown and bp._aux_play.is_empty() and bp._batter_ready:
				break
	_check(found, "some balls through the middle become your chance (%s)" % str(spec_used))
	if not found:
		print("FAILURES: %d" % (_failures + 1))
		quit(1)
		return
	var h: LiveHit = bp._hits[bp._hits.size() - 1]
	_check(h.human_state == "waiting" and int(h.play.get("fielder", 0)) == 1 and not h.fallback.is_empty(), "the ball is yours (waiting for your glove), with the AI's answer ready if you miss")
	var chances_before: int = bp._fld.chances
	var t := 0.0
	for i in 60 * 20:
		bp._process(1.0 / 60.0)
		if h.result_shown:
			break
	var text: String = String(bp._last_report)
	_check(h.result_shown and int(bp._fld.chances) == chances_before + 1, "it was played out and counted as a chance (%s)" % text.split("\n")[0])
	_check(int(bp._fld.caught) + int(bp._fld.missed) == int(bp._fld.chances), "caught or missed, never neither")
	if int(bp._fld.caught) > 0:
		_check(text.contains("1-3") or text.contains("Pop") or text.contains("Fly") or text.contains("Line") or text.contains("out"), "you made the play (%s)" % text.split("\n")[0])
	bp.queue_free()
	await process_frame

	# If you never get your glove on it, the defense plays it without you.
	var bp2 := _fresh()
	await process_frame
	bp2._auto_field = false
	var chance: LiveHit = null
	for spec in specs:
		bp2._debug_hit(spec[0], spec[1], spec[2])
		var h2: LiveHit = bp2._hits[bp2._hits.size() - 1]
		if h2.human_chance:
			chance = h2
			break
		for i in 60 * 14:
			bp2._process(1.0 / 60.0)
			if h2.result_shown and bp2._aux_play.is_empty() and bp2._batter_ready:
				break
	_check(chance != null, "found a comebacker again")
	if chance != null:
		for i in 60 * 20:
			bp2._process(1.0 / 60.0)
			if chance.result_shown:
				break
		_check(chance.result_shown and int(bp2._fld.missed) == 1 and chance.human_state == "done", "with no glove on it, it gets by you and the AI plays it (%s)" % String(bp2._last_report).split("\n")[0])
	bp2.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
