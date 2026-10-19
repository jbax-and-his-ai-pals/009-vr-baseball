extends SceneTree
## A seed replays a whole game: the pitcher, the batters, the defense and the rules all draw from
## streams seeded by the game seed, so two runs with the same seed end identically and two with
## different seeds do not.
## Run: godot --headless --path . -s res://tests/replay_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _play(seed_value: int) -> Dictionary:
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_mode_name = "Spectate"
	bp.game_innings = 1
	bp.forced_seed = seed_value
	bp.spectate_interval = 0.4
	root.add_child(bp)
	await process_frame
	var frames := 0
	while not bp._game.over and frames < 60 * 600:
		bp._process(1.0 / 60.0)
		frames += 1
	var g: GameState = bp._game
	var sig := {"final": g.final_text(), "line": g.line_text(), "pitches": g.pitch_count, "k": g.strikeouts, "bb": g.walks,
		"hits": g.hits, "hr": g.home_runs, "runs": g.runs, "home": g.home_score, "home_hits": g.home_team_hits,
		"over": g.over}
	bp.queue_free()
	await process_frame
	return sig


func _init() -> void:
	var a: Dictionary = await _play(4242)
	var b: Dictionary = await _play(4242)
	var c: Dictionary = await _play(99)
	print("  a: %s" % str(a))
	print("  b: %s" % str(b))
	print("  c: %s" % str(c))
	_check(a.over and a.pitches > 5, "the game was played to the end (%d pitches)" % a.pitches)
	_check(a == b, "the same seed replays the same game")
	_check(a != c, "a different seed plays a different one")
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
