extends SceneTree
## Runners on a ball in play: who goes, who is out, and a whole game run through the planner.
## Run: godot --headless --path . -s res://tests/baserunning_test.gd

const REL := Vector3(0.0, 2.1, 16.74)
var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _runner(p: Player = null) -> Player:
	return p if p != null else Player.new()


func _grounder(fielder: int, at: Vector3, t: float) -> Dictionary:
	return {"result": "out", "text": "Groundout", "caught_in_air": false, "fielder": fielder,
		"field_pos": at, "field_time": t, "arm": 33.0, "release_time": t + 0.5, "bases": 0,
		"throw": ThrowPlan.make(at + Vector3(0.0, 1.3, 0.0), Defense.FIRST + Vector3(0.0, 1.0, 0.0), t + 0.5, t + 0.5 + at.distance_to(Defense.FIRST) / 33.0 + 0.15, 1)}


func _init() -> void:
	var batter := _runner()
	var on := Player.new()

	# --- Home run: everyone scores.
	var plan := Baserunning.plan({"result": "home_run", "field_time": 4.0}, [on, on, on], 0, batter, _rng(1))
	_check(plan.runs == 4 and plan.final_bases == [null, null, null], "a grand slam scores four")

	# --- A deep fly with a runner on third: the sacrifice fly.
	var sac := 0
	for i in 100:
		var fly := {"result": "out", "text": "Flyout", "caught_in_air": true, "field_pos": Vector3(0.0, 0.0, 85.0),
			"field_time": 4.5, "arm": 33.0, "release_time": 5.0}
		var pl := Baserunning.plan(fly, [null, null, on], 0, batter, _rng(i))
		if pl.runs == 1 and pl.outs_added == 1:
			sac += 1
	_check(sac > 60, "a deep fly with a man on third scores him (%d/100)" % sac)

	# --- Two outs: a caught fly is the third out, nobody tags, no run.
	var fly2 := {"result": "out", "caught_in_air": true, "field_pos": Vector3(0.0, 0.0, 85.0), "field_time": 4.5,
		"arm": 33.0, "release_time": 5.0}
	var pl2 := Baserunning.plan(fly2, [null, null, on], 2, batter, _rng(3))
	_check(pl2.runs == 0 and pl2.outs_added == 1, "no run on a third-out fly")

	# --- Grounder with a runner on first: sometimes two, never two with two outs.
	var dps := 0
	var forces := 0
	for i in 200:
		var pl := Baserunning.plan(_grounder(6, Vector3(6.0, 0.0, 30.0), 1.3), [on, null, null], 0, batter, _rng(i))
		if pl.outs_added == 2:
			dps += 1
		elif pl.outs_added == 1 and String(pl.suffix).contains("force"):
			forces += 1
	_check(dps > 40 and dps <= 200, "a grounder to short with a man on first is usually a double play when fielded cleanly (%d/200)" % dps)
	var no_dp := true
	for i in 100:
		var pl := Baserunning.plan(_grounder(6, Vector3(6.0, 0.0, 30.0), 1.3), [on, null, null], 2, batter, _rng(i))
		if pl.outs_added > 1:
			no_dp = false
	_check(no_dp, "no double play with two outs")

	# --- A ball hit to first base at the bag has no time to turn two at second.
	var plan_pop := Baserunning.plan(_grounder(3, Vector3(-17.5, 0.0, 18.0), 1.2), [on, null, null], 0, batter, _rng(5))
	_check(plan_pop.outs_added >= 1, "something is always out on a ground out")

	# --- Each plan's own books balance: runs + outs + men left on = 1 (batter) + runners on.
	var rng := _rng(99)
	var balance_ok := true
	for i in 300:
		var bases: Array = [on if rng.randf() < 0.4 else null, on if rng.randf() < 0.3 else null, on if rng.randf() < 0.2 else null]
		var n_on := 0
		for b in bases:
			if b != null:
				n_on += 1
		var kinds := ["single", "double", "triple", "out", "out"]
		var kind: String = kinds[rng.randi() % kinds.size()]
		var in_air := rng.randf() < 0.5
		var play := {"result": kind, "text": kind, "bases": 1 + kinds.find(kind) if kind != "out" else 0,
			"caught_in_air": in_air and kind == "out", "fielder": 6, "field_pos": Vector3(rng.randf_range(-30, 30), 0.0, rng.randf_range(20, 90)),
			"field_time": rng.randf_range(1.5, 4.5), "arm": 33.0, "release_time": 4.0}
		play["throw"] = ThrowPlan.make(play.field_pos, Defense.FIRST, 3.0, 3.5, 1)
		var pl := Baserunning.plan(play, bases, 0, batter, rng)
		var on_after := 0
		for b in pl.final_bases:
			if b != null:
				on_after += 1
		# A third out empties the bases, so only count when the inning continues.
		if pl.outs_added < 3:
			if pl.runs + pl.outs_added + on_after != n_on + 1:
				balance_ok = false
				print("  unbalanced: ", play.result, " on=", n_on, " runs=", pl.runs, " outs=", pl.outs_added, " after=", on_after)
				break
	_check(balance_ok, "runs + outs + runners left on always equals the men who were up")

	# --- A human throw: a quick one to first beats the batter, a lob does not.
	var hold := Baserunning.plan_hold([null, null, null], batter, true)
	var bat_arrival: float = hold.runners[hold.runners.size() - 1].arrivals[1]
	var quick := Baserunning.plan_hold([null, null, null], batter, true)
	Baserunning.apply_throw(quick, 1, bat_arrival - 0.6, 0, Vector3(8.0, 0.0, 32.0), _rng(1))
	_check(quick.outs_added == 1, "a throw that beats the batter by 0.6 s is an out")
	var slow := Baserunning.plan_hold([null, null, null], batter, true)
	Baserunning.apply_throw(slow, 1, bat_arrival + 0.6, 0, Vector3(8.0, 0.0, 32.0), _rng(1))
	_check(slow.outs_added == 0 and slow.final_bases[0] != null, "a throw 0.6 s late is a runner on first")

	# --- Force at second with a man on first: the pivot turns two sometimes.
	var dp_count := 0
	var force_missed := 0
	for i in 100:
		var fp := Baserunning.plan_hold([on, null, null], batter, true)
		var run_second: float = Baserunning.runner_to(fp, 2).arrivals[2]
		Baserunning.apply_throw(fp, 2, run_second - 0.15, 0, Vector3(8.0, 0.0, 32.0), _rng(i))
		if fp.outs_added == 2:
			dp_count += 1
		if fp.outs_added < 1:
			force_missed += 1
	_check(force_missed < 8, "a throw to second that beats the runner by 0.15 s almost always gets the force")
	_check(dp_count > 10 and dp_count < 95, "a force at second turns two some of the time (%d/100)" % dp_count)

	# --- A throw to a base nobody is running to is nothing.
	var none := Baserunning.plan_hold([null, null, null], batter, true)
	Baserunning.apply_throw(none, 3, 5.0, 0, Vector3(8.0, 0.0, 32.0), _rng(1))
	_check(none.outs_added == 0, "a throw to a base with nobody coming is no play")

	# --- Which base a throw is aimed at.
	var ss := Vector3(8.5, 0.0, 32.5)
	_check(HumanFielding.pick_base(ss, Defense.FIRST - ss).base == 1, "a throw at first is a throw to first")
	_check(HumanFielding.pick_base(ss, Defense.SECOND - ss).base == 2, "a throw at second is a throw to second")
	_check(HumanFielding.pick_base(ss, Vector3(0.0, 0.0, 1.0)).base == 0, "a throw into center field is wild")
	_check(HumanFielding.throw_speed(2.0, 2.4, 33.0) >= HumanFielding.MIN_THROW_SPEED and HumanFielding.throw_speed(40.0, 2.4, 33.0) <= 33.0 * 1.2 + 0.01,
		"throw speed is bounded by a lob and the arm")
	_check(HumanFielding.in_glove(Vector3.ZERO, Vector3(0.2, 0.1, 0.0)) and not HumanFielding.in_glove(Vector3.ZERO, Vector3(0.6, 0.0, 0.0)),
		"the glove catches within its radius and not outside it")

	# --- Balls in the air: runners go a third of the way, then wait for the ball.
	var catch_play := {"result": "out", "text": "Flyout", "caught_in_air": true, "field_pos": Vector3(10.0, 0.0, 60.0),
		"field_time": 3.6, "arm": 33.0, "release_time": 4.1, "landing_time": 3.6}
	var pc := Baserunning.plan(catch_play, [null, on, null], 0, batter, _rng(4))
	var r2 = null
	for r in pc.runners:
		if r.from == 2:
			r2 = r
	_check(r2 != null and not r2.keys.is_empty(), "a runner on second leaves his base on a medium fly (hedges)")
	var last_key: Array = r2.keys[r2.keys.size() - 1]
	_check((last_key[1] as Vector3).distance_to(Defense.SECOND) < 0.1 and r2.to == 2, "and goes back to touch second after the catch")
	var mid: Array = r2.keys[1]
	_check((mid[1] as Vector3).distance_to(Defense.SECOND) > 3.0 and float(r2.keys[2][0]) >= 3.5,
		"he waited out in the open until the ball was caught")
	var drop := {"result": "single", "bases": 1, "field_pos": Vector3(10.0, 0.0, 60.0), "field_time": 4.2,
		"arm": 33.0, "release_time": 4.7, "landing_time": 3.4}
	var pd := Baserunning.plan(drop, [on, null, null], 0, batter, _rng(4))
	var r1 = null
	for r in pd.runners:
		if r.from == 1:
			r1 = r
	_check(r1 != null and float(r1.arrivals[2]) > 3.4, "a runner on first does not reach second before a fly ball lands (%.1f)" % float(r1.arrivals[2]))
	var liner := {"result": "single", "bases": 1, "field_pos": Vector3(10.0, 0.0, 40.0), "field_time": 2.0,
		"arm": 33.0, "release_time": 2.5, "landing_time": 0.7}
	var pl_liner := Baserunning.plan(liner, [on, null, null], 0, batter, _rng(4))
	var rr1 = null
	for r in pl_liner.runners:
		if r.from == 1:
			rr1 = r
	_check(rr1.hedge == null and float(rr1.arrivals[2]) < 4.0, "a ball through on the ground sends him at once")

	# --- Order is kept: nobody passes the man ahead, and nobody shares a base.
	var order_ok := true
	var rng3 := _rng(321)
	for i in 400:
		var b3: Array = [on if rng3.randf() < 0.6 else null, on if rng3.randf() < 0.5 else null, on if rng3.randf() < 0.4 else null]
		var kind3: String = ["single", "double", "triple", "out", "out"][rng3.randi() % 5]
		var land := rng3.randf_range(0.5, 5.0)
		var play3 := {"result": kind3, "text": kind3, "bases": {"single": 1, "double": 2, "triple": 3}.get(kind3, 0),
			"caught_in_air": kind3 == "out" and rng3.randf() < 0.6, "fielder": 6,
			"field_pos": Vector3(rng3.randf_range(-40, 40), 0.0, rng3.randf_range(15, 100)),
			"field_time": land + 0.1, "landing_time": land, "arm": 33.0, "release_time": land + 0.6}
		play3["throw"] = ThrowPlan.make(play3.field_pos, Defense.FIRST, land, land + 1.0, 1)
		var pl3 := Baserunning.plan(play3, b3, 0, batter, rng3)
		var taken := {}
		for r in pl3.runners:
			if r.out or int(r.to) < 1 or int(r.to) >= 4:
				continue
			if taken.has(int(r.to)):
				order_ok = false
			taken[int(r.to)] = true
		var by_from: Array = []
		for r in pl3.runners:
			if not r.out:
				by_from.append(r)
		by_from.sort_custom(func(a, c): return a.from > c.from)
		for j in range(1, by_from.size()):
			var ahead: RunnerPlan = by_from[j - 1]
			var behind: RunnerPlan = by_from[j]
			if int(behind.to) >= int(ahead.to) and int(ahead.to) < 4:
				order_ok = false
	_check(order_ok, "runners never share a base or pass the man ahead")

	# --- Two outs: everyone runs on contact, nobody waits to see whether it is caught.
	var air2 := {"result": "single", "bases": 1, "field_pos": Vector3(10.0, 0.0, 60.0), "field_time": 4.2,
		"arm": 33.0, "release_time": 4.7, "landing_time": 3.4}
	var p_two := Baserunning.plan(air2, [on, null, null], 2, batter, _rng(4))
	var r_two = null
	for r in p_two.runners:
		if r.from == 1:
			r_two = r
	_check(r_two.hedge == null and float(r_two.arrivals[2]) < 4.5, "with two outs a runner goes right away on a ball in the air")
	var p_one := Baserunning.plan(air2, [on, null, null], 1, batter, _rng(4))
	var r_one = null
	for r in p_one.runners:
		if r.from == 1:
			r_one = r
	_check(r_one.hedge != null and float(r_one.arrivals[2]) > 3.4, "with fewer than two he leads off and waits for it to land")

	# --- Where the throw goes on a ground ball.
	var near_home := {"result": "out", "text": "Groundout", "caught_in_air": false, "fielder": 1, "field_pos": Vector3(0.5, 0.0, 6.0),
		"field_time": 1.1, "arm": 33.0, "release_time": 1.5, "clean_ground": true,
		"throw": ThrowPlan.make(Vector3(0.5, 1.3, 6.0), Defense.FIRST, 1.5, 3.2, 1)}
	var loaded := [on, on, on]
	var rl: Array[RunnerPlan] = []
	for i in [3, 2, 1]:
		rl.append(Baserunning._runner_entry(i, i, on, 1.0))
	rl.append(Baserunning._runner_entry(0, 0, batter, 1.0))
	var opts_home := Baserunning.ground_options(near_home, rl, loaded, 0, true)
	var pick_home := Baserunning.choose_ground_throw(opts_home, true)
	_check(pick_home.kind in ["force", "dphome"] and int(pick_home.base) == 4, "bases loaded and the ball is near the plate: the throw goes home (%s)" % pick_home.kind)

	var ss_play := {"result": "out", "text": "Groundout", "caught_in_air": false, "fielder": 6, "field_pos": Vector3(8.0, 0.0, 33.0),
		"field_time": 1.3, "arm": 33.0, "release_time": 1.75, "clean_ground": true,
		"throw": ThrowPlan.make(Vector3(8.0, 1.3, 33.0), Defense.FIRST, 1.75, 3.7, 1)}
	var r1_only: Array[RunnerPlan] = [Baserunning._runner_entry(1, 1, on, 1.0), Baserunning._runner_entry(0, 0, batter, 1.0)]
	var pick_dp := Baserunning.choose_ground_throw(Baserunning.ground_options(ss_play, r1_only, [on, null, null], 0, true), true)
	_check(pick_dp.kind == "dp2", "runner on first, grounder to short: go for two (%s)" % pick_dp.kind)
	var pick_two_outs := Baserunning.choose_ground_throw(Baserunning.ground_options(ss_play, r1_only, [on, null, null], 2, true), true)
	_check(pick_two_outs.kind != "dp2" and pick_two_outs.kind != "dphome", "with two outs there is no double play to turn (%s)" % pick_two_outs.kind)
	var late_ball := ss_play.duplicate()
	late_ball["field_time"] = 3.6
	late_ball["release_time"] = 4.1
	var pick_late_ball := Baserunning.choose_ground_throw(Baserunning.ground_options(late_ball, r1_only, [on, null, null], 0, true), true)
	_check(pick_late_ball.kind == "first", "a ball fielded too late to get the runner is taken at first (%s)" % pick_late_ball.kind)
	var r3_only: Array[RunnerPlan] = [Baserunning._runner_entry(3, 3, on, 1.0), Baserunning._runner_entry(0, 0, batter, 1.0)]
	var pick_no_force := Baserunning.choose_ground_throw(Baserunning.ground_options(ss_play, r3_only, [null, null, on], 0, true), true)
	_check(pick_no_force.kind == "first", "a runner who is not forced is not a force play (%s)" % pick_no_force.kind)

	# --- Fielder's choice: a slow runner on first, a ball fielded late: the batter beats the throw
	# to first, but the force at second is still there.
	var slow_runner := Player.new()
	slow_runner.speed = 0.0
	var fast_batter := Player.new()
	fast_batter.speed = 100.0
	var fc_count := 0
	var fc_bad := 0
	for i in 100:
		var fcplay := {"result": "single", "bases": 1, "text": "Single", "caught_in_air": false, "fielder": 6,
			"field_pos": Vector3(8.0, 0.0, 33.0), "field_time": 2.0, "arm": 33.0, "release_time": 2.45, "clean_ground": true,
			"throw": ThrowPlan.make(Vector3(8.0, 1.3, 33.0), Defense.FIRST, 2.45, 3.6, 1)}
		var fcp := Baserunning.plan(fcplay, [slow_runner, null, null], 0, fast_batter, _rng(i))
		if fcp.result == "fielders_choice":
			fc_count += 1
			var outs_n := 0
			var from_out := -1
			for r in fcp.runners:
				if r.out:
					outs_n += 1
					from_out = int(r.from)
			if outs_n != 1 or from_out != 1:
				fc_bad += 1
	_check(fc_count > 40, "a batter who beats the throw can still be a fielder's choice on a slow lead runner (%d/100)" % fc_count)
	_check(fc_bad == 0, "and it is the runner from first, alone, who is out")

	# --- On a hit the defense has one throw: where it is most likely to get somebody.
	var multi_out := false
	var scored_untouched_throw_home := false
	for i in 300:
		var rngx := _rng(5000 + i)
		var bx: Array = [on, on if rngx.randf() < 0.7 else null, on if rngx.randf() < 0.5 else null]
		var dbl := {"result": "double", "bases": 2, "field_pos": Vector3(rngx.randf_range(-35, 35), 0.0, rngx.randf_range(55, 100)),
			"field_time": rngx.randf_range(2.5, 4.5), "arm": 33.0, "landing_time": 1.0}
		dbl["release_time"] = dbl.field_time + 0.6
		var pdx := Baserunning.plan(dbl, bx, 0, batter, rngx)
		var attempt_outs := 0
		for r in pdx.runners:
			if r.out:
				attempt_outs += 1
		if attempt_outs > 1:
			multi_out = true
	_check(not multi_out, "one throw on a hit puts out at most one runner")

	# A runner who will score easily is not thrown at: the throw goes to hold the batter.
	var easy := {"result": "single", "bases": 1, "field_pos": Vector3(20.0, 0.0, 90.0), "field_time": 4.5,
		"arm": 33.0, "release_time": 5.1, "landing_time": 1.0}
	var pe := Baserunning.plan(easy, [null, null, on], 0, batter, _rng(9))
	var throw_home := false
	for th in pe.throws:
		if int(th.base) == 4:
			throw_home = true
	_check(not throw_home and pe.runs == 1, "a runner who scores easily from third is not thrown at")

	# A close play at the plate: the throw goes home, and the runner is sometimes out, sometimes safe.
	var close := {"result": "single", "bases": 1, "field_pos": Vector3(8.0, 0.0, 52.0), "field_time": 3.8,
		"arm": 33.0, "release_time": 4.3, "landing_time": 1.0}
	var outs_home := 0
	var throws_home := 0
	for i in 200:
		var pcl := Baserunning.plan(close, [null, on, null], 0, batter, _rng(700 + i))
		var homed := false
		for th in pcl.throws:
			if int(th.base) == 4:
				homed = true
		if homed:
			throws_home += 1
			for r in pcl.runners:
				if r.out and int(r.out_base) == 4:
					outs_home += 1
	_check(throws_home > 100, "with a runner on second on a shallow single the throw goes home (%d/200)" % throws_home)
	_check(outs_home > 5 and outs_home < throws_home - 5, "and it is a real play at the plate: out %d of %d throws" % [outs_home, throws_home])

	# --- The infield fly rule: runners on first and second, fewer than two outs, a high shallow fly.
	var pop := {"result": "single", "bases": 1, "text": "Single", "caught_in_air": false, "fielder": 6,
		"field_pos": Vector3(8.0, 0.0, 30.0), "field_time": 4.6, "arm": 33.0, "release_time": 5.0,
		"landing_time": 4.2, "infield_fly": true}
	var pif := Baserunning.plan(pop, [on, on, null], 0, batter, _rng(3))
	var bat_out := false
	var moved := false
	for r in pif.runners:
		if r.from == 0 and r.out:
			bat_out = true
		if r.from > 0 and r.to != r.from:
			moved = true
	_check(bat_out and pif.outs_added == 1 and pif.text == "Infield fly rule, batter is out",
		"a dropped infield fly with runners on first and second is still an out")
	_check(not moved, "and nobody is forced to run on it")
	var pif2 := Baserunning.plan(pop, [on, null, null], 0, batter, _rng(3))
	_check(pif2.outs_added == 0, "with only first base occupied the rule does not apply")
	var pif3 := Baserunning.plan(pop, [on, on, null], 2, batter, _rng(3))
	var bat3_out := false
	for r in pif3.runners:
		if r.from == 0 and r.out:
			bat3_out = true
	_check(not bat3_out and pif3.text != "Infield fly rule, batter is out", "nor with two outs")
	# Everyone advances on a wild pitch.
	var adv := Baserunning.plan_advance([on, on, on])
	_check(adv.runs == 1 and adv.runners.size() == 3, "plan_advance moves the three runners and scores one")

	# --- A triple play: runners on first and second, nobody out, a hard grounder to third.
	var tp_play := {"result": "out", "text": "Groundout", "caught_in_air": false, "fielder": 5, "field_pos": Vector3(17.6, 0.0, 22.0),
		"field_time": 0.7, "arm": 38.0, "release_time": 1.0, "clean_ground": true,
		"throw": ThrowPlan.make(Vector3(17.6, 1.3, 22.0), Defense.FIRST, 1.0, 2.9, 1)}
	var tp_count := 0
	var dp_count2 := 0
	var rng_tp := _rng(808)
	for i in 300:
		var pt := Baserunning.plan(tp_play, [on, on, null], 0, batter, rng_tp)
		if pt.outs_added == 3:
			tp_count += 1
		elif pt.outs_added == 2:
			dp_count2 += 1
	print("  300 hard grounders to third with runners on first and second, nobody out: %d triple plays, %d double plays" % [tp_count, dp_count2])
	_check(tp_count > 0 and tp_count < 150, "a triple play can happen, but not every time (%d/300)" % tp_count)

	# --- A line drive caught: a runner who broke can be doubled off.
	var doubled := 0
	var rng_ld := _rng(909)
	for i in 400:
		var liner_play := {"result": "out", "text": "Lineout", "caught_in_air": true, "fielder": 3, "field_pos": Vector3(-17.2, 0.0, 22.0),
			"field_time": 0.9, "arm": 33.0, "release_time": 1.25, "landing_time": 0.9, "apex": 3.5}
		var pld := Baserunning.plan(liner_play, [on, null, null], 0, batter, rng_ld)
		if pld.outs_added == 2:
			doubled += 1
	print("  400 line drives caught with a runner on first, nobody out: %d doubled off" % doubled)
	_check(doubled > 2 and doubled < 80, "a runner is sometimes doubled off first on a line drive (%d/400)" % doubled)

	# --- The time play: a run that scores before a tag for the third out counts; a force erases it.
	var time_runs := 0
	var force_runs := 0
	for i in 200:
		var rng_tm := _rng(3000 + i)
		# A double: the runner from second scores, the batter is thrown out stretching for third with two outs.
		var dbl2 := {"result": "double", "bases": 2, "field_pos": Vector3(0.0, 0.0, 95.0), "field_time": 4.2, "arm": 33.0,
			"release_time": 4.8, "landing_time": 1.2}
		var ptm := Baserunning.plan(dbl2, [null, on, null], 2, batter, rng_tm)
		if ptm.outs_added >= 1:
			time_runs += ptm.runs
	_check(true, "(time-play runs counted across 200 doubles with two outs: %d)" % time_runs)
	var force_plan := Baserunning.plan(_grounder(6, Vector3(6.0, 0.0, 30.0), 1.3), [on, null, on], 2, batter, _rng(5))
	_check(force_plan.runs == 0, "a run does not count when the third out is the batter at first")

	# --- Whole games through the planner.
	var home := Team.generate("Home", 52.0, 9)
	var pitches := 0
	var pas := 0
	var runs_total := 0
	var dp_total := 0
	var finished := 0
	var singles_with_2nd := 0
	var scored_from_2nd := 0
	for seed_value in 16:
		var game := GameState.new(Team.generate("Away", 52.0, 14).lineup, 9)
		game.rng.seed = 11 + seed_value
		var pitcher := AIPitcher.new(home.player_at(1))
		pitcher.rng.seed = 12 + seed_value
		var defense := Defense.from_team(home)
		defense.rng.seed = 13 + seed_value
		var ai := BatterAI.new()
		ai.rng.seed = 14 + seed_value
		var guard := 0
		while not game.over and guard < 4000:
			guard += 1
			var p := pitcher.next_pitch(REL)
			var cur := game.current_batter()
			ai.profile = BatterProfile.from_player(cur)
			if not p.analysis.reached:
				game.pitch("ball")
				continue
			var r := ai.evaluate(p)
			match r.kind:
				"take":
					game.pitch("called_strike" if p.analysis.strike else "ball")
				"whiff":
					game.pitch("swinging_strike")
				"foul tip":
					game.pitch("foul_tip")
				_:
					var sim := BattedBall.simulate(r.contact_pos, r.vel, r.spin)
					var play := defense.resolve(sim, cur.run_factor())
					if not sim.fair and not sim.home_run and play.result != "out":
						game.pitch("foul")
					else:
						var lone_second: bool = game.bases[0] == null and game.bases[1] != null and game.bases[2] == null
						var bp := Baserunning.plan(play, game.bases, game.outs, cur, game.rng)
						var ev := game.in_play(play, bp)
						if lone_second and play.result == "single":
							singles_with_2nd += 1
							if ev.runs > 0:
								scored_from_2nd += 1
						if ev.outs_added == 2:
							dp_total += 1
		if game.over:
			finished += 1
		pitches += game.pitch_count
		pas += game.batters_faced
		runs_total += game.runs
	_check(finished == 16, "every simulated game finishes (%d/16)" % finished)
	print("  runner on second scored on %d of %d singles" % [scored_from_2nd, singles_with_2nd])
	if singles_with_2nd >= 8:
		var share := float(scored_from_2nd) / singles_with_2nd
		_check(share > 0.2 and share < 0.9, "a runner on second scores on a single some of the time (%.0f%%)" % (share * 100.0))
	var rpg := runs_total / 16.0
	print("  %d games: %.1f runs/game, %.1f pitches/PA, %d double plays" % [8, rpg, float(pitches) / maxi(pas, 1), dp_total])
	_check(rpg > 1.5 and rpg < 12.0, "runs per game is baseball-ish (%.1f)" % rpg)

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
