class_name StatsTracker
extends RefCounted
## Aggregate stats for the boards: what you threw (by pitch type) and how the lineup hit.
## Pure bookkeeping, fed by the game as things happen.
##
##   record_pitch(kind, mph, outcome)       outcome: ball | called_strike | swinging_strike |
##                                          foul | in_play
##   record_result(batter, result, ev, m)   result: single | double | triple | inside_park_hr |
##                                          home_run | error | out | walk | strikeout
##                                          ev = exit velocity (mph), m = distance (m)

var pitches := 0
var by_type := {}          # kind -> {n, strikes, whiffs, swings, balls, in_play, mph_sum, mph_max}
var last_pitch := {}       # kind, mph, outcome
var batters := {}          # name -> {pa, ab, h, d, t, hr, bb, k, ev_max}
var batter_order: Array[String] = []
var ev_sum := 0.0
var ev_count := 0
var ev_max := 0.0
var longest := 0.0
var hardest_name := ""


func reset() -> void:
	pitches = 0
	by_type.clear()
	last_pitch = {}
	batters.clear()
	batter_order.clear()
	ev_sum = 0.0
	ev_count = 0
	ev_max = 0.0
	longest = 0.0
	hardest_name = ""


func record_pitch(kind: String, mph: float, outcome: String) -> void:
	pitches += 1
	var t: Dictionary = by_type.get(kind, {"n": 0, "strikes": 0, "whiffs": 0, "swings": 0, "balls": 0,
		"in_play": 0, "mph_sum": 0.0, "mph_max": 0.0})
	t.n += 1
	t.mph_sum += mph
	t.mph_max = maxf(t.mph_max, mph)
	match outcome:
		"ball":
			t.balls += 1
		"called_strike":
			t.strikes += 1
		"swinging_strike":
			t.strikes += 1
			t.whiffs += 1
			t.swings += 1
		"foul":
			t.strikes += 1
			t.swings += 1
		"in_play":
			t.strikes += 1
			t.swings += 1
			t.in_play += 1
	by_type[kind] = t
	last_pitch = {"kind": kind, "mph": mph, "outcome": outcome}


func _batter(name: String) -> Dictionary:
	if not batters.has(name):
		batters[name] = {"pa": 0, "ab": 0, "h": 0, "d": 0, "t": 0, "hr": 0, "bb": 0, "k": 0, "ev_max": 0.0}
		batter_order.append(name)
	return batters[name]


## Make sure a batter has a row (so the lineup shows before anyone has batted).
func add_batter(name: String) -> void:
	_batter(name)


func record_result(name: String, result: String, ev: float = 0.0, meters: float = 0.0) -> void:
	var b := _batter(name)
	b.pa += 1
	match result:
		"walk", "hit_by_pitch":
			b.bb += 1
		"sacrifice":
			pass                  # a plate appearance, not an at-bat
		"strikeout":
			b.ab += 1
			b.k += 1
		"single":
			b.ab += 1
			b.h += 1
		"double":
			b.ab += 1
			b.h += 1
			b.d += 1
		"triple":
			b.ab += 1
			b.h += 1
			b.t += 1
		"home_run", "inside_park_hr":
			b.ab += 1
			b.h += 1
			b.hr += 1
		_:
			b.ab += 1            # outs and errors are at-bats
	if ev > 0.0:
		ev_sum += ev
		ev_count += 1
		b.ev_max = maxf(b.ev_max, ev)
		if ev > ev_max:
			ev_max = ev
			hardest_name = name
	longest = maxf(longest, meters)


# --------------------------------------------------------------------- derived
func strike_pct(t: Dictionary) -> float:
	return 100.0 * float(t.strikes) / maxf(float(t.n), 1.0)


func whiff_pct(t: Dictionary) -> float:
	return 100.0 * float(t.whiffs) / maxf(float(t.swings), 1.0)


func avg_mph(t: Dictionary) -> float:
	return float(t.mph_sum) / maxf(float(t.n), 1.0)


## Pitch types, most thrown first.
func types_sorted() -> Array[String]:
	var keys: Array[String] = []
	for k in by_type:
		keys.append(k)
	keys.sort_custom(func(a, b): return by_type[a].n > by_type[b].n)
	return keys


## Totals over every pitch.
func pitch_totals() -> Dictionary:
	var t := {"n": 0, "strikes": 0, "whiffs": 0, "swings": 0, "balls": 0, "in_play": 0, "mph_sum": 0.0, "mph_max": 0.0}
	for k in by_type:
		var x: Dictionary = by_type[k]
		for f in ["n", "strikes", "whiffs", "swings", "balls", "in_play", "mph_sum"]:
			t[f] += x[f]
		t.mph_max = maxf(t.mph_max, x.mph_max)
	return t


func batting_totals() -> Dictionary:
	var t := {"pa": 0, "ab": 0, "h": 0, "d": 0, "t": 0, "hr": 0, "bb": 0, "k": 0}
	for n in batters:
		for f in t:
			t[f] += batters[n][f]
	return t


## .xxx style average (".000" with no at-bats).
static func avg_text(h: int, ab: int) -> String:
	if ab <= 0:
		return ".000"
	var a := float(h) / ab
	if a >= 1.0:
		return "1.000"
	return ("%.3f" % a).substr(1)
