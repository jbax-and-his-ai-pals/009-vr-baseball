class_name Baserunning
extends RefCounted
## What every runner does on a ball in play: break on contact, take an extra base when the throw
## is late, get thrown out when it is not, tag up on a deep fly, go for the force at second.
## It works from the same play the defense produced, so the fielder's time and arm decide it.
##
## Everyone (the batter included) gets a timeline: when he leaves, when he reaches each base, and
## whether he is out. The scorebook then records the result and the figures run the timelines.
##
## Bases are numbered 0 (the batter's box), 1, 2, 3, and 4 = home plate / scoring.
## Times are seconds after contact. Pure functions: pass an rng for the dice.

const START_DELAY := 0.20          # a runner on base reacts this long after contact
const BASE_POS := [Vector3.ZERO, Defense.FIRST, Defense.SECOND, Defense.THIRD, Vector3.ZERO]
const LEAD_GAIN := 0.9             # a lead off the bag and a rolling start save a runner this long
const HEDGE := 0.30               # how far toward the next base a runner dares on a ball in the air
const AIR_TIME := 1.7              # a ball hanging this long is "in the air": runners wait to see it
const STAND_POS := [Vector3.ZERO, Vector3(-18.5, 0.0, 19.0), Vector3(0.0, 0.0, 37.9), Vector3(18.5, 0.0, 19.0)]
## Where the fielder who takes a throw at each base stands (the bag is beside him).
const RECEIVE_SPOT := [Vector3.ZERO, Vector3(-18.6, 0.0, 19.0), Vector3(0.6, 0.0, 38.3), Vector3(18.6, 0.0, 19.0), Vector3(0.0, 0.0, -1.0)]
const TP_PIVOT := 0.46             # a hurried transfer for a triple play
const TP_CLEAN := 0.72             # the chance each hurried transfer is clean
const PIVOT := 0.62                # a middle infielder takes a force throw and turns it


## Seconds of head start per base for runners already running when the ball is hit (a steal or
## a hit-and-run). Set by plan() for the duration of the call.
static var _head := {}


## When a runner starting from base `from` at time t_start reaches `to`, for a given run factor.
static func arrive(from: int, to: int, t_start: float, run_factor: float) -> float:
	if from > 0 and _head.has(from):
		t_start -= float(_head[from])
	var times: Array = Defense.RUNNER_TIMES
	var seg: float = float(times[to - 1]) - (float(times[from - 1]) if from > 0 else 0.0)
	if from > 0:
		seg = maxf(seg - LEAD_GAIN, 1.0)
	return t_start + seg / maxf(run_factor, 0.5)


## Seconds to run from base `from` to base `to` from a standing start on the bag.
static func run_time(from: int, to: int, run_factor: float) -> float:
	var times: Array = Defense.RUNNER_TIMES
	var seg: float = float(times[to - 1]) - (float(times[from - 1]) if from > 0 else 0.0)
	return seg / maxf(run_factor, 0.5)


static func _pos_of(base: int) -> Vector3:
	return Defense.HOME if base >= 4 else (BASE_POS[base] as Vector3)


## Keyframes for a runner who hedged off his base: out a third of the way, wait, then either on
## to the next base or back to the bag. [[time, position], ...]; the animator follows them.
static func _finish_keys(r: Dictionary) -> void:
	if not r.has("hedge"):
		return
	var h: Dictionary = r.hedge
	var from: int = r.from
	var base_p: Vector3 = BASE_POS[from]
	var hp: Vector3 = base_p.lerp(_pos_of(from + 1), HEDGE)
	var keys: Array = [[float(r.t_start), STAND_POS[from]], [float(h.t_reach), hp], [float(h.t_leave), hp]]
	if h.has("return_at"):
		keys.append([float(h.return_at), base_p])
	else:
		var ks: Array = r.arrivals.keys()
		ks.sort()
		for k in ks:
			keys.append([float(r.arrivals[k]), _pos_of(int(k))])
	r["keys"] = keys


## When a ball fielded at `at` at time t_field gets to a base (after the transfer and throw).
static func ball_arrive(at: Vector3, t_release: float, arm: float, base: int) -> float:
	var d := Vector2(at.x - BASE_POS[base].x, at.z - BASE_POS[base].z).length()
	var relay := 0.9 if d > 65.0 else 0.0
	return t_release + d / maxf(arm, 10.0) + 0.2 + relay


static func _runner_entry(id: int, from: int, who, rf: float) -> Dictionary:
	return {"from": from, "to": from, "who": who, "run_factor": rf, "out": false, "out_base": 0,
		"t_out": 0.0, "t_start": 0.0, "arrivals": {}, "scored": false}


static func _factor_of(who) -> float:
	if who is Player:
		return (who as Player).run_factor()
	return 1.0


## play: Defense.resolve() output (needs result, field_pos, field_time, arm, release_time,
## caught_in_air, fielder). bases: [on 1st, on 2nd, on 3rd] (Player / true / null).
## batter: the Player at the plate. Returns the plan (see the bottom of this function).
static func plan(play: Dictionary, bases: Array, outs_before: int, batter, rng: RandomNumberGenerator,
		head: Dictionary = {}) -> Dictionary:
	_head = head
	var planned := _plan(play, bases, outs_before, batter, rng)
	_head = {}
	return planned


static func _plan(play: Dictionary, bases: Array, outs_before: int, batter, rng: RandomNumberGenerator) -> Dictionary:
	var result: String = play.get("result", "out")
	var runners: Array[Dictionary] = []
	# Lead runner first so the ones behind cannot pass him.
	for i in [3, 2, 1]:
		var who = bases[i - 1]
		if who != null:
			var r := _runner_entry(i, i, who, _factor_of(who))
			runners.append(r)
	var bat := _runner_entry(0, 0, batter, _factor_of(batter))
	runners.append(bat)

	var out_result := {"runs": 0, "outs_added": 0, "throws": [], "events": [], "suffix": "", "batter_safe": false}
	# The infield fly rule: runners on first and second (or loaded), fewer than two outs, a high
	# fair pop-up an infielder can catch. The batter is out whether it is caught or dropped, and
	# nobody is forced, so a dropped ball does not open a force play.
	if play.get("infield_fly", false) and bases[0] != null and bases[1] != null and outs_before < 2 \
			and result in ["single", "double", "triple", "error", "out"] and not play.get("foul_out", false):
		bat.out = true
		bat.out_base = 0
		bat.t_out = float(play.get("field_time", 3.0))
		out_result.outs_added = 1
		out_result.events.append({"t": bat.t_out, "base": 0, "text": "INFIELD FLY", "kind": "out",
			"at": play.get("field_pos", Vector3.ZERO)})
		out_result["text"] = "Infield fly rule, batter is out"
		out_result["result"] = "out"
		result = "infield_fly"
	match result:
		"home_run":
			_home_run(runners, out_result)
		"single", "double", "triple", "inside_park_hr", "error":
			var handled := false
			if result == "single" and play.get("clean_ground", false) and int(play.get("fielder", 0)) in [1, 2, 3, 4, 5, 6]:
				handled = try_fielders_choice(play, runners, bases, outs_before, out_result, rng)
			if not handled:
				_hit(play, runners, out_result, outs_before, rng)
		"out":
			if play.get("caught_in_air", false):
				_caught(play, runners, out_result, outs_before, rng)
			else:
				_ground_out(play, runners, bases, outs_before, out_result, rng)
		"infield_fly":
			pass    # handled above: the batter is out and the runners hold
		_:
			pass    # a foul or nothing: nobody moves

	for r in runners:
		_finish_keys(r)
	var new_bases: Array = [null, null, null]
	var runs := 0
	for r in runners:
		if r.out:
			continue
		if r.to == 4:
			runs += 1
			r.scored = true
		elif r.to >= 1:
			new_bases[r.to - 1] = r.who if r.who != null else true
	var outs_added: int = out_result.outs_added
	# A run does not count if the third out comes on the same play before he scores... unless it
	# is a TIME PLAY: the third out was a tag (not a force, not the batter-runner) and he crossed
	# the plate before it.
	var voided := outs_before + outs_added >= 3 and result != "home_run"
	if voided:
		var cutoff := -1.0
		var out_list: Array = []
		for r in runners:
			if r.out:
				out_list.append(r)
		out_list.sort_custom(func(a, b): return float(a.t_out) < float(b.t_out))
		var third_i := 3 - outs_before - 1
		if third_i >= 0 and third_i < out_list.size():
			var third: Dictionary = out_list[third_i]
			if not (bool(third.get("forced_out", false)) or int(third.from) == 0):
				cutoff = float(third.t_out)          # a tag: runs before this moment count
		var kept := 0
		for r in runners:
			if r.scored:
				if cutoff > 0.0 and float(r.arrivals.get(4, 1e9)) < cutoff:
					kept += 1
				else:
					r.scored = false
					r.to = r.from
					r.arrivals.clear()
		runs = kept
		voided = kept == 0
		out_result.events = out_result.events.filter(func(e): return e.kind != "run" or (e.get("who") != null and not e.who.scored == false))
		if kept > 0:
			out_result["time_play"] = true
	# Label the batter's own result and find when everything has finished.
	if not bat.out and bat.to >= 1 and bat.arrivals.has(bat.to):
		var txt := "SAFE"
		if bat.to == 4:
			txt = "HOME RUN" if result == "home_run" else "RUN"
		out_result.events.append({"t": bat.arrivals[bat.to], "base": bat.to, "text": txt, "kind": "safe"})
	var end := float(play.get("field_time", 0.0)) + 0.5
	for r in runners:
		for k in r.arrivals:
			end = maxf(end, float(r.arrivals[k]) + 0.5)
		if r.has("keys"):
			end = maxf(end, float((r.keys as Array)[(r.keys as Array).size() - 1][0]) + 0.5)
		if r.out:
			end = maxf(end, float(r.t_out) + 0.5)
	for th in out_result.throws:
		end = maxf(end, float(th.t1) + 0.5)
	out_result["end_time"] = end
	out_result["runners"] = runners
	out_result["runs"] = runs
	out_result["final_bases"] = new_bases
	out_result["runs_voided"] = voided
	return out_result


# ----------------------------------------------------------------- a human fielder's play
## Before the ball is thrown: the batter runs to first and, on a ground ball, forced runners go.
## runners_go is false for balls in the air (nobody commits before it is caught).
static func plan_hold(bases: Array, batter, runners_go: bool) -> Dictionary:
	var runners: Array[Dictionary] = []
	var forced := {1: bases[0] != null, 2: bases[0] != null and bases[1] != null,
		3: bases[0] != null and bases[1] != null and bases[2] != null}
	for i in [3, 2, 1]:
		var who = bases[i - 1]
		if who == null:
			continue
		var r := _runner_entry(i, i, who, _factor_of(who))
		if runners_go and forced[i]:
			r.t_start = START_DELAY
			r.to = i + 1
			r.arrivals[i + 1] = arrive(i, i + 1, START_DELAY, r.run_factor)
		runners.append(r)
	var bat := _runner_entry(0, 0, batter, _factor_of(batter))
	bat.t_start = 0.0
	bat.to = 1
	bat.arrivals[1] = arrive(0, 1, 0.0, bat.run_factor)
	runners.append(bat)
	var res := {"runners": runners, "events": [], "throws": [], "runs": 0, "outs_added": 0,
		"suffix": "", "hold": true, "batter_safe": true}
	_tally(res, 0)
	return res


## A batter who is out without the ball being put in play (a strikeout): he walks off.
static func plan_leave(batter) -> Dictionary:
	var r := _runner_entry(0, 0, batter, _factor_of(batter))
	r.out = true
	r.out_base = 0
	r.t_out = 0.0
	var runners: Array[Dictionary] = [r]
	return {"runners": runners, "events": [{"t": 0.15, "base": 0, "text": "STRIKEOUT", "kind": "out", "at": Vector3(0.0, 0.0, 0.0)}],
		"throws": [], "runs": 0, "outs_added": 1, "suffix": "", "hold": false, "end_time": 0.8,
		"final_bases": [null, null, null], "hide_batter_at": 0.7}


## Everyone on base moves up one (a wild pitch or a passed ball). No batter.
static func plan_advance(bases: Array) -> Dictionary:
	var runners: Array[Dictionary] = []
	for i in [3, 2, 1]:
		var who = bases[i - 1]
		if who == null:
			continue
		var r := _runner_entry(i, i, who, _factor_of(who))
		r.t_start = 0.25
		r.to = i + 1
		r.arrivals[i + 1] = arrive(i, i + 1, 0.25, r.run_factor)
		runners.append(r)
	var res := {"runners": runners, "events": [], "throws": [], "runs": 0, "outs_added": 0,
		"suffix": "", "hold": false, "hide_batter_at": 9999.0}
	_tally(res, 0)
	return res


## A steal: one runner going to the next base, with the planned time he takes. The caller
## patches the plan with the outcome once the throw is known.
static func plan_steal(from_base: int, runner, run_seconds: float) -> Dictionary:
	var r := _runner_entry(from_base, from_base, runner, _factor_of(runner))
	r.t_start = 0.0
	r.to = from_base + 1
	r.arrivals[from_base + 1] = run_seconds
	var runners: Array[Dictionary] = [r]
	var res := {"runners": runners, "events": [], "throws": [], "runs": 0, "outs_added": 0,
		"suffix": "", "hold": false, "hide_batter_at": 9999.0, "steal": true}
	_tally(res, 0)
	return res


## A runner who dives back to his base after a throw over. out: he was too late.
static func plan_dive_back(base: int, runner, from_pos: Vector3, to_pos: Vector3, seconds: float, out: bool) -> Dictionary:
	var r := _runner_entry(base, base, runner, _factor_of(runner))
	r["dive"] = true                       # he goes back head first
	r["keys"] = [[0.0, from_pos], [seconds, to_pos]]
	var runners: Array[Dictionary] = [r]
	var events: Array = []
	if out:
		r.out = true
		r.out_base = base
		r.t_out = seconds
		events.append({"t": seconds, "base": base, "text": "OUT", "kind": "out"})
	else:
		events.append({"t": seconds, "base": base, "text": "SAFE", "kind": "safe"})
	var res := {"runners": runners, "events": events, "throws": [], "runs": 0, "outs_added": 1 if out else 0,
		"suffix": "", "hold": false, "hide_batter_at": 9999.0}
	_tally(res, 0)
	return res


## Mark the runner in a steal plan out at the base he was going to, at time t_out.
static func steal_out(plan: Dictionary, t_out: float) -> void:
	var r: Dictionary = plan.runners[0]
	var base: int = int(r.from) + 1
	r.out = true
	r.out_base = base
	r.t_out = t_out
	var full: float = r.arrivals.get(base, t_out)
	r.arrivals[base] = minf(full, t_out)
	plan.outs_added = 1
	plan.events.append({"t": t_out, "base": base, "text": "OUT", "kind": "out"})
	_tally(plan, 0)


## The runner of a steal plan is safe: a SAFE callout when he gets there.
static func steal_safe(plan: Dictionary) -> void:
	var r: Dictionary = plan.runners[0]
	var base: int = int(r.from) + 1
	plan.events.append({"t": float(r.arrivals.get(base, 3.0)), "base": base, "text": "SAFE", "kind": "safe"})
	_tally(plan, 0)


## The runner who is going to `base`, if any.
static func runner_to(plan: Dictionary, base: int):
	for r in plan.runners:
		if not r.out and int(r.to) == base and r.arrivals.has(base):
			return r
	return null


## A human throws to `base`; the ball gets there at t_arrive. Marks who is out and tallies.
## from_pos is where the throw started (for the pivot man's relay on a force at second).
static func apply_throw(plan: Dictionary, base: int, t_arrive: float, outs_before: int, from_pos: Vector3,
		rng: RandomNumberGenerator) -> void:
	var r = runner_to(plan, base)
	if r != null:
		var arrives: float = r.arrivals[base]
		if (arrives - t_arrive) + rng.randfn(0.0, 0.06) > 0.0:
			r.out = true
			r.out_base = base
			r.t_out = t_arrive
			plan.outs_added += 1
			plan.events.append({"t": t_arrive, "base": base, "text": "OUT", "kind": "out"})
			# A force at second: the pivot man turns it for the batter.
			if base == 2 and outs_before + 1 < 3:
				var bat = runner_to(plan, 1)
				if bat != null:
					var t_rel := t_arrive + PIVOT
					var t1: float = t_rel + Defense.SECOND.distance_to(Defense.FIRST) / 31.0 + 0.10
					if (float(bat.arrivals[1]) - t1) + rng.randfn(0.0, 0.10) > 0.0:
						bat.out = true
						bat.out_base = 1
						bat.t_out = t1
						plan.outs_added += 1
						plan.suffix = " (double play)"
						plan.events.append({"t": t1, "base": 1, "text": "OUT", "kind": "out"})
						plan.throws.append({"from": SECOND_BAG + Vector3(0.0, 1.0, 0.0), "to": Defense.FIRST + Vector3(0.0, 1.0, 0.0),
							"t0": t_rel, "t1": t1, "base": 1})
	plan.hold = false
	_tally(plan, outs_before)


## Runs, bases after the play, and when it is all over.
static func _tally(plan: Dictionary, outs_before: int) -> void:
	var new_bases: Array = [null, null, null]
	var runs := 0
	var end := 0.5
	for r in plan.runners:
		for k in r.arrivals:
			end = maxf(end, float(r.arrivals[k]) + 0.5)
		if r.out:
			end = maxf(end, float(r.t_out) + 0.5)
			continue
		if r.to == 4:
			runs += 1
		elif r.to >= 1:
			new_bases[r.to - 1] = r.who if r.who != null else true
	for th in plan.throws:
		end = maxf(end, float(th.t1) + 0.5)
	if outs_before + int(plan.outs_added) >= 3:
		runs = 0
	plan["runs"] = runs
	plan["final_bases"] = new_bases
	plan["end_time"] = end


# ----------------------------------------------------------------- home runs
static func _home_run(runners: Array, res: Dictionary) -> void:
	for r in runners:
		r.to = 4
		r.t_start = 0.12 if r.from == 0 else START_DELAY
		for k in range(r.from + 1, 5):
			r.arrivals[k] = arrive(r.from, k, r.t_start, r.run_factor) * 0.8
		if r.from > 0:
			res.events.append({"t": r.arrivals[4], "base": 4, "text": "RUN", "kind": "run"})


# ----------------------------------------------------------------- hits and errors
static func _hit(play: Dictionary, runners: Array, res: Dictionary, outs_before: int, rng: RandomNumberGenerator) -> void:
	var n: int = 1 if play.result == "error" else int(play.get("bases", 1))
	var at: Vector3 = play.get("field_pos", Vector3.ZERO)
	var arm: float = play.get("arm", 33.0)
	var release: float = play.get("release_time", float(play.get("field_time", 3.0)) + 0.5)
	var lead_to := 5
	var air_t: float = float(play.get("landing_time", 0.0))
	var airborne := air_t >= AIR_TIME and outs_before < 2
	# Every runner's contest with the ball: where he is trying to get to and whether the ball
	# can beat him there. The defense has ONE throw: it goes where it is most likely to get
	# somebody, never where the runner is going to score untouched.
	var attempts: Array = []
	for r in runners:
		var from: int = r.from
		r.t_start = 0.0 if from == 0 else START_DELAY
		# A ball in the air might be caught: he goes a third of the way and waits for it to land.
		var delay := 0.0
		if airborne and from >= 1:
			var t_reach: float = r.t_start + HEDGE * run_time(from, from + 1, r.run_factor)
			delay = maxf(0.0, air_t - t_reach)
			r["hedge"] = {"to": from + 1, "t_reach": t_reach, "t_leave": t_reach + delay}
		var to := mini(4, from + n)
		if from == 0:
			to = mini(4, n)
		if from >= 1 and play.result != "error" and not play.get("ground_rule", false):
			if to < 4:
				# He looks for an extra base when the throw will be late.
				var next := to + 1
				var ball_t := ball_arrive(at, release, arm, next)
				var run_t := arrive(from, next, r.t_start, r.run_factor) + delay
				var open_ahead := lead_to >= 5 or lead_to >= 4 or next <= lead_to - 1
				if ball_t - run_t > -0.25 and open_ahead:
					attempts.append({"r": r, "base": next, "run_t": run_t, "ball_t": ball_t, "delay": delay})
					to = next
			else:
				# Scoring from where he stands: a throw home might still get him.
				var ball_home := ball_arrive(at, release, arm, 4)
				attempts.append({"r": r, "base": 4, "run_t": arrive(from, 4, r.t_start, r.run_factor) + delay,
					"ball_t": ball_home, "delay": delay})
		# Cannot pass the runner ahead (a runner ahead who scored does not block).
		if lead_to < 4:
			to = mini(to, lead_to - 1)
		to = maxi(to, from if from > 0 else 1)
		r.to = to
		for k in range(from + 1, to + 1):
			r.arrivals[k] = arrive(from, k, r.t_start, r.run_factor) + delay
		lead_to = to
		if to == 4 and from > 0:
			res.events.append({"t": r.arrivals[4], "base": 4, "text": "RUN", "kind": "run", "who": r})

	# --- The throw.
	var target := -1
	for i in attempts.size():
		var a: Dictionary = attempts[i]
		a["p"] = _p_beat(a.run_t, a.ball_t)
		if target == -1 and a.p >= 0.25:
			target = i                              # the lead runner he has a real chance at
	if target == -1:
		var best_p := 0.10
		for i in attempts.size():
			if float(attempts[i].p) > best_p:
				best_p = attempts[i].p
				target = i
	if target != -1:
		var a: Dictionary = attempts[target]
		var tr: Dictionary = a.r
		var base: int = a.base
		res.throws.append({"from": at + Vector3(0.0, 1.3, 0.0), "to": _pos_of(base) + Vector3(0.0, 1.0, 0.0),
			"t0": release, "t1": a.ball_t, "base": base})
		var safe := (float(a.run_t) - float(a.ball_t)) + rng.randfn(0.0, 0.28) > 0.0
		if not safe:
			tr.out = true
			tr.out_base = base
			tr.t_out = a.ball_t
			tr.arrivals.clear()
			for k in range(int(tr.from) + 1, base + 1):
				tr.arrivals[k] = minf(arrive(tr.from, k, tr.t_start, tr.run_factor) + float(a.delay), tr.t_out)
			res.outs_added += 1
			res.events = res.events.filter(func(e): return not (e.kind == "run" and e.get("who") == tr))
			res.events.append({"t": a.ball_t, "base": base, "text": "OUT", "kind": "out"})
		# The ball went one way, so the batter takes the base he can on the throw.
		if base == 4:
			var bat: Dictionary = runners[runners.size() - 1]
			var second_free := true
			for r in runners:
				if r != bat and not r.out and int(r.to) == 2:
					second_free = false
			if bat.to == 1 and second_free and not bat.out and arrive(0, 2, 0.0, bat.run_factor) < float(a.ball_t) + 1.5:
				bat.to = 2
				bat.arrivals[2] = arrive(0, 2, 0.0, bat.run_factor)


# ----------------------------------------------------------------- caught in the air
static func _caught(play: Dictionary, runners: Array, res: Dictionary, outs_before: int, rng: RandomNumberGenerator) -> void:
	var t_catch: float = play.get("field_time", 3.0)
	var at: Vector3 = play.get("field_pos", Vector3.ZERO)
	var arm: float = play.get("arm", 33.0)
	var transfer: float = play.get("release_time", t_catch + 0.5) - t_catch
	var depth := Vector2(at.x, at.z).length()
	res.outs_added = 1                      # the batter
	var batter_r: Dictionary = runners[runners.size() - 1]
	batter_r.out = true
	batter_r.out_base = 0
	batter_r.t_out = t_catch
	res.events.append({"t": t_catch, "base": 0, "text": "OUT", "kind": "out", "at": at})
	var lead_to := 5
	for r in runners:
		if r.from == 0:
			continue
		var from: int = r.from
		# A runner tags up only on a ball deep enough to be worth it, and only with room for it to matter.
		var worth := (from == 3 and depth > 42.0) or (from == 2 and depth > 78.0) or (from == 1 and depth > 100.0)
		var dest := from
		# A hard line drive caught: a runner who broke on contact is in trouble.
		var liner: bool = float(play.get("landing_time", 9.0)) < AIR_TIME and float(play.get("apex", 0.0)) < 8.0 \
			and outs_before + 1 < 3 and not play.get("foul_out", false)
		if liner and rng.randf() < (0.14 if from < 3 else 0.07):
			var seg: float = run_time(from, from + 1, r.run_factor)
			var went: float = minf(0.5, maxf(t_catch - START_DELAY, 0.0) / seg)
			var back_t := t_catch + went * seg * 0.85 + 0.05
			var base_p: Vector3 = BASE_POS[from]
			var away: Vector3 = base_p.lerp(_pos_of(from + 1), went)
			r.t_start = START_DELAY
			r["keys"] = [[START_DELAY, STAND_POS[from]], [t_catch, away], [back_t, base_p]]
			var ball_back := ball_arrive(at, t_catch + transfer, arm, from)
			if ball_back + rng.randfn(0.0, 0.10) < back_t:
				r.out = true
				r.out_base = from
				r.t_out = ball_back
				res.outs_added += 1
				res.events.append({"t": ball_back, "base": from, "text": "OUT", "kind": "out"})
				res.throws.append({"from": at + Vector3(0.0, 1.3, 0.0), "to": BASE_POS[from] + Vector3(0.0, 1.0, 0.0),
					"t0": t_catch + transfer, "t1": ball_back, "base": from})
				res.suffix = " (runner doubled off)"
				res["text"] = "Lineout, double play (doubled off at %s)" % ["", "first", "second", "third"][from]
			r.to = from
			lead_to = from
			continue
		# Not deep enough to tag on, but out in the air where it might fall: he leaves a little way
		# and has to come back and touch his base once it is caught.
		if not worth and depth > 38.0 and t_catch >= 1.8 and outs_before < 2:
			var seg_t := run_time(from, from + 1, r.run_factor)
			var t_reach := START_DELAY + HEDGE * seg_t
			if t_catch > t_reach + 0.1:
				r.t_start = START_DELAY
				r["hedge"] = {"to": from + 1, "t_reach": t_reach, "t_leave": t_catch,
					"return_at": t_catch + HEDGE * seg_t * 0.85}
		if worth and outs_before + 1 < 3 and (from == 3 or lead_to > from + 1):
			var t0 := t_catch + 0.15
			var ball_t := ball_arrive(at, t_catch + transfer, arm, from + 1)
			var run_t := arrive(from, from + 1, t0, r.run_factor)
			var est := ball_t - run_t
			if est > -0.15:
				if est + rng.randfn(0.0, 0.30) > 0.0:
					dest = from + 1
					r.t_start = t0
					r.arrivals[dest] = run_t
				else:
					r.out = true
					r.out_base = from + 1
					r.t_out = ball_t
					r.t_start = t0
					res.outs_added += 1
					res.events.append({"t": ball_t, "base": from + 1, "text": "OUT", "kind": "out"})
					res.throws.append({"from": at + Vector3(0.0, 1.3, 0.0), "to": BASE_POS[from + 1] + Vector3(0.0, 1.0, 0.0),
						"t0": t_catch + transfer, "t1": ball_t, "base": from + 1})
		if not r.out:
			r.to = dest
			lead_to = dest
			if dest == 4:
				res.events.append({"t": r.arrivals[4], "base": 4, "text": "RUN", "kind": "run"})
	if res.runs == 0 and res.outs_added == 1:
		for r in runners:
			if r.from == 3 and r.to == 4:
				res.suffix = " (sacrifice fly)"


# ----------------------------------------------------------------- grounders
## How sure the defense has to be of a force on the lead runner before it gives up the sure
## out at first, and how fuzzy "can he get there" is.
const FORCE_MIN_P := 0.30
const FORCE_PREFERRED_P := 0.78
const DP_MIN_VALUE := 1.15
const P_SIGMA := 0.14


## Probability the ball beats the runner to a base: the margin in seconds, softened.
static func _p_beat(runner_arrival: float, ball_time: float) -> float:
	return 1.0 / (1.0 + exp(-(runner_arrival - ball_time) / (P_SIGMA * 0.55)))


## When the ball gets to a base from where it was fielded. A fielder at the bag steps on it.
static func _t_to_base(at: Vector3, t_field: float, release: float, arm: float, base: int) -> float:
	var bag := _pos_of(base)
	var d := Vector2(at.x - bag.x, at.z - bag.z).length()
	if d < 4.0:
		return t_field + 0.35
	return ball_arrive(at, release, arm, base)


## What each throw is worth to the defense on a ground ball: an expected number of outs.
## Options: "first" (the sure out), "force" at a base, "dp2" (second, then first), "dphome"
## (home, then first). Returns a list sorted best first.
static func ground_options(play: Dictionary, runners: Array, bases: Array, outs_before: int, first_available: bool) -> Array:
	var at: Vector3 = play.get("field_pos", Vector3.ZERO)
	var arm: float = play.get("arm", 33.0)
	var t_field: float = play.get("field_time", 2.0)
	var release: float = play.get("release_time", t_field + 0.45)
	var forced := {1: bases[0] != null, 2: bases[0] != null and bases[1] != null,
		3: bases[0] != null and bases[1] != null and bases[2] != null}
	var by_from := {}
	for r in runners:
		if r.from > 0:
			by_from[int(r.from)] = r
	var batter_r: Dictionary = runners[runners.size() - 1]
	var bat_rt := arrive(0, 1, 0.0, batter_r.run_factor)
	var t_first := _t_to_base(at, t_field, release, arm, 1)
	var opts: Array = []
	var first_value := 0.0
	if first_available:
		# The defense already ruled on the play at first when it fielded the ball.
		first_value = 0.95 if play.get("result", "out") == "out" else 0.0
	opts.append({"kind": "first", "base": 1, "value": first_value, "t": t_first, "p": first_value})
	for f in [3, 2, 1]:
		if not forced[f] or not by_from.has(f):
			continue
		var r: Dictionary = by_from[f]
		var base: int = f + 1
		var t := _t_to_base(at, t_field, release, arm, base)
		var a := arrive(f, base, START_DELAY, r.run_factor)
		var p := _p_beat(a, t)
		opts.append({"kind": "force", "base": base, "value": p, "t": t, "p": p, "arrival": a})
		if outs_before == 0 and base == 3 and forced[2] and by_from.has(1):
			# Runners on first and second, nobody out, the ball at third: a triple play is on the table.
			var tp_t2 := t + TP_PIVOT + _pos_of(3).distance_to(_pos_of(2)) / 31.0 + 0.10
			var tp_t1 := tp_t2 + TP_PIVOT + _pos_of(2).distance_to(Defense.FIRST) / 31.0 + 0.10
			var r1: Dictionary = by_from[1]
			var a_second := arrive(1, 2, START_DELAY, r1.run_factor)
			var p_second := _p_beat(a_second, tp_t2)
			var p_first := _p_beat(bat_rt, tp_t1)
			opts.append({"kind": "tp", "base": 3, "value": p * (1.0 + p_second * (1.0 + p_first)), "t": t, "p": p,
				"arrival": a, "t_second": tp_t2, "t_first": tp_t1, "arrival_second": a_second,
				"p_second": p_second, "p_first": p_first})
		if outs_before < 2:
			var d_relay := _pos_of(base).distance_to(Defense.FIRST)
			var t_rel := t + PIVOT + d_relay / 31.0 + 0.10
			if base == 4:
				t_rel = t + 0.40 + _pos_of(4).distance_to(Defense.FIRST) / 31.0 + 0.10
			var p1 := _p_beat(bat_rt, t_rel)
			if base == 2 or base == 4:
				opts.append({"kind": "dp2" if base == 2 else "dphome", "base": base, "value": p * (1.0 + p1), "t": t,
					"p": p, "arrival": a, "t_relay": t_rel, "p_relay": p1})
	opts.sort_custom(func(x, y):
		if absf(float(x.value) - float(y.value)) > 0.02:
			return float(x.value) > float(y.value)
		return int(x.base) > int(y.base))      # equal: the lead runner first
	return opts


## The throw he actually makes, from those options.
static func choose_ground_throw(opts: Array, first_available: bool) -> Dictionary:
	var first_opt: Dictionary = {}
	for o in opts:
		if o.kind == "first":
			first_opt = o
	var sure := float(first_opt.get("value", 0.0)) if first_available else 0.0
	# A double play that is worth more than the sure out.
	for o in opts:
		if o.kind == "tp" and float(o.value) >= 1.75:
			return o
	for o in opts:
		if (o.kind == "dp2" or o.kind == "dphome") and float(o.value) >= maxf(DP_MIN_VALUE, sure + 0.2):
			return o
	# Otherwise the lead runner, if he can really be had; if the batter is safe at first
	# anyway, any decent chance at a force is worth taking.
	for o in opts:
		if o.kind != "force":
			continue
		var p: float = o.p
		if (sure < 0.5 and p >= FORCE_MIN_P) or (p >= FORCE_PREFERRED_P and int(o.base) >= 3):
			return o
	return first_opt


static func _ground_out(play: Dictionary, runners: Array, bases: Array, outs_before: int, res: Dictionary, rng: RandomNumberGenerator) -> void:
	var opts := ground_options(play, runners, bases, outs_before, true)
	var pick := choose_ground_throw(opts, true)
	_execute_ground(play, runners, bases, outs_before, res, rng, pick, true)


## Carry out the chosen throw: who is out, who is safe, where everyone ends up.
static func _execute_ground(play: Dictionary, runners: Array, bases: Array, outs_before: int, res: Dictionary,
		rng: RandomNumberGenerator, pick: Dictionary, first_available: bool) -> void:
	var at: Vector3 = play.get("field_pos", Vector3.ZERO)
	var t_field: float = play.get("field_time", 2.0)
	var fielder := int(play.get("fielder", 6))
	var release: float = play.get("release_time", t_field + 0.45)
	var batter_r: Dictionary = runners[runners.size() - 1]
	var bat_rt := arrive(0, 1, 0.0, batter_r.run_factor)
	var by_from := {}
	for r in runners:
		if r.from > 0:
			by_from[int(r.from)] = r
	var forced := {1: bases[0] != null, 2: bases[0] != null and bases[1] != null,
		3: bases[0] != null and bases[1] != null and bases[2] != null}
	var cover_for := func(base: int) -> int:
		match base:
			2:
				return 4 if fielder == 6 else 6
			3:
				return 5
			4:
				return 2
			_:
				return 3
	var from_hand := at + Vector3(0.0, 1.3, 0.0)
	var batter_handled := false
	var kind: String = pick.get("kind", "first")
	var base_out := int(pick.get("base", 1))
	var runner_out_at := 0               # base where a lead runner was put out, 0 if none

	if kind == "tp":
		# Third base, then second, then first.
		var rs: Dictionary = by_from.get(2, {})
		var r1: Dictionary = by_from.get(1, {})
		var t3: float = pick.t
		res.throws.append({"from": from_hand, "to": _pos_of(3) + Vector3(0.0, 1.0, 0.0), "t0": release, "t1": t3, "base": 3})
		var got3 := (float(pick.arrival) - t3) + rng.randfn(0.0, 0.12) > 0.0
		if not rs.is_empty():
			rs.arrivals[3] = pick.arrival
		if got3 and not rs.is_empty():
			rs.out = true
			rs.out_base = 3
			rs.t_out = t3
			rs["forced_out"] = true
			res.outs_added += 1
			res.events.append({"t": t3, "base": 3, "text": "OUT", "kind": "out"})
			var t2: float = pick.t_second
			res.throws.append({"from": _pos_of(3) + Vector3(0.0, 1.0, 0.0), "to": _pos_of(2) + Vector3(0.0, 1.0, 0.0), "t0": t3 + TP_PIVOT, "t1": t2, "base": 2})
			var got2 := (float(pick.arrival_second) - t2) + rng.randfn(0.0, 0.12) > 0.0 and rng.randf() < TP_CLEAN
			if not r1.is_empty():
				r1.arrivals[2] = pick.arrival_second
			if got2 and not r1.is_empty():
				r1.out = true
				r1.out_base = 2
				r1.t_out = t2
				r1["forced_out"] = true
				res.outs_added += 1
				res.events.append({"t": t2, "base": 2, "text": "OUT", "kind": "out"})
				var t1: float = pick.t_first
				res.throws.append({"from": _pos_of(2) + Vector3(0.0, 1.0, 0.0), "to": Defense.FIRST + Vector3(0.0, 1.0, 0.0), "t0": t2 + TP_PIVOT, "t1": t1, "base": 1})
				var got1 := (bat_rt - t1) + rng.randfn(0.0, 0.10) > 0.0 and rng.randf() < TP_CLEAN
				if got1:
					batter_r.out = true
					batter_r.out_base = 1
					batter_r.t_out = t1
					batter_r.arrivals[1] = bat_rt
					res.outs_added += 1
					res.events.append({"t": t1, "base": 1, "text": "OUT", "kind": "out"})
					res["text"] = "Triple play %d-4-3" % fielder
					res.suffix = " (triple play)"
				else:
					res["text"] = "Double play %d-4" % fielder
					res.suffix = " (double play)"
			else:
				res["text"] = "Force out at third, %d-4" % fielder
			res["result"] = "fielders_choice"
	elif kind == "force" or kind == "dp2" or kind == "dphome":
		var src := base_out - 1                         # the runner forced to this base came from here
		var r: Dictionary = by_from.get(src, {})
		var t: float = pick.t
		res.throws.append({"from": from_hand, "to": _pos_of(base_out) + Vector3(0.0, 1.0, 0.0), "t0": release, "t1": t, "base": base_out})
		if base_out == 2:
			res["cover"] = {"fielder": int(cover_for.call(2)), "to": Defense.SECOND + Vector3(0.6, 0.0, -0.5), "t": t}
		var a: float = pick.arrival
		var got := (a - t) + rng.randfn(0.0, 0.12) > 0.0
		if not r.is_empty():
			r.arrivals[base_out] = a
		if got and not r.is_empty():
			r.out = true
			r["forced_out"] = true
			r.out_base = base_out
			r.t_out = t
			res.outs_added += 1
			res.events.append({"t": t, "base": base_out, "text": "OUT", "kind": "out"})
			runner_out_at = base_out
			var rcv := int(cover_for.call(base_out))
			if kind == "dp2" or kind == "dphome":
				var t_rel: float = pick.t_relay
				var t_hold: float = t + (PIVOT if kind == "dp2" else 0.40)
				var src_pos := _pos_of(base_out) + Vector3(0.0, 1.0, 0.0)
				res.throws.append({"from": src_pos, "to": Defense.FIRST + Vector3(0.0, 1.0, 0.0), "t0": t_hold, "t1": t_rel, "base": 1})
				var wins := (bat_rt - t_rel) + rng.randfn(0.0, 0.10) > 0.0 and outs_before + 2 <= 3
				if wins:
					batter_r.out = true
					batter_r.out_base = 1
					batter_r.t_out = t_rel
					batter_r.arrivals[1] = bat_rt
					res.outs_added += 1
					res.events.append({"t": t_rel, "base": 1, "text": "OUT", "kind": "out"})
					res["text"] = "Double play %d-%d-3" % [fielder, rcv]
					res.suffix = " (double play)"
				else:
					res["text"] = "Force out at %s, %d-%d" % [["", "first", "second", "third", "home"][base_out], fielder, rcv]
					res.suffix = " (force at %s)" % ["", "first", "second", "third", "home"][base_out]
			else:
				res["text"] = "Force out at %s, %d-%d" % [["", "first", "second", "third", "home"][base_out], fielder, rcv]
				res.suffix = " (force at %s)" % ["", "first", "second", "third", "home"][base_out]
			res["result"] = "fielders_choice"
		else:
			# Beat the throw: nobody is out and the batter is on.
			res.suffix = " (safe at %s)" % ["", "first", "second", "third", "home"][base_out]
	if not batter_r.out:
		if kind == "first" and first_available and play.get("result", "out") == "out":
			var th: Dictionary = play.get("throw", {})
			batter_r.out = true
			batter_r.out_base = 1
			batter_r.t_out = float(th.get("t1", t_field + 1.2))
			batter_r.arrivals[1] = bat_rt
			res.outs_added += 1
			if not th.is_empty():
				res.throws.append(th)
			res.events.append({"t": batter_r.t_out, "base": 1, "text": "OUT", "kind": "out"})
		else:
			batter_r.to = 1
			batter_r.arrivals[1] = bat_rt
			res.batter_safe = true
	batter_handled = true

	# --- The other runners: forced ones move up, the rest go when it makes sense. With two
	# outs everyone runs on contact; otherwise a man not forced goes only sometimes.
	var lead_to := 5
	for r in runners:
		if r.from == 0 or r.out:
			continue
		var from: int = r.from
		if not r.arrivals.is_empty() and r.to != from:
			lead_to = r.to
			continue
		var dest := from
		var move: bool = forced.get(from, false)
		if not move:
			var p_go := 1.0 if (outs_before >= 2 or play.get("bunt", false)) else 0.55
			move = rng.randf() < p_go and outs_before + res.outs_added < 3
		if move and (lead_to >= from + 2 or lead_to == 5 or lead_to > 3):
			dest = from + 1
			r.t_start = START_DELAY
			r.arrivals[dest] = arrive(from, dest, START_DELAY, r.run_factor)
		r.to = dest
		lead_to = dest
		if dest == 4:
			res.events.append({"t": r.arrivals[4], "base": 4, "text": "RUN", "kind": "run"})


## A clean ground ball that the batter would beat to first: a runner who is forced can still be
## had. Returns true when the defense goes for it (and sets who is out); false for a plain hit.
static func try_fielders_choice(play: Dictionary, runners: Array, bases: Array, outs_before: int,
		res: Dictionary, rng: RandomNumberGenerator) -> bool:
	if bases[0] == null:
		return false
	var opts := ground_options(play, runners, bases, outs_before, false)
	var pick := choose_ground_throw(opts, false)
	if pick.get("kind", "first") == "first":
		return false
	_execute_ground(play, runners, bases, outs_before, res, rng, pick, false)
	if res.outs_added == 0:
		res["result"] = "single"           # he beat it: a base hit, the throw was just a play
	return true


const SECOND_BAG := Vector3(0.0, 0.0, 38.80)
