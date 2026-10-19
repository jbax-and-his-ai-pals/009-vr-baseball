class_name RoleSwitch
extends RefCounted
## Between the halves of a two-way game you change roles: when your pitching half is over the game waits a moment, then you are the
## batter for the bottom (a one-inning GameState of your lineup against their pitcher), and when that is over you are on the mound
## again. The pitching game is kept in `top_game` while you bat. The scene (`host`) owns everything else.

var host                                    # the bullpen scene (untyped: its members are reached by name)

var two_way := false                       # you also bat: the bottom halves are played live
var top_game: GameState                    # while you bat, the pitching game waits here
var bottom_end_timer := -1.0               # counts down once your half is over, then hands the game back
var opp_pitcher: AIPitcher                 # their pitcher, kept from one bottom half to the next
var bat_log: Dictionary = {"ab": 0, "h": 0, "hr": 0, "rbi": 0, "bb": 0, "k": 0}
## ---------------------------------------------------------------- two-way games: pitch, then bat
## Between the halves of a two-way game you change roles: when your pitching half is over the game waits a
## moment, then you are the batter for the bottom (a one-inning GameState of your lineup against their
## pitcher), and when that is over you are on the mound again. The pitching game is kept in `_top_game`.
var role_timer := 2.5


## True while the game is between the halves: nobody pitches and no batter walks up.
func on_break() -> bool:
	return host._game != null and (host._game.awaiting_bottom or bottom_end_timer > 0.0)


func update_roles(delta: float) -> void:
	if host._game == null or not two_way:
		return
	var settled = host.flow.aux_play.is_empty() and host._walk_on.is_empty() and not host.flow.play_in_progress()
	for h in host.flight.hits:
		if not h.result_shown:
			settled = false
	if top_game == null and host._game.awaiting_bottom and settled:
		role_timer -= delta
		if role_timer <= 0.0:
			role_timer = 2.5
			enter_bottom()
	elif top_game != null and bottom_end_timer > 0.0 and settled:
		bottom_end_timer -= delta
		if bottom_end_timer <= 0.0:
			bottom_end_timer = -1.0
			finish_bottom_half()
	else:
		role_timer = 2.5


## Where you stand for the role: on the mound, or in the box.
func place_for_role() -> void:
	var mz = PitchPhysics.MOUND_Z
	var mh = PitchPhysics.MOUND_H
	if host._origin != null:
		if host._mode.human_batter:
			var side = 1.0 if host._settings.hand == "right" else -1.0
			host._origin.position = Vector3(side * 1.2, 0.0, -0.1)
			host._origin.rotation = Vector3(0.0, PI, 0.0)
		else:
			host._origin.position = Vector3(0.0, mh, mz)
			host._origin.rotation = Vector3.ZERO
	elif host._camera != null:
		if host._mode.human_batter:
			host._camera.global_position = Vector3(3.5, 1.7, -5.0)
			host._camera.look_at(Vector3(0.0, 1.5, 18.0))
		else:
			host._camera.global_position = Vector3(0.0, mh + 1.7, mz + 0.5)
			host._camera.look_at(Vector3(0.0, 1.0, 0.0))


## Who wears what: the home team fields in the top halves, the visitors in the bottoms (and the other way
## round for the men on the bases).
func dress_teams(bottom: bool) -> void:
	var fielding: Team = host._away if bottom else host._home
	var batting: Team = host._home if bottom else host._away
	for n in host._field_nodes:
		var d = host._field_nodes[n]
		if d is Doll:
			(d as Doll).recolor(fielding.jersey, fielding.pants, fielding.cap)
	var runners: Array = [host._runner]
	runners.append_array(host._base_runners)
	runners.append_array(host._leavers)
	for r in runners:
		if r is Doll:
			(r as Doll).recolor(batting.jersey, batting.pants, batting.cap)


func enter_bottom() -> void:
	top_game = host._game
	var half = GameState.new(host._home.lineup, 1)
	half.order_index = host._home_order % maxi(host._home.lineup.size(), 1)
	host._game = half
	host.flight.drop_held()
	host._mode = GameMode.hitting()
	host._sound.mode = host._mode
	host._ensure_bat_view()
	host.flight.bat_view.visible = true
	if opp_pitcher == null:
		opp_pitcher = AIPitcher.new(host._away.player_at(1))
		opp_pitcher.rng.seed = host._run_rng.randi()
	host._ai_pitcher = opp_pitcher
	host.world.ensure_pitcher_doll()
	(host._field_nodes[1] as Node3D).visible = true
	dress_teams(true)
	place_for_role()
	host._spectate_timer = 2.5
	if host._zone_markers:
		host._zone_markers.clear()
	host.flow.batter_ready = false
	host.flow.sync_batter()
	host.flow.begin_walk_on()
	host.slog.record("role_switch", {"to": "batting", "inning": top_game.inning, "score": "%d-%d" % [top_game.runs, top_game.home_score]})
	host.hud.show_notice("Bottom of %d: you are up to bat" % top_game.inning, true)
	host._sfx("pa_pitching_change")
	host.flow.refresh_base_runners()
	host.hud.refresh_hud()


## Your half is over (three outs, or a walk-off): the runs go on the board and you take the mound again.
func finish_bottom_half() -> void:
	var half = host._game
	bat_log.h += half.hits
	bat_log.hr += half.home_runs
	bat_log.bb += half.walks
	bat_log.k += half.strikeouts
	bat_log.rbi += half.runs
	host._home_order = half.order_index
	opp_pitcher = host._ai_pitcher
	host._game = top_game
	top_game = null
	host._mode = GameMode.pitching()
	host._sound.mode = host._mode
	dress_teams(false)
	if host.flight.bat_view != null:
		host.flight.bat_view.visible = false
	if host._field_nodes.has(1):
		(host._field_nodes[1] as Node3D).visible = false
	place_for_role()
	host._batter.visible = true
	host._batter.transform = host._batter_home
	if host._zone_markers:
		host._zone_markers.clear()
	var ev = host._game.finish_bottom(half.runs, half.hits)
	host.slog.record("role_switch", {"to": "pitching", "runs": half.runs, "hits": half.hits, "game_over": host._game.over})
	host.hud.show_notice("Bottom %d: Home %s" % [int(ev.get("inning_ended", 0)), "scores %d" % half.runs if half.runs > 0 else "goes down in order"], true)
	host.flow.after_event(ev)
	if not host._game.over:
		host.flow.sync_batter()
		host.flow.begin_walk_on()
	host.hud.refresh_hud()


## An event of the bottom half you are batting: the mini-game ending is the half ending, not the game.
func bottom_event(ev: Dictionary, extra: Dictionary) -> Dictionary:
	var out = ev.duplicate()
	var walk_off: bool = top_game.inning >= top_game.innings and top_game.home_score + host._game.runs > top_game.runs
	if bool(out.get("game_over", false)) or walk_off:
		out["game_over"] = false
		out["half_over"] = false
		bottom_end_timer = 2.5
	return out
