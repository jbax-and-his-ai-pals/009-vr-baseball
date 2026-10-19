class_name Backup
extends RefCounted
## Backing up a base: when a throw goes to a bag, one more fielder goes behind it in case it gets by.
## Pure: which fielder, and where he stands. The play director sends the AI ones there.
##
##   first base   the right fielder, behind the bag in foul ground
##   second base  the center fielder behind the bag (the left fielder if the throw comes from center)
##   third base   the left fielder, along the foul line (the right fielder if it comes from left)
##   home         the pitcher, a few steps behind the plate (the third baseman if he is the thrower)

const DEPTH := 9.0          # m behind the bag along the line of the throw
const MIN_SECONDS := 0.5    # no one is sent for a throw that arrives sooner than this


## {"fielder": position number, "spot": where he stands}. `from` is where the throw starts.
static func assignment(base: int, thrower: int, from: Vector3) -> Dictionary:
	var bag: Vector3 = Baserunning.BASE_POS[clampi(base, 1, 4)]
	var who := 0
	match base:
		1:
			who = 9
		2:
			who = 8 if thrower != 8 else (7 if from.x >= 0.0 else 9)
		3:
			who = 7 if thrower != 7 else 9
		_:
			who = 1 if thrower != 1 else 5
	var dir := Vector3(bag.x - from.x, 0.0, bag.z - from.z)
	if dir.length() < 0.5:
		dir = Vector3(0.0, 0.0, -1.0)
	var spot := bag + dir.normalized() * (DEPTH * (0.8 if base == 4 else 1.0))
	return {"fielder": who, "spot": Vector3(spot.x, 0.0, spot.z)}


## Where he gets to in `seconds`, starting from `home` at `speed` (m/s): he runs toward the spot as far as he can.
static func reach(home: Vector3, spot: Vector3, speed: float, seconds: float) -> Vector3:
	var d := Vector2(spot.x - home.x, spot.z - home.z)
	var can := speed * maxf(seconds, 0.0)
	if d.length() <= can or d.length() < 0.01:
		return Vector3(spot.x, 0.0, spot.z)
	var step := d.normalized() * can
	return Vector3(home.x + step.x, 0.0, home.z + step.y)
