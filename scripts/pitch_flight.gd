class_name PitchFlight
extends RefCounted
## The life of a pitch and of the ball it becomes: letting go (yours) or launching (the AI's), the flight and the batter's decision,
## the swing you take with the controller, landing in the mitt, contact and the batted ball, the defense's answer and the play
## it makes, and the balls still in the air. This is where the rules are applied to what the physics did. The scene (`host`)
## owns the game and the figures.

var host                                    # the bullpen scene (untyped: its members are reached by name)

var held_ball: MeshInstance3D
var pitches: Array[LivePitch] = []
var ball_mesh: ArrayMesh
var trail_mat: StandardMaterial3D
var count := 0
var strikes := 0
var best_mph := 0.0
var tracker := SwingTracker.new()          # your controller as a bat (Hitting)
var bat_view: MeshInstance3D               # the bat in your hand
var canned_index := 0
var hits: Array[LiveHit] = []
var play_hit: LiveHit
var outs := 0
var hit_count := 0
var errors := 0
var homers := 0
var swings := 0
var batter_free_at := 0.0   # a batter still finishing a swing cannot start another
var whiffs := 0
var in_play_count := 0


## He lets it go: a pitch at his body makes him jerk away, one near the zone sometimes
## draws a hitch of the bat (a check swing).
func batter_takes(pitch: LivePitch) -> void:
	var what = host._presenter.take(pitch.analysis, bool(pitch.bat.get("busy", false)), host.flow.batter_is_lefty(), host._fx_rng.randf())
	if what == "check":
		host._sfx_later(float(pitch.analysis.get("time", 0.5)) * 0.5, "bat_swing_slow", host._batter.global_position + Vector3(0.0, 1.1, 0.0), -6.0)


## The batter lets go of the bat: it drops, bounces and lies there until the next one comes up.
func drop_bat() -> void:
	var dropped = host._presenter.drop_bat()
	if dropped == null:
		return
	var xf: Transform3D = dropped
	if host._sound != null and host._sound.flip_next:
		host._sound.flip_next = false
		host._sfx("bat_flip", xf.origin)
	host._props.drop_bat(xf)


## Your pitching line only counts the pitches you threw, not the ones you hit.
func stat_pitch(label: String, mph: float, outcome: String) -> void:
	if host.roles.top_game == null:
		host._stats.record_pitch(label, mph, outcome)


func release_from_hand(release_t: float, vel_latency: float, spin_latency: float) -> void:
	var from = held_ball.global_position
	var r = host._human.throw(release_t, vel_latency, spin_latency, from, host._camera.global_position.y, host.manager.arm_fatigue(), host.manager.command_scale(), host._runners_on())
	held_ball.visible = false
	match String(r.kind):
		"drop":
			if bool(r.started):
				host.plays.call_balk("Dropped the ball")
			else:
				host.hud.show_notice("Too soft - that was a drop. Throw it!")
		"pickoff":
			host.plays.do_pickoff(int(r.base), from, r.vel as Vector3, float(r.err), float(r.quick))
		"pitch":
			host._last_delivery = float(r.delivery)
			var pitch = launch(from, r.vel, r.spin, "Your pitch", float(r.flutter), host._run_rng.randf() * 100.0)
			pitch.shape = r.shape
			pitch.label = PitchNamer.name_pitch(pitch.analysis, host._human.wrist.typical_mph(host.velocity_gain), float(r.hand_sign), bool(r.knuckle))
			host._haptics.play("release", clampf(float(pitch.analysis.get("speed_mph", 60.0)) / 90.0, 0.0, 1.0))
			host.slog.log_throw(pitch, from, release_t, vel_latency, r)


## Read the controller each frame: the ball in your hand follows it; grabs, the start of your delivery and
## releases come back as events.
func poll_hand(now: float) -> void:
	for e in host._human.poll(now, host._hand, host.flow.batter_ready and host.manager.visit_timer <= 0.0, host.release_mode == host.ReleaseMode.AUTO_PEAK):
		match String(e.type):
			"grab":
				host._haptics.play("grab")
				held_ball.visible = true
			"delivery_start":
				host.plays.on_delivery_start()
			"release":
				release_from_hand(float(e.t), float(e.vel_latency), float(e.spin_latency))
			"drop":
				host._human.drop()
				held_ball.visible = false
	if host._human.held and host._hand != null and host._hand.get_is_active():
		held_ball.global_position = host._hand.global_transform * HumanPitcher.HOLD_OFFSET


func drop_held() -> void:
	host._human.drop()
	held_ball.visible = false


func launch(from: Vector3, vel: Vector3, spin: Vector3, label: String, flutter_amp: float = 0.0, flutter_seed: float = 0.0) -> LivePitch:
	var pitch = LivePitch.new()
	pitch.pos = from
	pitch.vel = vel
	pitch.spin = spin
	pitch.label = label
	pitch.flutter_amp = flutter_amp
	pitch.flutter_seed = flutter_seed
	pitch.analysis = PitchPhysics.analyze(from, vel, spin, flutter_amp, flutter_seed)
	var pitcher_right = (host.throwing_hand == &"right_hand") if host._mode.human_pitcher else host._ai_pitcher.player.throws_right
	if host._batter_player != null:
		host._batter_ai.platoon = BatterAI.platoon_for(host._batter_player.bats_right, pitcher_right)
	pitch.bat = evaluate_batter({"release": from, "vel": vel, "spin": spin,
		"situation": {"bases": [host._game.bases[0] != null, host._game.bases[1] != null, host._game.bases[2] != null],
			"outs": host._game.outs, "strikes": host._game.strikes, "balls": host._game.balls, "call": host._bat_call},
		"flutter_amp": flutter_amp, "flutter_seed": flutter_seed, "analysis": pitch.analysis})
	if pitch.bat.swing:
		# He is still finishing the previous swing: he cannot offer at this one.
		var contact_at = host._game_time + float(pitch.bat.get("contact_time", 0.5))
		if contact_at < batter_free_at:
			pitch.bat = {"swing": false, "contact": false, "kind": "take", "busy": true,
				"p_swing": pitch.bat.get("p_swing", 0.0)}
		else:
			batter_free_at = contact_at + host.SWING_RECOVERY
	if pitch.bat.swing:
		swings += 1
		var swing_at: Vector3 = pitch.bat.get("bat_target", Vector3(0.0, 0.85, 0.0))
		var swing_in = float(pitch.bat.get("contact_time", pitch.analysis.get("time", 0.5)))
		if pitch.bat.get("bunt", false):
			host._batter.bunt_to(swing_at, swing_in)
		else:
			host._batter.swing_to(swing_at, swing_in)
			if host._sound != null:
				host._sound.swing(float(pitch.analysis.get("plate_mph", 60.0)), swing_in)
		if pitch.bat.contact:
			var b: Dictionary = pitch.bat
			pitch.sim = BattedBall.simulate(b.contact_pos, b.vel, b.spin)
			if b.kind == "hit":
				resolve_ball(pitch)
			else:
				pitch.play = {"result": "foul", "text": "Foul tip", "short": "Foul tip", "fielder": 0,
					"movements": [], "bases": 0, "field_time": 0.0, "field_pos": Vector3.ZERO, "foul_tip": true}
		else:
			whiffs += 1
	else:
		batter_takes(pitch)
	host._crew.begin_pitch(pitch.analysis, float(pitch.bat.get("contact_time", 99.0)) if pitch.bat.get("contact", false) else 99.0)
	pitch.ball = host.world.make_ball()
	pitch.ball.global_position = from
	if host._audio != null:
		host._audio.loop_on("whiz", "ball_flight_whiz", -16.0, null, pitch.ball)       # follows the ball in
	pitch.trail_inst = MeshInstance3D.new()
	pitch.trail_inst.mesh = pitch.trail_mesh
	pitch.trail_inst.material_override = trail_mat
	host.add_child(pitch.trail_inst)
	pitch.trail.append(from)
	pitches.append(pitch)
	while pitches.size() > host.MAX_PITCHES:
		free_pitch(pitches.pop_front())
	return pitch


## The batter's decision for this pitch: the AI's, or (when you bat) a take until your bat says otherwise.
func evaluate_batter(d: Dictionary) -> Dictionary:
	if host._mode.human_batter:
		return {"swing": false, "contact": false, "kind": "take", "p_swing": 0.0}
	return host._batter_ai.evaluate(d)


## Hitting: each step of a pitch in flight, does your bat meet the ball? If so the collision decides the hit.
## Returns true if the ball was hit (the pitch has become a batted ball).
func human_swing_check(pitch: LivePitch, next_pos: Vector3) -> bool:
	if pitch.pos.z < 3.0 and pitch.pos.z > -1.2:
		pitch.swing_peak = maxf(pitch.swing_peak, tracker.barrel_speed())
	var touch = BatPhysics.touch(pitch.pos, next_pos, tracker.knob, tracker.tip)
	if touch.is_empty():
		return false
	var res = BatPhysics.collide(touch, pitch.vel, tracker.knob, tracker.tip, tracker.knob_vel, tracker.tip_vel)
	if res.is_empty():
		return false
	res["contact_time"] = pitch.flight_time
	res["t_err"] = 0.0
	pitch.pos = touch.ball
	pitch.bat = res
	pitch.sim = BattedBall.simulate(res.contact_pos, res.vel, res.spin)
	if res.kind == "hit":
		resolve_ball(pitch)
	else:
		pitch.play = {"result": "foul", "text": "Foul tip", "short": "Foul tip", "fielder": 0,
			"movements": [], "bases": 0, "field_time": 0.0, "field_pos": Vector3.ZERO, "foul_tip": true}
	swings += 1
	contact(pitch)
	var where = "off the end" if float(res.s) > 0.76 else ("jammed" if float(res.s) < 0.38 else ("on the barrel" if BatPhysics.sweetness(float(res.s)) > 0.8 else "off the barrel"))
	var timing = "out front" if res.contact_pos.z > 0.35 else ("deep" if res.contact_pos.z < -0.2 else "on time")
	if res.kind == "hit":
		host.hud.show_notice("%s, %s: %.0f mph, %+.0f deg" % [where, timing, float(res.ev), float(res.la)], true)
	return true


## Your controller drives the bat every frame; the bat in your hand follows it.
func update_human_bat(now: float) -> void:
	if not host._mode.human_batter or host._hand == null or not host._hand.get_is_active():
		return
	tracker.update(now, host._hand.global_position, host._hand.global_transform.basis.get_rotation_quaternion())
	if bat_view != null:
		var dir = (tracker.tip - tracker.knob).normalized()
		bat_view.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), tracker.knob)


func free_pitch(pitch: LivePitch) -> void:
	pitch.ball.queue_free()
	pitch.trail_inst.queue_free()


func update_flight(pitch: LivePitch, delta: float) -> void:
	pitch.accum += delta
	var changed = false
	while pitch.accum >= PitchPhysics.SIM_DT and not pitch.landed:
		pitch.accum -= PitchPhysics.SIM_DT
		if pitch.bat.get("contact", false) and pitch.flight_time >= float(pitch.bat.contact_time):
			contact(pitch)
			changed = true
			break
		var s = PitchPhysics.step(pitch.pos, pitch.vel, pitch.spin, PitchPhysics.SIM_DT, true, pitch.flight_time, pitch.flutter_amp, pitch.flutter_seed)
		var next_pos = s[0]
		var in_mitt = absf(next_pos.x) < 0.6 and next_pos.y > 0.2 and next_pos.y < 1.5
		if next_pos.z <= host.MITT_Z and pitch.pos.z > host.MITT_Z and in_mitt:
			pitch.pos = pitch.pos.lerp(next_pos, (pitch.pos.z - host.MITT_Z) / (pitch.pos.z - next_pos.z))
			land(pitch)
			changed = true
			break
		if next_pos.y <= PitchPhysics.BALL_RADIUS or next_pos.z <= host.BACKSTOP_Z or pitch.flight_time > 3.0:
			pitch.pos = next_pos
			land(pitch)
			changed = true
			break
		if host._mode.human_batter and human_swing_check(pitch, next_pos):
			changed = true
			break
		pitch.pos = next_pos
		pitch.vel = s[1]
		pitch.flight_time += PitchPhysics.SIM_DT
		pitch.steps += 1
		if pitch.steps % 4 == 0:
			pitch.trail.append(pitch.pos)
			changed = true
	pitch.ball.global_position = pitch.pos
	# The stitches show the spin, slowed down so it reads instead of strobing.
	if not pitch.landed and pitch.spin.length_squared() > 0.0001:
		pitch.ball.global_rotate(pitch.spin.normalized(), pitch.spin.length() * delta * 0.12)
	if changed:
		rebuild_trail(pitch)


func land(pitch: LivePitch) -> void:
	host._bat_call = ""
	if host._audio != null:
		host._audio.loop_off("whiz")
	pitch.landed = true
	pitch.linger = host.LINGER_TIME
	pitch.trail.append(pitch.pos)
	var a = pitch.analysis
	count += 1
	best_mph = maxf(best_mph, a.speed_mph)
	if a.reached and a.strike:
		strikes += 1
	var outcome = "ball"
	var plate: Vector3 = a.get("plate_pos", Vector3.ZERO)
	if host.fielding.is_catcher():
		host.fielding.receive_cover = float(Framing.assess(host.fielding.glove_hist, plate).cover)
	if host._mode.human_batter and not pitch.bat.get("contact", false) and pitch.swing_peak > 8.0:
		pitch.bat = {"swing": true, "contact": false, "kind": "whiff", "p_swing": 1.0}      # you swung and missed
	if pitch.bat.get("swing", false):
		outcome = "swinging_strike"
	elif a.get("reached", false) and a.get("strike", false):
		outcome = "called_strike"
	elif a.get("reached", false) and PitchLocation.hits_batter(plate.x, plate.y, host.flow.batter_is_lefty()):
		outcome = "hit_by_pitch"
	if host.fielding.is_catcher() and a.get("reached", false) and outcome in ["ball", "called_strike"]:
		outcome = host.fielding.receive(pitch, plate, outcome)
	mark_pitch(a, outcome)
	host.bus.pitch_arrived.emit(pitch, outcome)
	host.bus.pitch_resolved.emit(pitch, outcome)
	if host._runners_on() and host.plays.steal.is_empty():
		host.hud.last_report_extra = "Delivery %.2f s with runners on" % host._last_delivery
	host.plays.resolve_steal(a)
	for i in 3:
		host.plays.since_throw[i] = int(host.plays.since_throw[i]) + 1
	# A pitch the catcher cannot handle: every runner moves up a base.
	var wild_ev = {}
	var wild_plan: PlayPlan = null
	if outcome != "hit_by_pitch" and not host._game.bases.is_empty() and host._game.bases != [null, null, null]:
		var off = PitchLocation.outside_by(plate.x, plate.y) if a.get("reached", false) else 0.9
		var p_wild = 0.0
		if off > 0.25:
			p_wild = 0.04 + 0.5 * clampf((off - 0.25) / 1.0, 0.0, 1.0)
		else:
			p_wild = 0.008                    # the odd passed ball
		if host.fielding.is_catcher():
			p_wild = Framing.gets_away(p_wild, host.fielding.receive_cover)
			if off > 0.25 and host.fielding.receive_cover > 0.6:
				host.fielding.fld.blocks += 1
				host.hud.show_notice("Blocked!", false)
		if host._run_rng.randf() < p_wild:
			if host.fielding.is_catcher():
				host.fielding.fld.passed += 1
			var before = host._game.bases.duplicate()
			wild_ev = host._game.wild_pitch(off <= 0.25)
			if wild_ev.get("result", "") != "":
				wild_plan = Baserunning.plan_advance(before)
				wild_plan.add_event(0.15, 0, "WILD PITCH" if off > 0.25 else "PASSED BALL", "safe", Vector3(0.0, 0.0, 0.0))
				wild_plan.shown_from = before
	var bases_before = host._game.bases.duplicate()
	var ev: Dictionary
	# Strike three that gets away from the catcher: with first base open (or two outs) he can run.
	var strike_three: bool = host._game.strikes == 2 and outcome in ["swinging_strike", "called_strike"]
	if strike_three and wild_ev.get("result", "") != "" and (host._game.bases[0] == null or host._game.outs == 2):
		ev = host._game.dropped_third_strike(host._run_rng.randf() < 0.55)
	else:
		ev = host._game.pitch(outcome)
	if wild_plan != null and not ev.get("pa_over", false) and host.flow.aux_play.is_empty():
		# Show them go: the batter stays put, the men on base run.
		var shown_from: Array = wild_plan.shown_from
		host.flow.aux_play = {"plan": wild_plan, "t": 0.0}
		host.flow.refresh_base_runners(shown_from)
	host.flow.begin_pa_exit(ev, bases_before)
	# The at-bat ended on a pitch a runner was running on (strike 'em out, throw 'em out).
	if ev.get("pa_over", false) and not host.plays.steal.is_empty() and host.plays.steal.has("apply_at"):
		host.plays.finish_steal()
	stat_pitch(pitch.label, a.speed_mph, outcome)
	var loc = PitchLocation.classify(plate.x, plate.y)
	host.slog.record("pitch", {"n": host._game.pitch_count, "label": pitch.label, "mph": a.speed_mph, "plate": plate,
		"reached": a.get("reached", false), "loc": loc.kind, "strike_zone": a.get("strike", false), "outcome": outcome,
		"swing": pitch.bat.get("swing", false), "bat": pitch.bat.get("kind", ""), "p_swing": pitch.bat.get("p_swing", 0.0),
		"t_err": pitch.bat.get("t_err", 0.0), "bunt": pitch.bat.get("bunt", false), "busy": pitch.bat.get("busy", false),
		"result": ev.get("result", ""), "text": ev.get("text", ""), "wild": wild_ev.get("result", ""),
		"delivery": host._last_delivery if host._runners_on() else null, "steal": not host.plays.steal.is_empty(),
		"fatigue": snappedf(host._home.player_at(1).fatigue(host._game.pitch_count), 0.01) if host._home else 0.0,
		"on_before": bases_before.map(func(x): return x != null)})
	if ev.get("result", "") == "strikeout":
		host._crew.call_it("ump_out", 0.55, 1.1, "ump_strike_three")             # strike three is rung up
	if wild_ev.get("result", "") != "":
		host._crew.chase()
	var wild_text = host.hud.event_text(wild_ev)
	host.hud.last_report = host.hud.format_report(pitch.label, a) + host.hud.bat_line(pitch) + ("\n" + wild_text if wild_text != "" else "") \
		+ "\n" + host.hud.event_text(ev) + host.acts.lab_lines(pitch)
	host.flow.after_event(ev)
	host.hud.refresh_hud()
	print(host.hud.last_report.replace("\n", " | "))


## The bat meets the ball: end the pitch's flight and send a batted ball out.
func contact(pitch: LivePitch) -> void:
	host._bat_call = ""
	if host._audio != null:
		host._audio.loop_off("whiz")
	pitch.landed = true
	pitch.linger = host.LINGER_TIME
	pitch.trail.append(pitch.pos)
	var a = pitch.analysis
	var b: Dictionary = pitch.bat
	var sim: Dictionary = pitch.sim
	count += 1
	best_mph = maxf(best_mph, a.speed_mph)
	if a.reached and a.strike:
		strikes += 1
	var in_play: bool = b.kind == "hit" and (sim.fair or sim.home_run)
	if in_play:
		host.flow.batter_ready = false
	mark_pitch(a, "in_play" if in_play else "foul")
	stat_pitch(pitch.label, a.speed_mph, "in_play" if in_play else "foul")
	if in_play:
		in_play_count += 1
	host._batter.snap_to_contact()
	host.bus.contact_made.emit(pitch)
	host.bus.pitch_resolved.emit(pitch, "in_play" if in_play else "foul")
	var head = host.hud.format_report(pitch.label, a)
	if "--contact-demo" in OS.get_cmdline_user_args():
		var gap = host._batter.sweet_spot_world().distance_to(pitch.pos)
		print("CONTACT CHECK: bat sweet spot is %.1f cm from the ball at contact" % (gap * 100.0))
	var h = LiveHit.new()
	h.summary = sim
	h.points = sim.points
	h.dt = sim.dt
	h.report = host.hud.format_hit(b, sim)
	h.play = pitch.play
	h.bunt = bool(b.get("bunt", false))
	if sim.fair or sim.home_run:
		host._crew.step_aside(float(sim.get("spray", 0.0)))
	h.play_end = host._director.play_end_time(h.play, (h.points.size() - 1) * h.dt)
	if pitch.human_chance:
		h.human_chance = true
		h.fallback = pitch.play_fallback
		h.human_state = "waiting"
		h.chance_end = float(h.play.get("field_time", 2.0)) + 0.9
		# Until he has it, the batter runs and (on a grounder) forced runners go.
		h.plan = Baserunning.plan_hold(host._game.bases, host._batter_player, float(sim.get("apex", 0.0)) < 3.0)
		h.play_end = 1e9
		host.hud.last_report_extra = "YOUR BALL - get your glove on it"
	elif not h.play.is_empty() and h.play.get("result", "") not in ["foul", ""]:
		if host._mode.human_fielders.has(1) and h.play.get("cover_pitcher", false) and h.play.get("result", "") == "out":
			# The first baseman is pulled off the bag: you are the pitcher, so first base is yours to cover.
			h.cover_t = float((h.play.run_times as Array)[0]) - 0.12
			h.cover_spot = h.play.cover_spot
			host.hud.show_notice("COVER FIRST!", true)
			host._haptics.play("ui_error", 0.6)
		# Everyone on base runs on the same physics as the fielders.
		var head_start = {}
		if not host.plays.steal.is_empty():
			head_start[int(host.plays.steal.from)] = float(host.flow.aux_play.get("t", 0.0)) if not host.flow.aux_play.is_empty() else 0.0
			host.plays.steal = {}
			host._bat_call = ""
			host.flow.aux_play = {}
		h.plan = Baserunning.plan(h.play, host._game.bases, host._game.outs, host._batter_player, host._run_rng, head_start)
		h.play_end = maxf(h.play_end, float(h.plan.end_time))
		# A double play (or a throw to a runner) changes where the ball goes and who covers.
		if h.plan.cover != null:
			var cv: PlayPlan.Cover = h.plan.cover
			var cf = host._defense.fielder_by_num(int(cv.fielder))
			if not cf.is_empty():
				h.play.movements = (h.play.movements as Array).duplicate()
				h.play.movements.append({"fielder": cv.fielder, "from": cf.home, "to": cv.to,
					"t0": 0.3, "t1": maxf(float(cv.t) - 0.1, 0.8), "dive": false})
		h.throws = host._director.build_throws(h)
		# Any play with runners (a caught foul ball too) takes the batter out of the box.
		host.flow.batter_ready = false
	play_hit = h
	host._director.start_play(h)
	h.ball = host.world.make_ball()
	h.ball.global_position = pitch.pos
	if host._audio != null and sim.fair and float(sim.get("apex", 9.0)) < 2.5 and not sim.home_run:
		# A grounder: it rolls along the dirt or the grass until somebody has it.
		var rest: Vector3 = sim.get("rest_pos", Vector3.ZERO)
		h.rolling = true
		host._audio.loop_on("roll", "ball_roll_dirt" if Vector2(rest.x, rest.z - 14.0).length() < 26.0 else "ball_roll_grass", -10.0, null, h.ball)
	if h.play.get("infield_fly", false):
		host._sound.umpire_says_later(0.9, "ump_infield_fly")
	h.trail_inst = MeshInstance3D.new()
	h.trail_inst.mesh = h.trail_mesh
	var hit_mat = StandardMaterial3D.new()
	hit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hit_mat.albedo_color = Color(0.2, 0.95, 1.0)
	h.trail_inst.material_override = hit_mat
	host.add_child(h.trail_inst)
	hits.append(h)
	# Keep the picture readable: only the two most recent batted balls leave a tracer.
	while hits.size() > 2:
		free_hit(hits.pop_front())
	# At contact: the pitch, plus how hard and at what angle it was hit. The full result
	# (distance, hang time, where it went) appears when the ball lands.
	host.hud.last_report = head + "\nCONTACT: %s  %.0f mph, launch %+.0f deg" % [
		"foul tip" if b.kind == "foul tip" else "%s" % sim.kind, b.ev, b.la]
	if b.kind == "foul tip":
		var tip_before = host._game.bases.duplicate()
		var tip_ev = host._game.pitch("foul_tip")
		host.flow.begin_pa_exit(tip_ev, tip_before)
		host.hud.last_report += "\n" + host.hud.event_text(tip_ev)
		host.flow.after_event(tip_ev)
	host.hud.refresh_hud()
	print(host.hud.last_report.replace("\n", " | "))
	var pl: Dictionary = h.play
	var pn: PlayPlan = h.plan
	var runner_moves = []
	if pn != null:
		for r in pn.runners:
			runner_moves.append({"who": r.who.name if r.who is Player else "?", "from": r.from, "to": r.to, "out": r.out,
				"out_base": r.out_base, "hedge": r.hedge != null})
	host.slog.record("contact", {"contact_kind": b.kind, "bunt": b.get("bunt", false), "ev": b.ev, "la": b.la, "spray": b.get("spray", 0.0),
		"hit_kind": sim.get("kind", ""), "distance": sim.get("distance", 0.0), "apex": sim.get("apex", 0.0),
		"hang": sim.get("hang_time", 0.0), "fair": sim.get("fair", false), "wall": sim.get("wall", false),
		"home_run": sim.get("home_run", false), "ground_rule": sim.get("ground_rule", false),
		"play": pl.get("result", ""), "text": pl.get("text", ""), "fielder": pl.get("fielder", 0),
		"field_time": pl.get("field_time", 0.0), "field_pos": pl.get("field_pos", Vector3.ZERO),
		"caught_in_air": pl.get("caught_in_air", false), "clean_ground": pl.get("clean_ground", false),
		"infield_fly": pl.get("infield_fly", false), "human_chance": h.human_chance,
		"runners": runner_moves, "plan_outs": pn.outs_added if pn != null else 0, "plan_runs": pn.runs if pn != null else 0,
		"plan_text": pn.text if pn != null else "", "plan_result": pn.result if pn != null else "",
		"throws": h.throws.map(func(t): return {"base": t.base, "by": t.by, "rec": t.rec})})


func update_hit(h: LiveHit, delta: float) -> void:
	if h.done:
		h.linger -= delta
		return
	h.t += delta
	if h.cover_t > 0.0 and h.t >= h.cover_t:
		host.fielding.check_cover(h)
	var n = h.points.size()
	var path_end = (n - 1) * h.dt
	if h.human_state in ["waiting", "holding", "gripped"]:
		host.fielding.update_human(h, delta)
	var fielded: bool = not h.play.is_empty() and int(h.play.get("fielder", 0)) != 0 \
		and h.play.get("result", "") not in ["home_run", "foul"] and h.human_state not in ["waiting"]
	var field_t: float = float(h.play.get("field_time", INF)) if fielded else INF

	# Where the ball is: along its flight; then with the fielder; then on its way to a base.
	var idx = 0
	if h.t < minf(path_end, field_t):
		idx = clampi(int(h.t / h.dt), 0, n - 2)
		var f = (h.t - idx * h.dt) / h.dt
		h.ball.global_position = h.points[idx].lerp(h.points[idx + 1], f)
	elif not fielded or h.t < field_t:
		idx = n - 1
		h.ball.global_position = h.points[n - 1]
	else:
		idx = clampi(int(minf(field_t, path_end) / h.dt), 0, n - 1)
		h.ball.global_position = host._director.ball_with_fielder(h)

	if h.human_state in ["holding", "gripped"]:
		h.ball.global_position = host.fielding.held_by_human(h)

	# Grow the trail while the ball is still on its own flight.
	if idx - h.last_idx >= 3 or h.t >= path_end:
		h.last_idx = idx
		h.trail_mesh.clear_surfaces()
		if idx >= 2:
			h.trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			var k = 0
			while k <= idx:
				h.trail_mesh.surface_add_vertex(h.points[k])
				k += 2
			h.trail_mesh.surface_add_vertex(h.points[idx])
			h.trail_mesh.surface_end()

	if h.rolling and (h.t >= minf(path_end, field_t) or h.done):
		h.rolling = false
		if host._audio != null:
			host._audio.loop_off("roll")
	# Where it came down.
	var grounder: bool = h.summary.wall or (h.summary.apex < 2.0 and not h.summary.home_run)
	var landed_due: bool = h.t >= path_end if grounder else h.t >= float(h.summary.get("landing_time", 1e9))
	if not h.landing_shown and (landed_due or h.t >= path_end):
		h.landing_shown = true
		show_landing(h)

	if h == play_hit:
		host._director.update_play(h)
	if not h.result_shown and h.t >= h.play_end:
		h.result_shown = true
		host.flow.announce_play(h)
	if h.t >= maxf(maxf(h.play_end, path_end), host._director.plan_anim_end(h.plan)):
		h.done = true
		h.ball.global_position = h.ball.global_position


func show_landing(h: LiveHit) -> void:
	var sim = h.summary
	host.bus.ball_landed.emit(h)
	var spot: Vector3 = sim.landing_pos
	var shown_distance: float = sim.distance
	if sim.wall or (sim.apex < 2.0 and not sim.home_run):
		spot = sim.rest_pos
		shown_distance = Vector2(spot.x, spot.z).length()
	elif sim.home_run and sim.has("fence_cross"):
		spot = sim.fence_cross
	var ring = TorusMesh.new()
	ring.inner_radius = 0.9
	ring.outer_radius = 1.25
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.55, 0.1) if sim.fair else Color(0.9, 0.9, 0.9)
	h.marker = MeshInstance3D.new()
	h.marker.mesh = ring
	h.marker.material_override = mat
	h.marker.position = Vector3(spot.x, 0.05, spot.z)
	host.add_child(h.marker)
	h.label = Label3D.new()
	h.label.text = ("HR  %.0f m" if sim.home_run else "%.0f m") % shown_distance
	h.label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	h.label.fixed_size = true
	h.label.pixel_size = 0.0016
	h.label.font_size = 64
	h.label.outline_size = 14
	h.label.modulate = Color(1.0, 0.85, 0.2)
	h.label.no_depth_test = true
	h.label.position = Vector3(spot.x, maxf(spot.y, 0.0) + 3.0, spot.z)
	host.add_child(h.label)
	if h.play.is_empty():
		host.hud.last_report = h.report
		host.hud.refresh_hud()
		print(h.report.replace("\n", " | "))


func free_hit(h: LiveHit) -> void:
	if h.rolling and host._audio != null:
		host._audio.loop_off("roll")
	if h == play_hit:
		host._director.reset_fielders()
		play_hit = null
	h.ball.queue_free()
	h.trail_inst.queue_free()
	if h.marker:
		h.marker.queue_free()
	if h.label:
		h.label.queue_free()


## Put this pitch on the zone as a dot colored by where it crossed, with a halo for the result.
func mark_pitch(a: Dictionary, outcome: String) -> void:
	if host._zone_markers == null or not a.get("reached", false):
		return
	var p: Vector3 = a.plate_pos
	host._sfx("zone_dot_pop", Vector3(p.x, p.y, 0.0), -8.0)
	var loc = PitchLocation.classify(p.x, p.y)
	var halo = Color(0.0, 0.0, 0.0, 0.0)
	match outcome:
		"in_play":
			halo = Color(0.2, 0.9, 1.0, 1.0)
		"swinging_strike":
			halo = Color(1.0, 1.0, 1.0, 1.0)
		"foul":
			halo = Color(0.6, 0.6, 0.6, 1.0)
		_:
			if loc.halo:
				halo = Color(1.0, 0.82, 0.15, 1.0)      # a corner that was not hit
	host._zone_markers.add(p.x, p.y, loc.color, halo)


## Inject a batted ball without a pitch (for looking at fielding and baserunning).
## The defense's answer for a ball in play. If a human plays the position that would field it,
## the ball is his chance, and the AI's version is what happens when he misses.
func resolve_ball(pitch: LivePitch) -> void:
	var run_f = host._batter_player.run_factor() * host._run_rng.randf_range(0.97, 1.03)
	# You are the pitcher: the ball is not yours to field (yet), so an AI one stays out of it.
	var skip: Array = [1] if host._mode.human_pitcher else []
	pitch.play = host._defense.resolve(pitch.sim, run_f, skip)
	if pitch.bat.get("bunt", false):
		pitch.play["bunt"] = true
	if host._mode.human_pitcher and host._mode.human_fielders.is_empty() and pitch.sim.get("fair", false) and not pitch.sim.get("home_run", false):
		# A comebacker: if the pitcher is the one who would get to it, the ball is yours (your glove, your throw).
		var with_pitcher = host._defense.resolve(pitch.sim, run_f, [])
		if int(with_pitcher.get("fielder", 0)) == 1 and with_pitcher.get("result", "") not in ["home_run", "foul"]:
			pitch.human_chance = true
			pitch.play = with_pitcher
			pitch.play_fallback = host._defense.resolve(pitch.sim, run_f, [1])
	if not host._mode.human_fielders.is_empty():
		var hn: int = host._mode.human_fielders[0]
		if int(pitch.play.get("fielder", 0)) == hn and pitch.play.get("result", "") != "home_run":
			pitch.human_chance = true
			pitch.play_fallback = host._defense.resolve(pitch.sim, run_f, [hn])


func debug_hit(ev_mph: float, launch_deg: float, spray_deg: float) -> void:
	var v = ev_mph / PitchPhysics.MPS_TO_MPH
	var la = deg_to_rad(launch_deg)
	var psi = deg_to_rad(spray_deg)
	var dir_h = Vector3(sin(psi), 0.0, cos(psi))
	var vel = dir_h * (v * cos(la)) + Vector3.UP * (v * sin(la))
	var spin = dir_h.cross(Vector3.UP).normalized() * (1800.0 * PitchPhysics.RPM_TO_RADS)
	var origin = Vector3(0.0, 0.9, 0.4)
	var rel = Vector3(0.0, PitchPhysics.MOUND_H + 1.85, PitchPhysics.MOUND_Z - 1.7)
	var pv = PitchPhysics.solve_aim(rel, 36.0, Vector3.ZERO, Vector3(0.0, 0.85, 0.0))
	var pitch = LivePitch.new()
	pitch.pos = origin
	pitch.label = "Test pitch"
	pitch.analysis = PitchPhysics.analyze(rel, pv, Vector3.ZERO)
	pitch.bat = {"swing": true, "contact": true, "kind": "hit", "ev": ev_mph, "la": launch_deg,
		"vel": vel, "spin": spin, "contact_pos": origin, "bat_target": origin, "contact_time": 0.0}
	pitch.sim = BattedBall.simulate(origin, vel, spin)
	resolve_ball(pitch)
	pitch.ball = host.world.make_ball()
	pitch.trail_inst = MeshInstance3D.new()
	pitch.trail_inst.mesh = pitch.trail_mesh
	host.add_child(pitch.trail_inst)
	pitches.append(pitch)
	swings += 1
	contact(pitch)


func debug_throw() -> void:
	var names = PitchPhysics.CANNED.keys()
	var key: String = names[canned_index % names.size()]
	canned_index += 1
	var def: Dictionary = PitchPhysics.CANNED[key]
	var rel = Vector3(0.0, PitchPhysics.MOUND_H + 1.85, PitchPhysics.MOUND_Z - 1.7)
	var spin: Vector3 = (def.rpm as Vector3) * PitchPhysics.RPM_TO_RADS
	var target = Vector3(randf_range(-0.15, 0.15), randf_range(0.6, 1.0), 0.0)
	var v = PitchPhysics.solve_aim(rel, float(def.mph) / PitchPhysics.MPS_TO_MPH, spin, target)
	launch(rel, v, spin, key)


func rebuild_trail(pitch: LivePitch) -> void:
	pitch.trail_mesh.clear_surfaces()
	if pitch.trail.size() < 2:
		return
	pitch.trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in pitch.trail:
		pitch.trail_mesh.surface_add_vertex(p)
	pitch.trail_mesh.surface_end()
