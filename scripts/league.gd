class_name League
extends RefCounted
## A small fictional league: eight teams, a double round-robin schedule, standings, and a quick
## way to decide the games you are not playing. Pure data and rules: no scene, so it is testable.
##
## Your team is always team 0 and always the home side in your own games (you pitch the top half).
## Every team plays every matchday, so a season of L matchdays is L games for each team.

const TEAM_COUNT := 8
const MAX_MATCHDAYS := 14                  # a double round robin among 8
const USER := 0

## name, jersey, cap
const TEAMS := [
	["Your Team", Color(0.12, 0.17, 0.50), Color(0.12, 0.17, 0.50)],
	["Harbor Gulls", Color(0.10, 0.45, 0.62), Color(0.96, 0.96, 0.98)],
	["Ridgeline Rams", Color(0.55, 0.18, 0.15), Color(0.92, 0.80, 0.30)],
	["Copperfield Foxes", Color(0.82, 0.42, 0.10), Color(0.15, 0.15, 0.18)],
	["Marsh Herons", Color(0.20, 0.50, 0.32), Color(0.95, 0.95, 0.90)],
	["Summit Peaks", Color(0.35, 0.30, 0.60), Color(0.90, 0.90, 0.95)],
	["Dunes Scorpions", Color(0.76, 0.62, 0.30), Color(0.20, 0.14, 0.08)],
	["Lakeside Loons", Color(0.15, 0.20, 0.30), Color(0.85, 0.20, 0.25)],
]

var seed_value := 1
var quality: Array[float] = []             # team strength, 50 = average
var matchdays := 10
## Every game played so far: {"md", "home", "away", "home_runs", "away_runs"}.
var results: Array = []


static func create(season_seed: int, season_matchdays: int = 10) -> League:
	var l := League.new()
	l.seed_value = season_seed
	l.matchdays = clampi(season_matchdays, 2, MAX_MATCHDAYS)
	var rng := RandomNumberGenerator.new()
	rng.seed = season_seed
	# Strengths: a spread from about 43 to 59, shuffled; your team is average (you are the difference).
	var q: Array[float] = []
	for i in TEAM_COUNT - 1:
		q.append(43.0 + 16.0 * float(i) / float(TEAM_COUNT - 2))
	for i in range(q.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := q[i]
		q[i] = q[j]
		q[j] = t
	l.quality = [50.0]
	l.quality.append_array(q)
	return l


func team_name(i: int) -> String:
	return String(TEAMS[i][0])


## A team's players (the same every time for a given league seed).
func team(i: int) -> Team:
	var t := Team.generate(team_name(i), quality[i], seed_value * 31 + i * 7 + 3)
	t.jersey = TEAMS[i][1]
	t.cap = TEAMS[i][2]
	return t


## The pairings of one matchday as [[home, away], ...]: the circle method, so over seven matchdays
## everybody meets everybody once, and the second seven repeat it with the sides swapped. Team 0 is
## always the home side.
func pairings(matchday: int) -> Array:
	var n := TEAM_COUNT
	var md := matchday % (n - 1)
	var ring: Array = []
	for i in range(1, n):
		ring.append(i)
	var rot: Array = []
	for i in ring.size():
		rot.append(ring[(i + md) % ring.size()])
	var seq: Array = [0] + rot
	var out: Array = []
	for i in n / 2:
		var a: int = seq[i]
		var b: int = seq[n - 1 - i]
		var flip := (matchday / (n - 1)) % 2 == 1
		var home := b if flip else a
		var away := a if flip else b
		if a == USER or b == USER:
			home = USER
			away = b if a == USER else a
		out.append([home, away])
	return out


## Who your team plays on this matchday.
func opponent(matchday: int) -> int:
	for p in pairings(matchday):
		if p[0] == USER:
			return int(p[1])
	return 1


## A quick, rating-based score for a game nobody plays: runs are Poisson around 4.3 shifted by the
## strength gap (and a small home edge); a tie goes to extra runs for the stronger side.
func quick_game(home: int, away: int, rng: RandomNumberGenerator) -> Array:
	var gap := quality[home] - quality[away]
	var h := _poisson(4.3 * exp(0.012 * gap) * 1.03, rng)
	var a := _poisson(4.3 * exp(-0.012 * gap) / 1.03, rng)
	while h == a:
		if rng.randf() < 0.5 + 0.005 * gap:
			h += 1
		else:
			a += 1
	return [h, a]


static func _poisson(mean: float, rng: RandomNumberGenerator) -> int:
	var l := exp(-mean)
	var k := 0
	var p := 1.0
	while true:
		k += 1
		p *= rng.randf()
		if p <= l:
			break
	return k - 1


## Decide every game of a matchday except your own, using the given result for yours.
func play_matchday(matchday: int, user_home_runs: int, user_away_runs: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 1009 + matchday
	for p in pairings(matchday):
		var home: int = p[0]
		var away: int = p[1]
		var score: Array = [user_home_runs, user_away_runs] if home == USER else quick_game(home, away, rng)
		results.append({"md": matchday, "home": home, "away": away, "home_runs": int(score[0]), "away_runs": int(score[1])})


## Standings, best first: wins, then run difference, then runs scored.
func standings() -> Array:
	var rows: Array = []
	for i in TEAM_COUNT:
		rows.append({"team": i, "name": team_name(i), "w": 0, "l": 0, "rs": 0, "ra": 0})
	for r in results:
		var h: Dictionary = rows[int(r.home)]
		var a: Dictionary = rows[int(r.away)]
		h.rs += int(r.home_runs)
		h.ra += int(r.away_runs)
		a.rs += int(r.away_runs)
		a.ra += int(r.home_runs)
		if int(r.home_runs) > int(r.away_runs):
			h.w += 1
			a.l += 1
		else:
			a.w += 1
			h.l += 1
	rows.sort_custom(func(x, y):
		if x.w != y.w:
			return x.w > y.w
		var dx: int = x.rs - x.ra
		var dy: int = y.rs - y.ra
		if dx != dy:
			return dx > dy
		return x.rs > y.rs)
	for i in rows.size():
		rows[i]["rank"] = i + 1
	return rows


func rank_of(team_index: int) -> int:
	for r in standings():
		if int(r.team) == team_index:
			return int(r.rank)
	return 0


func to_dict() -> Dictionary:
	return {"seed": seed_value, "matchdays": matchdays, "results": results}


static func from_dict(d: Dictionary) -> League:
	var l := League.create(int(d.get("seed", 1)), int(d.get("matchdays", 10)))
	var rs = d.get("results", [])
	if rs is Array:
		for r in rs:
			if r is Dictionary and r.has("home") and r.has("away") and r.has("home_runs") and r.has("away_runs"):
				l.results.append({"md": int(r.get("md", 0)), "home": int(r.home) % TEAM_COUNT, "away": int(r.away) % TEAM_COUNT,
					"home_runs": int(r.home_runs), "away_runs": int(r.away_runs)})
	return l
