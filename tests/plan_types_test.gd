extends SceneTree
## The typed plans: a play's baserunning is a PlayPlan of RunnerPlans, PlanEvents and ThrowPlans, with the
## fields spelled out in one place (and a typo is an error, not a silently missing key).
## Run: godot --headless --path . -s res://tests/plan_types_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	# The pieces.
	var r := RunnerPlan.make(2, null, 1.1)
	_check(r.from == 2 and r.to == 2 and r.run_factor == 1.1 and not r.out and r.hedge == null and r.keys.is_empty() and r.arrivals.is_empty(), "a runner starts on his base, not out, with nothing planned")
	var hg := RunnerPlan.Hedge.new()
	_check(not hg.has_return(), "a hedge has no return unless one is set")
	hg.return_at = 3.2
	_check(hg.has_return(), "and has one when it is")
	var e := PlanEvent.make(1.5, 3, "OUT", "out")
	_check(e.t == 1.5 and e.base == 3 and e.text == "OUT" and e.kind == "out" and not e.has_at() and e.who == null, "an event is at its base unless it says where")
	_check(PlanEvent.make(0.1, 0, "BALK", "out", Vector3(0.0, 0.0, 0.0)).has_at(), "a label can sit somewhere else (even at the origin)")
	var t := ThrowPlan.make(Vector3(1, 2, 3), Vector3(4, 5, 6), 1.0, 2.0, 1)
	_check(t.from == Vector3(1, 2, 3) and t.t1 == 2.0 and t.base == 1 and t.by == 0 and t.rec == 0, "a throw knows who throws and catches only once the director says")
	var p := PlayPlan.new()
	_check(p.runners.is_empty() and p.runs == 0 and p.text == "" and p.result == "" and p.cover == null and p.hide_batter_at == 0.25 and p.final_bases == [null, null, null], "an empty plan: nobody, no words, the batter leaves at 0.25 s")
	var runner := RunnerPlan.make(1, null, 1.0)
	runner.to = 2
	runner.arrivals[2] = 3.1
	p.runners.append(runner)
	p.add_event(3.1, 2, "SAFE", "safe")
	p.add_throw(Vector3.ZERO, Vector3.ONE, 1.0, 2.0, 2)
	_check(p.runner_to(2) == runner and p.runner_to(3) == null and p.events.size() == 1 and p.throws.size() == 1, "a plan finds who is going to a base and collects events and throws")
	runner.out = true
	_check(p.runner_to(2) == null, "not a man who is out")

	# What Baserunning makes.
	var batter := Player.new()
	var on := Player.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var hr := Baserunning.plan({"result": "home_run", "field_time": 4.0}, [on, null, null], 0, batter, rng)
	_check(hr is PlayPlan and hr.runners.size() == 2 and hr.runners[0] is RunnerPlan and hr.runs == 2, "a home run is a PlayPlan with two RunnerPlans that score")
	_check(hr.events.size() >= 1 and hr.events[0] is PlanEvent, "and its calls are PlanEvents")
	var grounder := {"result": "out", "field_pos": Vector3(6.0, 0.0, 30.0), "field_time": 1.3, "arm": 33.0, "release_time": 1.75, "fielder": 6, "caught_in_air": false}
	var gp := Baserunning.plan(grounder, [on, null, null], 0, batter, rng)
	_check(gp.throws.size() >= 1 and gp.throws[0] is ThrowPlan and gp.throws[0].t1 > gp.throws[0].t0, "a ground out has its throws as ThrowPlans, leaving before they arrive")
	_check(gp.final_bases.size() == 3 and gp.end_time > 1.0, "and says where everyone ends up and when it is over")
	var steal := Baserunning.plan_steal(1, on, 3.2)
	_check(steal.steal and steal.runners.size() == 1 and steal.hide_batter_at > 1000.0, "a steal plan is marked as one and never hides the batter")
	Baserunning.steal_out(steal, 2.9)
	_check(steal.runners[0].out and steal.runners[0].out_base == 2 and steal.outs_added == 1 and steal.events.size() == 1, "and can be settled as an out at second")
	var rd := Baserunning.plan_rundown(1, on, "rundown_out")
	_check(rd.rundown and not rd.turns.is_empty() and rd.fielders_at == [1, 2] and rd.runners[0].keys.size() > 2, "a rundown has its turns, its fielders and the runner's back-and-forth keyframes")
	var leave := Baserunning.plan_leave(batter)
	_check(leave.runners[0].out and leave.outs_added == 1 and is_equal_approx(leave.hide_batter_at, 0.7), "a strikeout has the batter walk off")
	var hold := Baserunning.plan_hold([on, null, null], batter, true)
	_check(hold.hold and hold.batter_safe, "a held play (a human has the ball) is marked")
	var fly := {"result": "out", "field_pos": Vector3(0.0, 1.0, 70.0), "field_time": 4.0, "arm": 33.0, "release_time": 4.5, "fielder": 8, "caught_in_air": true, "landing_time": 4.0, "apex": 25.0}
	var hedged := false
	for i in 30:
		var fp := Baserunning.plan(fly, [null, on, null], 0, batter, rng)
		for rr in fp.runners:
			if rr.hedge != null:
				hedged = true
				_check(rr.hedge.t_leave >= rr.hedge.t_reach and not rr.keys.is_empty(), "a runner who hedges has the keyframes to show it")
				break
		if hedged:
			break
	_check(hedged, "a runner on second hedges on a deep fly")
	var scored := GameState.new([batter] as Array[Player], 3)
	var ev := scored.in_play({"result": "home_run"}, hr)
	_check(int(ev.runs) == 2 and scored.runs == 2, "the scorebook reads a typed plan")
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
