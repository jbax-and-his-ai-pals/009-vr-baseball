class_name HudText
extends RefCounted
## What the boards say: the pitching, batting and info boards you glance at, the scoreboard in the park, the notice that flashes
## up, and the text of a pitch report, a hit and an event. It owns the boards and the last report; the scene (`host`) owns the game.

var host                                    # the bullpen scene (untyped: its members are reached by name)

var notice := ""
var notice_until := 0.0
var hud: Node3D                 # holds the stat boards
var pitch_board: StatBoard
var bat_board: StatBoard
var info_board: StatBoard
var last_report := ""
var last_report_extra := ""


## Three boards that hang still in the park (not on your head): what you have thrown, how the
## lineup has hit, and the last pitch's details.
func build_boards() -> void:
	hud = Node3D.new()
	host.add_child(hud)
	var mound = Vector3(0.0, 0.0, PitchPhysics.MOUND_Z)
	# The two pitching boards stand just in front of the mound on either side, close enough to
	# read at a glance. The batting board hangs behind the plate, drawn large to be read from here.
	var specs = [
		["pitch", Vector3(-2.7, 3.1, 15.2), 2.5, 1.0],
		["info", Vector3(2.7, 2.8, 15.2), 2.7, 1.0],
		["bat", Vector3(0.0, 14.0, -6.5), 2.7, 4.6],
	]
	for sp in specs:
		var b = StatBoard.new()
		b.width = sp[2]
		hud.add_child(b)
		b.position = sp[1]
		b.scale = Vector3.ONE * float(sp[3])
		# Face the mound, where you stand.
		var to_mound: Vector3 = mound - (sp[1] as Vector3)
		b.rotation.y = atan2(to_mound.x, to_mound.z)
		match sp[0]:
			"pitch":
				pitch_board = b
			"bat":
				bat_board = b
			_:
				info_board = b


func bat_line(pitch: LivePitch) -> String:
	var b: Dictionary = pitch.bat
	if b.get("swing", false):
		return "\nBatter: swing and miss  (%s)" % host._batter_ai.profile.name
	if pitch.analysis.get("reached", false):
		return "\nBatter takes: %s  (%s)" % ["called strike" if pitch.analysis.strike else "ball", host._batter_ai.profile.name]
	return ""


func format_hit(b: Dictionary, sim: Dictionary) -> String:
	if b.kind == "foul tip":
		return "FOUL TIP\nExit velo %.0f mph" % b.ev
	var outcome: String
	if sim.home_run:
		outcome = "HOME RUN!"
	elif not sim.fair:
		outcome = "FOUL BALL"
	elif sim.wall:
		outcome = "OFF THE WALL"
	else:
		outcome = sim.kind.to_upper()
	var where = BattedBall.spray_text(sim.spray)
	if sim.wall:
		var wall_at: Vector3 = sim.rest_pos
		var wall_d = Vector2(wall_at.x, wall_at.z).length()
		return "%s  (%s)\nExit velo %.0f mph | Launch %+.0f deg | Spray %+.0f deg\nReaches the wall at %.0f m (%.0f ft) | Apex %.1f m" % [
			outcome, where, sim.ev_mph, sim.launch, sim.spray, wall_d, wall_d * 3.28084, sim.apex]
	if sim.apex < 2.0 and not sim.home_run:
		# A ball that never leaves the ground: report where it rolls to.
		var rest: Vector3 = sim.rest_pos
		var roll = Vector2(rest.x, rest.z).length()
		return "%s  (%s)\nExit velo %.0f mph | Launch %+.0f deg | Spray %+.0f deg\nRolls %.0f m (%.0f ft) | %d bounces" % [
			outcome, where, sim.ev_mph, sim.launch, sim.spray, roll, roll * 3.28084, sim.bounces]
	var feet: float = sim.distance * 3.28084
	return "%s  (%s)\nExit velo %.0f mph | Launch %+.0f deg | Spray %+.0f deg\nDistance %.0f m (%.0f ft) | Apex %.1f m | Hang %.1f s" % [
		outcome, where, sim.ev_mph, sim.launch, sim.spray, sim.distance, feet, sim.apex, sim.hang_time]


## Words for what a pitch or play did to the game.
func event_text(ev: Dictionary) -> String:
	if ev.is_empty():
		return ""
	var parts: Array[String] = []
	if ev.get("text", "") != "":
		parts.append(ev.text)
	if ev.get("runs", 0) > 0 and "run" not in String(ev.get("text", "")):
		parts.append("%d run%s" % [ev.runs, "" if ev.runs == 1 else "s"])
	if ev.get("pa_over", false) and ev.get("result", "") == "strikeout":
		parts.append("Strikeout")
	if ev.get("half_over", false):
		parts.append("THREE OUTS - end of inning %d" % int(ev.get("inning_ended", host._game.inning - 1)))
		if ev.has("home_runs_scored"):
			parts.append("Bottom %d: Home %s" % [int(ev.inning_ended), "scores %d" % int(ev.home_runs_scored) if int(ev.home_runs_scored) > 0 else "goes down in order"])
	if ev.get("game_over", false):
		parts.append(host._game.final_text() + " | " + host._game.line_text())
	return " | ".join(parts)


func refresh_scoreboard() -> void:
	if host._stadium == null or host._game == null:
		return
	var g = host.roles.top_game if host.roles.top_game != null else host._game
	var live: GameState = host._game if host.roles.top_game != null else null
	var who = host._batter_player.name if host._batter_player else ""
	var line = ""
	if host._batter_player:
		var bs: Dictionary = host._stats.batters.get(who, {})
		line = StatsTracker.avg_text(int(bs.get("h", 0)), int(bs.get("ab", 0))) if not bs.is_empty() else ""
		line = ("%s  %d-%d today" % [line, int(bs.get("h", 0)), int(bs.get("ab", 0))]) if not bs.is_empty() else ""
	var pitcher = "YOU" if host._mode.human_pitcher else host._ai_pitcher.player.name
	var home_by_inning: Array = g.home_inning_runs
	var home_runs = g.home_score
	var home_hits = g.home_team_hits
	if live != null:
		home_by_inning = g.home_inning_runs.duplicate()
		while home_by_inning.size() < g.inning:
			home_by_inning.append(0)
		home_by_inning[g.inning - 1] = live.runs
		home_runs += live.runs
		home_hits += live.hits
	host._stadium.set_scoreboard({
		"inning": g.inning, "innings": maxi(g.innings, g.inning), "inning_runs": g.inning_runs, "runs": g.runs,
		"home_inning_runs": home_by_inning, "home_runs": home_runs, "home_hits": home_hits,
		"hits": g.hits, "errors": g.errors, "balls": host._game.balls, "strikes": host._game.strikes, "outs": host._game.outs,
		"batter": who, "batter_line": line, "pitcher": pitcher,
		"last_kind": String(host._stats.last_pitch.get("kind", "")), "last_mph": float(host._stats.last_pitch.get("mph", 0.0)),
		"final": g.over})


func format_report(label: String, a: Dictionary) -> String:
	var head = "%s\n%.1f mph | %d rpm" % [label, a.speed_mph, roundi(a.spin_rpm)]
	if not a.reached:
		return head + "\nDid not reach the plate"
	var p: Vector3 = a.plate_pos
	var text = head + "\nPlate %.1f mph in %.2fs" % [a.plate_mph, a.time]
	if a.has("ivb_in"):
		text += "\nInduced vert %+.1f in | horiz %+.1f in" % [a.ivb_in, a.hb_in]
	text += "\n%s  %s  (%+.1f in x, %.1f in y)" % [
		"STRIKE" if a.strike else "BALL", PitchLocation.classify(p.x, p.y).label, p.x * PitchPhysics.M_TO_IN, p.y * PitchPhysics.M_TO_IN]
	return text


func settings_line() -> String:
	var line = "mode: %s" % host._mode.name
	if host._mode.human_pitcher:
		line += " | %s aim | %s spin | tag: %s" % [
			host.AimMode.keys()[host.aim_mode].to_lower().replace("_", " "),
			host.SpinMode.keys()[host.spin_mode].to_lower().replace("_", " "), host._current_tag()]
	else:
		line += "\npitching: " + host._ai_pitcher.player.pitcher_line()
	if host._batter_player:
		line += "\nat bat: " + host._batter_player.hitter_line()
	return line


func set_hud_idle() -> void:
	if host._xr_active:
		last_report = "Hold GRIP to pick up the ball.\nThrow, then open your hand."
	else:
		last_report = "No headset found.\nPress SPACE to throw a canned pitch."
	refresh_hud()


func show_notice(text: String, quiet: bool = false) -> void:
	if not quiet:
		host._sfx("ui_notice", null, -6.0)
	notice = text
	notice_until = Time.get_ticks_msec() / 1000.0 + 1.6
	refresh_hud()


func short_name(full: String) -> String:
	var parts = full.split(" ")
	if parts.size() < 2:
		return full
	return "%s. %s" % [parts[0].substr(0, 1), parts[parts.size() - 1]]


## Break a long report line at its " | " separators so it fits the board.
func wrap_text(text: String, max_chars: int = 58) -> Array:
	var out: Array = []
	for raw in text.split("\n"):
		var line = ""
		for piece in raw.split(" | "):
			if line != "" and line.length() + piece.length() + 3 > max_chars:
				out.append(line)
				line = piece
			else:
				line = piece if line == "" else line + " | " + piece
		if line != "":
			out.append(line)
	return out


func refresh_hud() -> void:
	if pitch_board == null:
		return
	# --- Pitching: what you have thrown.
	var g = host.roles.top_game if host.roles.top_game != null else host._game
	var t = host._stats.pitch_totals()
	pitch_board.title = "PITCHING"
	pitch_board.subtitle = host._mode.name if host._mode else ""
	pitch_board.accent = Color(0.12, 0.40, 0.78)
	pitch_board.tiles = [
		[g.innings_pitched_text() if g else "0.0", "IP"], [str(g.pitch_count) if g else "0", "PITCHES"],
		[str(g.strikeouts) if g else "0", "K"], [str(g.walks) if g else "0", "BB"], [str(g.hits) if g else "0", "H"]]
	pitch_board.columns = [{"head": "PITCH", "w": 0.34, "align": "l"}, {"head": "#", "w": 0.10, "align": "r"},
		{"head": "AVG", "w": 0.17, "align": "r"}, {"head": "MAX", "w": 0.15, "align": "r"},
		{"head": "STR%", "w": 0.12, "align": "r"}, {"head": "WHF%", "w": 0.12, "align": "r"}]
	var prow: Array = []
	for k in host._stats.types_sorted():
		var x: Dictionary = host._stats.by_type[k]
		prow.append([k, x.n, "%.0f" % host._stats.avg_mph(x), "%.0f" % x.mph_max, "%.0f" % host._stats.strike_pct(x),
			("%.0f" % host._stats.whiff_pct(x)) if x.swings > 0 else "-"])
	if prow.is_empty():
		prow.append(["-", "", "", "", "", ""])
	else:
		prow.append(["TOTAL", t.n, "%.0f" % (host._stats.avg_mph(t)), "%.0f" % t.mph_max, "%.0f" % host._stats.strike_pct(t),
			("%.0f" % host._stats.whiff_pct(t)) if t.swings > 0 else "-"])
	pitch_board.rows = prow
	pitch_board.total_row = prow.size() > 1
	var pl: Array = []
	if g:
		pl.append("%s   |   %d R" % [host._game.situation_text(), g.runs])
		if host.roles.top_game != null:
			pl.append("YOU ARE BATTING: bottom %d, Home %d - Away %d" % [g.inning, g.home_score + host._game.runs, g.runs])
		if host.acts.scenario != null:
			pl.append("%s: %s" % [host.acts.scenario.title.to_upper(), host.acts.scenario.progress_text(g)])
		if host.acts.tutorial != null:
			pl.append(host.acts.tutorial.prompt())
	pitch_board.lines = pl
	pitch_board.refresh()

	# --- Batting: how the lineup has done against you.
	var bt = host._stats.batting_totals()
	bat_board.title = "BATTING"
	bat_board.subtitle = "vs you"
	bat_board.accent = Color(0.72, 0.18, 0.20)
	bat_board.tiles = [[StatsTracker.avg_text(bt.h, bt.ab), "AVG"], [str(bt.h), "H"], [str(bt.hr), "HR"],
		[str(bt.k), "K"], [("%.0f" % (host._stats.ev_sum / maxf(float(host._stats.ev_count), 1.0))) if host._stats.ev_count > 0 else "-", "AVG EV"]]
	bat_board.columns = [{"head": "BATTER", "w": 0.34, "align": "l"}, {"head": "AB", "w": 0.10, "align": "r"},
		{"head": "H", "w": 0.10, "align": "r"}, {"head": "HR", "w": 0.10, "align": "r"},
		{"head": "BB", "w": 0.10, "align": "r"}, {"head": "K", "w": 0.10, "align": "r"},
		{"head": "AVG", "w": 0.16, "align": "r"}]
	var brow: Array = []
	for n in host._stats.batter_order:
		var b: Dictionary = host._stats.batters[n]
		brow.append([short_name(n), b.ab, b.h, b.hr, b.bb, b.k, StatsTracker.avg_text(b.h, b.ab)])
	brow.append(["TOTAL", bt.ab, bt.h, bt.hr, bt.bb, bt.k, StatsTracker.avg_text(bt.h, bt.ab)])
	bat_board.rows = brow
	var bl: Array = []
	if host._stats.ev_count > 0:
		bl.append("Hardest hit %.0f mph (%s)   |   Longest %.0f m" % [host._stats.ev_max, short_name(host._stats.hardest_name), host._stats.longest])
	bat_board.lines = bl
	bat_board.refresh()

	# --- The last pitch / play, and notices.
	info_board.show_plot = true
	info_board.plot = host._zone_markers.entries() if host._zone_markers else []
	info_board.title = "LAST PITCH"
	info_board.subtitle = host._batter_player.name if host._batter_player else ""
	info_board.accent = Color(0.18, 0.50, 0.30)
	var info: Array = []
	if notice != "":
		info.append(">> " + notice)
	info.append_array(wrap_text(last_report))
	if last_report_extra != "":
		info.append(">> " + last_report_extra)
	if host._batter_player:
		info.append_array(wrap_text(host._batter_player.hitter_line()))
	while info.size() > 9:
		info.pop_front()
	info_board.lines = info
	info_board.refresh()


## Between the halves: a card with the inning's story (hits, runs and strikeouts since the half began).
var half_start := {"hits": 0, "k": 0, "bb": 0, "runs": 0}


func counters() -> Dictionary:
	var g: GameState = host._game
	return {"hits": g.hits, "k": g.strikeouts, "bb": g.walks, "runs": g.runs}


func on_half_over(ev: Dictionary) -> void:
	var g: GameState = host._game
	var now := counters()
	if not ev.get("game_over", false):
		var due: Player = g.current_batter()
		show_notice("
".join(InningCard.lines(int(ev.get("inning_ended", g.inning)), half_start, now, g.runs, g.home_score, due.name if due != null else "")), true)
	half_start = now

