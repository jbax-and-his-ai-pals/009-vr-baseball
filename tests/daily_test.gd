extends SceneTree
## The daily game: the same visitors and the same dice for everybody on a given day, three innings, its
## own board per day (the last two weeks are kept), and a Play row that says how you did today.
## Run: godot --headless --path . -s res://tests/daily_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _scene(day: int) -> Node3D:
	var c := GameConfig.new()
	c.daily = day
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.apply_config(c)
	root.add_child(bp)
	return bp


func _init() -> void:
	GameConfig.today_override = 20000
	var c := GameConfig.new()
	c.daily = 20000
	c.mode = "Fielding"
	c.innings = 9
	c.two_way = true
	var n := c.normalized()
	_check(n.daily == 20000 and n.mode == "Pitching" and n.activity == "Game" and n.innings == 3 and not n.two_way, "a daily game is a three-inning pitching game")
	_check(n.is_scored() and n.leaderboard_key() == "Daily/20000/Standard", "with its own board for the day (%s)" % n.leaderboard_key())
	_check(n.title().begins_with("Daily game - 2024-10-04") or n.title().begins_with("Daily game - 2024"), "titled by its date (%s)" % n.title())
	_check(GameConfig.from_dict(n.to_dict()).daily == 20000, "and it round-trips")
	_check(GameConfig.daily_seed(20000) != GameConfig.daily_seed(20001), "every day has its own seed")
	var s := GameConfig.new()
	s.daily = 5
	s.scenario = Scenario.ids()[0]
	_check(s.normalized().daily == 0, "a challenge is not a daily game")

	# The menu.
	var settings := Settings.new()
	var m := MenuModel.new(settings)
	m.stack = ["main", "play"]
	var idx := -1
	for i in m.items().size():
		if m.items()[i].id == "daily":
			idx = i
	_check(idx == 0 and m.items()[idx].value == "new today", "the first row of Play is the daily game, new today")
	m.profile.record_game(n, {"kind": "pitching", "k": 5, "outs": 9, "h": 1, "r": 0, "bb": 0, "pitches": 40, "won": true})
	_check(String(m.items()[idx].value).begins_with("best today: "), "after playing it shows your best (%s)" % m.items()[idx].value)
	var ev := m.activate(idx)
	_check(ev.get("type", "") == "start" and ev.config.daily == 20000 and settings.last_game.get("daily", 0) == 20000, "choosing it starts today's game")
	# Boards: two weeks kept.
	var p := PlayerProfile.new()
	for d in range(19980, 20000):
		var dc := GameConfig.new()
		dc.daily = d
		p.record_game(dc.normalized(), {"kind": "pitching", "k": 3, "outs": 9, "pitches": 30})
	var daily_keys := p.keys_played().filter(func(k): return String(k).begins_with("Daily/"))
	_check(daily_keys.size() == PlayerProfile.DAILY_KEPT, "only the last %d days' boards are kept (%d)" % [PlayerProfile.DAILY_KEPT, daily_keys.size()])
	_check(daily_keys.has("Daily/19999/Standard") and not daily_keys.has("Daily/19980/Standard"), "the old ones go")

	# The scene: the same day is the same game.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var a := _scene(20000)
	await process_frame
	var names_a: Array = a._away.lineup.map(func(x): return x.name)
	var seed_a: int = a._game_seed
	var config_a: GameConfig = a._current_config()
	a.queue_free()
	await process_frame
	var b := _scene(20000)
	await process_frame
	var names_b: Array = b._away.lineup.map(func(x): return x.name)
	_check(names_a == names_b and seed_a == b._game_seed, "two scenes on the same day have the same visitors and the same seed")
	_check(config_a.daily == 20000 and config_a.innings == 3, "and the running game keeps being a daily one")
	b.queue_free()
	await process_frame
	var c2 := _scene(20001)
	await process_frame
	var names_c: Array = c2._away.lineup.map(func(x): return x.name)
	_check(names_c != names_a and c2._game_seed != seed_a, "the next day is a different game")
	c2.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
