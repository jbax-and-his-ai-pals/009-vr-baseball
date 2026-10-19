extends SceneTree
## The player's saved history: Game Score, boards that keep the best, totals that outlive the capped
## game list, a file that survives a round trip (and damage), and the Stats screen that shows it.
## Run: godot --headless --path . -s res://tests/profile_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _line(outs: int, k: int, h: int, r: int, bb: int, won := false) -> Dictionary:
	return {"outs": outs, "pitches": outs * 5, "strikes": outs * 3, "k": k, "bb": bb, "h": h, "r": r, "hr": 0, "max_mph": 88.0, "won": won, "lost": not won}


func _init() -> void:
	# Game Score (Bill James): a complete-game shutout is far above a blowup.
	_check(PlayerProfile.game_score(_line(27, 9, 3, 0, 1)) == 50 + 27 + 2 * 5 + 9 - 6 - 1, "a nine-inning gem scores %d" % PlayerProfile.game_score(_line(27, 9, 3, 0, 1)))
	_check(PlayerProfile.game_score(_line(9, 2, 9, 7, 3)) < 30, "three innings of 9 hits and 7 runs is a poor score (%d)" % PlayerProfile.game_score(_line(9, 2, 9, 7, 3)))
	_check(PlayerProfile.ip_text(20) == "6.2", "innings pitched read 6.2")

	var cfg := GameConfig.new()
	var p := PlayerProfile.new()
	var r1 := p.record_game(cfg, _line(27, 5, 6, 2, 2, true), 100.0)
	_check(r1.rank == 1 and r1.personal_best and r1.key == "Pitching/9inn/Standard", "the first game tops its board (%s)" % str(r1))
	var r2 := p.record_game(cfg, _line(27, 10, 2, 0, 0, true), 200.0)
	_check(r2.rank == 1 and r2.personal_best, "a better game takes first")
	var r3 := p.record_game(cfg, _line(15, 1, 8, 6, 4), 300.0)
	_check(r3.rank == 3 and not r3.personal_best, "a poor one is third (%d)" % r3.rank)
	_check(p.top(r1.key, 2).size() == 2 and int(p.top(r1.key, 1)[0].score) == r2.score, "the board is best first")
	var casual := GameConfig.new()
	casual.assist = "Casual"
	var rc := p.record_game(casual, _line(27, 10, 2, 0, 0, true), 400.0)
	_check(rc.rank == 1 and p.keys_played().size() == 2, "an easier assist level has its own board")
	var practice := GameConfig.new()
	practice.activity = "Practice"
	var rp := p.record_game(practice, _line(3, 1, 0, 0, 0), 500.0)
	_check(rp.rank == 0 and rp.key == "" and p.keys_played().size() == 2, "practice is recorded but on no board")
	_check(int(p.totals.games) == 5 and int(p.totals.wins) == 3 and int(p.totals.losses) == 2, "lifetime totals count every game (%s)" % str(p.totals))

	# The board and history are capped; totals are not.
	for i in 40:
		p.record_game(cfg, _line(3, 0, 5, 5, 0), 1000.0 + i)
	_check(p.top(r1.key, 99).size() == PlayerProfile.TOP_KEPT, "a board keeps its best %d" % PlayerProfile.TOP_KEPT)
	for i in 300:
		p.record_game(practice, _line(3, 0, 0, 0, 0), 5000.0 + i)
	_check(p.games.size() == PlayerProfile.MAX_GAMES and int(p.totals.games) == 345, "the game list is capped but the totals keep counting (%d, %d)" % [p.games.size(), int(p.totals.games)])

	# Challenges.
	var c1 := p.record_challenge("escape", 0, 14)
	_check(not c1.improved and p.challenge("escape").attempts == 1 and p.challenge("escape").best == 0, "a failed attempt counts but earns nothing")
	var c2 := p.record_challenge("escape", 2, 14)
	_check(c2.improved and c2.first_win and p.challenge("escape").best == 2, "the first win is noted")
	var c3 := p.record_challenge("escape", 1, 9)
	_check(not c3.improved and p.challenge("escape").best == 2 and p.challenge("escape").best_pitches == 9, "a worse win keeps the stars and records fewer pitches")
	_check(p.challenge("never").attempts == 0, "an untried challenge is empty")

	# Saving.
	var path := "user://test_profile.json"
	_check(p.save(path), "it saves")
	var q := PlayerProfile.load_from(path)
	_check(q.games.size() == p.games.size() and int(q.totals.games) == 345 and q.top(r1.key, 1)[0].score == p.top(r1.key, 1)[0].score
		and q.challenge("escape").best == 2, "it comes back the same")
	_check(PlayerProfile.load_from("user://no_such_profile.json").games.is_empty(), "a missing file is an empty profile")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	_check(PlayerProfile.load_from(path).games.is_empty(), "a damaged file is an empty profile")
	var odd := PlayerProfile.from_dict({"games": [5, {"x": 1}], "boards": {"k": [1, {"score": 3, "t": 1}]}, "totals": 7, "challenges": {"a": 3}})
	_check(odd.games.is_empty() and odd.boards["k"].size() == 1 and odd.totals.is_empty() and odd.challenges.is_empty(), "odd shapes are dropped, not trusted")

	# The Stats screen.
	var s := Settings.new()
	var m := MenuModel.new(s)
	m.profile = PlayerProfile.new()
	m.stack = ["main"]
	var idx := -1
	for i in m.items().size():
		if m.items()[i].id == "stats":
			idx = i
	m.activate(idx)
	_check(m.screen() == "stats" and m.items()[0].label == "No games finished yet", "a new player sees an empty Stats screen")
	m.profile = p
	m.stats_key = r1.key
	var rows := m.items()
	var has_key := false
	var top_rows := 0
	for row in rows:
		if row.id == "stats_key":
			has_key = true
		if row.id == "info" and String(row.label).begins_with("#"):
			top_rows += 1
	_check(rows[0].label.contains("games") and has_key and top_rows == 5, "lifetime lines, a leaderboard picker and its top five (%d)" % top_rows)
	var before := m.stats_key
	var key_row := -1
	for i in rows.size():
		if rows[i].id == "stats_key":
			key_row = i
	m.activate(key_row)
	_check(m.stats_key != before, "the picker switches leaderboards (%s)" % MenuModel.key_label(m.stats_key))
	_check(MenuModel.key_label("Pitching/9inn/Standard") == "Pitching, 9 inn, Standard", "board names read as words")
	_check(m.items()[0].enabled == false and m.items()[m.items().size() - 1].id == "back", "info lines are not buttons")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
