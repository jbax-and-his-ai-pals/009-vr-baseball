class_name GameMode
extends RefCounted
## Who controls what. Each role is held by a human or by the AI, so a game mode is just a
## different assignment, not different code:
##
##   PITCHING   you pitch; AI batters, fielders and runners         (playable)
##   SPECTATE   AI pitcher, batters and fielders; you watch         (playable)
##   FIELDING   you play a fielding position; AI pitcher and batter (playable)
##   HITTING    you bat against an AI pitcher                       (reserved)
##
## `supported` is false for modes whose human-control side is not built yet, so the game never
## pretends to offer them. AI behaviour for every role already exists (BatterAI, Defense,
## AIPitcher), which is what makes the remaining modes additions rather than rewrites.

var name := "Pitching"
var human_pitcher := true
var human_batter := false
var human_fielders: Array[int] = []        # position numbers (1-9) a human plays
var supported := true
var summary := ""


static func pitching() -> GameMode:
	var m := GameMode.new()
	m.name = "Pitching"
	m.summary = "You pitch. AI batters, fielders and runners."
	return m


static func spectate() -> GameMode:
	var m := GameMode.new()
	m.name = "Spectate"
	m.human_pitcher = false
	m.summary = "All AI. Watch the game."
	return m


## The human plays one fielding position; the AI pitches and bats.
static func fielding(position: int = 6) -> GameMode:
	var m := GameMode.new()
	m.name = "Fielding (%s)" % Defense.NAMES.get(position, "?")
	m.human_pitcher = false
	m.human_fielders = [position]
	m.summary = "You field one position with a glove and throw to bases. AI pitcher, batters and teammates."
	return m


## The human bats against an AI pitcher: the controller is the bat, for every batter on his team.
static func hitting() -> GameMode:
	var m := GameMode.new()
	m.name = "Hitting"
	m.human_pitcher = false
	m.human_batter = true
	m.summary = "You bat against an AI pitcher: swing the controller. AI fielders and runners."
	return m


static func by_name(n: String) -> GameMode:
	match n.to_lower():
		"spectate":
			return spectate()
		"fielding":
			return fielding()
		"hitting":
			return hitting()
		_:
			return pitching()


func is_ai_fielder(position: int) -> bool:
	return position not in human_fielders


## True when nothing in the game needs a human at the controls.
func is_all_ai() -> bool:
	return not human_pitcher and not human_batter and human_fielders.is_empty()
