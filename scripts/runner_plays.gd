class_name RunnerPlays
extends RefCounted
## Everything that happens on the bases that is not a batted ball: a runner breaking for the next base and whether he makes it, the
## pitcher throwing over (yours or the AI's), a rundown, a balk, and the throws that fly between fielders. It owns the runners' leads and
## the steal in progress; the scene (`host`) owns everything else.

var host                                    # the bullpen scene (untyped: its members are reached by name)

const RECEIVE_FOR_STEAL := {1: 6, 2: 5}

var pickoff_override := ""                 # tests: force a throw over's outcome
var node_moves: Array = []                 # fielders walking into position for a rundown
var steal := {}                     # a runner who is going: {from, runner, run_t, plan, apply_at, done}
var leads := [2.4, 2.4, 2.4]        # meters each runner stands off his base
var since_throw := [5, 5, 5]        # pitches since you last threw over, per base
var flights: Array = []             # balls in the air that are not a pitch or a hit (throws)


## Your motion has started (or an AI pitcher is about to throw): a runner may break for the next
## base. Only one runner goes at a time.
func on_delivery_start() -> void:
	if host._runners_on():
		GameLog.event("delivery_start", {"s": host.slog.brief(), "t_hand": host._delivery_start})
	if host._game == null or not host._runners_on() or not steal.is_empty() or not host._aux_play.is_empty() or host._game.over:
		return
	var tired = 0.0
	if host._mode.human_pitcher:
		tired = host.manager.arm_fatigue()
	for base in [2, 1]:
		var runner = host._game.bases[base - 1]
		if not (runner is Player):
			continue
		var p = StealModel.steal_chance(runner as Player, base, host._game.outs, host._game.bases, tired)
		if host._run_rng.randf() >= p:
			continue
		var lead: float = float(leads[base - 1])
		var run_t = StealModel.run_time(runner as Player, base, lead)
		var plan = Baserunning.plan_steal(base, runner, run_t)
		host._aux_play = {"plan": plan, "t": 0.0}
		steal = {"from": base, "runner": runner, "run_t": run_t, "plan": plan}
		host.slog.record("steal_break", {"base": base, "runner": (runner as Player).name, "chance": snappedf(p, 0.001), "lead": lead,
			"run_t": run_t, "delivery_so_far": host._last_delivery})
		host._refresh_base_runners()
		return
	# No steal: perhaps a play is on (squeeze, hit and run).
	var call = StealModel.play_call(host._game.bases, host._game.outs, host._game.strikes, host._game.inning, host._game.runs - host._game.home_score,
		host._batter_ai.profile, host._run_rng)
	if call == "":
		return
	var from_base = 3 if call == "squeeze" else 1
	var rnr = host._game.bases[from_base - 1]
	if not (rnr is Player):
		return
	var lead_c: float = float(leads[from_base - 1])
	var run_c = StealModel.run_time(rnr as Player, from_base, lead_c)
	var plan_c = Baserunning.plan_steal(from_base, rnr, run_c)
	host._aux_play = {"plan": plan_c, "t": 0.0}
	steal = {"from": from_base, "runner": rnr, "run_t": run_c, "plan": plan_c, "call": call}
	host._bat_call = call
	host.slog.record("play_call", {"call": call, "base": from_base, "runner": (rnr as Player).name, "batter": host._batter_ai.profile.name})
	host.hud.show_notice("%s!" % call.replace("_", " ").to_upper(), true)
	host._refresh_base_runners()


## The pitch is in the catcher's glove (or it was hit and the steal was cancelled elsewhere):
## did the runner make it? When you are the catcher the throw is yours (see _catcher_release).
func resolve_steal(a: Dictionary) -> void:
	if steal.is_empty() or steal.has("apply_at") or steal.has("await"):
		return
	var base = int(steal.from)
	var t_now = float(host._aux_play.get("t", 0.0)) if not host._aux_play.is_empty() else 0.0
	if host.fielding.is_catcher() and base < 3 and not steal.has("call"):
		# He is going: get the ball out of the glove with your throwing hand and throw it to the base.
		steal["await"] = {"left": maxf(float(steal.run_t) - t_now - 0.2, 0.8), "a_time": float(a.get("time", 0.5))}
		host.fielding.field_samples.clear()
		host.hud.show_notice("THROW HIM OUT!", true)
		host._haptics.play("ui_error", 0.5)
		return
	var res = StealModel.resolve(host._last_delivery, float(a.get("time", 0.5)), float(steal.run_t), host._run_rng,
		0.4 if base == 3 else StealModel.POP_TIME)       # at the plate the catcher just tags him
	apply_steal(bool(res.safe), float(res.t_ball), float(a.get("time", 0.0)), {"t_ball": res.t_ball, "t_run": res.t_run, "delivery": host._last_delivery})


## Put a steal's result in the picture and in the book (_finish_steal does the book when the picture gets there).
func apply_steal(safe: bool, t_ball_raw: float, flight: float, info: Dictionary) -> void:
	var plan: Dictionary = steal.plan
	var t_now = float(host._aux_play.get("t", 0.0)) if not host._aux_play.is_empty() else 0.0
	var base = int(steal.from)
	var t_ball: float = maxf(t_ball_raw, t_now + 0.3)
	if safe:
		Baserunning.steal_safe(plan)
	else:
		Baserunning.steal_out(plan, t_ball)
	# The catcher's throw: from the plate to the glove of the man covering the base.
	var cover: int = RECEIVE_FOR_STEAL.get(base, 2)
	var glove: Vector3 = (Baserunning.RECEIVE_SPOT[base + 1] as Vector3) + Vector3(0.0, 1.15, 0.0)
	var dur = Vector2(0.0 - glove.x, -1.35 - glove.z).length() / 33.0 + 0.1
	if base < 3:
		spawn_flight(Vector3(0.0, 1.5, -1.2), glove, maxf(t_ball - dur - t_now, 0.05), dur, cover, not safe)
		if not host.fielding.is_catcher():
			# He comes up out of the crouch and throws; the arm starts early enough that the ball leaves on time.
			host._crew.pop_throw_in(maxf(maxf(t_ball - dur - t_now, 0.05) - 0.42, 0.0), glove)
	steal["safe"] = safe
	steal["apply_at"] = t_ball
	var entry = {"base": base, "safe": safe, "flight": flight}
	entry.merge(info)
	host.slog.record("steal_resolve", entry)
	host.hud.last_report_extra = "STEAL ATTEMPT: %s" % ("safe" if safe else "OUT")


func finish_steal() -> void:
	if steal.is_empty() or steal.get("done", false):
		return
	steal["done"] = true
	var base = int(steal.from)
	# The scorebook only changes if he is still on that base (a walk or an inning change may have moved him).
	if host._game.bases[base - 1] == steal.runner:
		var ev = host._game.steal(base, bool(steal.safe))
		host.hud.last_report = ("STOLEN BASE\n" if steal.safe else "CAUGHT STEALING\n") + host.hud.event_text(ev)
		host._after_event(ev)
		host.hud.refresh_hud()
	steal = {}
	host._bat_call = ""


## A throw to a base (not a pitch): where it goes, whether it gets him, or a balk.
func do_pickoff(base: int, from: Vector3, vel: Vector3, err: float, quick: float = 0.7) -> void:
	if host._mode.human_pitcher:
		host._haptics.play("release", 0.5)
	var runner = host._game.bases[base - 1]
	var glove: Vector3 = (Baserunning.RECEIVE_SPOT[base] as Vector3) + Vector3(0.0, 1.15, 0.0)
	var speed = clampf(vel.length() * 0.85, 12.0, 30.0)
	var dist = Vector2(from.x - glove.x, from.z - glove.z).length()
	var dur = dist / speed + 0.1
	var receiver = HumanFielding.receiver(base, 1)
	spawn_flight(from, glove, 0.0, dur, receiver)
	for i in 3:
		since_throw[i] = 0
	if runner == null:
		if host._runners_on():
			call_balk("Threw to an empty base")
		else:
			host.hud.show_notice("Throw to %s" % ["", "first", "second", "third"][base])
		return
	var lefty: bool = (host.throwing_hand == &"left_hand") if host._mode.human_pitcher else not host._ai_pitcher.player.throws_right
	var chance = StealModel.pickoff_chance(float(leads[base - 1]), err, vel.length(), runner as Player, quick, base, lefty)
	var lead_now = float(leads[base - 1])
	var outcome = pickoff_override if pickoff_override != "" else StealModel.pickoff_outcome(chance, lead_now, host._run_rng)
	if outcome == "rundown_safe_ahead" and base < 3 and host._game.bases[base] != null:
		outcome = "rundown_safe_back"                 # the next base is taken
	var out = outcome == "out"
	host.slog.record("pickoff", {"base": base, "runner": (runner as Player).name, "lead": lead_now, "err_deg": err, "quick": snappedf(quick, 0.01), "lefty": lefty,
		"speed": vel.length(), "chance": snappedf(chance, 0.001), "outcome": outcome})
	if outcome.begins_with("rundown") and host._aux_play.is_empty():
		start_rundown(base, runner, outcome)
		return
	if host._aux_play.is_empty():
		var bag = Baserunning.BASE_POS[base] as Vector3
		var plan = Baserunning.plan_dive_back(base, runner, host._director.stand_for(base), PlayDirector.BASE_STANDS[base - 1], dur + 0.25, out)
		host._aux_play = {"plan": plan, "t": 0.0}
	leads[base - 1] = StealModel.lead_after_throw()
	if out:
		var ev = host._game.pickoff(base)
		host.hud.last_report = "PICKED OFF at %s\n" % ["", "first", "second", "third"][base] + host.hud.event_text(ev)
		host._after_event(ev)
	else:
		host.hud.last_report = "Throw over to %s: safe" % ["", "first", "second", "third"][base]
	host.hud.refresh_hud()


## A throw over catches him between the bases: two fielders run him back and forth. The book is settled
## now (out, back safe, or on to the next base); the picture plays it out.
func start_rundown(base: int, runner, outcome: String) -> void:
	var before = host._game.bases.duplicate()
	var plan = Baserunning.plan_rundown(base, runner, outcome)
	host._aux_play = {"plan": plan, "t": 0.0}
	leads[base - 1] = StealModel.lead_after_throw()
	var behind = int(HumanFielding.receiver(base, 1))
	var ahead = 2 if base >= 3 else (5 if base == 2 else 4)
	if base == 2:
		ahead = 5
	elif base == 1:
		ahead = 6 if behind == 4 else 4
	var spot_b: Vector3 = Baserunning.RECEIVE_SPOT[base]
	var spot_a: Vector3 = Baserunning.RECEIVE_SPOT[mini(base + 1, 4)]
	# The fielders move to their bags, and the ball goes back and forth as the runner turns.
	move_node(host._field_nodes.get(behind), spot_b, 0.5)
	move_node(host._field_nodes.get(ahead), spot_a, 0.6)
	var hand = Vector3(0.0, 1.5, 0.0)
	var throws: Array = [0.4] + (plan.turns as Array).map(func(t): return float(t) - 0.2)
	var holder_is_behind = true
	for tt in throws:
		var from_spot: Vector3 = (spot_b if holder_is_behind else spot_a) + hand
		var to_spot: Vector3 = (spot_a if holder_is_behind else spot_b) + Vector3(0.0, 1.15, 0.0)
		spawn_flight(from_spot, to_spot, float(tt), 0.42, ahead if holder_is_behind else behind)
		holder_is_behind = not holder_is_behind
	var text = ""
	match outcome:
		"rundown_out":
			var ev = host._game.pickoff(base)
			text = "RUN DOWN between %s and %s\n" % [["", "first", "second", "third"][base], ["", "second", "third", "home"][base]] + host.hud.event_text(ev)
			host._after_event(ev)
		"rundown_safe_ahead":
			var ev2 = host._game.advance_runner(base)
			text = "Beats the rundown!\n" + host.hud.event_text(ev2)
			host._after_event(ev2)
		_:
			text = "In a rundown, but he gets back safe"
	host.hud.last_report = text
	host._haptics.play("buzz", 0.3)
	host._refresh_base_runners(before)             # the figure keeps running until the picture is done
	host.hud.refresh_hud()


func move_node(node: Node3D, to: Vector3, seconds: float) -> void:
	if node == null:
		return
	node_moves.append({"node": node, "from": node.position, "to": Vector3(to.x, 0.0, to.z), "t": 0.0, "dur": seconds})


func call_balk(why: String) -> void:
	host._haptics.play("buzz")
	host.slog.record("balk", {"why": why})
	host._sound.umpire_says_later(0.2, "ump_balk")
	var before = host._game.bases.duplicate()
	var ev = host._game.balk()
	if ev.get("result", "") == "":
		return
	if host._aux_play.is_empty():
		var plan = Baserunning.plan_advance(before)
		(plan["events"] as Array).append({"t": 0.1, "base": 0, "text": "BALK", "kind": "out", "at": Vector3(0.0, 0.0, 0.0)})
		host._aux_play = {"plan": plan, "t": 0.0}
		host._refresh_base_runners(before)
	host.hud.last_report = "BALK - %s\n" % why + host.hud.event_text(ev)
	host._after_event(ev)
	host.hud.refresh_hud()


## A ball in the air that is a throw: spawn it with a delay and a duration; the receiver puts his
## glove up as it arrives.
func spawn_flight(from: Vector3, to: Vector3, delay: float, dur: float, receiver: int, tag: bool = false) -> void:
	var b = host._make_ball()
	b.visible = false
	flights.append({"ball": b, "from": from, "to": to, "t": 0.0, "delay": delay, "dur": maxf(dur, 0.1),
		"receiver": receiver, "caught": false, "tag": tag})


func update_flights(delta: float) -> void:
	for i in range(node_moves.size() - 1, -1, -1):
		var nm: Dictionary = node_moves[i]
		nm.t += delta
		var nn: Node3D = nm.node
		if not is_instance_valid(nn):
			node_moves.remove_at(i)
			continue
		var u = clampf(float(nm.t) / float(nm.dur), 0.0, 1.0)
		var dir: Vector3 = (nm.to as Vector3) - (nm.from as Vector3)
		nn.position = (nm.from as Vector3).lerp(nm.to, u)
		if u < 1.0 and dir.length() > 0.2:
			nn.rotation.y = atan2(dir.x, dir.z)
		if u >= 1.0:
			node_moves.remove_at(i)
	for i in range(flights.size() - 1, -1, -1):
		var f: Dictionary = flights[i]
		f.t += delta
		var local = float(f.t) - float(f.delay)
		var ball: Node3D = f.ball
		if local < 0.0:
			continue
		var u = clampf(local / float(f.dur), 0.0, 1.0)
		var from: Vector3 = f.from
		var to: Vector3 = f.to
		var d = Vector2(from.x - to.x, from.z - to.z).length()
		ball.visible = true
		var bpos = from.lerp(to, u) + Vector3(0.0, clampf(0.07 * d, 0.2, 4.0) * 4.0 * u * (1.0 - u), 0.0)
		var catcher_node = host._field_nodes.get(int(f.receiver))
		if catcher_node is Doll:
			bpos = bpos.lerp((catcher_node as Doll).glove_world(), smoothstep(0.75, 0.97, u))
		ball.global_position = bpos
		if local >= float(f.dur) - 0.25 and not f.caught:
			f.caught = true
			var rec = host._field_nodes.get(int(f.receiver))
			if rec is Doll:
				(rec as Doll).play("tag" if bool(f.get("tag", false)) else "catch", 0.6)
				host._sfx_later(0.25, "tag_slap" if bool(f.get("tag", false)) else "glove_catch_throw", (rec as Node3D).global_position + Vector3(0.0, 1.0, 0.0))
		if local >= float(f.dur) + 1.0:
			ball.queue_free()
			flights.remove_at(i)


## With a runner leading off, the AI pitcher sometimes steps off and throws over instead of pitching.
## Returns true if he did (the pitch waits a moment).
func ai_throw_over() -> bool:
	if host.acts.derby or host._game == null or not host._runners_on() or not steal.is_empty() or not host._aux_play.is_empty():
		return false
	for b in [1, 2, 3]:
		var runner = host._game.bases[b - 1]
		if runner == null or (b < 3 and host._game.bases[b] != null):
			continue              # nobody there, or he cannot go anywhere
		if not StealModel.ai_throws_over(float(leads[b - 1]), int(since_throw[b - 1]), host._run_rng):
			continue
		host._spectate_timer = 1.6
		var from = Vector3(0.0, PitchPhysics.MOUND_H + 1.55, PitchPhysics.MOUND_Z - 1.1)
		var cmd: float = host._ai_pitcher.player.command
		var mound_man = host._field_nodes.get(1)
		if mound_man is Doll:
			(mound_man as Doll).throw_to(Vector3.ZERO, "sidearm", 0.6)
		do_pickoff(b, from, Vector3(0.0, 0.0, -25.0), host._run_rng.randf_range(0.0, 9.0) * (1.6 - cmd / 100.0), 0.6)
		return true
	return false
