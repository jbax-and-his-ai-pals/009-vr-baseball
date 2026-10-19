class_name Scenario
extends RefCounted
## A challenge: a made-up situation with one job to do ("bases loaded, nobody out, 9th, up by one:
## get out of it"), judged as the game goes on, and scored in stars (0 failed, 1-3 how cleanly).
## Pure rules: it reads a GameState and the event it just produced, so it is tested without a scene.
##
##   var s := Scenario.by_id("escape")
##   s.apply(game, lineup)          # set the inning, outs, runners, count and score
##   s.on_pitch("corner", true)     # per pitch that reached the plate (location kind, strike)
##   s.update(game, ev)             # after every event; returns "running" | "success" | "fail"
##   s.stars                        # 0-3 once it has finished
##
## Rules: "hold" (finish the half inning without giving up more than allowed), "ks" (strike out N
## in a row, no one on), "pickoff" (get a runner out on the bases within N pitches), "corners"
## (N corner strikes within M pitches), "nohit" (no hits over the game).

var id := ""
var title := ""
var goal := ""
var setup := {}
var rule := ""
var params := {}
var state := "running"
var stars := 0
var pitches := 0                    # pitches thrown since it began

var _start := {}
var _corners := 0
var _last_text := ""


static func catalog() -> Array[Scenario]:
	var out: Array[Scenario] = []
	out.append(_make("escape", "Escape the jam", "Bases loaded, nobody out, 9th inning, up by one. Do not let a run score.",
		{"inning": 9, "innings": 9, "outs": 0, "bases": [true, true, true], "runs": 3, "home_score": 4},
		"hold", {"allow_runs": 0, "stars": [14, 22]}))
	out.append(_make("side", "Strike out the side", "Three batters, three strikeouts. Nobody on, nobody out.",
		{"inning": 3, "innings": 9, "outs": 0, "bases": [false, false, false], "runs": 0, "home_score": 0},
		"ks", {"need": 3, "stars": [11, 16]}))
	out.append(_make("pickoff", "Pick him off", "A fast runner on first, and he wants to go. Get him out on the bases within 10 pitches.",
		{"inning": 5, "innings": 9, "outs": 1, "bases": [true, false, false], "runs": 0, "home_score": 0},
		"pickoff", {"max_pitches": 10, "stars": [4, 7], "fast_runner": true}))
	out.append(_make("corners", "Paint the corners", "Hit the gold corners of the zone: 5 corner strikes in 14 pitches.",
		{"inning": 1, "innings": 9, "outs": 0, "bases": [false, false, false], "runs": 0, "home_score": 0},
		"corners", {"need": 5, "max_pitches": 14, "stars": [9, 12]}))
	out.append(_make("lead", "Protect the lead", "Two outs in the 9th, runner on third, up by one. One more out, no run.",
		{"inning": 9, "innings": 9, "outs": 2, "bases": [false, false, true], "runs": 2, "home_score": 3},
		"hold", {"allow_runs": 0, "stars": [4, 8]}))
	out.append(_make("nohit", "No-hitter (3 innings)", "Three innings, no hits. Walks are allowed, but they cost you stars.",
		{"inning": 1, "innings": 3, "outs": 0, "bases": [false, false, false], "runs": 0, "home_score": 0},
		"nohit", {}))
	return out


static func by_id(scenario_id: String) -> Scenario:
	for s in catalog():
		if s.id == scenario_id:
			return s
	return null


static func ids() -> Array:
	var out: Array = []
	for s in catalog():
		out.append(s.id)
	return out


static func _make(sid: String, t: String, g: String, setup_dict: Dictionary, rule_name: String, p: Dictionary) -> Scenario:
	var s := Scenario.new()
	s.id = sid
	s.title = t
	s.goal = g
	s.setup = setup_dict
	s.rule = rule_name
	s.params = p
	return s


## Put the game in the starting situation. `lineup` supplies the runners (a real Player is needed:
## the running game reads their speed and aggression).
func apply(game: GameState, lineup: Array) -> void:
	game.innings = int(setup.get("innings", game.innings))
	game.inning = int(setup.get("inning", 1))
	game.outs = int(setup.get("outs", 0))
	game.balls = 0
	game.strikes = 0
	game.runs = int(setup.get("runs", 0))
	game.home_score = int(setup.get("home_score", 0))
	game.inning_runs.clear()
	game.home_inning_runs.clear()
	for i in game.inning - 1:
		game.inning_runs.append(0)
		game.home_inning_runs.append(0)
	# Runners: the fastest in the lineup if the challenge is about a runner going; otherwise ordinary ones.
	var pool: Array = lineup.duplicate()
	if bool(params.get("fast_runner", false)):
		pool.sort_custom(func(a, b): return float(a.speed) > float(b.speed))
	var bases_cfg: Array = setup.get("bases", [false, false, false])
	var k := 0
	for i in 3:
		game.bases[i] = null
		if bool(bases_cfg[i]) and not pool.is_empty():
			game.bases[i] = pool[k % pool.size()]
			k += 1
	_start = _counters(game)
	state = "running"
	stars = 0
	pitches = 0
	_corners = 0


func _counters(g: GameState) -> Dictionary:
	return {"k": g.strikeouts, "outs": g.outs_recorded, "h": g.hits, "bb": g.walks, "hbp": g.hit_by_pitches, "runs": g.runs,
		"pitches": g.pitch_count, "po": g.pickoffs, "cs": g.caught_stealing, "sb": g.stolen_bases, "e": g.errors}


## A pitch reached the plate (not one put in play): where it crossed (PitchLocation kind) and the call.
func on_pitch(location_kind: String, was_strike: bool) -> void:
	if state == "running" and was_strike and location_kind == "corner":
		_corners += 1


func _d(g: GameState, key: String) -> int:
	var now := _counters(g)
	return int(now[key]) - int(_start[key])


## Judge the game after an event. Returns the state.
func update(game: GameState, ev: Dictionary) -> String:
	if state != "running":
		return state
	pitches = _d(game, "pitches")
	match rule:
		"hold":
			if _d(game, "runs") > int(params.get("allow_runs", 0)):
				_finish(0)
			elif bool(ev.get("half_over", false)) or game.over:
				_finish(_stars_by_pitches())
		"ks":
			var ks := _d(game, "k")
			var spoiled := _d(game, "h") + _d(game, "bb") + _d(game, "hbp") + _d(game, "e") > 0 or _d(game, "outs") > ks
			if spoiled:
				_finish(0)
			elif ks >= int(params.need):
				_finish(_stars_by_pitches())
		"pickoff":
			if _d(game, "po") + _d(game, "cs") >= 1:
				_finish(_stars_by_pitches())
			elif _d(game, "sb") >= 1 or pitches >= int(params.max_pitches):
				_finish(0)
		"corners":
			if _corners >= int(params.need):
				_finish(_stars_by_pitches())
			elif pitches >= int(params.max_pitches):
				_finish(0)
		"nohit":
			if _d(game, "h") > 0:
				_finish(0)
			elif game.over:
				var walks := _d(game, "bb") + _d(game, "hbp")
				_finish(3 if walks == 0 else (2 if walks <= 2 else 1))
	return state


func _stars_by_pitches() -> int:
	var t: Array = params.get("stars", [])
	if t.size() < 2:
		return 3
	return 3 if pitches <= int(t[0]) else (2 if pitches <= int(t[1]) else 1)


func _finish(s: int) -> void:
	stars = s
	state = "success" if s > 0 else "fail"


## Where you stand, for the board ("Strikeouts 1 of 3").
func progress_text(game: GameState) -> String:
	match rule:
		"hold":
			return "Runs allowed %d of %d" % [_d(game, "runs"), int(params.get("allow_runs", 0))] if state == "running" else _result_text()
		"ks":
			return "Strikeouts %d of %d" % [_d(game, "k"), int(params.need)] if state == "running" else _result_text()
		"pickoff":
			return "Pitches %d of %d" % [pitches, int(params.max_pitches)] if state == "running" else _result_text()
		"corners":
			return "Corners %d of %d (pitches %d of %d)" % [_corners, int(params.need), pitches, int(params.max_pitches)] if state == "running" else _result_text()
		"nohit":
			return "Hits allowed %d" % _d(game, "h") if state == "running" else _result_text()
	return ""


func _result_text() -> String:
	if state == "success":
		return "DONE - %s in %d pitches" % ["*".repeat(stars) if stars > 0 else "", pitches]
	return "FAILED"


static func stars_text(n: int) -> String:
	return "*".repeat(n) + "-".repeat(3 - n)
