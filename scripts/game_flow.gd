class_name GameFlow
extends RefCounted
## The rhythm of a game: the batter walking up and stepping in, the plate appearance ending and the batter leaving, a play being
## announced, and everything that follows an event of the game (the scoreboard, the crowd, the dugouts, the next batter, the end of
## the game). It owns whether the batter is ready and the animation of a walk or strikeout; the scene (`host`) owns everything else.

var host                                    # the bullpen scene (untyped: its members are reached by name)

var batter_ready := true                  # in the box and pitching may go on
var unready_for := 0.0
var aux_play := {}                        # a walk or strikeout's own runner animation
var game_over_timer := -1.0


## Put the right hitter at the plate: the lineup's next man in a Game, the chosen archetype in Practice.
func sync_batter() -> void:
	if host.lineup_mode == "Game" and host._game and host._game.current_batter() != null:
		host._batter_player = host._game.current_batter()
		host._batter_ai.profile = BatterProfile.from_player(host._batter_player)
	host._batter_ai.bats_left = batter_is_lefty()
	host.hud.refresh_scoreboard()
	# A batter already standing in his box (the first of a game) takes the right side now; everyone
	# else is placed when he walks on, so the last batter never flips sides in front of you.
	if batter_ready and host._walk_on.is_empty() and aux_play.is_empty() and not play_in_progress() and host._batter != null:
		host._presenter.place_in_box(batter_is_lefty())


func batter_is_lefty() -> bool:
	if "--lefty" in OS.get_cmdline_user_args():
		return true                      # debug: make every batter left-handed
	return host._batter_player != null and not host._batter_player.bats_right


## A strikeout or a walk ended the at-bat on the pitch: the batter leaves the box (walks off,
## or jogs to first with the men ahead of him moving up) and the next batter walks on.
func begin_pa_exit(ev: Dictionary, bases_before: Array) -> void:
	if not ev.get("pa_over", false):
		return
	batter_ready = false
	host.slog.record("pa_exit", {"result": ev.get("result", ""), "text": ev.get("text", "")})
	var plan: Dictionary
	if String(ev.get("result", "")) in ["walk", "hit_by_pitch"] or ev.get("batter_reached", false):
		plan = Baserunning.plan_hold(bases_before, host._batter_player, true)
		plan["hide_batter_at"] = 0.3
		if String(ev.get("result", "")) == "hit_by_pitch":
			(plan["events"] as Array).append({"t": 0.1, "base": 0, "text": "HIT BY PITCH", "kind": "out",
				"at": Vector3(0.9, 0.0, 0.0)})
	else:
		plan = Baserunning.plan_leave(host._batter_player)
	plan["walk_on_when_hidden"] = true
	if String(ev.get("result", "")) == "strikeout":
		plan["keep_bat"] = true            # he carries it back to the dugout
	aux_play = {"plan": plan, "t": 0.0}
	for lab in host._play_labels:
		lab.visible = false
	refresh_base_runners(bases_before)


## The next batter comes from the dugout to the box. Pitching waits until he is there.
func begin_walk_on() -> void:
	if host.roles.on_break():
		batter_ready = false         # between the halves: nobody walks up
		return
	host._crew.return_to_plate()      # the umpire is back behind the plate for the next batter
	if host._game != null and not host._game.over:
		host._sfx("pa_now_batting")
		if host._fx_rng.randf() < 0.4:
			host._sfx("organ_stinger", null, -6.0)
	if host._game != null and host._game.over:
		batter_ready = true
		return
	batter_ready = false
	# A new batter: the last batter's pitch dots are done with.
	if host._zone_markers:
		host._zone_markers.clear()
	host.hud.refresh_hud()
	var duration = host._presenter.begin_walk_on(batter_is_lefty())
	host.slog.record("walk_on", {"duration": snappedf(duration, 0.01), "batter": host._batter_player.name if host._batter_player else ""})
	if host._game != null and not host._game.over and host._fx_rng.randf() < 0.5:
		host._sfx("music_walkup", null, -10.0)


## True while a ball in play (one with runners moving) has not been announced yet.
func play_in_progress() -> bool:
	for h in host.flight.hits:
		if not h.result_shown and not h.plan.is_empty():
			return true
	return false


func update_batter_lifecycle(delta: float) -> void:
	host.plays.update_flights(delta)
	if host.flight.play_hit == null or host.flight.play_hit.done:
		host._director.drift_to_homes(delta)        # between plays the fielders walk to where they should stand
	if not host.plays.steal.is_empty():
		if host.plays.steal.has("apply_at") and not host.plays.steal.get("done", false):
			# Decided on the base: put it in the book (also if the run animation has already ended).
			if aux_play.is_empty() or float(aux_play.t) >= float(host.plays.steal.apply_at):
				host.plays.finish_steal()
		elif host.plays.steal.has("await") and aux_play.is_empty():
			host.fielding.catcher_release(Vector3.ZERO)       # the run is over and you never threw
		elif aux_play.is_empty():
			host.plays.steal = {}            # the delivery never became a pitch: nothing to resolve
			host._bat_call = ""
	# Safety net: if nothing is happening that could make the batter ready, make him ready.
	var busy = not aux_play.is_empty() or not host._walk_on.is_empty()
	for h in host.flight.hits:
		if not h.result_shown:
			busy = true
	if batter_ready or busy or host.roles.on_break():
		unready_for = 0.0
	else:
		unready_for += delta
		if unready_for > 2.0:
			GameLog.mark("watchdog: the batter was not ready for 2 s and nothing explained it", host.slog.snapshot())
			batter_ready = true
			host._batter.visible = true
			host._batter.set_carry(false, true)
			host._batter.transform = host._batter_home
			unready_for = 0.0
	if not aux_play.is_empty():
		aux_play.t += delta
		var plan: Dictionary = aux_play.plan
		host._director.animate_plan(plan, float(aux_play.t))
		if float(aux_play.t) >= host._director.plan_anim_end(plan):
			aux_play = {}
			host._runner.visible = false
			for lv in host._leavers:
				lv.visible = false
			refresh_base_runners()
			host.hud.refresh_scoreboard()
	host._presenter.update(delta)


## The batter-runner has left the box: his bat drops (unless he carries it off), and if the plan says
## so the next batter starts walking on.
func on_batter_hidden(plan: Dictionary) -> void:
	if not plan.get("keep_bat", false):
		host.flight.drop_bat()
	host._batter.visible = false
	if plan.get("walk_on_when_hidden", false):
		begin_walk_on()


## He is in the box: the pitcher may throw.
func on_batter_arrived() -> void:
	host.manager.refresh_sign()
	host._sfx("batter_step_dirt", host._batter_home.origin)
	if host._fx_rng.randf() < 0.5:
		host._sfx_later(0.5, "bat_tap_plate", Vector3(0.0, 0.1, 0.0), -4.0)
	batter_ready = true
	host.hud.refresh_hud()


## The play is over: tell the scorebook, say what happened.
func announce_play(h: LiveHit) -> void:
	var play = h.play
	var text: String = play.get("text", "")
	var ev = {}
	if h.summary.get("home_run", false):
		text = "HOME RUN!"
		ev = host._game.in_play({"result": "home_run"}, h.plan)
	elif play.is_empty():
		return
	elif play.get("foul_tip", false):
		# Already counted when the bat hit it (a tip into the mitt is a strike on the spot).
		host.hud.last_report = "FOUL TIP\n" + h.report
		host.hud.refresh_hud()
		return
	elif play.get("result", "") == "foul":
		var bases_foul = host._game.bases.duplicate()
		host._crew.call_it("ump_foul", 0.1, 1.0)
		ev = host._game.pitch("foul_bunt" if h.bunt else "foul")
		text = "Foul bunt" if h.bunt else "Foul ball"
		if ev.get("pa_over", false):
			begin_pa_exit(ev, bases_foul)
	else:
		ev = host._game.in_play(play, h.plan)
		if play.get("ground_rule", false):
			host._sound.umpire_says_later(0.3, "ump_time")      # dead ball: two bases
	if host._runner:
		host._runner.visible = false       # he is on a base now (or out): the base figures take over
	host.hud.last_report_extra = ""
	var lines = text.to_upper() + "\n" + h.report
	if not ev.is_empty():
		var extra = host.hud.event_text(ev)
		if extra != "":
			lines += "\n" + extra
	host.hud.last_report = lines
	after_event(ev, {"ev": float(h.summary.get("ev_mph", 0.0)), "dist": float(h.summary.get("distance", 0.0))})
	host.hud.refresh_hud()
	host.slog.record("play_result", {"text": text, "result": ev.get("result", ""), "runs": ev.get("runs", 0), "outs_added": ev.get("outs_added", 0),
		"pa_over": ev.get("pa_over", false), "half_over": ev.get("half_over", false), "game_over": ev.get("game_over", false),
		"state_text": ev.get("text", ""), "duration": snappedf(h.t, 0.01)})
	print(host.hud.last_report.replace("\n", " | "))


## How far the crowd gets to its feet for this event (0 for nothing special).
func crowd_excitement(ev: Dictionary) -> float:
	match String(ev.get("result", "")):
		"home_run":
			return 1.0
		"triple", "double":
			return 0.5
		"strikeout":
			return 0.3
	return 0.6 if int(ev.get("runs", 0)) > 0 else 0.0


## After anything that changes the game: next batter, runners, scoreboard, game over.
func after_event(ev: Dictionary, extra: Dictionary = {}) -> void:
	if ev.is_empty():
		return
	if host.roles.top_game != null:
		ev = host.roles.bottom_event(ev, extra)
	if host._sound != null:
		host._sound.crowd_react(ev, host._game)
	if host._stadium != null:
		host._stadium.pulse(crowd_excitement(ev))
	if host._dugouts != null:
		host._dugouts.react_event(ev, "home" if host.roles.top_game != null else "away")
		if ev.get("game_over", false):
			host._dugouts.cheer("home" if host._game.home_score > host._game.runs else "away", "celebrate", true)
	match String(ev.get("result", "")):
		"home_run":
			host._haptics.play("rumble", 1.0)
		"strikeout":
			host._haptics.play("rumble", 0.3)
	if ev.get("pa_over", false):
		if host._batter_player and host.roles.top_game == null:
			host._stats.record_result(host._batter_player.name, String(ev.get("result", "out")),
				float(extra.get("ev", 0.0)), float(extra.get("dist", 0.0)))
		sync_batter()
		if aux_play.is_empty():
			begin_walk_on()          # after a ball in play the next batter comes up now
	elif aux_play.is_empty() and host._walk_on.is_empty() and not play_in_progress():
		batter_ready = true          # a foul (or any pitch that did not end the at-bat): he is still up
	if host.acts.drill or host.acts.derby:
		# A drill is not a game: nobody is ever out, nobody stays on, the count never fills.
		host._game.outs = 0
		host._game.bases = [null, null, null]
		host._game.balls = 0
		host._game.strikes = 0
		host._game.inning = 1
		host._game.over = false
	host.acts.update_scenario(ev)
	host.manager.update_alignment()
	host.manager.refresh_sign()
	if ev.get("game_over", false):
		host.results.record_finished_game()
		game_over_timer = -1.0 if (host.acts.scenario != null or host._career_game) else 8.0
		host.slog.record("game_over", {"final": host._game.final_text(), "line": host._game.line_text(), "stats": {"k": host._game.strikeouts,
			"bb": host._game.walks, "hits": host._game.hits, "wp": host._game.wild_pitches, "sb": host._game.stolen_bases, "cs": host._game.caught_stealing,
			"po": host._game.pickoffs, "balks": host._game.balks, "hbp": host._game.hit_by_pitches, "sac": host._game.sacrifices}})
	if ev.get("half_over", false):
		host.slog.record("half_over", {"inning": ev.get("inning_ended", 0), "home_runs_scored": ev.get("home_runs_scored", -1),
			"runs": host._game.runs, "home": host._game.home_score})
	if aux_play.is_empty():
		refresh_base_runners()
	host.hud.refresh_scoreboard()


## Figures on the bases that match the scorebook.
func refresh_base_runners(bases: Array = []) -> void:
	if host._game == null:
		return
	var on: Array = bases if bases.size() == 3 else host._game.bases
	if host._base_runners.is_empty():
		for i in 3:
			var fig = host.world.runner_doll(host._director.stand_for(i + 1))
			fig.idle_bounce = true             # on his toes off the bag
			fig.crouch = 0.6
			fig.visible = false
			host._base_runners.append(fig)
	for i in 3:
		var who = on[i]
		host.plays.leads[i] = StealModel.lead(who as Player, int(host.plays.since_throw[i])) if who is Player else 2.4
		host._base_runners[i].visible = on[i] != null
		(host._base_runners[i] as Doll).watching = false
		host._base_runners[i].position = host._director.stand_for(i + 1)
		host._base_runners[i].rotation.y = atan2(-Baserunning.BASE_POS[i + 1].x, -Baserunning.BASE_POS[i + 1].z)
