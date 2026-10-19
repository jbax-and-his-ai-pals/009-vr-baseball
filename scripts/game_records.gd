class_name GameRecords
extends RefCounted
## What you did in a game, written as one line for the book (PlayerProfile) and the career. Pure: it
## reads the game state and the trackers it is given, so it can be tested without a scene.
##
##   GameRecords.pitching(game, stats, sign_tally, opponent, left_line, bat_log)
##   GameRecords.hitting(game, best_ev, opponent)
##   GameRecords.fielding(game, fld, position, opponent)


## The result of the game as the home side (you pitch for the home side) sees it.
static func _home_result(line: Dictionary, game: GameState) -> void:
	line["won"] = game.home_score > game.runs
	line["lost"] = game.home_score < game.runs
	line["score_for"] = game.home_score
	line["score_against"] = game.runs


## A pitching line. `left_line` is the line closed when you handed the ball over ({} if you did not);
## `bat_log` is what you did at bat in a two-way game ({} or all zeros if you did not bat).
static func pitching(game: GameState, stats: StatsTracker, sign_tally: Dictionary, opponent: String,
		left_line: Dictionary = {}, bat_log: Dictionary = {}) -> Dictionary:
	var line: Dictionary
	if not left_line.is_empty():
		# You left earlier: the line is closed, but win or loss is the team's result.
		line = left_line.duplicate()
	else:
		var t := stats.pitch_totals()
		var n := maxi(int(t.n), 1)
		var types := {}
		for kind in stats.by_type:
			var x: Dictionary = stats.by_type[kind]
			types[kind] = {"n": int(x.n), "strikes": int(x.strikes), "whiffs": int(x.whiffs), "swings": int(x.swings),
				"mph_sum": float(x.mph_sum), "mph_max": float(x.mph_max)}
		line = {"signs": int(sign_tally.get("called", 0)), "sign_hits": int(sign_tally.get("perfect", 0)), "opp": opponent,
			"innings": game.innings, "types": types, "outs": game.outs_recorded, "pitches": game.pitch_count,
			"strikes": int(t.strikes), "k": game.strikeouts, "bb": game.walks, "h": game.hits, "r": game.runs, "hr": game.home_runs,
			"max_mph": float(t.mph_max), "avg_mph": float(t.mph_sum) / n}
	_home_result(line, game)
	var batted := 0
	for k in ["h", "hr", "bb", "k", "rbi"]:
		batted += int(bat_log.get(k, 0))
	if batted > 0:
		line["bat"] = {"h": int(bat_log.get("h", 0)), "hr": int(bat_log.get("hr", 0)), "bb": int(bat_log.get("bb", 0)),
			"k": int(bat_log.get("k", 0)), "rbi": int(bat_log.get("rbi", 0))}
	return line


## What you did as a batter: your lineup's line against their pitcher.
static func hitting(game: GameState, best_ev: float, opponent: String) -> Dictionary:
	return {"kind": "hitting", "pa": game.batters_faced, "h": game.hits, "hr": game.home_runs, "k": game.strikeouts,
		"bb": game.walks, "r": game.runs, "ev_max": best_ev, "opp": opponent, "innings": game.innings,
		"won": game.runs > game.home_score, "lost": game.runs < game.home_score,
		"score_for": game.runs, "score_against": game.home_score}


## What you did as a fielder (see PlayerProfile.fielding_score).
static func fielding(game: GameState, fld: Dictionary, position: int, opponent: String) -> Dictionary:
	var line := fld.duplicate()
	line["kind"] = "fielding"
	line["position"] = position
	line["r"] = game.runs
	line["opp"] = opponent
	line["innings"] = game.innings
	_home_result(line, game)
	return line


## "2 for 3-ish": a short sentence about your batting in a two-way game, or "" if you did not bat.
static func bat_text(bat: Dictionary) -> String:
	if bat.is_empty():
		return ""
	var bits: Array = []
	if int(bat.get("h", 0)) > 0:
		bits.append("%d hit%s" % [int(bat.h), "" if int(bat.h) == 1 else "s"])
	if int(bat.get("hr", 0)) > 0:
		bits.append("%d HR" % int(bat.hr))
	if int(bat.get("rbi", 0)) > 0:
		bits.append("%d run%s" % [int(bat.rbi), "" if int(bat.rbi) == 1 else "s"])
	if int(bat.get("bb", 0)) > 0:
		bits.append("%d walk%s" % [int(bat.bb), "" if int(bat.bb) == 1 else "s"])
	if int(bat.get("k", 0)) > 0:
		bits.append("%d K" % int(bat.k))
	return "At bat: " + ", ".join(bits) if not bits.is_empty() else ""
