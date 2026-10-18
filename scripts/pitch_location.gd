class_name PitchLocation
extends RefCounted
## Names and colors where a pitch crossed the plate, so you can see at a glance whether you
## hit a corner or threw a cookie. Pure, and it shares the batter's idea of "edge" so what is
## shown is what the batter actually felt.
##
##   MIDDLE      dead center: easy to square up, amber (a warning)
##   IN ZONE     a strike, nothing special, light green
##   GOOD        a strike near an edge, green
##   CORNER      a strike on a corner: hardest to hit, bright green with a gold halo
##   JUST OFF    a ball within a hand's width of the zone, orange (a chase pitch)
##   BALL        red, and WAY OFF a darker red

const MIDDLE := 0.35
const GOOD := 0.60
const CORNER := 0.80
const JUST_OFF := 0.15
const WAY_OFF := 0.45


## 0 at dead center, 1 on the edge of the strike zone; larger when outside it.
static func edge_of(x: float, y: float) -> float:
	var mid := 0.5 * (PitchPhysics.ZONE_TOP + PitchPhysics.ZONE_BOTTOM)
	var half_h := 0.5 * (PitchPhysics.ZONE_TOP - PitchPhysics.ZONE_BOTTOM)
	return maxf(absf(x) / PitchPhysics.ZONE_HALF_W, absf(y - mid) / half_h)


## How far outside the zone (meters, 0 inside).
static func outside_by(x: float, y: float) -> float:
	var dx := maxf(absf(x) - PitchPhysics.ZONE_HALF_W, 0.0)
	var dy := maxf(maxf(PitchPhysics.ZONE_BOTTOM - y, y - PitchPhysics.ZONE_TOP), 0.0)
	return sqrt(dx * dx + dy * dy)


## Does a pitch crossing here hit the batter standing in his box? A right-hander stands on the
## third-base side (+x), a left-hander on the other: his body is well off the plate, from about
## the knees to the shoulders.
static func hits_batter(x: float, y: float, lefty: bool = false) -> bool:
	var side := -x if lefty else x
	return side >= 0.62 and side <= 1.28 and y >= 0.25 and y <= 1.60


static func classify(x: float, y: float) -> Dictionary:
	var strike := absf(x) <= PitchPhysics.ZONE_HALF_W + PitchPhysics.BALL_RADIUS \
		and y >= PitchPhysics.ZONE_BOTTOM - PitchPhysics.BALL_RADIUS \
		and y <= PitchPhysics.ZONE_TOP + PitchPhysics.BALL_RADIUS
	var edge := edge_of(x, y)
	if strike:
		if edge >= CORNER:
			return {"kind": "corner", "label": "CORNER", "strike": true, "edge": edge, "halo": true,
				"color": Color(0.15, 0.95, 0.30)}
		if edge >= GOOD:
			return {"kind": "good", "label": "GOOD LOCATION", "strike": true, "edge": edge, "halo": false,
				"color": Color(0.25, 0.85, 0.35)}
		if edge < MIDDLE:
			return {"kind": "middle", "label": "MIDDLE", "strike": true, "edge": edge, "halo": false,
				"color": Color(1.0, 0.72, 0.15)}
		return {"kind": "zone", "label": "IN ZONE", "strike": true, "edge": edge, "halo": false,
			"color": Color(0.55, 0.9, 0.45)}
	var out := outside_by(x, y)
	if out <= JUST_OFF:
		return {"kind": "just_off", "label": "JUST OFF", "strike": false, "edge": edge, "halo": false,
			"color": Color(1.0, 0.5, 0.15)}
	if out >= WAY_OFF:
		return {"kind": "way_off", "label": "WAY OFF", "strike": false, "edge": edge, "halo": false,
			"color": Color(0.65, 0.1, 0.12)}
	return {"kind": "ball", "label": "BALL", "strike": false, "edge": edge, "halo": false,
		"color": Color(0.95, 0.2, 0.2)}
