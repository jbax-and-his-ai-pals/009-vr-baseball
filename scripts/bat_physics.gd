class_name BatPhysics
extends RefCounted
## You swinging a bat: when the ball and a moving bat meet, what comes off. Pure geometry and a
## simple collision (no engine physics), so a swing can be tested with made-up numbers.
##
## The bat is a line from the knob (a) to the tip (b), LENGTH long, with a radius that grows from the
## handle to the barrel. The ball is a sphere that moved from `prev` to `now` this step. If the sphere
## meets the bat while closing on it, the ball leaves with:
##   - along the contact normal n (from the bat toward the ball): the two-body collision with an
##     effective bat mass and a bounciness that both peak at the sweet spot,
##         u' = ((m - e M) u + (1 + e) M w) / (m + M)
##     (u the ball's speed along n, w the bat's), which at the sweet spot is about 0.27 of the pitch plus
##     1.27 of the bat's speed,
##   - across it: the sliding between ball and bat mostly kept,
##   - spin: backspin when the ball is hit below its centre, topspin above.
## The result has the same keys BatterAI gives for an AI swing, so the rest of the game cannot tell.

const LENGTH := 0.85
const BALL_R := 0.0366
const SWEET := 0.62                    # metres from the knob
const BALL_MASS := 0.145
const BAT_MASS := 0.80                 # effective mass at the sweet spot, kg


## The bat's radius at a distance s from the knob (thin handle, fat barrel).
static func radius_at(s: float) -> float:
	return lerpf(0.015, 0.036, smoothstep(0.15, 0.55, s))


## 1 at the sweet spot, falling off toward the handle and the end.
static func sweetness(s: float) -> float:
	var d := (s - SWEET) / 0.16
	return exp(-d * d)


## Closest point on segment a-b to point p, as {"s": metres along from a, "point": Vector3}.
static func closest_on_segment(a: Vector3, b: Vector3, p: Vector3) -> Dictionary:
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0 if len2 < 1e-9 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return {"s": t * sqrt(len2), "point": a + ab * t}


## Did the swept ball (prev -> now) touch the bat (a-b)? Returns {} or {"s", "point" (on the bat),
## "ball" (ball centre when it touched), "dist"}.
static func touch(prev: Vector3, now: Vector3, a: Vector3, b: Vector3) -> Dictionary:
	var best := {}
	var best_gap := 1e9
	var steps := 6
	for i in steps + 1:
		var p := prev.lerp(now, float(i) / steps)
		var c := closest_on_segment(a, b, p)
		var gap: float = p.distance_to(c.point) - (BALL_R + radius_at(float(c.s)))
		if gap < best_gap:
			best_gap = gap
			best = {"s": c.s, "point": c.point, "ball": p, "dist": p.distance_to(c.point)}
	return best if best_gap <= 0.0 else {}


## Velocity of the point at distance s on a bat whose knob moves at va and tip at vb.
static func bat_point_velocity(va: Vector3, vb: Vector3, s: float) -> Vector3:
	return va.lerp(vb, clampf(s / LENGTH, 0.0, 1.0))


## Resolve a touch. `ball_vel` is the ball's velocity, `va` / `vb` the knob's and tip's velocities.
## Returns {} if the bat and ball are not closing on each other, otherwise a BatterAI-style result:
##   kind "hit" or "foul tip", swing, contact, vel, spin, ev (mph), la, spray, s (where on the bat),
##   quality (0..1), bat_speed_mph (the bat's speed at that point), contact_pos, bat_target.
static func collide(hit: Dictionary, ball_vel: Vector3, a: Vector3, b: Vector3, va: Vector3, vb: Vector3) -> Dictionary:
	var s: float = hit.s
	var n: Vector3 = (hit.ball as Vector3) - (hit.point as Vector3)
	if n.length() < 1e-5:
		n = (b - a).cross(Vector3.UP)
	n = n.normalized()
	var vbat := bat_point_velocity(va, vb, s)
	var u := ball_vel.dot(n)
	var w := vbat.dot(n)
	if w - u <= 0.5:
		return {}                                        # moving apart (or barely touching): no collision
	var sweet := sweetness(s)
	var m_eff := BAT_MASS * (0.45 + 0.55 * sweet)        # a handle or the end feels like a lighter bat
	var e := 0.18 + 0.34 * sweet                         # and a deader one
	var u_after := ((BALL_MASS - e * m_eff) * u + (1.0 + e) * m_eff * w) / (BALL_MASS + m_eff)
	var vb_t := vbat - n * w
	var vp_t := ball_vel - n * u
	var vel_after := n * u_after + vb_t + (vp_t - vb_t) * 0.75
	# Hit below the centre of the ball (n points up) and it backspins; above, it tops.
	var out_dir := vel_after.normalized()
	var backspin_rpm := clampf(2600.0 * n.y - 150.0, -2500.0, 4500.0)
	var spin := out_dir.cross(Vector3.UP).normalized() * (backspin_rpm * PitchPhysics.RPM_TO_RADS)
	var gap_ratio := float(hit.dist) / (BALL_R + radius_at(s))
	var ev := vel_after.length()
	var kind := "foul tip" if (gap_ratio > 0.92 and (w - u) < 8.0) or ev < 9.0 else "hit"
	var quality := clampf(sweet * 0.7 + clampf(ev / 48.0, 0.0, 1.0) * 0.3, 0.0, 1.0)
	return {"kind": kind, "contact": true, "swing": true, "vel": vel_after, "spin": spin,
		"ev": ev * PitchPhysics.MPS_TO_MPH, "la": BattedBall.launch_degrees(vel_after), "spray": BattedBall.spray_degrees(vel_after),
		"s": s, "quality": quality, "bat_speed_mph": vbat.length() * PitchPhysics.MPS_TO_MPH,
		"contact_pos": hit.ball, "bat_target": hit.ball}
