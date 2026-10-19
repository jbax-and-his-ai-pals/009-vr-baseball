class_name GameResults
extends RefCounted
## When a game ends: your line (pitching, hitting or fielding, see GameRecords), its place in the book (PlayerProfile) and, in a
## career, the result of the start. The scene (`host`) owns the game.

var host                                    # the bullpen scene (untyped: its members are reached by name)

var game_recorded := false
var best_ev := 0.0


## What you did as a batter this game: the lineup is you, so it is the lineup's line against their pitcher.
func hitting_line() -> Dictionary:
	return GameRecords.hitting(host._game, best_ev, host._home.name)


## What you did as a fielder this game (see PlayerProfile.fielding_score).
func fielding_line() -> Dictionary:
	return GameRecords.fielding(host._game, host.fielding.fld, host.fielding.human_num(), host._away.name)


## A career start is over: the result goes into the season, you are told how you did, and you go back to the menu.
func finish_career_start() -> void:
	if host._career == null:
		return
	var line = game_line()
	var res = host._career.finish_start(line, host._game.home_score, host._game.runs)
	host._career.save()
	var d: Dictionary = res.deltas
	host.slog.record("career_start", {"won": res.won, "rank": res.rank, "over": res.over, "deltas": d, "line": line})
	host.hud.show_notice("%s %d-%d vs %s   CMD %+.1f  STA %+.1f   Rank #%d%s" % ["WIN" if res.won else "LOSS", host._game.home_score, host._game.runs,
		res.opponent, float(d.command), float(d.stamina), int(res.rank), "   SEASON OVER" if res.over else ""], true)
	host._props.later(7.0, func():
		Session.show_menu = true
		host.get_tree().reload_current_scene.call_deferred())


## What you did in this game, as one pitching line.
func game_line() -> Dictionary:
	return GameRecords.pitching(host._game, host._stats, host.manager.sign_tally, host._away.name, host.manager.left_line, host.roles.bat_log)


## A finished game goes in the book (only games you pitch that count for a leaderboard).
func record_finished_game() -> void:
	if host.acts.drill or host.acts.derby or game_recorded or not (host._mode.human_pitcher or host.manager.user_left or not host._mode.human_fielders.is_empty() or host._mode.human_batter):
		return
	game_recorded = true
	var cfg = host._current_config()
	if host._career_game:
		host._profile.record_game(cfg, game_line())          # counts in your lifetime totals, on no board
		host._profile.save()
		finish_career_start()
		return
	if not cfg.is_scored():
		return
	var line = fielding_line() if not host._mode.human_fielders.is_empty() else (hitting_line() if host._mode.human_batter else game_line())
	var r = host._profile.record_game(cfg, line)
	host._profile.save()
	var text = "Game Score %d" % int(r.score)
	var bat_note = GameRecords.bat_text(line.get("bat", {}))
	if bat_note != "":
		text += "   " + bat_note
	if int(r.rank) == 1:
		text += " - best on this board!"
	elif int(r.rank) > 0:
		text += " - #%d on this board" % int(r.rank)
	host.slog.record("game_recorded", {"score": r.score, "rank": r.rank, "key": r.key, "line": line})
	host.hud.show_notice(text, true)
