class_name GameConfig
extends RefCounted
## Everything that defines one game, chosen in the menu: which mode, what kind of session,
## where you play, how long, and at which assist level. The game consumes this and the
## leaderboards key off it, so two games with the same key are comparable.
##
##   mode      Pitching | Spectate | Fielding      (Hitting is reserved)
##   activity  Game      a nine-man lineup, count, outs and innings
##             Practice  one batter you choose, the count still counts
##             Bullpen   free throws: no lineup, no score
##   position  your fielding position (3..9) in Fielding mode
##   innings   1, 3 or 9 in a Game
##   batter    the practice batter's profile name
##   assist    Casual | Standard | Pro  (see Settings)

const MODES := ["Pitching", "Spectate", "Fielding"]
const ACTIVITIES := ["Game", "Practice", "Bullpen"]
const INNINGS := [1, 3, 9]
const BATTERS := ["Little Leaguer", "Rookie", "Contact Hitter", "Slugger", "All-Star", "MVP"]

var mode := "Pitching"
var activity := "Game"
var position := 6
var innings := 9
var batter := "Contact Hitter"
var assist := "Standard"


static func from_settings(s: Settings) -> GameConfig:
	var c := GameConfig.new()
	c.assist = s.assist
	return c


## Fix anything out of range or meaningless for the mode, rather than reject it.
func normalized() -> GameConfig:
	var c := GameConfig.new()
	c.mode = mode if mode in MODES else "Pitching"
	c.activity = activity if activity in ACTIVITIES else "Game"
	c.position = clampi(position, 3, 9)
	c.innings = innings if innings in INNINGS else 9
	c.batter = batter if batter in BATTERS else "Contact Hitter"
	c.assist = assist if assist in Settings.ASSISTS else "Standard"
	# Spectating is always a full game of watching; there is nothing to practise.
	if c.mode == "Spectate":
		c.activity = "Game"
	# A bullpen has no innings and nobody to field.
	if c.activity == "Bullpen" and c.mode != "Pitching":
		c.activity = "Game"
	return c


func is_scored() -> bool:
	return activity == "Game" and mode != "Spectate"


## What a leaderboard is keyed on. Only scored games have one.
func leaderboard_key() -> String:
	if not is_scored():
		return ""
	var where := "%s/%dinn" % [mode, innings]
	if mode == "Fielding":
		where = "Fielding%d/%dinn" % [position, innings]
	return "%s/%s" % [where, assist]


func title() -> String:
	var who := mode
	if mode == "Fielding":
		who = "Fielding (%s)" % Defense.NAMES.get(position, "?")
	match activity:
		"Game":
			return "%s - %d-inning game" % [who, innings] if mode != "Spectate" else "Spectate - watch a game"
		"Practice":
			return "%s - practice vs %s" % [who, batter]
		_:
			return "%s - bullpen" % who


func to_dict() -> Dictionary:
	return {"mode": mode, "activity": activity, "position": position, "innings": innings,
		"batter": batter, "assist": assist}


static func from_dict(d: Dictionary) -> GameConfig:
	var c := GameConfig.new()
	c.mode = str(d.get("mode", c.mode))
	c.activity = str(d.get("activity", c.activity))
	c.position = int(d.get("position", c.position))
	c.innings = int(d.get("innings", c.innings))
	c.batter = str(d.get("batter", c.batter))
	c.assist = str(d.get("assist", c.assist))
	return c.normalized()
