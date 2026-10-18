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
			rows.append(_row("stats", "Stats & leaderboards", "", false, "coming soon"))
			rows.append(_row("quit", "Quit"))
		"play":
			rows.append(_row("mode:Pitching", "Pitching", "you pitch to AI batters"))
			rows.append(_row("mode:Fielding", "Fielding", "you play a position"))
			rows.append(_row("mode:Spectate", "Spectate", "watch an AI game"))
			rows.append(_row("mode:Hitting", "Hitting", "", false, "coming soon"))
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
			rows.append(_row("vignette", "Comfort vignette", "on" if settings.vignette else "off"))
			rows.append(_row("snap_turn", "Snap turn", "on" if settings.snap_turn else "off"))
			rows.append(_row("developer", "Developer options", "on" if settings.developer else "off"))
			rows.append(_row("audio", "Sound", "volume, crowd, music"))
			rows.append(_row("back", "Back"))
		"audio":
			for bus in VOLUME_ROWS:
				rows.append(_row("vol:" + bus, VOLUME_ROWS[bus], "%d%%" % roundi(float(settings.volumes.get(bus, 1.0)) * 100.0)))
			rows.append(_row("back", "Back"))
		"pause":
			rows.append(_row("resume", "Resume"))
			if current_game != null and current_game.mode == "Pitching" and current_game.activity == "Game":
				rows.append(_row("ibb", "Intentional walk", "", true, "walk the current batter"))
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
