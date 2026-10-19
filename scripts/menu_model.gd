class_name MenuModel
extends RefCounted
## The menu as pure data: which screen you are on, what its rows say, and what choosing a row
## does. No nodes, so the whole flow is testable without a window. `GameMenu` draws it and
## feeds it pointer clicks.
##
## Choosing a row returns an event for the game to act on (or {} when it was handled here):
##   {"type": "start", "config": GameConfig}   begin that game
##   {"type": "resume"} / "restart" / "main_menu" / "quit"
##   {"type": "settings"}                      a setting changed: save it
##
## Screens: main, play, setup (for the mode in `config`), options, and pause (in a game).

var settings: Settings
var config := GameConfig.new()
var stack: Array[String] = ["main"]
var current_game: GameConfig = null       # the game being played, for the pause screen
var profile: PlayerProfile = PlayerProfile.new()   # what the Stats screen shows
var career: Career = null                 # the saved career, if any
var new_name := Career.NAMES[0]           # the career being set up
var new_build := "Balanced"
var new_length := 10
var new_innings := 3
var can_mound_visit := false              # the pause screen offers these (the scene says when)
var can_leave := false
var stats_key := ""                       # the leaderboard the Stats screen is showing
const VOLUME_ROWS := {"Master": "Master volume", "SFX": "Effects", "Crowd": "Crowd", "Music": "Music", "Voice": "Voices"}
const VOLUME_STEPS := [0.0, 0.25, 0.5, 0.75, 1.0]


func _init(s: Settings = null) -> void:
	settings = s if s != null else Settings.new()
	config.assist = settings.assist


func open_main() -> void:
	stack = ["main"]
	current_game = null


func open_pause(game: GameConfig) -> void:
	current_game = game
	stack = ["pause"]


func screen() -> String:
	return stack[stack.size() - 1]


func can_go_back() -> bool:
	return stack.size() > 1


func title() -> String:
	match screen():
		"main":
			return "VR BASEBALL"
		"play":
			return "Choose a mode"
		"setup":
			return config.mode.to_upper()
		"options":
			return "Options"
		"audio":
			return "Sound"
		"challenges":
			return "Challenges"
		"career":
			return "Career"
		"career_new":
			return "New career"
		"standings":
			return "Standings"
		"career_abandon":
			return "Abandon career?"
		"confirm_leave":
			return "Leave the game?"
		"stats":
			return "Stats"
		"stats_types":
			return "Pitch types"
		"stats_games":
			return "Recent games"
		"pause":
			return "Paused" if current_game == null else "Paused - " + current_game.title()
	return ""


func _cycle(values: Array, current) -> Variant:
	var i := values.find(current)
	return values[(i + 1) % values.size()]


func _row(id: String, label: String, value: String = "", enabled: bool = true, note: String = "") -> Dictionary:
	return {"id": id, "label": label, "value": value, "enabled": enabled, "note": note}


func items() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	match screen():
		"main":
			var last := GameConfig.from_dict(settings.last_game) if not settings.last_game.is_empty() else null
			if last != null:
				rows.append(_row("continue", "Continue", last.title()))
			rows.append(_row("play", "Play"))
			rows.append(_row("options", "Options"))
			rows.append(_row("stats", "Stats & leaderboards"))
			rows.append(_row("quit", "Quit"))
		"play":
			rows.append(_row("mode:Pitching", "Pitching", "you pitch to AI batters"))
			rows.append(_row("mode:Fielding", "Fielding", "you play a position"))
			rows.append(_row("mode:Spectate", "Spectate", "watch an AI game"))
			rows.append(_row("mode:Hitting", "Hitting", "", false, "coming soon"))
			rows.append(_row("career", "Career", "season %d of %d" % [mini(career.matchday + 1, career.league.matchdays), career.league.matchdays] if career != null and not career.is_over() else ("season over" if career != null else "a season in the league"), true, "your own pitcher, one start per matchday"))
			rows.append(_row("challenges", "Challenges", "%d of %d done" % [_challenges_done(), Scenario.ids().size()], true, "short pitching situations to solve"))
			rows.append(_row("back", "Back"))
		"setup":
			if config.mode == "Fielding":
				rows.append(_row("position", "Position", Defense.NAMES.get(config.position, "?")))
			if config.mode != "Spectate":
				rows.append(_row("activity", "Session", _activity_label()))
			if config.activity == "Game" or config.mode == "Spectate":
				rows.append(_row("innings", "Innings", str(config.innings)))
			if config.activity == "Practice":
				rows.append(_row("batter", "Batter", config.batter))
			rows.append(_row("assist", "Assist", config.assist, true, Settings.ASSIST_NOTES.get(config.assist, "")))
			var key := config.leaderboard_key()
			rows.append(_row("start", "Start", "", true, "scored: " + key if key != "" else "not scored"))
			rows.append(_row("back", "Back"))
		"options":
			rows.append(_row("hand", "Throwing hand", settings.hand, true, "applies next game"))
			rows.append(_row("assist_opt", "Assist", settings.assist, true, Settings.ASSIST_NOTES.get(settings.assist, "")))
			rows.append(_row("quality", "Quality", settings.quality, true, "applies next game"))
			rows.append(_row("locomotion", "Movement", settings.locomotion))
			rows.append(_row("haptics", "Haptics", settings.haptics))
			rows.append(_row("colorblind", "Zone colours", "colour-blind" if settings.colorblind else "standard", true, "blue and orange instead of green and red"))
			rows.append(_row("call_text", "Umpire call text", "on" if settings.call_text else "off", true, "calls also shown as words"))
			rows.append(_row("signs", "Catcher signs", "on" if settings.signs else "off", true, "he calls a pitch and a spot; Y shakes him off"))
			rows.append(_row("gestures", "Hand signals", "on" if settings.gestures else "off", true, "hand overhead: intentional walk; hand at your ear: call the bullpen"))
			rows.append(_row("seated", "Seated play", "on" if settings.seated else "off", true, "lifts your height to a standing pitcher's"))
			rows.append(_row("vignette", "Comfort vignette", "on" if settings.vignette else "off"))
			rows.append(_row("snap_turn", "Snap turn", "on" if settings.snap_turn else "off"))
			rows.append(_row("developer", "Developer options", "on" if settings.developer else "off"))
			rows.append(_row("audio", "Sound", "volume, crowd, music"))
			rows.append(_row("back", "Back"))
		"career":
			if career == null:
				rows.append(_row("info", "No career yet", "", false))
				rows.append(_row("career_new", "New career", "", true, "create a pitcher and play a season"))
			else:
				var tot := career.season_totals()
				rows.append(_row("info", "%s  (%s)" % [career.pitcher_name, career.build], "%d-%d, %s IP" % [tot.w, tot.l, PlayerProfile.ip_text(int(tot.outs))], false))
				rows.append(_row("info", "Rank #%d of %d" % [career.league.rank_of(League.USER), League.TEAM_COUNT],
					"CMD %d  STA %d  VEL %d" % [roundi(float(career.ratings.command)), roundi(float(career.ratings.stamina)), roundi(float(career.ratings.velocity))], false))
				if career.is_over():
					rows.append(_row("info", "Season complete", "", false))
					rows.append(_row("career_abandon", "Start a new career", "", true, "this ends the saved one"))
				else:
					rows.append(_row("career_play", "Play next start", "vs %s" % career.opponent_name(), true,
						"%d-inning start, matchday %d of %d" % [career.innings_per_start, career.matchday + 1, career.league.matchdays]))
					rows.append(_row("standings", "Standings"))
					rows.append(_row("career_abandon", "Abandon career"))
			if career != null and career.is_over():
				rows.append(_row("standings", "Final standings"))
			rows.append(_row("back", "Back"))
		"career_new":
			rows.append(_row("new_name", "Pitcher", new_name))
			rows.append(_row("new_build", "Build", new_build, true, _build_note(new_build)))
			rows.append(_row("new_length", "Season", "%d starts" % new_length))
			rows.append(_row("new_innings", "Innings per start", str(new_innings)))
			rows.append(_row("career_create", "Start career"))
			rows.append(_row("back", "Back"))
		"standings":
			if career != null:
				for r in career.league.standings():
					var me := int(r.team) == League.USER
					rows.append(_row("info", "%s%d. %s" % [">" if me else " ", int(r.rank), r.name], "%d-%d  (%+d)" % [int(r.w), int(r.l), int(r.rs) - int(r.ra)], false))
			rows.append(_row("back", "Back"))
		"confirm_leave":
			rows.append(_row("info", "A reliever finishes the game; your line is closed.", "", false))
			rows.append(_row("leave_game", "Yes, take me out"))
			rows.append(_row("back", "No, stay in"))
		"career_abandon":
			rows.append(_row("info", "This deletes your pitcher and season.", "", false))
			rows.append(_row("career_abandon_yes", "Yes, abandon it"))
			rows.append(_row("back", "No, keep it"))
		"challenges":
			for sc in Scenario.catalog():
				var rec := profile.challenge(sc.id)
				rows.append(_row("challenge:" + sc.id, sc.title, Scenario.stars_text(int(rec.best)), true, sc.goal))
			rows.append(_row("back", "Back"))
		"stats":
			for line in profile.lifetime_lines():
				rows.append(_row("info", line, "", false))
			var keys := profile.keys_played()
			if not keys.is_empty():
				if stats_key not in keys:
					stats_key = keys[0]
				rows.append(_row("stats_key", "Leaderboard", key_label(stats_key), keys.size() > 1, "best games by Game Score"))
				var rank := 1
				for entry in profile.top(stats_key, 5):
					var ln: Dictionary = entry.line
					rows.append(_row("info", "#%d   score %d" % [rank, int(entry.score)], _line_text(ln), false))
					rank += 1
			if not profile.type_lines(1).is_empty():
				rows.append(_row("stats_types", "Pitch types", "", true, "what you throw, how often, how well"))
			if not profile.games.is_empty():
				rows.append(_row("stats_games", "Recent games", "", true, "your last box scores"))
			rows.append(_row("back", "Back"))
		"stats_types":
			for t in profile.type_lines(8):
				rows.append(_row("info", "%s  %d" % [t.kind, int(t.n)], "%.0f%% str  %s  %.0f avg  %.0f top" % [
					t.strike_pct, ("%.0f%% whf" % t.whiff_pct) if float(t.whiff_pct) >= 0.0 else "- whf", t.mph_avg, t.mph_max], false))
			rows.append(_row("back", "Back"))
		"stats_games":
			for g in profile.recent(8):
				var gl: Dictionary = g.line
				var result := "W" if bool(gl.get("won", false)) else ("L" if bool(gl.get("lost", false)) else "-")
				var opp := String(gl.get("opp", ""))
				rows.append(_row("info", "%s %s%s" % [result, "%d-%d" % [int(gl.get("score_for", 0)), int(gl.get("score_against", 0))] if gl.has("score_for") else "", (" vs " + opp) if opp != "" else ""],
					_line_text(gl), false))
			rows.append(_row("back", "Back"))
		"audio":
			for bus in VOLUME_ROWS:
				rows.append(_row("vol:" + bus, VOLUME_ROWS[bus], "%d%%" % roundi(float(settings.volumes.get(bus, 1.0)) * 100.0)))
			rows.append(_row("back", "Back"))
		"pause":
			rows.append(_row("resume", "Resume"))
			if current_game != null and current_game.mode == "Pitching" and current_game.activity == "Game":
				rows.append(_row("ibb", "Intentional walk", "", true, "walk the current batter"))
			if can_mound_visit:
				rows.append(_row("mound_visit", "Mound visit", "", true, "the catcher comes out: catch your breath (once a game)"))
			if can_leave:
				rows.append(_row("confirm_leave", "Take me out", "", true, "the bullpen takes over"))
			rows.append(_row("restart", "Restart game"))
			rows.append(_row("options", "Options"))
			rows.append(_row("main_menu", "Main menu"))
	return rows


func _activity_label() -> String:
	match config.activity:
		"Game":
			return "Game"
		"Practice":
			return "Practice"
		_:
			return "Bullpen"


func _activities() -> Array:
	return ["Game", "Practice", "Bullpen"] if config.mode == "Pitching" else ["Game", "Practice"]


## Choose row `index` of the current screen.
func activate(index: int) -> Dictionary:
	var rows := items()
	if index < 0 or index >= rows.size() or not rows[index].enabled:
		return {}
	var id: String = rows[index].id
	if id.begins_with("mode:"):
		config.mode = id.substr(5)
		config.assist = settings.assist
		config = config.normalized()
		stack.append("setup")
		return {}
	match id:
		"career":
			stack.append("career")
			return {}
		"career_new":
			stack.append("career_new")
			return {}
		"standings":
			stack.append("standings")
			return {}
		"career_abandon":
			stack.append("career_abandon")
			return {}
		"new_name":
			new_name = _cycle(Career.NAMES, new_name)
			return {}
		"new_build":
			new_build = _cycle(Career.BUILDS.keys(), new_build)
			return {}
		"new_length":
			new_length = _cycle([6, 10, 14], new_length)
			return {}
		"new_innings":
			new_innings = _cycle(GameConfig.INNINGS, new_innings)
			return {}
		"career_create":
			career = Career.create(new_name, new_build, new_length, new_innings, randi(), settings.hand == "right")
			stack = ["main", "play", "career"]
			return {"type": "career_changed"}
		"career_abandon_yes":
			career = null
			stack = ["main", "play", "career"]
			return {"type": "career_changed"}
		"career_play":
			var cc := GameConfig.new()
			cc.career = true
			cc.assist = settings.assist
			cc.innings = career.innings_per_start
			cc = cc.normalized()
			settings.last_game = cc.to_dict()
			return {"type": "start", "config": cc}
	if id.begins_with("challenge:"):
		var c := GameConfig.new()
		c.scenario = id.substr(10)
		c.assist = settings.assist
		c = c.normalized()
		settings.last_game = c.to_dict()
		return {"type": "start", "config": c}
	if id.begins_with("vol:"):
		var bus := id.substr(4)
		var cur := float(settings.volumes.get(bus, 1.0))
		var next := 0.0
		for st in VOLUME_STEPS:
			if st > cur + 0.01:
				next = st
				break
		settings.volumes[bus] = next                 # past the top it wraps to silent
		return {"type": "settings"}
	match id:
		"audio":
			stack.append("audio")
		"stats":
			stack.append("stats")
		"stats_types":
			stack.append("stats_types")
		"stats_games":
			stack.append("stats_games")
		"challenges":
			stack.append("challenges")
		"stats_key":
			var ks := profile.keys_played()
			if not ks.is_empty():
				stats_key = _cycle(ks, stats_key)
		"continue":
			var c := GameConfig.from_dict(settings.last_game)
			return {"type": "start", "config": c}
		"play":
			stack.append("play")
		"options":
			stack.append("options")
		"back":
			back()
		"quit":
			return {"type": "quit"}
		"resume", "restart", "main_menu":
			return {"type": id}
		"ibb":
			return {"type": "intentional_walk"}
		"mound_visit":
			return {"type": "mound_visit"}
		"confirm_leave":
			stack.append("confirm_leave")
		"leave_game":
			return {"type": "leave_game"}
		"position":
			config.position = 3 if config.position >= 9 else config.position + 1
		"activity":
			config.activity = _cycle(_activities(), config.activity)
		"innings":
			config.innings = _cycle(GameConfig.INNINGS, config.innings)
		"batter":
			config.batter = _cycle(GameConfig.BATTERS, config.batter)
		"assist":
			config.assist = _cycle(Settings.ASSISTS, config.assist)
			settings.assist = config.assist
			return {"type": "settings"}
		"start":
			var c := config.normalized()
			settings.last_game = c.to_dict()
			return {"type": "start", "config": c}
		"hand":
			settings.hand = _cycle(Settings.HANDS, settings.hand)
			return {"type": "settings"}
		"assist_opt":
			settings.assist = _cycle(Settings.ASSISTS, settings.assist)
			config.assist = settings.assist
			return {"type": "settings"}
		"quality":
			settings.quality = _cycle(Settings.QUALITY, settings.quality)
			return {"type": "settings"}
		"locomotion":
			settings.locomotion = _cycle(Settings.LOCOMOTION, settings.locomotion)
			return {"type": "settings"}
		"haptics":
			settings.haptics = _cycle(Settings.HAPTICS, settings.haptics)
			return {"type": "settings"}
		"colorblind":
			settings.colorblind = not settings.colorblind
			return {"type": "settings"}
		"call_text":
			settings.call_text = not settings.call_text
			return {"type": "settings"}
		"signs":
			settings.signs = not settings.signs
			return {"type": "settings"}
		"gestures":
			settings.gestures = not settings.gestures
			return {"type": "settings"}
		"seated":
			settings.seated = not settings.seated
			return {"type": "settings"}
		"vignette":
			settings.vignette = not settings.vignette
			return {"type": "settings"}
		"snap_turn":
			settings.snap_turn = not settings.snap_turn
			return {"type": "settings"}
		"developer":
			settings.developer = not settings.developer
			return {"type": "settings"}
	return {}


func back() -> Dictionary:
	if stack.size() > 1:
		stack.pop_back()
	return {}


## One game line as words: a pitcher's (IP, K, R) or a fielder's (caught of chances).
static func _line_text(ln: Dictionary) -> String:
	if String(ln.get("kind", "pitching")) == "fielding":
		return "%d of %d caught, %d err" % [int(ln.get("caught", 0)), int(ln.get("chances", 0)), int(ln.get("errors", 0))]
	return "%s IP, %d K, %d R" % [PlayerProfile.ip_text(int(ln.get("outs", 0))), int(ln.get("k", 0)), int(ln.get("r", 0))]


func _build_note(b: String) -> String:
	match b:
		"Power":
			return "a harder arm, rougher aim"
		"Control":
			return "pin-point aim, a lighter arm"
		"Workhorse":
			return "goes deep into games"
	return "no weaknesses, no strengths"


func _challenges_done() -> int:
	var n := 0
	for sid in Scenario.ids():
		if int(profile.challenge(sid).best) > 0:
			n += 1
	return n


## "Pitching/9inn/Standard" as words.
static func key_label(key: String) -> String:
	var parts := key.split("/")
	if parts.size() != 3:
		return key
	return "%s, %s, %s" % [parts[0], parts[1].replace("inn", " inn"), parts[2]]
