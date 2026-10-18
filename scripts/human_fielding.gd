class_name HumanFielding
extends RefCounted
## The rules for a human playing a fielding position: how close the glove has to be, and what
## a throw means. Pure functions so they can be tested without a headset.
##
## You catch the ball with a glove (your off-hand controller): if the ball comes within
## CATCH_RADIUS of the glove while it is in play, you have it. A ball in the air is an out.
## A grounder you then throw: the base your throw is aimed at is whichever one the throw is
## closest to heading for (inside THROW_CONE_DEG), the ball flies there at your throwing
## speed (capped by the fielder's arm), and the base runners' own timelines decide whether
## it beats them. A throw outside the cone sails into the stands: a throwing error.

const CATCH_RADIUS := 0.34          # m: a mitt plus a little help
const THROW_CONE_DEG := 26.0        # a throw this close to a base is a throw to that base
const MIN_THROW_SPEED := 6.0        # m/s: a lob
const HOLD_LIMIT := 5.0             # s: hold the ball this long and the play is dead (single)
const CATCH_PAUSE := 0.15           # s: the receiving fielder squeezing it


static func base_position(base: int) -> Vector3:
	match base:
		1:
			return Defense.FIRST
		2:
			return Defense.SECOND
		3:
			return Defense.THIRD
		_:
			return Defense.HOME


## Which base a throw is aimed at. dir is the throw's direction (only its horizontal part counts).
## Returns {"base": 1..4, "err": degrees off the line}, or base 0 when it is aimed at none of them.
static func pick_base(from: Vector3, dir: Vector3, cone: float = THROW_CONE_DEG) -> Dictionary:
	var d := Vector2(dir.x, dir.z)
	if d.length() < 0.05:
		return {"base": 0, "err": 180.0}
	d = d.normalized()
	var best := 0
	var best_err := 180.0
	for b in [1, 2, 3, 4]:
		var bp := base_position(b)
		var to := Vector2(bp.x - from.x, bp.z - from.z)
		if to.length() < 1.0:
			continue
		var err := rad_to_deg(absf(d.angle_to(to.normalized())))
		if err < best_err:
			best_err = err
			best = b
	if best_err > cone:
		return {"base": 0, "err": best_err}
	return {"base": best, "err": best_err}


## How fast the ball leaves the hand: hand speed scaled by the throw gain, within what an arm can do.
static func throw_speed(hand_speed: float, gain: float, arm: float) -> float:
	return clampf(hand_speed * gain, MIN_THROW_SPEED, arm * 1.2)


## Seconds from release until the receiving fielder has it. A throw that is a little off the
## line costs time (he has to reach for it).
static func arrival_delay(from: Vector3, base: int, speed: float, err_deg: float) -> float:
	var bp := base_position(base)
	var d := Vector2(bp.x - from.x, bp.z - from.z).length()
	return d / maxf(speed, 1.0) + CATCH_PAUSE + err_deg * 0.012


## The fielder who takes a throw at a base (for the scorebook).
static func receiver(base: int, thrower: int) -> int:
	match base:
		1:
			return 3
		2:
			return 4 if thrower == 6 else 6
		3:
			return 5
		_:
			return 2


static func in_glove(glove: Vector3, ball: Vector3, radius: float = CATCH_RADIUS) -> bool:
	return glove.distance_to(ball) <= radius
