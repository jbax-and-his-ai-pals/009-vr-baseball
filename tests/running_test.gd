extends SceneTree
## The running game: steals, pickoffs, balks.
## Run: godot --headless --path . -s res://tests/running_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _runner(speed: float, aggression: float = 50.0) -> Player:
	var p := Player.new()
	p.speed = speed
	p.aggression = aggression
	return p


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5

	# --- Who goes.
	var fast := _runner(90.0, 70.0)
	var slow := _runner(20.0, 40.0)
	var open2 := [fast, null, null]
	_check(StealModel.steal_chance(fast, 1, 0, open2) > StealModel.steal_chance(slow, 1, 0, [slow, null, null]) * 3.0,
		"a fast, aggressive runner goes far more often than a slow one")
	_check(StealModel.steal_chance(fast, 1, 0, [fast, fast, null]) == 0.0, "nobody steals into an occupied base")
	_check(StealModel.steal_chance(fast, 2, 0, [null, fast, null]) < StealModel.steal_chance(fast, 1, 0, open2),
		"stealing third is rarer than stealing second")
	_check(StealModel.steal_chance(fast, 3, 0, [null, null, fast]) == 0.0, "and nobody steals home")

	# --- Whether he makes it: your delivery time is the lever.
	var runner := _runner(55.0)
	var lead := StealModel.lead(runner, 3)
	var run_t := StealModel.run_time(runner, 1, lead)
	var quick_safe := 0
	var slow_safe := 0
	for i in 400:
		if StealModel.resolve(0.65, 0.50, run_t, rng).safe:
			quick_safe += 1
		if StealModel.resolve(1.45, 0.50, run_t, rng).safe:
			slow_safe += 1
	print("  runner needs %.2f s from a %.1f m lead; safe %d%% vs a 0.65 s delivery, %d%% vs a 1.45 s one" % [
		run_t, lead, quick_safe * 100 / 400, slow_safe * 100 / 400])
	_check(slow_safe > quick_safe + 120, "a slow delivery makes the steal much more likely to succeed")
	_check(quick_safe < 300, "a quick delivery gets a fair number of runners")
	_check(slow_safe > 300, "and a slow one gets almost nobody")

	# --- Leads: they grow when you ignore them and shrink after a throw over.
	_check(StealModel.lead(runner, 6) > StealModel.lead(runner, 1) + 0.5, "ignored, a runner takes a bigger lead")
	_check(StealModel.lead(runner, 0) < StealModel.lead(runner, 3), "and it shrinks right after a throw over")
	_check(StealModel.lead(runner, 20) <= StealModel.LEAD_MAX, "but never past the maximum")

	# --- Pickoffs.
	var long_lead := StealModel.pickoff_chance(3.8, 3.0, 28.0, runner)
	var short_lead := StealModel.pickoff_chance(1.8, 3.0, 28.0, runner)
	var wild_throw := StealModel.pickoff_chance(3.8, 25.0, 28.0, runner)
	_check(long_lead > 0.2 and short_lead == 0.0, "a big lead can be picked off, a short one cannot (%.2f / %.2f)" % [long_lead, short_lead])
	_check(wild_throw == 0.0, "a throw way off the line never gets him")

	# --- Balks.
	_check(StealModel.is_balk(true, true, false, false), "starting the motion and not throwing, with a runner on, is a balk")
	_check(StealModel.is_balk(true, false, false, true), "throwing to a base nobody is on is a balk")
	_check(not StealModel.is_balk(false, true, false, false), "nothing is a balk with the bases empty")
	_check(not StealModel.is_balk(true, true, true, false), "a delivery that ends in a pitch is not a balk")

	# --- The scorebook.
	var g := GameState.new(Team.generate("A", 50.0, 5).lineup, 9)
	g.bases = [fast, null, null]
	var sb := g.steal(1, true)
	_check(g.bases[0] == null and g.bases[1] != null and g.stolen_bases == 1 and sb.result == "stolen_base", "a stolen base moves him to second")
	var cs := g.steal(2, false)
	_check(g.bases[1] == null and g.outs == 1 and g.caught_stealing == 1 and cs.outs_added == 1, "caught stealing is an out and he is gone")
	g.bases = [fast, null, null]
	g.outs = 2
	var third := g.steal(1, false)
	_check(third.half_over and g.outs == 0 and g.balls == 0 and g.strikes == 0, "caught stealing for the third out ends the inning and clears the count")
	g = GameState.new(Team.generate("A", 50.0, 5).lineup, 9)
	g.bases = [null, fast, null]
	var po := g.pickoff(2)
	_check(po.outs_added == 1 and g.bases[1] == null and g.pickoffs == 1, "a pickoff is an out")
	g.bases = [fast, null, fast]
	var bk := g.balk()
	_check(bk.runs == 1 and g.bases[1] != null and g.bases[0] == null and g.balks == 1 and g.wild_pitches == 0,
		"a balk moves every runner up and the man on third scores")

	# --- Animating a steal.
	var plan := Baserunning.plan_steal(1, fast, 3.0)
	_check(plan.runners.size() == 1 and plan.runners[0].to == 2 and plan.runners[0].arrivals.has(2), "a steal plan sends one runner to the next base")
	Baserunning.steal_out(plan, 2.7)
	_check(plan.runners[0].out and plan.outs_added == 1 and float(plan.runners[0].arrivals[2]) <= 2.7, "an out steal ends with him tagged at the bag")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
