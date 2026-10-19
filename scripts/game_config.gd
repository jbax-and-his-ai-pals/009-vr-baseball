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
##   position  your fielding position (1..9; 1 is the pitcher, 2 the catcher) in Fielding mode
##   innings   1, 3 or 9 in a Game
##   batter    the practice batter's profile name
##   assist    Casual | Standard | Pro  (see Settings)

const MODES := ["Pitching", "Spectate", "Fielding", "Hitting"]
const ACTIVITIES := ["Game", "Practice", "Bullpen", "Drill", "Derby"]
const INNINGS := [1, 3, 9]
const BATTERS := ["Little Leaguer", "Rookie", "Contact Hitter", "Slugger", "All-Star", "MVP"]

var mode := "Pitching"
var activity := "Game"
var position := 6
var innings := 9
var batter := "Contact Hitter"
var assist := "Standard"
var scenario := ""             # a challenge id (see Scenario); "" for an ordinary game
var tutorial := false          # the pitching lesson (a bullpen with prompts)
var daily := 0                 # a daily game: the day number (days since 1970), 0 for an ordinary game
var park := "harbor"           # which ballpark (see Park)
var two_way := false           # pitch the top halves, bat the bottom halves yourself
var career := false            # the next start of your saved career (teams, pitcher and innings come from it)


static func from_settings(s: Settings) -> GameConfig:
	var c := GameConfig.new()
	c.assist = s.assist
	return c


## Fix anything out of range or meaningless for the mode, rather than reject it.
func normalized() -> GameConfig:
	var c := GameConfig.new()
	c.mode = mode if mode in MODES else "Pitching"
	c.activity = activity if activity in ACTIVITIES else "Game"
	c.position = clampi(position, 1, 9)
	c.innings = innings if innings in INNINGS else 9
	c.batter = batter if batter in BATTERS else "Contact Hitter"
	c.assist = assist if assist in Settings.ASSISTS else "Standard"
	if tutorial and scenario == "" and not career:
		c.tutorial = true
		c.mode = "Pitching"
		c.activity = "Bullpen"
		c.assist = "Casual"
	if career and scenario == "":
		c.career = true
		c.mode = "Pitching"
		c.activity = "Game"
	# A challenge is always you pitching a short game: it has its own results, not a leaderboard.
	if scenario != "" and scenario in Scenario.ids():
		c.scenario = scenario
		c.mode = "Pitching"
		c.activity = "Game"
		c.innings = int(Scenario.by_id(scenario).setup.get("innings", 9)) if int(Scenario.by_id(scenario).setup.get("innings", 9)) in INNINGS else 9
	c.park = park if park in Park.ids() else Park.DEFAULT_ID
	if daily > 0 and scenario == "" and not career and not tutorial:
		# The daily game: everybody gets the same visitors and the same dice for the day, three innings.
		c.daily = daily
		c.mode = "Pitching"
		c.activity = "Game"
		c.innings = 3
		c.park = Park.DEFAULT_ID
	c.two_way = two_way and c.mode == "Pitching" and c.activity == "Game" and c.scenario == "" and not c.career and not c.tutorial and c.daily == 0
	# Spectating is always a full game of watching; there is nothing to practise.
	if c.mode == "Spectate":
		c.activity = "Game"
	# A drill is ten balls hit to your position: only for Fielding.
	if c.activity == "Drill" and c.mode != "Fielding":
		c.activity = "Game"
	# A derby is ten outs of easy pitches to swing at: only for Hitting.
	if c.activity == "Derby" and c.mode != "Hitting":
		c.activity = "Game"
	# A bullpen has no innings and nobody to field.
	if c.activity == "Bullpen" and c.mode != "Pitching":
		c.activity = "Game"
	return c


func is_scored() -> bool:
	return activity == "Game" and mode != "Spectate" and scenario == "" and not career


## What a leaderboard is keyed on. Only scored games have one.
func leaderboard_key() -> String:
	if not is_scored():
		return ""
	if daily > 0:
		return "Daily/%d/%s" % [daily, assist]
	var where := "%s/%dinn%s%s" % [mode, innings, "+bat" if two_way else "", "" if park == Park.DEFAULT_ID else "@" + park]
	if mode == "Fielding":
		where = "Fielding%d/%dinn" % [position, innings]
	return "%s/%s" % [where, assist]


## Days since 1970-01-01 (UTC): the day a daily game belongs to.
static var today_override := 0


static func today() -> int:
	return today_override if today_override > 0 else int(Time.get_unix_time_from_system() / 86400.0)


## The seed everyone shares for a daily game.
static func daily_seed(day: int) -> int:
	return day * 7919 + 13


func title() -> String:
	if daily > 0:
		return "Daily game - %s" % Time.get_date_string_from_unix_time(daily * 86400)
	if scenario != "":
		return "Challenge - %s" % Scenario.by_id(scenario).title
	if tutorial:
		return "Learn to pitch"
	if career:
		return "Career - season start"
	var who := mode
	if mode == "Fielding":
		who = "Fielding (%s)" % Defense.NAMES.get(position, "?")
	match activity:
		"Game":
			if two_way:
				return "Two-way - %d-inning game" % innings
			return "%s - %d-inning game" % [who, innings] if mode != "Spectate" else "Spectate - watch a game"
		"Practice":
			return "%s - practice vs %s" % [who, batter]
		"Drill":
			return "%s - drill" % who
		"Derby":
			return "Home run derby"
		_:
			return "%s - bullpen" % who


func to_dict() -> Dictionary:
	return {"mode": mode, "activity": activity, "position": position, "innings": innings,
		"batter": batter, "assist": assist, "scenario": scenario, "career": career, "tutorial": tutorial, "two_way": two_way, "park": park, "daily": daily}


static func from_dict(d: Dictionary) -> GameConfig:
	var c := GameConfig.new()
	c.mode = str(d.get("mode", c.mode))
	c.activity = str(d.get("activity", c.activity))
	c.position = int(d.get("position", c.position))
	c.innings = int(d.get("innings", c.innings))
	c.batter = str(d.get("batter", c.batter))
	c.assist = str(d.get("assist", c.assist))
	c.scenario = str(d.get("scenario", ""))
	c.career = bool(d.get("career", false))
	c.tutorial = bool(d.get("tutorial", false))
	c.two_way = bool(d.get("two_way", false))
	c.park = str(d.get("park", Park.DEFAULT_ID))
	c.daily = int(d.get("daily", 0))
	return c.normalized()
