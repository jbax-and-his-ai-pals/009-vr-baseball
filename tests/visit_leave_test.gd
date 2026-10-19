extends SceneTree
## A mound visit (rests the arm once, the catcher walks out and back) and taking yourself out (a
## reliever finishes the game, your line is closed, the team result is still yours), with the pause
## menu offering both only when they make sense.
## Run: godot --headless --path . -s res://tests/visit_leave_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _rows(m: MenuModel) -> Array:
	return m.items().map(func(r): return r.id)


func _init() -> void:
	# The pause menu.
	var m := MenuModel.new(Settings.new())
	var cfg := GameConfig.new()
	m.open_pause(cfg)
	_check(not _rows(m).has("mound_visit") and not _rows(m).has("confirm_leave"), "nothing offered unless the scene says so")
	m.can_mound_visit = true
	m.can_leave = true
	_check(_rows(m).has("mound_visit") and _rows(m).has("confirm_leave"), "a game you pitch offers a visit and a way out")
	_check(m.activate(_rows(m).find("mound_visit")).get("type", "") == "mound_visit", "the visit is an event")
	m.activate(_rows(m).find("confirm_leave"))
	_check(m.screen() == "confirm_leave" and _rows(m).has("leave_game") and m.items()[_rows(m).find("leave_game")].enabled, "leaving asks first")
	_check(m.activate(_rows(m).find("leave_game")).get("type", "") == "leave_game", "and then it is an event")

	# In the scene.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_innings = 1
	root.add_child(bp)
	await process_frame

	bp._game.pitch_count = 100
	var tired_before: float = bp.manager.arm_fatigue()
	bp.manager.mound_visit()
	var tired_after: float = bp.manager.arm_fatigue()
	_check(bp.manager.visit_used and tired_after < tired_before and bp.manager.visit_timer > 4.0 and bp._crew.is_visiting(),
		"a mound visit rests the arm (%.2f to %.2f), stops pitching for a few seconds and sends the catcher out" % [tired_before, tired_after])
	var credit: int = bp.manager.fatigue_credit
	bp.manager.mound_visit()
	_check(bp.manager.fatigue_credit == credit and bp.manager.visit_timer <= 5.2, "only one visit a game")
	for i in 60 * 7:
		bp._process(1.0 / 60.0)
	_check(bp.manager.visit_timer <= 0.0 and not bp._crew.is_visiting() and bp._catcher.position.distance_to(PlateCrew.CATCHER_HOME) < 0.05,
		"then the catcher is back behind the plate and you can pitch again")
	bp._game.pitch_count = 0

	# Taking yourself out.
	for i in 6:
		bp.flight.debug_throw()
		for j in 60 * 3:
			bp._process(1.0 / 60.0)
	var outs_before: int = bp._game.outs_recorded
	var pitches_before: int = bp._game.pitch_count
	var starter: String = bp._ai_pitcher.player.name
	bp.manager.leave_game()
	_check(not bp._mode.human_pitcher and bp.manager.user_left and bp.manager.left_line.get("pitches", -1) == pitches_before and bp.manager.left_line.get("outs", -1) == outs_before,
		"you are out of the game with your line as it stood (%d pitches, %d outs)" % [pitches_before, outs_before])
	_check(bp._ai_pitcher.player.name != starter and bp._spectate_timer > 0.0, "a reliever takes over")
	var games_before := int(bp._profile.totals.get("games", 0))
	var t := 0.0
	for i in 60 * 400:
		bp._process(1.0 / 60.0)
		if bp._game.over and bp.results.game_recorded:
			break
	_check(bp._game.over and bp.results.game_recorded, "the game goes on without you and ends")
	var line: Dictionary = bp.results.game_line()
	_check(line.pitches == pitches_before and line.outs == outs_before and line.won == (bp._game.home_score > bp._game.runs),
		"your line is closed, the win or loss is the team's")
	_check(int(bp._profile.totals.get("games", 0)) == games_before + 1, "and it is in your history")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
