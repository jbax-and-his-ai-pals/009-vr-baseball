class_name Framing
extends RefCounted
## Catching a pitch as the catcher: where your glove is as the ball arrives decides two things.
##
##   - the umpire's call on a borderline pitch: a glove that is on the ball, still, and giving the
##     umpire a good look "frames" it (a pitch a little off the edge becomes a strike); a stab that
##     yanks the glove around loses strikes. The umpire is human, so it is a probability, not a switch.
##   - whether a pitch in the dirt or wide gets by you (a wild pitch / passed ball) or is blocked.
##
## Pure: give it the glove's samples and where the pitch crossed the plate.
##
##   var q := Framing.assess(samples, plate_pos)         # {"miss": m, "speed": m/s, "quality": 0..1, "cover": 0..1}
##   var c := Framing.call_strike(plate_pos, q.quality, roll)   # {"strike": bool, "p": float, "framed": bool, "lost": bool}
##   var p := Framing.gets_away(base_p, q.cover)

const HALF_W := PitchPhysics.ZONE_HALF_W + PitchPhysics.BALL_RADIUS
const BOTTOM := PitchPhysics.ZONE_BOTTOM - PitchPhysics.BALL_RADIUS
const TOP := PitchPhysics.ZONE_TOP + PitchPhysics.BALL_RADIUS

const SOFT := 0.012           # m: how fuzzy the umpire's edge is (about half an inch)
const MAX_BONUS := 0.065      # m: a perfect frame is worth about this much zone (2.5 in); a bad one costs the same
const CLEAN_MISS := 0.10      # m: a glove this close to the ball is on it
const MAX_MISS := 0.45        # m: farther than this the glove is nowhere near
const STILL_SPEED := 0.6      # m/s: a glove moving this slowly is quiet
const WILD_SPEED := 3.0       # m/s: a glove this fast is stabbing
const COVER_FLOOR := 0.1      # a glove right on a ball in the dirt lets only this fraction of wild pitches through
const NEUTRAL := 0.6          # the quality of a receiver who neither helps nor hurts
const WINDOW := 0.25          # s of glove history that is looked at


## How far inside (-) or outside (+) the umpire's edge a pitch crossed, in meters.
static func edge_distance(plate_pos: Vector3) -> float:
	var dx := absf(plate_pos.x) - HALF_W
	var dy := maxf(BOTTOM - plate_pos.y, plate_pos.y - TOP)
	return maxf(dx, dy)


## samples: [[time, glove position], ...] oldest first, ending when the ball arrived.
## The plate position is where the ball crossed; only the glove's x and y are compared (it is behind the plate).
static func assess(samples: Array, plate_pos: Vector3) -> Dictionary:
	if samples.is_empty():
		return {"miss": MAX_MISS, "speed": WILD_SPEED, "quality": 0.0, "cover": 0.0}
	var last: Array = samples[samples.size() - 1]
	var g: Vector3 = last[1]
	var miss := Vector2(g.x - plate_pos.x, g.y - plate_pos.y).length()
	var speed := 0.0
	var i := samples.size() - 1
	while i > 0 and float(last[0]) - float(samples[i - 1][0]) <= WINDOW:
		i -= 1
	if i < samples.size() - 1:
		var first: Array = samples[i]
		var dt := maxf(float(last[0]) - float(first[0]), 0.016)
		var d: Vector3 = (g - (first[1] as Vector3))
		speed = Vector2(d.x, d.y).length() / dt
	var near := 1.0 - clampf((miss - CLEAN_MISS) / (MAX_MISS - CLEAN_MISS), 0.0, 1.0)
	var quiet := 1.0 - clampf((speed - STILL_SPEED) / (WILD_SPEED - STILL_SPEED), 0.0, 1.0)
	return {"miss": miss, "speed": speed, "quality": near * (0.35 + 0.65 * quiet), "cover": near}


## The umpire's call. quality NEUTRAL is a receiver who neither helps nor hurts (the strike zone as drawn); roll is 0..1.
static func call_strike(plate_pos: Vector3, quality: float, roll: float) -> Dictionary:
	var d := edge_distance(plate_pos)
	var truth := d <= 0.0
	if plate_pos.y < 0.12:
		return {"strike": false, "p": 0.0, "framed": false, "lost": truth}      # in the dirt is never a strike
	var bonus := clampf((clampf(quality, 0.0, 1.0) - NEUTRAL) * (MAX_BONUS / (1.0 - NEUTRAL)), -MAX_BONUS, MAX_BONUS)
	var p := 1.0 / (1.0 + exp((d - bonus) / SOFT))
	var strike := roll < p
	return {"strike": strike, "p": p, "framed": strike and not truth, "lost": truth and not strike}


## A pitch that is hard to handle gets by more often when the glove is not on it.
static func gets_away(base_p: float, cover: float) -> float:
	return base_p * lerpf(1.0, COVER_FLOOR, clampf(cover, 0.0, 1.0))
