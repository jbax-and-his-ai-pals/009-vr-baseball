class_name Defense
extends RefCounted
## Turns a batted ball into a baseball result: caught for an out, fielded and thrown to first,
## a single/double/triple, an error, a foul. Pure logic (no nodes), so it can be unit tested.
##
## For each ball in play it walks the ball's recorded path and asks each fielder "could you be
## standing there by the time the ball is?" given when he starts moving (reaction), how fast he
## runs, how far he can reach and how far he can dive. The earliest interception wins. A ball in
## the air that is reached is an out; one fielded on the ground is thrown to first and either
## beats the runner or does not. If the runner beats the throw he keeps going while he can beat
## the ball to the next base.
##
## Coordinates match the game: home plate at the origin, +Z toward center field, +X toward third
## base / left field, -X toward first base / right field. Times are seconds after contact.

# Position numbers as scored: 1 P, 2 C, 3 1B, 4 2B, 5 3B, 6 SS, 7 LF, 8 CF, 9 RF.
const NAMES := {1: "P", 2: "C", 3: "1B", 4: "2B", 5: "3B", 6: "SS", 7: "LF", 8: "CF", 9: "RF"}
const BASE_DIST := 27.432
const FIRST := Vector3(-19.40, 0.0, 19.40)
const SECOND := Vector3(0.0, 0.0, 38.80)
const THIRD := Vector3(19.40, 0.0, 19.40)
const HOME := Vector3.ZERO
const GLOVE_TOP := 2.7              # highest a ball can be caught without leaving the ground
const MIN_PLAY_TIME := 0.15         # seconds after contact before any fielder can field it
const ACCEL_LOSS := 0.45            # seconds lost getting up to top speed
const COMFORT_WINDOW := 0.33        # how much later than the first reach he may settle for an easier one
const RUNNER_TIMES := [4.15, 7.55, 10.95, 14.45]   # contact -> 1st, 2nd, 3rd, home (average runner)

## A fielder: {num, name, home, speed, reaction, reach, dive, arm, transfer, glove, visible}
var fielders: Array[Dictionary] = []
var team: Team
var rng := RandomNumberGenerator.new()
var infield_in := false              # the four infielders play on the grass to cut off the run at the plate

## Where each infielder stands when the infield is in (number -> home spot): about four metres forward and a little in.
const INFIELD_IN_SPOTS := {
	3: Vector3(-16.0, 0.0, 18.0),
	4: Vector3(-8.0, 0.0, 28.0),
	5: Vector3(16.0, 0.0, 18.0),
	6: Vector3(8.0, 0.0, 28.0),
}


## Infield in: a runner on third, fewer than two outs, late, and a run that matters (the defense leads
## by at most one, or the game is tied). `lead` is the defense's runs minus the offense's.
static func wants_infield_in(outs: int, bases: Array, inning: int, lead: int) -> bool:
	return bases[2] != null and outs < 2 and inning >= 7 and lead >= -1 and lead <= 1


## Put the infield in (or back at normal depth). Fielders' positions move; ratings do not.
func set_infield_in(on: bool) -> void:
	infield_in = on
	for f in fielders:
		var base: Vector3 = f.get("base_home", f.home)
		f["base_home"] = base
		f["home"] = INFIELD_IN_SPOTS[f.num] if on and INFIELD_IN_SPOTS.has(f.num) else base


## defense_skill (0..1) is the quick way to get a whole team of the same quality (0.6 = average).
## Pass a Team to use its actual players instead.
func _init(defense_skill: float = 0.6, from_team_players: Team = null) -> void:
	rng.randomize()
	team = from_team_players
	if team == null:
		# Neutral, repeatable: position tendencies but no random spread.
		team = Team.generate("Defense", 50.0 + (defense_skill - 0.6) * 100.0, 1, 0.0)
	_build()


static func from_team(t: Team) -> Defense:
	return Defense.new(0.6, t)


## How each rating becomes a game quantity. Rating 50 is the calibrated baseline.
func _build() -> void:
	fielders.clear()
	# position: home spot, throw transfer time (s)
	var spec := {
		1: [Vector3(0.0, 0.0, 17.2), 0.50],     # the pitcher: the player on the mound, abstract
		2: [Vector3(0.0, 0.0, -1.4), 0.45],
		3: [Vector3(-17.5, 0.0, 22.5), 0.45],
		4: [Vector3(-8.5, 0.0, 32.5), 0.42],
		5: [Vector3(17.5, 0.0, 22.0), 0.44],
		6: [Vector3(8.5, 0.0, 32.5), 0.42],
		7: [Vector3(40.0, 0.0, 80.0), 0.62],
		8: [Vector3(0.0, 0.0, 98.0), 0.62],
		9: [Vector3(-40.0, 0.0, 80.0), 0.62],
	}
	for pos in range(1, 10):
		var pl: Player = team.player_at(pos)
		var home: Vector3 = spec[pos][0]
		var rng_unit := clampf(pl.fielding_range / 100.0, 0.0, 1.0)
		fielders.append({
			"num": pos, "name": NAMES[pos], "home": home, "player": pl,
			"speed": 7.5 * Player.factor(pl.speed, 0.8),
			"reaction": 0.27 - 0.20 * (rng_unit - 0.5) + (0.07 if home.z > 50.0 else 0.0),
			"reach": 1.35 + 0.6 * (rng_unit - 0.5),
			"dive": 1.15 + 1.0 * (rng_unit - 0.5),
			"arm": 33.0 * Player.factor(pl.arm, 0.7),
			"transfer": spec[pos][1],
			"glove": clampf(0.93 + 0.10 * (pl.hands / 100.0), 0.90, 0.995),
			"visible": pos != 1,
		})


func fielder_by_num(num: int) -> Dictionary:
	for f in fielders:
		if f.num == num:
			return f
	return {}


## sim: BattedBall.simulate() result. Returns the play (see end of function for keys).
## exclude: fielder numbers the AI must not use (a human plays that position).
func resolve(sim: Dictionary, batter_run: float = 1.0, exclude: Array = []) -> Dictionary:
	if sim.get("home_run", false):
		return _result("home_run", "HOME RUN", sim)
	var pts: PackedVector3Array = sim.points
	var dt: float = sim.dt
	var landing_t: float = sim.get("landing_time", 0.0)
	var fair: bool = sim.get("fair", false)
	var run_times := RUNNER_TIMES.map(func(t): return t / maxf(batter_run, 0.5))

	# 1. Who gets there first? For each fielder, the earliest path sample he can reach on foot
	#    (and, failing that, with a dive).
	var found: Array = []
	for f in fielders:
		if f.num in exclude:
			continue
		var hit := _first_reach(f, pts, dt, f.speed, f.reach)
		if hit.is_empty():
			var diving := _first_reach(f, pts, dt, f.speed + 1.2, f.reach + f.dive)
			if not diving.is_empty():
				diving["dive"] = true
				hit = diving
		if hit.is_empty():
			continue
		# A dive costs time (getting up) but is only chosen when nobody can run it down.
		hit["key"] = hit.t + (0.6 if hit.get("dive", false) else 0.0)
		hit["fielder"] = f
		hit["dist"] = Vector2(hit.pos.x - f.home.x, hit.pos.z - f.home.z).length()
		found.append(hit)
	var best := {}
	var best_t := INF
	for h in found:
		best_t = minf(best_t, h.key)
	# Fielders who can all get there at about the same time (very common under a high fly ball:
	# several can reach the same descending sample) are decided by who has to work least, then
	# who is closest: the center fielder calls off the left fielder, not whoever is first in a list.
	var field_of_candidates: Array = []
	for h in found:
		if h.key <= best_t + 0.25:
			field_of_candidates.append(h)
	if not field_of_candidates.is_empty():
		field_of_candidates.sort_custom(func(a, b):
			var na: float = 0.0 if a.need < 0.05 else a.need
			var nb: float = 0.0 if b.need < 0.05 else b.need
			if absf(na - nb) > 0.3:
				return na < nb
			if a.get("dive", false) != b.get("dive", false):
				return not a.get("dive", false)
			return a.dist < b.dist)
		best = field_of_candidates[0]

	var play: Dictionary
	if best.is_empty():
		play = _unfielded(sim, run_times, exclude)
	else:
		play = _fielded(best, sim, fair, landing_t, run_times)
	# A ball that bounced over the fence: if nobody caught it in the air or got to it before it
	# left, it is dead and everyone is awarded two bases (a ground-rule double).
	if sim.get("ground_rule", false) and play.get("result", "") != "out" 			and float(play.get("field_time", 99.0)) >= float(sim.get("total_time", 0.0)) - 0.4:
		var gr := _result("double", "Ground-rule double", sim)
		gr["bases"] = 2
		gr["ground_rule"] = true
		gr["field_pos"] = sim.get("rest_pos", Vector3.ZERO)
		gr["field_time"] = float(sim.get("total_time", 3.0))
		gr["landing_time"] = landing_t
		return gr
	# What the runners need to know about the ball: how long it was in the air.
	play["landing_time"] = landing_t
	play["apex"] = float(sim.get("apex", 0.0))
	# A fair fly ball an infielder can catch with ordinary effort: the infield fly rule may apply.
	var lp: Vector3 = sim.get("landing_pos", Vector3.ZERO)
	var shallow := Vector2(lp.x, lp.z).length() < 46.0
	var high := float(sim.get("apex", 0.0)) > 8.0 and landing_t > 1.8
	play["infield_fly"] = fair and shallow and high and not sim.get("home_run", false) \
		and int(play.get("fielder", 0)) in [0, 1, 2, 3, 4, 5, 6]
	return play


## The path sample at which f makes the play: the first one he can reach, then (within a
## third of a second) whichever he can reach most comfortably. A fielder who can get there
## early does not sprint at the very edge of his range when he can settle under it.
## A runner is not at top speed instantly: ACCEL_LOSS seconds are lost getting up to it.
func _first_reach(f: Dictionary, pts: PackedVector3Array, dt: float, speed: float, reach: float) -> Dictionary:
	var home: Vector3 = f.home
	var react: float = f.reaction
	var n := pts.size()
	var i := int(ceil(MIN_PLAY_TIME / dt))
	var found := {}
	while i < n:
		var p := pts[i]
		var t := i * dt
		if not found.is_empty() and t > found.t + COMFORT_WINDOW:
			break
		if p.y <= GLOVE_TOP:
			var d := Vector2(p.x - home.x, p.z - home.z).length()
			var avail := t - react - ACCEL_LOSS
			var travel := maxf(d - reach, 0.0)
			var ok := travel <= 0.0 or (avail > 0.0 and travel <= speed * avail)
			if ok:
				var need := 0.0 if travel <= 0.0 else travel / maxf(avail, 1e-3)
				# Stay on the same side of "in the air / on the ground" as the first sample.
				var airborne: bool = p.y > 0.30
				if found.is_empty():
					found = {"t": t, "pos": p, "need": need, "travel": travel, "index": i, "airborne": airborne}
				elif airborne == found.airborne and need < found.need - 0.05:
					found = {"t": t, "pos": p, "need": need, "travel": travel, "index": i, "airborne": airborne}
		i += 2
	return found


func _fielded(hit: Dictionary, sim: Dictionary, fair: bool, landing_t: float, run_times: Array) -> Dictionary:
	var f: Dictionary = hit.fielder
	var p: Vector3 = hit.pos
	var t: float = hit.t
	var dive: bool = hit.get("dive", false)
	var in_air: bool = p.y > 0.30 and t <= landing_t + 0.04 and sim.get("landing_time", 0.0) > 0.0
	var need_frac: float = hit.need / maxf(f.speed, 0.1)
	# Chance to make the play cleanly: skill, then how hard he had to work, then how hard it was hit.
	var p_clean: float = f.glove
	if need_frac > 0.8:
		p_clean *= lerpf(1.0, 0.72, clampf((need_frac - 0.8) / 0.2, 0.0, 1.0))
	if dive:
		p_clean *= 0.62
	p_clean *= exp(-maxf(sim.ev_mph - 88.0, 0.0) / 140.0)
	var clean := rng.randf() < p_clean
	var routine := need_frac <= 0.7 and not dive

	var movement := {"fielder": f.num, "from": f.home, "to": Vector3(p.x, 0.0, p.z),
		"t0": f.reaction, "t1": t, "dive": dive}

	# --- Caught in the air.
	if in_air:
		if clean:
			# A low ball caught in the air is a lineout whatever the launch-angle bucket says.
			var label := "Popout" if sim.kind == "Pop-up" else ("Flyout" if sim.kind == "Fly ball" else "Lineout")
			var short := "%s to %s" % [label, f.name]
			if not fair:
				short = "Foul out to %s" % f.name
			return _play("out", short, f, p, t, {"caught_in_air": true, "movements": [movement], "foul_out": not fair})
		# Dropped: it falls in. He retrieves it a moment later.
		var why := "%s dives, can't hold it" % f.name if dive else "%s drops it" % f.name
		return _hit_after(f, p, t + 0.8, sim, run_times, why, [movement], true)

	# --- A ball in foul territory that is not caught is just a foul.
	if not fair:
		return _play("foul", "Foul ball", f, p, t, {"movements": [movement]})

	# --- Fielded on the ground (or on a bounce/roll).
	if not clean:
		if routine:
			var err := _hit_after(f, p, t + 0.9, sim, run_times, "ERROR on %s (E%d)" % [f.name, f.num], [movement], false)
			err["result"] = "error"
			err["error"] = true
			err["bases"] = maxi(err.bases, 1)
			err["short"] = "Error, %s (E%d)" % [f.name, f.num]
			err["text"] = err.short
			return err
		# Beat him: it gets through.
		return _hit_after(f, p, t + 0.7, sim, run_times, "Gets past %s" % f.name, [movement], false)

	return _throw_play(f, p, t, sim, run_times, [movement])


## He has the ball at p at time t_field: throw to first. Out if it beats the runner.
func _throw_play(f: Dictionary, p: Vector3, t_field: float, sim: Dictionary, run_times: Array, movements: Array) -> Dictionary:
	var release: float = t_field + f.transfer
	var to_first := Vector2(p.x - FIRST.x, p.z - FIRST.z).length()
	var unassisted: bool = f.num == 3 and to_first < 4.0
	var arrive: float = release + (0.0 if unassisted else to_first / f.arm + 0.15)
	if unassisted:
		arrive = t_field + 0.25
	var margin := float(run_times[0]) - arrive + rng.randfn(0.0, 0.07)
	if margin > 0.0:
		var label := "Groundout %s" % ("3U" if unassisted else "%d-3" % f.num)
		var covering := fielder_by_num(3)
		var cover_move := {"fielder": 3, "from": covering.home, "to": FIRST + Vector3(0.8, 0.0, -0.4),
			"t0": 0.3, "t1": minf(arrive, 2.5), "dive": false}
		var mv := movements.duplicate()
		if f.num != 3:
			mv.append(cover_move)
		return _play("out", label, f, p, t_field, {
			"movements": mv, "throw": {"from": p + Vector3(0.0, 1.3, 0.0), "to": FIRST + Vector3(0.0, 1.0, 0.0),
				"t0": release, "t1": arrive, "base": 1},
			"runner_out_at": 1, "run_times": run_times, "margin": margin})
	var late := _hit_after(f, p, t_field, sim, run_times, "", movements, false, true)
	late["clean_ground"] = true       # he had it cleanly; the batter just beat the throw
	return late


## The ball was fielded (or retrieved) at p after t_field and the batter is safe at first; how
## far can he go? Bases while he beats the ball there, after the fielder's transfer and throw.
func _hit_after(f: Dictionary, p: Vector3, t_field: float, sim: Dictionary, run_times: Array,
		note: String, movements: Array, in_air_drop: bool, already_thrown_late: bool = false) -> Dictionary:
	var release: float = t_field + f.transfer
	var bases := 1
	var bases_pos := [FIRST, SECOND, THIRD, HOME]
	for k in range(1, 4):
		var base_pos: Vector3 = bases_pos[k]
		var dist := Vector2(p.x - base_pos.x, p.z - base_pos.z).length()
		# Deep balls need a relay man: slower than a straight throw.
		var relay := 0.9 if dist > 65.0 else 0.0
		var arrive: float = release + dist / f.arm + 0.2 + relay
		if float(run_times[k]) + 0.30 < arrive:
			bases = k + 1
		else:
			break
	var names := {1: "Single", 2: "Double", 3: "Triple", 4: "Inside-the-park HR"}
	var where := _field_zone(p, f)
	var text := "%s to %s" % [names[bases], where]
	if note != "" and in_air_drop:
		text = "%s to %s (%s)" % [names[bases], where, note]
	var kind := "single" if bases == 1 else ("double" if bases == 2 else ("triple" if bases == 3 else "inside_park_hr"))
	var throw_base: int = bases + 1 if bases < 4 else 4
	var tb: Vector3 = bases_pos[mini(throw_base - 1, 3)]
	return _play(kind, text, f, p, t_field, {
		"bases": bases, "movements": movements, "run_times": run_times, "note": note,
		"throw": {"from": p + Vector3(0.0, 1.3, 0.0), "to": tb + Vector3(0.0, 1.0, 0.0),
			"t0": release, "t1": release + Vector2(p.x - tb.x, p.z - tb.z).length() / f.arm + 0.2, "base": throw_base}})


## Nobody could reach it on any sample: it rolls on to a stop, or hits the wall. The nearest
## fielder retrieves it there.
func _unfielded(sim: Dictionary, run_times: Array, exclude: Array = []) -> Dictionary:
	var rest: Vector3 = sim.rest_pos
	var best_f := {}
	var best_t := INF
	for f in fielders:
		if f.num in exclude:
			continue
		var d := Vector2(rest.x - f.home.x, rest.z - f.home.z).length()
		var t: float = f.reaction + d / f.speed
		t = maxf(t, sim.get("total_time", 0.0) * 0.6)    # the ball gets there when it gets there
		if t < best_t:
			best_t = t
			best_f = f
	if not sim.fair:
		return _play("foul", "Foul ball", best_f, rest, best_t, {"movements": []})
	var mv := {"fielder": best_f.num, "from": best_f.home, "to": Vector3(rest.x, 0.0, rest.z),
		"t0": best_f.reaction, "t1": best_t, "dive": false}
	var out := _hit_after(best_f, rest, best_t + 0.25, sim, run_times, "", [mv], false)
	if sim.get("wall", false) and out.bases == 1:
		out.bases = 2
		out.result = "double"
		out.short = "Double off the wall"
		out.text = out.short
	return out


func _field_zone(p: Vector3, f: Dictionary) -> String:
	var psi := rad_to_deg(atan2(p.x, p.z))
	var depth := Vector2(p.x, p.z).length()
	if depth < 42.0:
		return f.get("name", "the infield")
	if psi > 14.0:
		return "left"
	if psi < -14.0:
		return "right"
	return "center"


func _play(result: String, text: String, f: Dictionary, p: Vector3, t: float, extra: Dictionary) -> Dictionary:
	var d := {
		"result": result, "short": text, "text": text,
		"fielder": f.get("num", 0), "fielder_name": f.get("name", ""),
		"field_pos": p, "field_time": t,
		"arm": float(f.get("arm", 33.0)), "release_time": t + float(f.get("transfer", 0.5)),
		"bases": 0 if result in ["out", "foul"] else 1,
		"movements": [], "run_times": RUNNER_TIMES, "caught_in_air": false, "error": false,
	}
	for k in extra:
		d[k] = extra[k]
	if result in ["single", "double", "triple", "inside_park_hr"]:
		d["bases"] = extra.get("bases", 1)
	# Name the fielder in a hit's description when it was a ground ball to the infield.
	if result == "single" and Vector2(p.x, p.z).length() < 42.0:
		d.short = "Single to %s" % f.get("name", "")
		d.text = d.short
	return d


func _result(kind: String, text: String, sim: Dictionary) -> Dictionary:
	return {"result": kind, "short": text, "text": text, "fielder": 0, "fielder_name": "",
		"field_pos": sim.get("landing_pos", Vector3.ZERO), "field_time": sim.get("landing_time", 0.0),
		"bases": 4, "movements": [], "run_times": RUNNER_TIMES, "caught_in_air": false, "error": false}
