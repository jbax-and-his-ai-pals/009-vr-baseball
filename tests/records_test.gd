extends SceneTree
## Game lines: what you did, written once, the same way every time.
## Run: godot --headless --path . -s res://tests/records_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	var team := Team.generate("Away", 50.0, 3)
	var g := GameState.new(team.lineup, 3)
	g.allow_extra = true
	for i in 9:
		g.pitch("swinging_strike")
	g.home_score = 2
	g.runs = 1
	var stats := StatsTracker.new()
	stats.record_pitch("Fastball", 80.0, "swinging_strike")
	stats.record_pitch("Fastball", 82.0, "called_strike")
	stats.record_pitch("Curveball", 70.0, "ball")
	var line := GameRecords.pitching(g, stats, {"called": 4, "perfect": 3}, "Away")
	_check(line.pitches == g.pitch_count and line.k == g.strikeouts and line.opp == "Away" and line.innings == 3, "a pitching line carries the game's totals")
	_check(line.signs == 4 and line.sign_hits == 3, "and the signs")
	_check(line.types.has("Fastball") and int(line.types.Fastball.n) == 2 and float(line.types.Fastball.mph_max) == 82.0, "and each pitch type")
	_check(line.won and not line.lost and line.score_for == 2 and line.score_against == 1, "and the team's result (you pitch for the home side)")
	_check(is_equal_approx(line.max_mph, 82.0) and line.avg_mph > 70.0, "max and average speed")
	_check(not line.has("bat"), "no batting unless you batted")
	var two_way := GameRecords.pitching(g, stats, {}, "Away", {}, {"h": 2, "hr": 1, "bb": 1, "k": 0, "rbi": 3, "ab": 3})
	_check(two_way.bat.h == 2 and two_way.bat.hr == 1 and two_way.bat.rbi == 3, "a two-way game adds what you did at the plate")
	_check(GameRecords.bat_text(two_way.bat) == "At bat: 2 hits, 1 HR, 3 runs, 1 walk", GameRecords.bat_text(two_way.bat))
	_check(GameRecords.bat_text({}) == "" and GameRecords.bat_text({"h": 0, "hr": 0}) == "", "nothing to say if you did nothing")
	_check(GameRecords.bat_text({"h": 1, "k": 2}) == "At bat: 1 hit, 2 K", "singular and plural")
	var closed := {"pitches": 30, "k": 4, "opp": "Away", "won": false, "lost": false}
	g.home_score = 0
	g.runs = 3
	var left := GameRecords.pitching(g, stats, {}, "Away", closed)
	_check(left.pitches == 30 and left.k == 4 and left.lost and not left.won and left.score_against == 3, "after you leave your line is closed but the result is the team's")
	_check(closed.won == false and not closed.has("score_for"), "and the closed line itself is not changed")
	var hit := GameRecords.hitting(g, 101.0, "Home")
	_check(hit.kind == "hitting" and hit.ev_max == 101.0 and hit.won == (g.runs > g.home_score) and hit.opp == "Home", "a hitting line")
	var fld := GameRecords.fielding(g, {"chances": 3, "caught": 2, "missed": 1, "errors": 0, "assists": 1}, 6, "Away")
	_check(fld.kind == "fielding" and fld.position == 6 and fld.caught == 2 and fld.r == g.runs, "a fielding line")
	var p := PlayerProfile.new()
	var cfg := GameConfig.new().normalized()
	p.record_game(cfg, two_way)
	_check(int(p.totals.get("h_h", 0)) == 2 and int(p.totals.get("h_hr", 0)) == 1 and int(p.totals.get("h_r", 0)) == 3 and int(p.totals.games) == 1, "your batting in a two-way game counts toward lifetime batting")
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
