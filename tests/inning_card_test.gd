extends SceneTree
## The card between innings.
## Run: godot --headless --path . -s res://tests/inning_card_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	_check(InningCard.ordinal(1) == "1ST" and InningCard.ordinal(3) == "3RD" and InningCard.ordinal(9) == "9TH" and InningCard.ordinal(12) == "12TH", "ordinals")
	var l := InningCard.lines(3, {"hits": 1, "k": 2, "bb": 0, "runs": 0}, {"hits": 3, "k": 5, "bb": 1, "runs": 1}, 1, 2, "Dante Reyes")
	_check(l[0] == "END OF THE 3RD" and l[1] == "Away 1   Home 2", "the inning and the score")
	_check(l[2] == "This half: 1 run, 2 hits, 3 K, 1 walk", "what happened in it (%s)" % l[2])
	_check(l[3] == "Due up: Dante Reyes", "and who is due up")
	var quiet := InningCard.lines(1, {}, {}, 0, 0, "")
	_check(quiet.size() == 3 and quiet[2] == "This half: 0 runs, 0 hits", "a quiet half says so, with nobody due up if nobody is known (%s)" % quiet[2])
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_mode_name = "Spectate"
	bp.game_innings = 3
	root.add_child(bp)
	await process_frame
	bp._game.hits = 2
	bp._game.strikeouts = 3
	bp.hud.on_half_over({"inning_ended": 1})
	_check(bp.hud.notice.contains("END OF THE 1ST") and bp.hud.notice.contains("2 hits") and bp.hud.notice.contains("3 K"), "the scene shows it at the end of a half (%s)" % bp.hud.notice.replace("\n", " | "))
	_check(bp.hud.half_start.hits == 2, "and starts counting the next half from there")
	bp.hud.notice = ""
	bp.hud.on_half_over({"inning_ended": 3, "game_over": true})
	_check(bp.hud.notice == "", "no card when the game is over")
	bp.queue_free()
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
