class_name Manager
extends RefCounted
## The decisions around the pitching: the catcher's signs and how you did against them, the hand signals (walk him, call the
## bullpen), the mound visit, handing the ball over, the AI manager changing his pitcher or walking someone, the infield alignment,
## the fatigue of your arm, and the umpire's call as words. The scene (`host`) owns everything else.

var host                                    # the bullpen scene (untyped: its members are reached by name)

## The umpire's call as words, for anyone who cannot hear it well (Options > Umpire call text).
const CALL_WORDS := {"ump_strike": "STRIKE", "ump_strike_three": "STRIKE THREE", "ump_ball": "BALL", "ump_out": "OUT", "ump_safe": "SAFE",
	"ump_foul": "FOUL BALL", "ump_balk": "BALK", "ump_infield_fly": "INFIELD FLY", "ump_time": "TIME", "ump_play_ball": "PLAY BALL"}

var visit_used := false                     # the one mound visit a game
var visit_timer := 0.0                      # seconds left of a visit (no pitching during it)
var fatigue_credit := 0                     # pitches your arm is rested by (a mound visit)
var user_left := false                      # you handed the ball to the bullpen
var left_line := {}                         # your line at that moment
var sign := {}                              # the catcher's call for the next pitch ({} when none)
var sign_tally := {"called": 0, "perfect": 0, "type": 0, "loc": 0, "shaken": 0}
var sign_label: Label3D
var sign_marker: MeshInstance3D
var seat_done := false
var gestures := Gestures.new()
var tired_notice := false
var relievers_used := 0
var runs_at_pitcher_change := 0


## First base open, a runner in scoring position, two outs or the late innings, and a hitter
## the defense does not want to pitch to: the AI manager walks him on purpose.
func wants_intentional_walk() -> bool:
	if host._game == null or host._batter_player == null or host._game.balls != 0 or host._game.strikes != 0:
		return false
	if host._game.bases[0] != null or (host._game.bases[1] == null and host._game.bases[2] == null):
		return false
	var late = host._game.inning >= maxi(host._game.innings - 2, 1)
	if host._game.outs < 1 and not late:
		return false
	return host._batter_player.power >= 68.0 and host._batter_player.hitting_overall() >= 62.0 and host._game.runs - host._game.home_score <= 2


## Walk the batter on purpose (the manager's call, or the pause menu): no pitches, the usual
## forced advance, and he trots to first.
func issue_intentional_walk() -> void:
	if host._game == null or not host._batter_ready or not host._aux_play.is_empty() or host._game.over:
		return
	host._log("intentional_walk", {"batter": host._batter_player.name if host._batter_player else ""})
	var before = host._game.bases.duplicate()
	var ev = host._game.intentional_walk()
	host._begin_pa_exit(ev, before)
	host._last_report = "INTENTIONAL WALK\n" + host._event_text(ev)
	host._after_event(ev)
	host._refresh_hud()


## How worn out the human pitcher's arm is (0 fresh .. 1 spent), from his pitch count and the
## starter's stamina. Tells you once when it starts to show.
func arm_fatigue() -> float:
	if host._game == null or host._home == null:
		return 0.0
	var f: float = host._home.player_at(1).fatigue(maxi(host._game.pitch_count - fatigue_credit, 0))
	if f > 0.35 and not tired_notice:
		tired_notice = true
		host._show_notice("Your arm is getting tired")
	return f


## The AI manager's call: a starter who is spent or getting hit hard is replaced by a reliever.
func maybe_change_pitcher() -> void:
	if host._ai_pitcher == null or host._game == null:
		return
	var tired = host._ai_pitcher.player.fatigue(host._ai_pitcher.pitches_thrown)
	var rough = host._game.runs - runs_at_pitcher_change >= 5
	if tired < 0.9 and not rough:
		return
	if host._game.outs != 0 or host._game.balls != 0 or host._game.strikes != 0:
		return               # changes happen between batters
	relievers_used += 1
	host._log("pitcher_change", {"tired": snappedf(tired, 0.01), "pitches": host._ai_pitcher.pitches_thrown,
		"runs_since": host._game.runs - runs_at_pitcher_change})
	var rp = Team.relief_pitcher(50.0 + 2.0 * relievers_used, 4000 + relievers_used * 31)
	host._ai_pitcher = AIPitcher.new(rp)
	host._ai_pitcher.rng.seed = host._run_rng.randi()
	runs_at_pitcher_change = host._game.runs
	host._show_notice("New pitcher: %s" % rp.name)
	host._sfx_later(1.0, "pa_pitching_change")
	host._refresh_scoreboard()


## The catcher comes out to the mound: you catch your breath (the arm is rested by 15 pitches) and cannot
## pitch for a few seconds. Once a game.
func mound_visit() -> void:
	if not host._mode.human_pitcher or visit_used or host._game == null or host._game.over:
		return
	visit_used = true
	fatigue_credit = 15
	visit_timer = 5.2
	host._crew.visit_mound()
	host._log("mound_visit", {"pitches": host._game.pitch_count})
	host._show_notice("Mound visit: you catch your breath", true)


## You hand the ball over: a reliever finishes the game (an AI pitcher, like Spectate), your line is closed
## as it stands, and the team's result is yours at the end.
func leave_game() -> void:
	if not host._mode.human_pitcher or host._game == null or host._game.over:
		return
	left_line = host._game_line()
	user_left = true
	host._game.bottom_live = false              # with you out of the game the bottom halves are played for you
	host._drop_held()
	relievers_used += 1
	var rp = Team.relief_pitcher(52.0, 5000 + relievers_used * 31)
	host._ai_pitcher = AIPitcher.new(rp)
	host._ai_pitcher.rng.seed = host._run_rng.randi()
	runs_at_pitcher_change = host._game.runs
	host._mode = GameMode.spectate()
	host._sound.mode = host._mode
	host._ensure_pitcher_doll()
	host._spectate_timer = 2.0
	host._log("leave_game", {"line": left_line, "reliever": rp.name})
	host._show_notice("%s takes over" % rp.name)
	host._sfx_later(1.0, "pa_pitching_change")
	host._refresh_scoreboard()
	host._refresh_hud()


func on_umpire_spoke(id: String, delay: float) -> void:
	if not host._settings.call_text or not CALL_WORDS.has(id):
		return
	host._props.later(delay, func():
		if host._call_label == null:
			return
		var words: String = CALL_WORDS[id]
		if id in ["ump_strike", "ump_ball"] and host._game != null:
			words += "  " + host._game.count_text()
		host._call_label.text = words
		host._call_label.visible = true
		host._call_label_until = host._game_time + 1.7)


## Hand signals with your glove hand (Options > Hand signals): overhead is an intentional walk, at the
## ear calls for the bullpen. Only while you pitch and the other hand is empty.
func poll_gestures(delta: float) -> void:
	if not host._settings.gestures or not host._xr_active or host._off_hand == null or host._camera == null or not host._off_hand.get_is_active() 			or not host._mode.human_pitcher or host._game == null or host._game.over or host.acts.scenario != null:
		return
	var sig = gestures.update(delta, host._camera.global_position, host._off_hand.global_position, host._held)
	match sig:
		"intentional_walk":
			host._log("gesture", {"signal": sig})
			host._haptics.play("ui_select")
			issue_intentional_walk()
		"bullpen_phone":
			host._log("gesture", {"signal": sig})
			host._haptics.play("ui_select")
			if host._menu != null and not host._menu.is_open() and host.lineup_mode == "Game":
				host._toggle_pause()
				host._menu.model.can_leave = true
				host._menu.goto("confirm_leave")


## Seated play: once the headset is tracking, lift the whole rig so a seated head is where a standing
## pitcher's would be (see Comfort.seated_offset). Done once per game start.
func seat_check() -> void:
	if seat_done or not host._settings.seated or not host._xr_active or host._origin == null or host._camera == null:
		return
	if host._camera.position.y < 0.3:
		return                          # not tracking yet
	seat_done = true
	var lift = Comfort.seated_offset(host._camera.position.y)
	host._origin.position.y += lift
	host._log("seated", {"head_y": snappedf(host._camera.position.y, 0.01), "lift": snappedf(lift, 0.01)})


## The catcher calls the next pitch (Options > Catcher signs): a pitch and a spot, shown by his knee and a
## marker on the zone. Only when you pitch in a game.
func signs_enabled() -> bool:
	return host._settings.signs and host._mode.human_pitcher and host.lineup_mode == "Game" and host.acts.scenario == null and host._game != null and not host._game.over


func refresh_sign() -> void:
	if sign_label == null:
		return
	if not signs_enabled():
		sign = {}
		sign_label.visible = false
		sign_marker.visible = false
		return
	var side = -1.0 if host._batter_is_lefty() else 1.0
	sign = CatcherSigns.call_pitch({"balls": host._game.balls, "strikes": host._game.strikes, "outs": host._game.outs,
		"bases": [host._game.bases[0] != null, host._game.bases[1] != null, host._game.bases[2] != null], "batter_side": side}, [], host._fx_rng)
	sign_label.text = "SIGN: %s" % sign.words
	sign_label.visible = true
	var tg: Vector2 = sign.target
	sign_marker.position = Vector3(tg.x, tg.y, 0.02)
	sign_marker.visible = true


## Y (or P): shake him off and he calls something else.
func shake_off() -> void:
	if sign.is_empty():
		host._show_notice("Y cycles batters in Practice mode", true)
		return
	sign_tally.shaken += 1
	var old = String(sign.words)
	refresh_sign()
	host._show_notice("Shook off %s: now %s" % [old, sign.words], true)


## A pitch reached the plate: was it what he called?
func grade_sign(pitch: LivePitch, plate: Vector3) -> void:
	if sign.is_empty() or not pitch.analysis.get("reached", false):
		return
	var g = CatcherSigns.grade(sign, pitch.label, plate.x, plate.y)
	sign_tally.called += 1
	if g.perfect:
		sign_tally.perfect += 1
	if g.type:
		sign_tally.type += 1
	if g.loc:
		sign_tally.loc += 1
	host._log("sign", {"sign": sign.words, "thrown": pitch.label, "type": g.type, "loc": g.loc, "perfect": g.perfect})
	if g.perfect:
		host._show_notice("SIGN HIT!", true)
		host._sfx("corner_chime")
		host._haptics.play("ui_select")


## The infield plays in when a run at the plate matters (see Defense.wants_infield_in).
func update_alignment() -> void:
	if host._game == null or host._defense == null:
		return
	var want = Defense.wants_infield_in(host._game.outs, host._game.bases, host._game.inning, host._game.home_score - host._game.runs) and not host._game.over
	if want != host._defense.infield_in:
		host._defense.set_infield_in(want)
		host._log("alignment", {"infield_in": want})
		if want:
			host._show_notice("Infield in", true)


## A career pitcher's command narrows or widens the aim funnel (1.0 for everyone else).
func command_scale() -> float:
	return host._career.funnel_factor() if host._career_game and host._career != null else 1.0
