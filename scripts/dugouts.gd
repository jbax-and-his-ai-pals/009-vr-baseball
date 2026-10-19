class_name Dugouts
extends Node
## The people at the edges of the field: teammates at the rail of each dugout and a coach in each
## coach's box. They stand there and react to the game: the batting side cheers a run or a homer,
## groans a strikeout, the fielding side pumps a fist at one. Nothing here touches the rules.
##
##   dugouts.setup(parent, home_team, away_team, style_fn)
##   dugouts.react_event(ev, batting_side)     "home" or "away": who is at bat
##   dugouts.cheer("away", "celebrate")        a side does one clip, a beat apart from each other

const HOME_X := 1.0                 # the home dugout is on the third-base side (+x), the visitors' on the first-base side
const RAIL_Z := 6.5                 # just in front of the dugout's face (the pit box ends at z = 5.6)
const MATES := 4                    # teammates at each rail
const COACH_1B := Vector3(-22.5, 0.0, 14.0)
const COACH_3B := Vector3(22.5, 0.0, 14.0)

## Each reaction: the clip, how long it plays, how many of the group do it.
const REACTIONS := {
	"celebrate": {"clip": "celebrate", "seconds": 1.2},
	"fist": {"clip": "fist_pump", "seconds": 0.9},
	"groan": {"clip": "react", "seconds": 1.0},
}

var mates := {"home": [], "away": []}          # side -> Array[Doll]
var coaches: Array[Doll] = []
var _later: Array = []                         # [seconds left, Doll, clip, duration]
var _rng := RandomNumberGenerator.new()


func setup(parent: Node3D, home: Team, away: Team, style_fn: Callable) -> void:
	_rng.seed = 11
	parent.add_child(self)
	for side in ["home", "away"]:
		var team: Team = home if side == "home" else away
		var sx := HOME_X if side == "home" else -HOME_X
		for i in MATES:
			var at := Vector3(sx * (10.0 + 2.2 * i), 0.0, RAIL_Z)
			var d := Doll.create(parent, at, team.jersey, team.pants, team.cap, false, int(style_fn.call(300 + i + (0 if side == "home" else 10))))
			d.locomotion = false
			d.rotation.y = -sx * 0.35
			mates[side].append(d)
	for spot in [COACH_1B, COACH_3B]:
		var c := Doll.create(parent, spot, away.jersey, away.pants, away.cap, false, int(style_fn.call(320 if spot.x < 0.0 else 321)))
		c.locomotion = false
		c.rotation.y = PI + (0.5 if spot.x < 0.0 else -0.5)        # watching the plate
		coaches.append(c)


## A side does a reaction; each person starts a moment after the last so it is not a chorus line.
func cheer(side: String, kind: String, include_coaches: bool = false) -> void:
	var r: Dictionary = REACTIONS.get(kind, REACTIONS.celebrate)
	var t := 0.0
	for d in mates.get(side, []):
		_later.append([t + _rng.randf_range(0.0, 0.25), d, String(r.clip), float(r.seconds) * _rng.randf_range(0.9, 1.2)])
		t += 0.12
	if include_coaches:
		for c in coaches:
			_later.append([_rng.randf_range(0.0, 0.3), c, String(r.clip), float(r.seconds)])


## What the people at the edges do about an event of the game. `batting_side` is who is at bat.
func react_event(ev: Dictionary, batting_side: String) -> void:
	var fielding := "home" if batting_side == "away" else "away"
	match String(ev.get("result", "")):
		"home_run":
			cheer(batting_side, "celebrate", true)
			cheer(fielding, "groan")
			return
		"triple", "double":
			cheer(batting_side, "fist")
		"strikeout":
			cheer(fielding, "fist")
			cheer(batting_side, "groan")
		"error":
			cheer(fielding, "groan")
	if int(ev.get("runs", 0)) > 0 and String(ev.get("result", "")) != "home_run":
		cheer(batting_side, "celebrate", true)


func pending() -> int:
	return _later.size()


func _process(delta: float) -> void:
	for i in range(_later.size() - 1, -1, -1):
		var e: Array = _later[i]
		e[0] = float(e[0]) - delta
		if float(e[0]) <= 0.0:
			var d: Doll = e[1]
			if is_instance_valid(d):
				d.play(String(e[2]), float(e[3]))
			_later.remove_at(i)
