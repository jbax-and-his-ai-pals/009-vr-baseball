class_name Career
extends RefCounted
## One season of you as a pitcher in the fictional league: a created pitcher whose ratings grow with
## use, one start per matchday against a league opponent, every other game decided quickly, and a
## standings table. Saved to user://career.json.
##
## Ratings never gate the physics of your throws; they set how fast you tire (stamina) and how
## forgiving your aim funnel is (command), so a veteran is a little easier to throw strikes with.
##
##   var c := Career.create("Cal Reyes", "Control", 10, 3, 42)
##   c.user_team()  c.opponent_team()          # the two teams for this start
##   c.finish_start(line, my_runs, their_runs)  # after the game: the season moves on
##   c.save()

const PATH := "user://career.json"
const VERSION := 1
const BUILDS := {
	"Balanced": {"velocity": 50.0, "command": 50.0, "movement": 50.0, "stamina": 50.0},
	"Power": {"velocity": 62.0, "command": 44.0, "movement": 50.0, "stamina": 46.0},
	"Control": {"velocity": 44.0, "command": 62.0, "movement": 48.0, "stamina": 46.0},
	"Workhorse": {"velocity": 48.0, "command": 48.0, "movement": 48.0, "stamina": 66.0},
}
const NAMES := ["Cal Reyes", "Idris Okafor", "Mateo Brandt", "Rowan Quill", "Kai Takeda", "Felix Alvarado"]
const RATING_CAP := 92.0

var pitcher_name := "Cal Reyes"
var build := "Balanced"
var throws_right := true
var innings_per_start := 3
var matchday := 0                 # the next start's matchday (0-based)
var league: League
var ratings := {}                 # velocity, command, movement, stamina
var starts: Array = []            # your finished starts: {"md", "opp", "line", "won", "my_runs", "their_runs"}
var save_path := PATH
var repertoire: Array[String] = ["Fastball", "Curveball", "Slider", "Changeup"]     # the pitches you have learned
var arsenal: Dictionary = {}      # pitch name -> {"n", "strikes"}: every pitch you have thrown in the career (the pitch lab's names)

## A pitch you throw often enough, and for strikes often enough, becomes part of your arsenal.
const LEARN_MIN_THROWN := 15
const LEARN_MIN_STRIKE_PCT := 40.0
const LEARNABLE := ["Cutter", "Sinker", "Two-seam", "Splitter", "Slurve", "Knuckleball"]
const LEARN_BONUS := 1.0          # movement rating a new pitch is worth


static func create(name: String, build_name: String, season_matchdays: int, innings: int, season_seed: int, right_handed := true) -> Career:
	var c := Career.new()
	c.pitcher_name = name
	c.build = build_name if BUILDS.has(build_name) else "Balanced"
	c.throws_right = right_handed
	c.innings_per_start = innings if innings in GameConfig.INNINGS else 3
	c.league = League.create(season_seed, season_matchdays)
	c.ratings = (BUILDS[c.build] as Dictionary).duplicate()
	return c


func is_over() -> bool:
	return matchday >= league.matchdays


func opponent_index() -> int:
	return league.opponent(matchday)


func opponent_name() -> String:
	return league.team_name(opponent_index())


## Your team, with you as the starting pitcher (your ratings, your name).
func user_team() -> Team:
	var t := league.team(League.USER)
	var p := pitcher_player()
	t.alignment[1] = p
	var order: Array[Player] = []
	for x in t.lineup:
		order.append(p if x.position == 1 else x)
	t.lineup = order
	return t


func opponent_team() -> Team:
	return league.team(opponent_index())


func pitcher_player() -> Player:
	var p := Player.new()
	p.name = pitcher_name
	p.number = 17
	p.position = 1
	p.throws_right = throws_right
	for k in ratings:
		p.set(k, float(ratings[k]))
	var rep: Array[String] = repertoire.duplicate()
	p.repertoire = rep
	return p


## What the pitch lab called a pitch, as a name in the arsenal (a four-seam is a fastball).
static func family(label: String) -> String:
	return "Fastball" if label == "Four-seam" else label


## A start's pitches go in the arsenal; any learnable one thrown enough, for strikes, is learned (and adds a little
## movement). Returns the names learned this time.
func learn_from(line: Dictionary) -> Array:
	var types = line.get("types", {})
	var learned: Array = []
	if not (types is Dictionary):
		return learned
	for label in types:
		var kind := family(String(label))
		var x: Dictionary = types[label]
		var a: Dictionary = arsenal.get(kind, {"n": 0, "strikes": 0})
		a["n"] = int(a.n) + int(x.get("n", 0))
		a["strikes"] = int(a.strikes) + int(x.get("strikes", 0))
		arsenal[kind] = a
	for kind in LEARNABLE:
		if repertoire.has(kind) or not arsenal.has(kind):
			continue
		var a: Dictionary = arsenal[kind]
		if int(a.n) >= LEARN_MIN_THROWN and 100.0 * float(a.strikes) / float(a.n) >= LEARN_MIN_STRIKE_PCT:
			repertoire.append(kind)
			ratings["movement"] = clampf(float(ratings.movement) + LEARN_BONUS, 15.0, RATING_CAP)
			learned.append(kind)
	return learned


## How forgiving your aim funnel is: 1.0 at command 50, tighter for a veteran, looser for a rookie.
func funnel_factor() -> float:
	return clampf(1.25 - float(ratings.command) / 200.0, 0.8, 1.2)


## What a start teaches you: command from throwing strikes, stamina from a long outing, movement and
## velocity a little from every good start. Returns the changes, e.g. {"command": 0.6, ...}.
func grow(line: Dictionary) -> Dictionary:
	var pitches := maxi(int(line.get("pitches", 0)), 1)
	var strike_pct := 100.0 * float(line.get("strikes", 0)) / pitches
	var good := clampf(float(PlayerProfile.game_score(line) - 45) / 25.0, 0.0, 1.0)       # 0 for a poor start, 1 for a gem
	var deltas := {
		"command": clampf((strike_pct - 55.0) / 15.0, -0.3, 1.0),
		"stamina": minf(float(pitches) / 100.0, 1.0) * 0.8,
		"movement": 0.2 + 0.4 * good,
		"velocity": 0.1 + 0.3 * good,
	}
	var applied := {}
	for k in deltas:
		var before := float(ratings[k])
		ratings[k] = clampf(before + float(deltas[k]), 15.0, RATING_CAP)
		applied[k] = snappedf(float(ratings[k]) - before, 0.01)
	return applied


## The start is over: `line` is your pitching line (see PlayerProfile.game_score), `my_runs` and
## `their_runs` the final score. Grows you, decides the rest of the matchday, moves the season on.
func finish_start(line: Dictionary, my_runs: int, their_runs: int) -> Dictionary:
	var opp := opponent_index()
	var deltas := grow(line)
	var learned := learn_from(line)
	league.play_matchday(matchday, my_runs, their_runs)
	var won := my_runs > their_runs
	starts.append({"md": matchday, "opp": opp, "line": line, "won": won, "my_runs": my_runs, "their_runs": their_runs})
	matchday += 1
	return {"won": won, "deltas": deltas, "rank": league.rank_of(League.USER), "over": is_over(), "opponent": league.team_name(opp), "learned": learned}


## Your season line, summed over your starts.
func season_totals() -> Dictionary:
	var t := {"starts": starts.size(), "w": 0, "l": 0, "outs": 0, "k": 0, "bb": 0, "h": 0, "r": 0, "pitches": 0}
	for s in starts:
		if bool(s.won):
			t.w += 1
		else:
			t.l += 1
		for k in ["outs", "k", "bb", "h", "r", "pitches"]:
			t[k] += int(s.line.get(k, 0))
	return t


func to_dict() -> Dictionary:
	return {"version": VERSION, "name": pitcher_name, "build": build, "throws_right": throws_right,
		"innings": innings_per_start, "matchday": matchday, "ratings": ratings, "starts": starts, "league": league.to_dict(),
		"repertoire": repertoire, "arsenal": arsenal}


static func from_dict(d: Dictionary) -> Career:
	var ld = d.get("league", {})
	var c := Career.create(str(d.get("name", "Cal Reyes")), str(d.get("build", "Balanced")), int((ld as Dictionary).get("matchdays", 10)) if ld is Dictionary else 10,
		int(d.get("innings", 3)), int((ld as Dictionary).get("seed", 1)) if ld is Dictionary else 1, bool(d.get("throws_right", true)))
	if ld is Dictionary:
		c.league = League.from_dict(ld)
	c.matchday = clampi(int(d.get("matchday", 0)), 0, c.league.matchdays)
	var r = d.get("ratings", {})
	if r is Dictionary:
		for k in c.ratings:
			if r.has(k) and (r[k] is float or r[k] is int):
				c.ratings[k] = clampf(float(r[k]), 15.0, RATING_CAP)
	var rp = d.get("repertoire", [])
	if rp is Array:
		for k in rp:
			if String(k) in LEARNABLE and not c.repertoire.has(String(k)):
				c.repertoire.append(String(k))
	var ar = d.get("arsenal", {})
	if ar is Dictionary:
		for k in ar:
			if ar[k] is Dictionary:
				c.arsenal[String(k)] = {"n": int(ar[k].get("n", 0)), "strikes": int(ar[k].get("strikes", 0))}
	var ss = d.get("starts", [])
	if ss is Array:
		for s in ss:
			if s is Dictionary and s.has("line") and s.has("won"):
				c.starts.append(s)
	return c


func save(path: String = "") -> bool:
	var f := FileAccess.open(path if path != "" else save_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	return true


## The saved career, or null if there is none (or the file is damaged).
static func load_from(path: String = PATH) -> Career:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
		return from_dict(json.data)
	return null


static func delete_saved(path: String = PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
