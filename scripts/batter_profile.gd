class_name BatterProfile
extends RefCounted
## A batter's skills. Every rating is 0..1; BatterAI turns them into perception noise, a
## swing decision, timing error, bat-plane error, and bat speed. Ratings read as:
##   eye         - sees where the pitch will cross; lays off balls, takes borderline pitches
##   contact     - puts the bat on the ball: small vertical / along-the-bat aiming error
##   power       - bat speed (and so exit velocity)
##   timing      - how consistent the swing time is
##   recognition - adjusts to changes of speed and reads movement: a changeup or a knuckler
##                 fools a low-recognition batter
##   aggression  - swings at hittable pitches more often (and chases a bit more)

var name := "Average"
var eye := 0.5
var contact := 0.5
var power := 0.5
var timing := 0.5
var recognition := 0.5
var aggression := 0.5
## Typical upward bat path, degrees. Hitters differ: grounders vs fly-ball swings.
var attack_angle := 10.0


static func make(n: String, e: float, c: float, p: float, t: float, r: float, a: float, attack: float = 10.0) -> BatterProfile:
	var b := BatterProfile.new()
	b.name = n
	b.eye = e
	b.contact = c
	b.power = p
	b.timing = t
	b.recognition = r
	b.aggression = a
	b.attack_angle = attack
	return b


## A profile read from a player's hitting ratings (0-100 -> 0..1).
static func from_player(p: Player) -> BatterProfile:
	return make(p.name, p.eye / 100.0, p.contact / 100.0, p.power / 100.0, p.timing / 100.0,
		p.recognition / 100.0, p.aggression / 100.0, p.loft)


## The six archetypes, weakest to strongest (the practice squad's players as profiles).
static func all() -> Array[BatterProfile]:
	var out: Array[BatterProfile] = []
	for p in Team.archetype_roster().lineup:
		out.append(from_player(p))
	return out


static func by_name(n: String) -> BatterProfile:
	for b in all():
		if b.name == n:
			return b
	return all()[1]
