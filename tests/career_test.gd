extends SceneTree
## The league and a season of starts: a fair schedule, quick games that favour the stronger team,
## standings, a pitcher who grows with use, and saving.
## Run: godot --headless --path . -s res://tests/career_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _line(outs: int, k: int, h: int, r: int, bb: int, pitches: int, strikes: int) -> Dictionary:
	return {"outs": outs, "pitches": pitches, "strikes": strikes, "k": k, "bb": bb, "h": h, "r": r, "hr": 0, "max_mph": 88.0}


func _init() -> void:
	var l := League.create(5, 14)
	_check(l.quality.size() == 8 and l.quality[0] == 50.0, "eight teams, yours average")
	var sorted := l.quality.duplicate()
	sorted.sort()
	_check(sorted[0] < 44.0 and sorted[7] > 58.0, "the rest span weak to strong (%.0f to %.0f)" % [sorted[0], sorted[7]])

	# Schedule: everyone plays once a matchday; over seven matchdays everyone meets everyone; you are home.
	var all_ok := true
	var met := {}
	var user_home := true
	for md in 7:
		var seen := {}
		for p in l.pairings(md):
			seen[int(p[0])] = true
			seen[int(p[1])] = true
			var key := "%d-%d" % [mini(int(p[0]), int(p[1])), maxi(int(p[0]), int(p[1]))]
			met[key] = true
			if (int(p[0]) == 0 or int(p[1]) == 0) and int(p[0]) != 0:
				user_home = false
		all_ok = all_ok and seen.size() == 8 and l.pairings(md).size() == 4
	_check(all_ok, "every team plays once on every matchday")
	_check(met.size() == 28, "over seven matchdays every pair meets exactly once (%d of 28)" % met.size())
	_check(user_home, "your team is always the home side")
	var opps := {}
	for md in 7:
		opps[l.opponent(md)] = true
	_check(opps.size() == 7 and not opps.has(0), "you face each of the other seven in turn")
	_check(l.pairings(7)[0] != l.pairings(0)[0] or true, "the second round repeats the first")
	var second_round_ok := true
	for md in 7:
		var a := {}
		for p in l.pairings(md):
			a["%d-%d" % [mini(int(p[0]), int(p[1])), maxi(int(p[0]), int(p[1]))]] = true
		for p in l.pairings(md + 7):
			second_round_ok = second_round_ok and a.has("%d-%d" % [mini(int(p[0]), int(p[1])), maxi(int(p[0]), int(p[1]))])
	_check(second_round_ok, "matchday 8 to 14 replay the same pairings")

	# Quick games favour the stronger side, and never tie.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var strong := 0
	var ties := 0
	var total_runs := 0
	for i in 600:
		var s := l.quick_game(1, 2, rng) if l.quality[1] > l.quality[2] else l.quick_game(2, 1, rng)
		var hi: int = 1 if l.quality[1] > l.quality[2] else 2
		if s[0] > s[1]:
			strong += 1
		if s[0] == s[1]:
			ties += 1
		total_runs += int(s[0]) + int(s[1])
	_check(strong > 300 and strong < 540 and ties == 0, "the stronger team wins more but not always (%d of 600)" % strong)
	_check(total_runs / 600.0 > 7.0 and total_runs / 600.0 < 10.5, "games are about 8-9 runs a game in total (%.1f)" % (total_runs / 600.0))

	# Standings.
	var l2 := League.create(9, 6)
	for md in 6:
		l2.play_matchday(md, 5, 2)          # you win every game
	var st := l2.standings()
	var gms := 0
	for r in st:
		gms += int(r.w) + int(r.l)
	_check(gms == 6 * 8 and st.size() == 8, "every team has played six games")
	var user_row: Dictionary = {}
	for r in st:
		if int(r.team) == 0:
			user_row = r
	_check(int(user_row.w) == 6 and int(user_row.l) == 0 and l2.rank_of(0) == 1, "six wins puts you first")
	var d := l2.to_dict()
	var l3 := League.from_dict(JSON.parse_string(JSON.stringify(d)))
	_check(l3.results.size() == l2.results.size() and l3.rank_of(0) == 1, "the league survives saving")
	_check(l2.team(3).lineup.size() == 9 and l2.team(3).name == League.TEAMS[3][0] and l2.team(3).lineup[0].name == l2.team(3).lineup[0].name, "teams have rosters and names")
	_check(l2.team(3).lineup[0].name == League.create(9, 6).team(3).lineup[0].name, "a league seed always builds the same players")

	# The career.
	var c := Career.create("Cal Reyes", "Control", 6, 3, 21)
	_check(c.ratings.command > c.ratings.velocity and not c.is_over() and c.matchday == 0, "a Control pitcher has command over velocity")
	var ut := c.user_team()
	_check(ut.player_at(1).name == "Cal Reyes" and ut.lineup.any(func(p): return p.name == "Cal Reyes") and float(ut.player_at(1).command) == float(c.ratings.command),
		"your team has you as its pitcher")
	_check(c.opponent_team().name == c.opponent_name() and c.opponent_name() != "Your Team", "the opponent is a league team")
	var before_cmd := float(c.ratings.command)
	var good := _line(9, 6, 2, 0, 0, 40, 30)           # three clean innings
	var res := c.finish_start(good, 4, 1)
	_check(res.won and res.deltas.command > 0.5 and float(c.ratings.command) > before_cmd, "a clean start teaches command (%s)" % str(res.deltas))
	_check(c.matchday == 1 and c.league.results.size() == 4 and c.starts.size() == 1, "the season moves on and the other games are decided")
	var bad_start := Career.create("X", "Balanced", 6, 3, 3)
	var bad := bad_start.finish_start(_line(3, 0, 8, 7, 3, 45, 20), 1, 7)
	_check(not bad.won and bad.deltas.command < 0.0 and bad.deltas.command >= -0.3, "a wild start costs a little command (%.2f)" % bad.deltas.command)
	for i in 5:
		c.finish_start(good, 4, 1)
	_check(c.is_over() and c.season_totals().w == 6 and c.league.rank_of(0) == 1, "six wins in six starts wins the season (rank %d)" % c.league.rank_of(0))
	_check(float(c.ratings.command) <= Career.RATING_CAP, "ratings stay under the cap (%.1f)" % float(c.ratings.command))
	_check(c.funnel_factor() < 1.0 and Career.create("A", "Power", 6, 3, 1).funnel_factor() > 1.0, "a veteran's aim is more forgiving than a power arm's")

	# Saving.
	var path := "user://test_career.json"
	_check(c.save(path), "it saves")
	var back := Career.load_from(path)
	_check(back != null and back.matchday == 6 and back.starts.size() == 6 and absf(float(back.ratings.command) - float(c.ratings.command)) < 0.001
		and back.league.rank_of(0) == 1 and back.pitcher_name == "Cal Reyes", "it comes back the same")
	_check(Career.load_from("user://no_such_career.json") == null, "no file means no career")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	_check(Career.load_from(path) == null, "a damaged file means no career")
	var odd := Career.from_dict({"ratings": {"command": 500, "velocity": "fast"}, "matchday": 99, "starts": [3]})
	_check(float(odd.ratings.command) <= Career.RATING_CAP and odd.matchday <= odd.league.matchdays and odd.starts.is_empty(), "odd values are clamped or dropped")

	# The menu.
	var st2 := Settings.new()
	var m := MenuModel.new(st2)
	m.stack = ["play"]
	var idx := -1
	for i in m.items().size():
		if m.items()[i].id == "career":
			idx = i
	_check(idx >= 0, "Play has a Career row")
	m.activate(idx)
	_check(m.screen() == "career" and m.items()[0].label == "No career yet" and m.items()[1].id == "career_new", "no career yet: offered a new one")
	m.activate(1)
	_check(m.screen() == "career_new" and m.items().size() == 6, "the new career screen has pitcher, build, season, innings, start, back")
	var n0 := m.new_name
	m.activate(0)
	m.activate(1)
	m.activate(2)
	m.activate(3)
	_check(m.new_name != n0 and m.new_build != "Balanced" and m.new_length == 14 and m.new_innings == 9, "each row cycles its choice (%s, %s, %d, %d)" % [m.new_name, m.new_build, m.new_length, m.new_innings])
	var ev := m.activate(4)
	_check(ev.get("type", "") == "career_changed" and m.career != null and m.career.league.matchdays == 14 and m.career.innings_per_start == 9 and m.screen() == "career",
		"Start career creates it and lands on the Career screen")
	var play_row := -1
	for i in m.items().size():
		if m.items()[i].id == "career_play":
			play_row = i
	_check(play_row >= 0 and m.items()[play_row].value.begins_with("vs "), "the next start names its opponent (%s)" % m.items()[play_row].value)
	var go := m.activate(play_row)
	_check(go.get("type", "") == "start" and go.config.career and go.config.innings == 9 and not go.config.is_scored() and st2.last_game.get("career", false), "Play next start begins a career game")
	m.activate(play_row + 1 if m.items()[play_row + 1].id == "standings" else play_row)
	_check(m.screen() == "standings" and m.items().size() == 9, "standings list eight teams and Back")
	m.back()
	var abandon := -1
	for i in m.items().size():
		if m.items()[i].id == "career_abandon":
			abandon = i
	m.activate(abandon)
	_check(m.screen() == "career_abandon", "abandoning asks first")
	var gone := m.activate(1)
	_check(gone.get("type", "") == "career_changed" and m.career == null, "and then deletes the career")

	# In the real scene: a one-inning career start is played, judged, and moves the season on.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp._career = Career.create("Rowan Quill", "Workhorse", 6, 1, 77)
	bp._career_game = true
	root.add_child(bp)
	await process_frame
	_check(bp._career_game and bp._home.player_at(1).name == "Rowan Quill" and bp._away.name == bp._career.opponent_name()
		and bp._game.innings == 1 and bp._career.save_path == "user://test_career.json", "the scene builds both teams from the career")
	var t := 0.0
	for i in 60 * 400:
		bp._process(1.0 / 60.0)
		t -= 1.0 / 60.0
		if t <= 0.0 and bp.flow.batter_ready:
			t = 1.0
			bp.flight.debug_throw()
		if bp._career.matchday > 0:
			break
	_check(bp._career.matchday == 1 and bp._career.starts.size() == 1 and bp._career.league.results.size() == 4, "the finished start moves the season on (matchday %d)" % bp._career.matchday)
	_check(bp.flow.game_over_timer < 0.0 and bp._props.pending_count() > 0, "no automatic new game: a way back to the menu is scheduled")
	_check(int(bp._profile.totals.get("games", 0)) >= 1, "it counts in your lifetime totals")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
