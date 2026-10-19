class_name PlayerProfile
extends RefCounted
## What survives between sessions about how YOU pitch: every finished game's line, lifetime totals,
## the best games per leaderboard (a leaderboard is a GameConfig.leaderboard_key(): mode, length and
## assist level, so an easy preset never skews a harder board), and your challenge results.
## Saved to user://profile.json. A missing or damaged file is just an empty profile.
##
##   var p := PlayerProfile.load_from()
##   var r := p.record_game(config, line)      # line: see game_line() in the scene
##   p.top("Pitching/9inn/Standard", 5)        # best games
##   p.save()

const PATH := "user://profile.json"
const VERSION := 1
const MAX_GAMES := 300          # the history is capped; lifetime totals are kept separately
const TOP_KEPT := 10            # per leaderboard

var games: Array = []           # newest last: {"t", "key", "title", "line", "score"}
var boards: Dictionary = {}     # key -> [{"score", "t", "line"}] best first
var totals: Dictionary = {}     # lifetime counters
var save_path := PATH           # where save() writes (tests point this elsewhere)
var challenges: Dictionary = {} # scenario id -> {"best": int stars, "attempts": int, "wins": int, "best_pitches": int}


## Bill James's Game Score, as one pitcher's line (every run charged to him is counted as earned):
## 50, +1 per out, +2 per complete inning after the fourth, +1 per strikeout, -2 per hit, -4 per run, -1 per walk.
static func game_score(line: Dictionary) -> int:
	var outs := int(line.get("outs", 0))
	var after_fourth := maxi(0, outs / 3 - 4)
	return 50 + outs + 2 * after_fourth + int(line.get("k", 0)) - 2 * int(line.get("h", 0)) \
		- 4 * int(line.get("r", 0)) - int(line.get("bb", 0))


## Fielding Score for one game at one position: catches and assists up, misses, errors and runs against down.
static func fielding_score(line: Dictionary) -> int:
	return 50 + 6 * int(line.get("caught", 0)) + 5 * int(line.get("assists", 0)) - 8 * int(line.get("missed", 0)) \
		- 10 * int(line.get("errors", 0)) - 2 * int(line.get("r", 0)) \
		+ 5 * int(line.get("covers", 0)) - 8 * int(line.get("uncovered", 0)) + 4 * int(line.get("frames", 0)) - 3 * int(line.get("lost", 0)) + 2 * int(line.get("blocks", 0)) - 8 * int(line.get("passed", 0))


## Hitting Score for one game: hits, homers, walks and runs up, strikeouts down.
static func hitting_score(line: Dictionary) -> int:
	return 50 + 6 * int(line.get("h", 0)) + 8 * int(line.get("hr", 0)) + 3 * int(line.get("bb", 0)) + 2 * int(line.get("r", 0)) - 4 * int(line.get("k", 0))


static func ip_text(outs: int) -> String:
	return "%d.%d" % [outs / 3, outs % 3]


## Put a finished game in the book. Returns {"score", "rank" (1 = best on its board, 0 = not on it),
## "personal_best": bool, "key"}.
func record_game(config: GameConfig, line: Dictionary, when: float = -1.0) -> Dictionary:
	var key := config.leaderboard_key()
	var fielding := String(line.get("kind", "pitching")) == "fielding"
	var hitting := String(line.get("kind", "pitching")) == "hitting"
	var score := fielding_score(line) if fielding else (hitting_score(line) if hitting else game_score(line))
	var t := when if when >= 0.0 else Time.get_unix_time_from_system()
	games.append({"t": t, "key": key, "title": config.title(), "line": line, "score": score})
	while games.size() > MAX_GAMES:
		games.pop_front()
	_add_totals(line)
	var out := {"score": score, "rank": 0, "personal_best": false, "key": key}
	if key != "":
		_prune_daily(key)
		var board: Array = boards.get(key, [])
		out.personal_best = board.is_empty() or score > int(board[0].score)
		board.append({"score": score, "t": t, "line": line})
		board.sort_custom(func(a, b): return int(a.score) > int(b.score))
		while board.size() > TOP_KEPT:
			board.pop_back()
		boards[key] = board
		for i in board.size():
			if board[i].t == t and int(board[i].score) == score:
				out.rank = i + 1
				break
	return out


## Daily boards pile up one per day: keep the last two weeks.
const DAILY_KEPT := 14


func _prune_daily(new_key: String) -> void:
	if not new_key.begins_with("Daily/"):
		return
	var days := {}
	for k in boards.keys():
		if String(k).begins_with("Daily/"):
			days[int(String(k).split("/")[1])] = true
	days[int(new_key.split("/")[1])] = true
	var sorted_days: Array = days.keys()
	sorted_days.sort()
	while sorted_days.size() > DAILY_KEPT:
		var old: int = sorted_days.pop_front()
		for k in boards.keys():
			if String(k).begins_with("Daily/%d/" % old):
				boards.erase(k)


func _add_totals(line: Dictionary) -> void:
	if String(line.get("kind", "pitching")) == "hitting":
		totals["h_games"] = int(totals.get("h_games", 0)) + 1
		for k in ["pa", "h", "hr", "k", "bb", "r"]:
			totals["h_" + k] = int(totals.get("h_" + k, 0)) + int(line.get(k, 0))
		totals["h_ev_max"] = maxf(float(totals.get("h_ev_max", 0.0)), float(line.get("ev_max", 0.0)))
		return
	if String(line.get("kind", "pitching")) == "fielding":
		totals["f_games"] = int(totals.get("f_games", 0)) + 1
		for k in ["chances", "caught", "missed", "errors", "assists"]:
			totals["f_" + k] = int(totals.get("f_" + k, 0)) + int(line.get(k, 0))
		return
	var bat = line.get("bat", {})
	if bat is Dictionary and not (bat as Dictionary).is_empty():
		# What you did at the plate in a two-way game counts toward your lifetime batting.
		for k in ["h", "hr", "k", "bb"]:
			totals["h_" + k] = int(totals.get("h_" + k, 0)) + int(bat.get(k, 0))
		totals["h_r"] = int(totals.get("h_r", 0)) + int(bat.get("rbi", 0))
	totals["games"] = int(totals.get("games", 0)) + 1
	var types: Dictionary = totals.get("types", {})
	var lt = line.get("types", {})
	if lt is Dictionary:
		for kind in lt:
			var t: Dictionary = types.get(kind, {"n": 0, "strikes": 0, "whiffs": 0, "swings": 0, "mph_sum": 0.0, "mph_max": 0.0})
			var x: Dictionary = lt[kind]
			t["n"] = int(t.n) + int(x.get("n", 0))
			t["strikes"] = int(t.strikes) + int(x.get("strikes", 0))
			t["whiffs"] = int(t.whiffs) + int(x.get("whiffs", 0))
			t["swings"] = int(t.swings) + int(x.get("swings", 0))
			t["mph_sum"] = float(t.mph_sum) + float(x.get("mph_sum", 0.0))
			t["mph_max"] = maxf(float(t.mph_max), float(x.get("mph_max", 0.0)))
			types[kind] = t
		totals["types"] = types
	if bool(line.get("won", false)):
		totals["wins"] = int(totals.get("wins", 0)) + 1
	elif bool(line.get("lost", false)):
		totals["losses"] = int(totals.get("losses", 0)) + 1
	for k in ["signs", "sign_hits"]:
		totals[k] = int(totals.get(k, 0)) + int(line.get(k, 0))
	for k in ["outs", "pitches", "strikes", "k", "bb", "h", "r", "hr"]:
		totals[k] = int(totals.get(k, 0)) + int(line.get(k, 0))
	totals["max_mph"] = maxf(float(totals.get("max_mph", 0.0)), float(line.get("max_mph", 0.0)))


## Lifetime numbers per pitch type, most thrown first: [{"kind", "n", "strike_pct", "whiff_pct", "mph_avg", "mph_max"}].
func type_lines(n: int = 6) -> Array:
	var out: Array = []
	var types: Dictionary = totals.get("types", {})
	for kind in types:
		var t: Dictionary = types[kind]
		var cnt := maxi(int(t.n), 1)
		out.append({"kind": kind, "n": int(t.n), "strike_pct": 100.0 * float(t.strikes) / cnt,
			"whiff_pct": 100.0 * float(t.whiffs) / maxf(float(t.swings), 1.0) if int(t.swings) > 0 else -1.0,
			"mph_avg": float(t.mph_sum) / cnt, "mph_max": float(t.mph_max)})
	out.sort_custom(func(a, b): return int(a.n) > int(b.n))
	return out.slice(0, n)


## The last `n` finished games, newest first: {"t", "key", "title", "line", "score"}.
func recent(n: int = 8) -> Array:
	var out: Array = games.duplicate()
	out.reverse()
	return out.slice(0, n)


func top(key: String, n: int = 5) -> Array:
	var board: Array = boards.get(key, [])
	return board.slice(0, n)


func keys_played() -> Array:
	var out: Array = boards.keys()
	out.sort()
	return out


## A one-line summary of the lifetime totals for the stats screen.
func lifetime_lines() -> Array:
	var g := int(totals.get("games", 0))
	var fg := int(totals.get("f_games", 0))
	var hg := int(totals.get("h_games", 0))
	var hit_line: Array = [] if hg == 0 else ["Hitting: %d games, %d H, %d HR, %d K, hardest %.0f mph" % [hg, int(totals.get("h_h", 0)), int(totals.get("h_hr", 0)), int(totals.get("h_k", 0)), float(totals.get("h_ev_max", 0.0))]]
	if g == 0 and fg == 0 and hg == 0:
		return ["No games finished yet"]
	if g == 0 and fg == 0:
		return hit_line
	if g == 0:
		return ["Fielding: %d games, %d of %d caught, %d errors" % [fg, int(totals.get("f_caught", 0)), int(totals.get("f_chances", 0)), int(totals.get("f_errors", 0))]]
	var pitches := int(totals.get("pitches", 0))
	var strike_pct := 100.0 * float(totals.get("strikes", 0)) / maxf(pitches, 1)
	return [
		"%d games, %d-%d" % [g, int(totals.get("wins", 0)), int(totals.get("losses", 0))],
		"%s IP, %d K, %d BB" % [ip_text(int(totals.get("outs", 0))), int(totals.get("k", 0)), int(totals.get("bb", 0))],
		"%d H, %d R, %d HR" % [int(totals.get("h", 0)), int(totals.get("r", 0)), int(totals.get("hr", 0))],
		"%d pitches, %.0f%% strikes, top %.0f mph" % [pitches, strike_pct, float(totals.get("max_mph", 0.0))],
	] + ([] if int(totals.get("signs", 0)) == 0 else ["Catcher signs: %d of %d hit" % [int(totals.get("sign_hits", 0)), int(totals.get("signs", 0))]]) + ([] if fg == 0 else ["Fielding: %d games, %d of %d caught, %d errors" % [fg, int(totals.get("f_caught", 0)), int(totals.get("f_chances", 0)), int(totals.get("f_errors", 0))]])


## Stars (0-3) and tries for a challenge, 0 / 0 if never tried.
func challenge(id: String) -> Dictionary:
	return challenges.get(id, {"best": 0, "attempts": 0, "wins": 0, "best_pitches": 0})


## Record one attempt of a challenge: `stars` 0 means it failed.
func record_challenge(id: String, stars: int, pitches: int) -> Dictionary:
	var c: Dictionary = challenge(id).duplicate()
	c["attempts"] = int(c.attempts) + 1
	var first_win := stars > 0 and int(c.wins) == 0
	if stars > 0:
		c["wins"] = int(c.wins) + 1
		c["best_pitches"] = pitches if int(c.best_pitches) == 0 else mini(int(c.best_pitches), pitches)
	var improved := stars > int(c.best)
	c["best"] = maxi(int(c.best), stars)
	challenges[id] = c
	return {"improved": improved, "first_win": first_win, "best": c.best}


# ------------------------------------------------------------------ saving
func to_dict() -> Dictionary:
	return {"version": VERSION, "games": games, "boards": boards, "totals": totals, "challenges": challenges}


static func from_dict(d: Dictionary) -> PlayerProfile:
	var p := PlayerProfile.new()
	var g = d.get("games", [])
	if g is Array:
		for x in g:
			if x is Dictionary and x.has("line") and x.has("score"):
				p.games.append(x)
	var b = d.get("boards", {})
	if b is Dictionary:
		for k in b:
			if b[k] is Array:
				var rows: Array = []
				for r in b[k]:
					if r is Dictionary and r.has("score") and r.has("t"):
						rows.append(r)
				p.boards[String(k)] = rows
	var t = d.get("totals", {})
	if t is Dictionary:
		p.totals = t
	var c = d.get("challenges", {})
	if c is Dictionary:
		for k in c:
			if c[k] is Dictionary:
				p.challenges[String(k)] = c[k]
	return p


func save(path: String = "") -> bool:
	if path == "":
		path = save_path
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("PlayerProfile: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(to_dict()))
	return true


static func load_from(path: String = PATH) -> PlayerProfile:
	if not FileAccess.file_exists(path):
		return PlayerProfile.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PlayerProfile.new()
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
		return from_dict(json.data)
	return PlayerProfile.new()
