class_name Activities
extends RefCounted
## The things you can do instead of (or inside) an ordinary game: the home run derby, a fielding drill, a challenge (a short
## situation to solve) and the pitching lesson with the pitch lab. Each has its own small state and its own end; the scene (`host`)
## owns everything else and is told what happened.

var host                                    # the bullpen scene (untyped: its members are reached by name)

var tutorial: Tutorial                     # the pitching lesson, when that is what you are playing
var derby := false                         # home run derby: ten outs of easy pitches
var derby_outs := 0
var derby_hr := 0
var derby_done := false
var drill := false                         # ten balls hit to your fielding position
var drill_left := 10
var drill_timer := 3.0
var drill_started := 0
var drill_done := false
var scenario: Scenario            # the challenge being played (null in an ordinary game)
var scenario_id := ""
var scenario_done := false


## Batting practice pitches: slow, straight and over the middle (a little wandering so it is not a machine).
func derby_pitch(release: Vector3) -> Dictionary:
	var target = Vector3(host._run_rng.randf_range(-0.12, 0.12), host._run_rng.randf_range(0.65, 1.0), 0.0)
	var vel = PitchPhysics.solve_aim(release, 23.0, Vector3.ZERO, target)
	return {"vel": vel, "spin": Vector3.ZERO, "kind": "BP fastball"}


## One pitch of the derby is over: a homer is a homer; a swing that is not, or a strike you took, is an out;
## a ball you let go is free. Ten outs and it is over.
func derby_tally(pitch: LivePitch, home_run: bool, struck: bool) -> void:
	if not derby or derby_done:
		return
	if home_run:
		derby_hr += 1
	elif struck or pitch.bat.get("swing", false) or pitch.bat.get("contact", false):
		derby_outs += 1
	host.hud.show_notice("Derby: %d home runs, %d of 10 outs" % [derby_hr, derby_outs], true)
	if derby_outs >= 10:
		finish_derby()


func finish_derby() -> void:
	derby_done = true
	var stars = 3 if derby_hr >= 8 else (2 if derby_hr >= 5 else (1 if derby_hr >= 2 else 0))
	var r = host._profile.record_challenge("derby", stars, derby_hr)
	host._profile.save()
	host.slog.record("derby", {"home_runs": derby_hr, "stars": stars})
	host.hud.show_notice("DERBY OVER: %d home runs   %s%s" % [derby_hr, Scenario.stars_text(stars), "  (new best!)" if r.improved else ""], true)
	host._props.later(7.0, func():
		Session.show_menu = true
		host.get_tree().reload_current_scene.call_deferred())


func mode_is_not_fielding(c: GameConfig) -> bool:
	return c.mode != "Fielding"


## The drill: every few seconds a ball is hit at your position (grounders to an infielder, fly balls to an
## outfielder); after ten the result is saved as stars and you go back to the menu.
func run_drill(delta: float) -> void:
	if not drill or drill_done or host._game == null:
		return
	var busy = not host._hits.is_empty() and not (host._hits[host._hits.size() - 1] as LiveHit).result_shown
	if busy or not host._aux_play.is_empty() or not host._walk_on.is_empty():
		return
	drill_timer -= delta
	if drill_timer > 0.0:
		return
	if drill_left <= 0:
		finish_drill()
		return
	var n = host.fielding.human_num()
	var home: Vector3 = host._defense.fielder_by_num(n).home
	var spray = rad_to_deg(atan2(home.x, home.z)) + host._run_rng.randf_range(-5.0, 5.0)
	var infield = n in [3, 4, 5, 6]
	var ev = host._run_rng.randf_range(68.0, 92.0) if infield else host._run_rng.randf_range(86.0, 98.0)
	var la = host._run_rng.randf_range(-8.0, 3.0) if infield else host._run_rng.randf_range(20.0, 34.0)
	drill_left -= 1
	drill_started += 1
	drill_timer = 3.5
	host.hud.show_notice("Drill: ball %d of %d" % [drill_started, drill_started + drill_left], true)
	host._debug_hit(ev, la, spray)


func finish_drill() -> void:
	drill_done = true
	var caught = int(host.fielding.fld.caught) + int(host.fielding.fld.assists)
	var stars = 3 if (int(host.fielding.fld.caught) >= 9 and int(host.fielding.fld.errors) == 0) else (2 if int(host.fielding.fld.caught) >= 7 else (1 if int(host.fielding.fld.caught) >= 5 else 0))
	var r = host._profile.record_challenge("drill_f%d" % host.fielding.human_num(), stars, int(host.fielding.fld.caught))
	host._profile.save()
	host.slog.record("drill", {"position": host.fielding.human_num(), "chances": host.fielding.fld.chances, "caught": host.fielding.fld.caught, "errors": host.fielding.fld.errors, "assists": host.fielding.fld.assists, "stars": stars})
	host.hud.show_notice("DRILL: %d of %d fielded, %d errors   %s%s" % [int(host.fielding.fld.caught), drill_started, int(host.fielding.fld.errors), Scenario.stars_text(stars), "  (new best!)" if r.improved else ""], true)
	host._props.later(7.0, func():
		Session.show_menu = true
		host.get_tree().reload_current_scene.call_deferred())


## A challenge is judged after every event; when it ends the result is saved and you go back to the menu.
func update_scenario(ev: Dictionary) -> void:
	if scenario == null or scenario_done:
		return
	var st = scenario.update(host._game, ev)
	if st == "running":
		host.hud.refresh_hud()
		return
	scenario_done = true
	var r = host._profile.record_challenge(scenario.id, scenario.stars, scenario.pitches)
	host._profile.save()
	host.slog.record("challenge", {"id": scenario.id, "state": st, "stars": scenario.stars, "pitches": scenario.pitches})
	if st == "success":
		host.hud.show_notice("CHALLENGE COMPLETE  %s%s" % [Scenario.stars_text(scenario.stars), "  (new best!)" if r.improved else ""], true)
		host._sfx_later(0.3, "music_victory", null, -4.0)
		host._sfx_later(0.3, "crowd_cheer_big")
		host._haptics.play("rumble", 0.8)
	else:
		host.hud.show_notice("Challenge failed - try again", true)
		host._sfx_later(0.3, "crowd_groan")
	host.hud.refresh_hud()
	host._props.later(6.0, func():
		Session.show_menu = true
		host.get_tree().reload_current_scene.call_deferred())


## The pitch lab: in the bullpen (and the lesson) every pitch is explained under its report.
func lab_lines(pitch: LivePitch) -> String:
	if not (host._config.activity == "Bullpen" or host._config.tutorial) or pitch.shape.is_empty():
		return ""
	return "\n" + "\n".join(PitchLab.explain(pitch.label, pitch.analysis, pitch.shape))


## One pitch of the lesson: it moves on by itself and says what it saw.
func tutorial_pitch(pitch: LivePitch) -> void:
	if tutorial == null or pitch.shape.is_empty() or not pitch.analysis.get("reached", false):
		return
	var r = tutorial.on_pitch(pitch.label, bool(pitch.analysis.get("strike", false)))
	if String(r.text) != "":
		host.hud.show_notice(String(r.text), true)
	if r.advanced:
		host._settings.tutorial_step = tutorial.step
		host._settings.save()
		host._sfx("corner_chime")
		host._haptics.play("ui_select")
	host.hud.refresh_hud()
