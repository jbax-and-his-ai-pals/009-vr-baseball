class_name FieldingControl
extends RefCounted
## What you do with your hands as a fielder: the glove (which catches), the throwing hand (which throws), thumbstick running,
## covering first as the pitcher, and the catcher's work (framing a pitch, throwing out a runner). It owns the state of your fielding
## line; the scene (`host`) owns everything else and this class reaches into it by name.

var host                                    # the bullpen scene (untyped: its members are reached by name)

const FIELD_LOCOMOTION_MIN := 0.15
const COVER_RADIUS := 1.6        # m: close enough to the bag to take the flip

var fld := {"chances": 0, "caught": 0, "missed": 0, "errors": 0, "assists": 0, "frames": 0, "lost": 0, "blocks": 0, "passed": 0}   # your fielding this game
var glove_hist: Array = []                 # [time, glove position] for the last moments (the catcher judges them)
var glove_override := Vector3.INF          # debug / tests: a glove that is exactly here
var auto_field := false          # debug: the glove finds the ball and throws to first on its own
var field_samples: Array = []    # [time, hand position] while holding a ball to throw
## ---------------------------------------------------------------- the catcher (Fielding at position 2)
var receive_cover := 0.0


## You are the catcher and a runner is going: every frame, wait for you to take the ball out of the glove with
## your throwing hand and let it go toward the base (or for the time to run out).
func poll_catcher_throw(delta: float, now: float) -> void:
	var w: Dictionary = host.plays.steal.get("await", {}) if not host.plays.steal.is_empty() else {}
	if w.is_empty():
		return
	w["left"] = float(w.left) - delta
	if host._xr_active and host._hand != null and host._hand.get_is_active():
		field_samples.append([now, host._hand.global_position])
		while field_samples.size() > 2 and now - float(field_samples[0][0]) > 0.15:
			field_samples.pop_front()
		var grip = host._hand.get_float("grip")
		if not w.get("gripped", false):
			if grip > HumanPitcher.GRAB_THRESHOLD and host._hand.global_position.distance_to(glove_pos(null)) < 0.45:
				w["gripped"] = true
				field_samples.clear()
		elif grip < HumanPitcher.RELEASE_THRESHOLD and field_samples.size() >= 2:
			var first: Array = field_samples[0]
			var last: Array = field_samples[field_samples.size() - 1]
			var dt = maxf(float(last[0]) - float(first[0]), 0.02)
			var vel: Vector3 = ((last[1] as Vector3) - (first[1] as Vector3)) / dt * host.velocity_gain
			field_samples.clear()
			catcher_release(vel)
			return
	if float(w.left) <= 0.0:
		catcher_release(Vector3.ZERO)


## The ball leaves your hand with this velocity (zero: you never threw). Fast and straight at the base gets him
## when it beats his run; anything else, or too slow, and he is safe.
func catcher_release(vel: Vector3) -> void:
	var w: Dictionary = host.plays.steal.get("await", {})
	host.plays.steal.erase("await")
	var target = int(host.plays.steal.from) + 1
	var t_rel = float(host.flow.aux_play.get("t", 0.0)) if not host.flow.aux_play.is_empty() else 0.0
	var from = glove_pos(null)
	if from.y < -10.0:
		from = Vector3(0.0, 1.2, -1.0)                  # no controller: the throw starts from behind the plate
	var safe = true
	var t_ball = t_rel + 0.6
	var why = "no throw"
	var speed = 0.0
	var err = 0.0
	if vel.length() >= HumanFielding.MIN_THROW_SPEED:
		var arm = float(host._defense.fielder_by_num(2).get("arm", 33.0))
		speed = HumanFielding.throw_speed(vel.length(), 1.0, arm)
		var choice = HumanFielding.pick_base(from, vel, host._throw_cone)
		err = float(choice.err)
		if int(choice.base) == target:
			t_ball = t_rel + HumanFielding.arrival_delay(from, target, speed, err) + host._run_rng.randfn(0.0, 0.04)
			safe = float(host.plays.steal.run_t) <= t_ball
			why = "on the bag"
		else:
			why = "wild"
	host._haptics.play("throw", clampf(speed / 35.0, 0.2, 1.0))
	host.plays.apply_steal(safe, t_ball, float(w.get("a_time", 0.0)), {"t_ball": t_ball, "t_run": host.plays.steal.run_t, "human": true, "why": why, "speed": speed, "err": err})
	if not safe:
		fld.assists += 1
		host.hud.show_notice("Caught him!", true)
	else:
		host.hud.show_notice("Wild throw - safe!" if why == "wild" else ("Too slow - safe" if why == "on the bag" else "No throw - he is safe"), true)


func human_num() -> int:
	if host._mode.human_pitcher:
		return 1                          # a ball hit back at you is yours to field
	return int(host._mode.human_fielders[0]) if not host._mode.human_fielders.is_empty() else 0


func is_catcher() -> bool:
	return host._mode != null and host._mode.human_fielders.has(2)


func sample_glove(now: float) -> void:
	var g = glove_pos(null)
	glove_hist.append([now, g])
	while glove_hist.size() > 2 and now - float(glove_hist[0][0]) > 0.6:
		glove_hist.pop_front()


## A pitch the batter took arrives in your mitt: the umpire's call depends on how you caught it.
func receive(pitch: LivePitch, plate: Vector3, outcome: String) -> String:
	var q = Framing.assess(glove_hist, plate)
	receive_cover = float(q.cover)
	var c = Framing.call_strike(plate, float(q.quality), host._run_rng.randf())
	var result = "called_strike" if c.strike else "ball"
	if c.framed:
		fld.frames += 1
		host.hud.show_notice("Framed it!", true)
		host._haptics.play("catch", 0.8)
	elif c.lost:
		fld.lost += 1
		host.hud.show_notice("Lost the call - too much glove movement" if float(q.speed) > Framing.STILL_SPEED else "Lost the call - get the glove on it", false)
	host.slog.record("receive", {"miss": snappedf(float(q.miss), 0.001), "speed": snappedf(float(q.speed), 0.01), "quality": snappedf(float(q.quality), 0.01),
		"p": snappedf(float(c.p), 0.01), "call": result, "was": outcome})
	return result


## Where your glove is: the off-hand controller, a little in front of it.
func glove_pos(h: LiveHit) -> Vector3:
	if glove_override != Vector3.INF:
		return glove_override
	if host._xr_active and host._off_hand and host._off_hand.get_is_active():
		return host._off_hand.global_transform * Vector3(0.0, 0.0, -0.12)
	if auto_field and h != null:
		# Debug: a glove that is where the ball will be when the fielder would have reached it.
		if h.t >= float(h.play.get("field_time", 0.0)) - 0.05:
			return h.ball.global_position
	return Vector3(0.0, -50.0, 0.0)


func held_by_human(h: LiveHit) -> Vector3:
	if h.human_state == "gripped" and host._xr_active and host._hand:
		return host._hand.global_transform * HumanPitcher.HOLD_OFFSET
	if host._xr_active and host._off_hand:
		return glove_pos(h)
	return h.catch_pos


## Each frame while the ball is yours: did the glove get it? did you run out of time?
func update_human(h: LiveHit, _delta: float) -> void:
	match h.human_state:
		"waiting":
			var ball = h.ball.global_position
			if ball.y < 3.2 and HumanFielding.in_glove(glove_pos(h), ball, host._catch_radius):
				human_catch(h, ball)
			elif h.t > h.chance_end:
				human_miss(h)
		"holding", "gripped":
			if auto_field and h.human_state == "holding" and h.t - h.catch_t > 0.7:
				var from = h.ball.global_position
				var to_first: Vector3 = Defense.FIRST - from
				human_throw(h, to_first.normalized() * 27.0)
			elif h.t - h.catch_t > HumanFielding.HOLD_LIMIT:
				human_hold_too_long(h)


func fielder_play(h: LiveHit, result: String, text: String, extra: Dictionary) -> Dictionary:
	var hn = human_num()
	var fn = host._defense.fielder_by_num(hn)
	var play = {"result": result, "text": text, "short": text, "fielder": hn, "fielder_name": fn.get("name", ""),
		"field_pos": h.catch_pos, "field_time": h.catch_t, "arm": float(fn.get("arm", 33.0)),
		"release_time": h.catch_t + float(fn.get("transfer", 0.45)), "bases": 0, "movements": [],
		"run_times": Defense.RUNNER_TIMES, "caught_in_air": false, "error": false}
	for k in extra:
		play[k] = extra[k]
	return play


func human_catch(h: LiveHit, ball: Vector3) -> void:
	host._haptics.play("catch")
	fld.chances += 1
	fld.caught += 1
	print("FIELDING: caught at t=%.2f y=%.2f" % [h.t, ball.y])
	h.catch_pos = ball
	h.catch_t = h.t
	var sim = h.summary
	var airborne: bool = ball.y > 0.30 and float(sim.get("landing_time", 0.0)) > 0.0 \
		and h.t <= float(sim.get("landing_time", 0.0)) + 0.04
	var fair: bool = sim.get("fair", false)
	var who: String = host._defense.fielder_by_num(human_num()).get("name", "")
	if airborne:
		var label = "Popout" if sim.get("kind", "") == "Pop-up" else ("Flyout" if sim.get("kind", "") == "Fly ball" else "Lineout")
		var text = "%s to %s" % [label, who] if fair else "Foul out to %s" % who
		h.play = fielder_play(h, "out", text, {"caught_in_air": true, "foul_out": not fair})
		h.plan = Baserunning.plan(h.play, host._game.bases, host._game.outs, host._batter_player, host._run_rng)
		h.play_end = maxf(h.t + 0.6, float(h.plan.end_time))
		h.human_state = "done"
		host.hud.last_report_extra = "CAUGHT!"
		return
	if not fair:
		h.play = fielder_play(h, "foul", "Foul ball", {})
		h.plan = {}
		h.play_end = h.t + 0.5
		h.human_state = "done"
		return
	h.play = fielder_play(h, "out", "", {})
	h.human_state = "holding"
	host.hud.last_report_extra = "GOT IT - throw to a base!"
	h.play_end = 1e9


## The ball got past you (or you never reached it): the rest of the defense plays it.
func human_miss(h: LiveHit) -> void:
	fld.chances += 1
	fld.missed += 1
	print("FIELDING: missed at t=%.2f" % h.t)
	h.human_state = "done"
	h.play = h.fallback if not h.fallback.is_empty() else {"result": "single", "text": "Single", "bases": 1,
		"field_pos": h.ball.global_position, "field_time": h.t, "movements": [], "fielder": 0}
	if h.play.get("result", "") in ["foul", ""]:
		h.plan = {}
		h.play_end = maxf(h.t + 0.5, float(h.play.get("field_time", 0.0)))
	else:
		h.plan = Baserunning.plan(h.play, host._game.bases, host._game.outs, host._batter_player, host._run_rng)
		h.play_end = maxf(h.t + 0.5, float(h.plan.end_time))
	host.hud.last_report_extra = "Got by you"


## The batter is about to reach first: is the pitcher (you) standing on the bag to take the flip?
func check_cover(h: LiveHit) -> void:
	h.cover_t = -1.0
	var head = host._camera.global_position
	var d = Vector2(head.x - h.cover_spot.x, head.z - h.cover_spot.z).length()
	if d <= COVER_RADIUS:
		fld.covers += 1
		host.hud.show_notice("Covered first", true)
		host._haptics.play("catch", 0.6)
		host.slog.record("cover_first", {"covered": true, "distance": snappedf(d, 0.01)})
		return
	fld.uncovered += 1
	host.slog.record("cover_first", {"covered": false, "distance": snappedf(d, 0.01)})
	var spot: Vector3 = h.play.get("field_pos", h.ball.global_position)
	h.play = {"result": "single", "text": "Safe - nobody covered first", "short": "Safe - nobody covered first", "bases": 1,
		"fielder": int(h.play.get("fielder", 3)), "fielder_name": String(h.play.get("fielder_name", "1B")), "field_pos": spot,
		"field_time": float(h.play.get("field_time", h.t)), "movements": [], "run_times": h.play.get("run_times", Defense.RUNNER_TIMES),
		"caught_in_air": false, "error": false}
	h.plan = Baserunning.plan(h.play, host._game.bases, host._game.outs, host._batter_player, host._run_rng)
	h.play_end = maxf(h.t + 0.8, float(h.plan.end_time))
	host.hud.last_report_extra = "Nobody covered first!"
	host.hud.show_notice("Nobody covered first - he is safe", true)


func human_hold_too_long(h: LiveHit) -> void:
	fld.errors += 1
	h.human_state = "done"
	h.play = fielder_play(h, "single", "Infield single (held the ball)", {"bases": 1})
	Baserunning.apply_throw(h.plan, 0, 0.0, host._game.outs, h.catch_pos, host._run_rng)
	h.play_end = maxf(h.t + 0.5, float(h.plan.end_time))


## You let go of the ball with this velocity (m/s, world space).
func human_throw(h: LiveHit, vel: Vector3) -> void:
	host._haptics.play("throw")
	var hn = human_num()
	var fn = host._defense.fielder_by_num(hn)
	var from = h.ball.global_position
	var choice = HumanFielding.pick_base(from, vel, host._throw_cone)
	var speed = HumanFielding.throw_speed(vel.length(), 1.0, float(fn.get("arm", 33.0)))
	h.human_state = "thrown"
	h.catch_pos = from if h.catch_pos == Vector3.ZERO else h.catch_pos
	if choice.base == 0:
		# It sails: runners take the base they were going to and one more.
		var wild = fielder_play(h, "error", "Throwing error, %s (E%d)" % [fn.get("name", ""), hn],
			{"bases": 1, "error": true})
		h.play = wild
		h.plan = Baserunning.plan(wild, host._game.bases, host._game.outs, host._batter_player, host._run_rng)
		h.play_end = maxf(h.t + 0.8, float(h.plan.end_time))
		host.hud.last_report_extra = "Wild throw!"
		fld.errors += 1
		return
	var base: int = choice.base
	print("FIELDING: throw to base %d at %.1f m/s (%.0f deg off)" % [base, speed, choice.err])
	var t_arrive = h.t + HumanFielding.arrival_delay(from, base, speed, float(choice.err))
	var target = HumanFielding.base_position(base)
	Baserunning.apply_throw(h.plan, base, t_arrive, host._game.outs, from, host._run_rng)
	(h.plan.throws as Array).insert(0, {"from": from, "to": target + Vector3(0.0, 1.0, 0.0),
		"t0": h.t, "t1": t_arrive, "base": base})
	var to_pos = HumanFielding.receiver(base, hn)
	var outs: int = h.plan.outs_added
	var text = ""
	var result = "out"
	if outs >= 2:
		text = "Double play %d-%d-3" % [hn, to_pos]
	elif outs == 1:
		var batter_out = false
		for r in h.plan.runners:
			if r.out and int(r.from) == 0:
				batter_out = true
		text = ("Groundout %d-%d" % [hn, to_pos]) if batter_out else ("Force out at %s, %d-%d" % [
			["", "first", "second", "third", "home"][base], hn, to_pos])
	else:
		result = "single"
		text = "Infield single"
	h.play = fielder_play(h, result, text, {"bases": 1 if result == "single" else 0,
		"throw": h.plan.throws[0]})
	h.plan["text"] = text
	h.play_end = maxf(t_arrive + 0.6, float(h.plan.end_time))
	host.hud.last_report_extra = ("Throw to %s: %s" % [["", "first", "second", "third", "home"][base], "OUT" if outs > 0 else "safe"])
	if outs > 0:
		fld.assists += 1


## Thumbstick locomotion: you run to the ball. Speed is your fielder's.
func move_fielder(delta: float) -> void:
	if host._origin == null or host._off_hand == null or not host._off_hand.get_is_active() or host._camera == null:
		return
	var stick: Vector2 = host._off_hand.get_vector2("primary")
	if stick.length() < FIELD_LOCOMOTION_MIN:
		return
	var speed = float(host._defense.fielder_by_num(human_num()).get("speed", 7.0))
	var yaw = host._camera.global_rotation.y
	var fwd = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right = Vector3(cos(yaw), 0.0, -sin(yaw))
	var step = (fwd * stick.y + right * stick.x) * speed * delta
	host._origin.global_position += step
	host._origin.global_position.y = 0.0


## Holding a ball in the glove: grab it with your throwing hand and throw.
func poll_fielding(now: float) -> void:
	var h = holding_hit()
	if h == null or not host._hand.get_is_active():
		field_samples.clear()
		return
	field_samples.append([now, host._hand.global_position])
	while field_samples.size() > 2 and now - float(field_samples[0][0]) > 0.15:
		field_samples.pop_front()
	var grip = host._hand.get_float("grip")
	if h.human_state == "holding":
		if grip > HumanPitcher.GRAB_THRESHOLD and host._hand.global_position.distance_to(glove_pos(h)) < 0.45:
			h.human_state = "gripped"
			field_samples.clear()
	elif h.human_state == "gripped" and grip < HumanPitcher.RELEASE_THRESHOLD and field_samples.size() >= 2:
		var a: Array = field_samples[0]
		var b: Array = field_samples[field_samples.size() - 1]
		var dt = maxf(float(b[0]) - float(a[0]), 0.02)
		var vel: Vector3 = ((b[1] as Vector3) - (a[1] as Vector3)) / dt * host.velocity_gain
		human_throw(h, vel)
		field_samples.clear()


func holding_hit() -> LiveHit:
	for h in host.flight.hits:
		if h.human_state in ["holding", "gripped"]:
			return h
	return null
