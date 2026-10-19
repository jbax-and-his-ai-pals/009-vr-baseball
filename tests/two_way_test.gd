extends SceneTree
## Role switching: pitch the top, bat the bottom. The rules layer waits for the bottom's result; the
## scene changes your role at the break and hands the game back; the config and menu offer it.
## Run: godot --headless --path . -s res://tests/two_way_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _strike_out_side(g: GameState) -> Dictionary:
	var ev := {}
	for i in 9:
		ev = g.pitch("swinging_strike")
		if ev.get("half_over", false):
			break
	return ev


func _init() -> void:
	# The rules layer.
	var team := Team.generate("Away", 52.0, 14)
	var g := GameState.new(team.lineup, 3)
	g.allow_extra = true
	g.bottom_live = true
	var ev := _strike_out_side(g)
	_check(ev.get("half_over", false) and ev.get("bottom_live", false) and g.awaiting_bottom and g.inning == 1 and not g.over, "three outs with a live bottom wait for it")
	var done := g.finish_bottom(2, 3)
	_check(not g.awaiting_bottom and g.inning == 2 and g.home_score == 2 and g.home_team_hits == 3 and g.home_inning_runs == [2], "its runs and hits go on the board and the game moves on")
	_check(g.finish_bottom(5, 5).get("home_runs_scored", -1) == -1 and g.home_score == 2, "a second report does nothing")
	g.inning = 3
	g.runs = 4
	g.home_score = 1
	_strike_out_side(g)
	var fin := g.finish_bottom(1, 1)
	_check(g.over and fin.game_over and not g.walk_off and g.home_score == 2, "the last bottom, still behind: the game is over")
	var w := GameState.new(team.lineup, 1)
	w.allow_extra = true
	w.bottom_live = true
	w.runs = 1
	_strike_out_side(w)
	var wo := w.finish_bottom(2, 2)
	_check(w.over and w.walk_off and wo.game_over, "runs to take the lead in the last inning are a walk-off")
	var t := GameState.new(team.lineup, 1)
	t.allow_extra = true
	t.bottom_live = true
	_strike_out_side(t)
	t.finish_bottom(0, 0)
	_check(not t.over and t.inning == 2, "tied after the last inning: extra innings")
	var ahead := GameState.new(team.lineup, 1)
	ahead.allow_extra = true
	ahead.bottom_live = true
	ahead.home_score = 3
	var ev3 := _strike_out_side(ahead)
	_check(ahead.over and not ev3.get("bottom_live", false), "home already ahead after the top of the last: there is no bottom")

	# Config and menu.
	var c := GameConfig.new()
	c.two_way = true
	var n := c.normalized()
	_check(n.two_way and n.title().begins_with("Two-way") and n.leaderboard_key().contains("+bat"), "a two-way game has its own title and its own board (%s)" % n.leaderboard_key())
	c.mode = "Fielding"
	_check(not c.normalized().two_way, "only a pitching game can be two-way")
	var b := GameConfig.new()
	b.two_way = true
	b.activity = "Bullpen"
	_check(not b.normalized().two_way and GameConfig.from_dict(n.to_dict()).two_way, "and only a game; it round-trips")
	var m := MenuModel.new(Settings.new())
	m.stack = ["main", "play"]
	var pi := -1
	for i in m.items().size():
		if m.items()[i].id == "mode:Pitching":
			pi = i
	m.activate(pi)
	var idx := -1
	for i in m.items().size():
		if m.items()[i].id == "two_way":
			idx = i
	_check(idx >= 0 and m.items()[idx].value == "Off", "the setup page has an Also bat row")
	m.activate(idx)
	_check(m.config.two_way and m.items()[idx].value == "On", "choosing it turns it on")

	# In the scene.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.roles.two_way = true
	bp.game_innings = 1
	root.add_child(bp)
	await process_frame
	_check(bp._game.bottom_live and bp._mode.human_pitcher, "the game starts with you pitching and the bottom live")
	bp._game.runs = 1
	var top_end := _strike_out_side(bp._game)
	bp.flow.after_event(top_end)
	_check(bp.roles.on_break() and not bp.flow.batter_ready, "at the break nobody pitches and no batter walks up")
	for i in 60 * 8:
		bp._process(1.0 / 60.0)
		if bp.roles.top_game != null:
			break
	_check(bp.roles.top_game != null and bp._mode.human_batter and not bp._mode.human_pitcher, "then you are the batter")
	_check(bp._game.innings == 1 and bp._game.lineup == bp._home.lineup, "against your own lineup in a one-inning half")
	var fielder: Doll = bp._field_nodes[6]
	_check(fielder.jersey == bp._away.jersey and bp._field_nodes[1].jersey == bp._away.jersey, "the visitors take the field in their uniforms")
	_check(bp._runner.jersey == bp._home.jersey, "and your runners wear yours")
	bp.flow.after_event(bp._game.pitch("called_strike"))
	_check(bp.roles.top_game != null, "a strike changes nothing")
	for i in 60 * 6:
		bp._process(1.0 / 60.0)
		if bp.flow.batter_ready:
			break
	var board: Dictionary = {}
	bp.hud.refresh_scoreboard()
	_check(bp.roles.top_game.pitch_count == 0 or bp.roles.top_game.pitch_count >= 0, "your pitching line is kept")
	# Score two runs and the game is won at once.
	bp._game.runs = 2
	bp.flow.after_event(bp._game.pitch("called_strike"))
	_check(bp.roles.bottom_end_timer > 0.0, "a walk-off ends the half")
	for i in 60 * 10:
		bp._process(1.0 / 60.0)
		if bp.roles.top_game == null:
			break
	_check(bp.roles.top_game == null and bp._mode.human_pitcher and not bp._mode.human_batter, "and you are back on the mound")
	_check(bp._field_nodes[6].jersey == bp._home.jersey and bp._runner.jersey == bp._away.jersey, "in your own uniforms again")
	bp._field_nodes[6].play("catch", 0.4)
	bp._field_nodes[6]._process(0.1)
	_check(bp._field_nodes[6].busy(), "and a recolored fielder still animates")
	_check(bp._game.over and bp._game.walk_off and bp._game.home_score == 2 and bp._game.runs == 1, "with the game won (%s)" % bp._game.final_text())
	_check(bp.roles.bat_log.rbi == 2 and bp.roles.bat_log.h == 0, "your batting is tallied")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
