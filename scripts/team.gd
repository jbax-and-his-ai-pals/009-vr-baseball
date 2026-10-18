class_name Team
extends RefCounted
## A team: colors, a batting order, and who plays where. Fictional by design.

const FIRST_NAMES := ["Marcus", "Dante", "Eli", "Rafael", "Jonah", "Tobias", "Cal", "Mateo", "Idris", "Wes",
	"Nolan", "Santiago", "Kai", "Beau", "Omar", "Felix", "Rowan", "Hugo", "Silas", "Theo"]
const LAST_NAMES := ["Reyes", "Okafor", "Lindqvist", "Brandt", "Mendez", "Calloway", "Takeda", "Whitfield", "Duarte",
	"Novak", "Ashby", "Pruitt", "Castellan", "Boyle", "Haverford", "Quill", "Alvarado", "Sterling", "Voss", "Kimura"]

var name := "Team"
var jersey := Color(0.12, 0.17, 0.50)
var pants := Color(0.62, 0.64, 0.70)
var cap := Color(0.12, 0.17, 0.50)
var lineup: Array[Player] = []                 # batting order
var alignment := {}                            # position number -> Player


func player_at(position: int) -> Player:
	return alignment.get(position)


## Rating offsets (relative to an average player) that make a position look like itself.
const POSITION_NORMS := {
	1: {"velocity": 8, "command": 6, "movement": 4, "speed": -8, "contact": -12, "power": -12, "eye": -6},
	2: {"arm": 12, "hands": 10, "fielding_range": -4, "speed": -18, "power": 2},
	3: {"hands": 8, "power": 10, "fielding_range": -8, "arm": -6, "speed": -8},
	4: {"fielding_range": 8, "hands": 8, "speed": 4, "contact": 5, "power": -6, "arm": -2},
	5: {"arm": 12, "hands": 4, "power": 4, "speed": -2},
	6: {"fielding_range": 14, "arm": 8, "hands": 10, "speed": 6, "power": -6},
	7: {"speed": 5, "fielding_range": 4, "arm": -4, "power": 6},
	8: {"speed": 12, "fielding_range": 14, "arm": 2, "contact": 3},
	9: {"arm": 10, "power": 6, "speed": 2, "fielding_range": 4},
}


## A full roster with each position's tendencies. `quality` shifts everyone (50 = average).
static func generate(team_name: String, quality: float = 50.0, seed_value: int = 1, jitter: float = 9.0) -> Team:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var t := Team.new()
	t.name = team_name
	var order := [8, 6, 9, 3, 7, 5, 4, 2, 1]        # a plausible batting order by position
	var used := {}
	for pos in range(1, 10):
		var p := Player.new()
		var fn: String = FIRST_NAMES[rng.randi() % FIRST_NAMES.size()]
		var ln: String = LAST_NAMES[rng.randi() % LAST_NAMES.size()]
		p.name = "%s %s" % [fn, ln]
		p.number = 1 + rng.randi() % 98
		while used.has(p.number):
			p.number = 1 + rng.randi() % 98
		used[p.number] = true
		p.position = pos
		p.bats_right = rng.randf() < 0.7
		var norm: Dictionary = POSITION_NORMS[pos]
		for key in ["contact", "power", "eye", "timing", "recognition", "speed", "fielding_range", "hands", "arm", "velocity", "command", "movement", "stamina"]:
			var v := quality + (rng.randfn(0.0, jitter) if jitter > 0.0 else 0.0) + float(norm.get(key, 0))
			p.set(key, clampf(v, 15.0, 98.0))
		p.aggression = clampf(50.0 + rng.randfn(0.0, 14.0), 20.0, 85.0)
		p.loft = clampf(10.0 + (p.power - 50.0) * 0.12 + rng.randfn(0.0, 2.0), 4.0, 18.0)
		t.alignment[pos] = p
	for pos in order:
		t.lineup.append(t.alignment[pos])
	return t


## A relief pitcher: a bit fresher and a different arm than the starter. `quality` shifts him.
static func relief_pitcher(quality: float, seed_value: int) -> Player:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var p := Player.new()
	p.name = "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]]
	p.number = 60 + rng.randi() % 39
	p.position = 1
	var norm: Dictionary = POSITION_NORMS[1]
	for key in ["velocity", "command", "movement", "stamina", "contact", "power", "eye", "speed"]:
		p.set(key, clampf(quality + rng.randfn(0.0, 8.0) + float(norm.get(key, 0)), 15.0, 98.0))
	var rep: Array[String] = ["Fastball", "Slider" if rng.randf() < 0.5 else "Curveball", "Changeup"]
	p.repertoire = rep
	return p


## The six batter archetypes as a practice squad: "who is at the plate" for pitching practice.
static func archetype_roster() -> Team:
	var t := Team.new()
	t.name = "Practice Squad"
	t.jersey = Color(0.84, 0.16, 0.18)
	t.pants = Color(0.95, 0.95, 0.97)
	t.cap = Color(0.12, 0.17, 0.50)
	# name, eye, contact, power, timing, recognition, aggression, loft, speed
	var spec := [
		["Little Leaguer", 15, 15, 15, 20, 25, 65, 6.0, 40],
		["Rookie", 35, 35, 35, 40, 40, 55, 8.0, 50],
		["Contact Hitter", 70, 85, 35, 80, 70, 45, 7.0, 60],
		["Slugger", 45, 50, 95, 55, 50, 70, 14.0, 40],
		["All-Star", 80, 80, 75, 80, 75, 50, 11.0, 62],
		["MVP", 95, 95, 90, 95, 90, 50, 12.0, 70],
	]
	var n := 10
	for s in spec:
		var p := Player.new()
		p.name = s[0]
		p.number = n
		n += 11
		p.eye = s[1]
		p.contact = s[2]
		p.power = s[3]
		p.timing = s[4]
		p.recognition = s[5]
		p.aggression = s[6]
		p.loft = s[7]
		p.speed = s[8]
		t.lineup.append(p)
	return t
