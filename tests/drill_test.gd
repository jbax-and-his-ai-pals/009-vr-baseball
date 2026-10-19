extends SceneTree
## The fielding drill: ten balls hit at your position, never any outs or runners to spoil it, a result
## in stars saved, and a way back to the menu. Also the config and menu for it.
## Run: godot --headless --path . -s res://tests/drill_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	# Config and menu.
	var c := GameConfig.new()
	c.mode = "Fielding"
	c.activity = "Drill"
	c.position = 6
	var n := c.normalized()
	_check(n.activity == "Drill" and not n.is_scored() and n.title() == "Fielding (SS) - drill", "a Fielding drill is not scored and has a title (%s)" % n.title())
	var p := GameConfig.new()
	p.mode = "Pitching"
	p.activity = "Drill"
	_check(p.normalized().activity == "Game", "a drill only exists for Fielding")
	var m := MenuModel.new(Settings.new())
	m.stack = ["main", "play"]
	var idx := -1
	for i in m.items().size():
		if m.items()[i].id == "mode:Fielding":
			idx = i
	m.activate(idx)
	var acts := ["Game"]
	for i in 3:
		var row := -1
		for j in m.items().size():
			if m.items()[j].id == "activity":
				row = j
		acts.append(m.items()[row].value)
		m.activate(row)
	_check("Drill" in acts, "the Fielding setup can choose Drill (%s)" % str(acts))
	m.config.activity = "Drill"
	var start_row := -1
	var rows := m.items()
	for j in rows.size():
		if rows[j].id == "start":
			start_row = j
	_check(start_row >= 0 and String(rows[start_row].note).begins_with("ten balls to you"), "the Start row explains it and shows your best (%s)" % str(rows[start_row].note if start_row >= 0 else ""))

	# In the scene.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_mode_name = "Fielding"
	bp.fielding_position = 6
	root.add_child(bp)
	await process_frame
	bp._drill = true
	bp.fielding.auto_field = true
	var worst_outs := 0
	for i in 60 * 400:
		bp._process(1.0 / 60.0)
		worst_outs = maxi(worst_outs, bp._game.outs)
		if bp._drill_done:
			break
	_check(bp._drill_done and bp._drill_started == 10, "ten balls were hit and the drill finished (%d)" % bp._drill_started)
	_check(worst_outs <= 1 and bp._game.inning == 1, "no inning ever ended on you (most outs seen: %d)" % worst_outs)
	_check(int(bp.fielding.fld.chances) >= 3 and int(bp.fielding.fld.caught) + int(bp.fielding.fld.missed) + int(bp.fielding.fld.errors) >= 3, "your chances were counted (%s)" % str(bp.fielding.fld))
	var rec: Dictionary = bp._profile.challenge("drill_f6")
	_check(int(rec.attempts) == 1, "the result is saved against your position (%s)" % str(rec))
	_check(bp._props.pending_count() > 0 and not bp._game_recorded, "a way back to the menu is scheduled, and it is not recorded as a game")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
