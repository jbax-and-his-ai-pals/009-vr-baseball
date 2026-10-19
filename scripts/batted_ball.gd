class_name BattedBall
extends RefCounted
## Flight of a batted ball: gravity, drag, Magnus lift, a bounce for grounders, the fence
## and the foul lines. Simulated once at contact into a path that can be played back, plus a
## summary (where it lands, how far, how high, how long).

const BALL_RADIUS := 0.0366
const MASS := 0.145
const AREA := PI * BALL_RADIUS * BALL_RADIUS
const AIR_DENSITY := 1.2
## Lower than the pitch model's 0.35: drag on a baseball falls at batted-ball speeds.
const DRAG_CD := 0.33
const GRAVITY := Vector3(0.0, -9.81, 0.0)
const DT := 1.0 / 240.0
const RECORD_EVERY := 2          # path sample interval = 2 * DT = 1/120 s
const MAX_TIME := 14.0


## The park's air changes it: thin air (altitude) carries a fly ball farther, and a wind pushes it (drag and
## lift act on the ball's speed through the air, not over the ground). Pitches do not feel it (see PitchPhysics).
static func accel(v: Vector3, spin: Vector3) -> Vector3:
	var park := Park.now()
	var rho := AIR_DENSITY * park.air
	var rel := v - park.wind
	var speed := rel.length()
	if speed < 0.01:
		return GRAVITY
	var a := GRAVITY - rel * (0.5 * rho * DRAG_CD * AREA * speed / MASS)
	var dir := spin.cross(rel)
	var w := dir.length() / speed
	if w > 0.01:
		var s := BALL_RADIUS * w / speed
		var cl := PitchPhysics.LIFT_SCALE * s / (2.32 * s + 0.4)
		a += dir.normalized() * (0.5 * rho * AREA * cl * speed * speed / MASS)
	return a


static func _rk4(pos: Vector3, v: Vector3, spin: Vector3) -> Array:
	var k1 := accel(v, spin)
	var v2 := v + k1 * (DT * 0.5)
	var k2 := accel(v2, spin)
	var v3 := v + k2 * (DT * 0.5)
	var k3 := accel(v3, spin)
	var v4 := v + k3 * DT
	var k4 := accel(v4, spin)
	var np := pos + (v + 2.0 * v2 + 2.0 * v3 + v4) * (DT / 6.0)
	var nv := v + (k1 + 2.0 * k2 + 2.0 * k3 + k4) * (DT / 6.0)
	return [np, nv]


## Fair territory: in front of the plate and inside the foul lines.
static func is_fair(p: Vector3) -> bool:
	return p.z > 0.0 and absf(p.x) <= p.z + 0.3


static func spray_degrees(v: Vector3) -> float:
	return rad_to_deg(atan2(v.x, v.z))


static func launch_degrees(v: Vector3) -> float:
	return rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))


static func hit_kind(launch_deg: float) -> String:
	if launch_deg < 10.0:
		return "Ground ball"
	if launch_deg < 25.0:
		return "Line drive"
	if launch_deg < 50.0:
		return "Fly ball"
	return "Pop-up"


## Pretty direction for a right-handed batter's view (positive spray = left side).
static func spray_text(psi: float) -> String:
	var a := absf(psi)
	var side := "left" if psi > 0.0 else "right"
	if a < 8.0:
		return "center"
	if a < 22.0:
		return "%s-center" % side
	if a <= 45.0:
		return "%s field" % side
	return "foul, %s" % side


## origin: where the ball is at contact. vel/spin: just after contact.
static func simulate(origin: Vector3, vel: Vector3, spin: Vector3) -> Dictionary:
	var pos := origin
	var v := vel
	var sp := spin
	var t := 0.0
	var pts := PackedVector3Array([pos])
	var step_i := 0
	var apex := pos.y
	var landed := false
	var landing := Vector3.ZERO
	var landing_t := 0.0
	var bounces := 0
	var home_run := false
	var wall_hit := false
	var ground_rule := false
	var hr_cross := Vector3.ZERO
	var ended := false
	var rolling := false
	while t < MAX_TIME and not ended:
		var r := _rk4(pos, v, sp)
		pos = r[0]
		v = r[1]
		t += DT
		step_i += 1
		if not landed:
			apex = maxf(apex, pos.y)  # first flight only, not bounce heights

		# Fence: crossing the park outline in front of the plate.
		if pos.z > 0.0:
			var psi := rad_to_deg(atan2(pos.x, pos.z))
			if Vector2(pos.x, pos.z).length() >= Stadium.fence_radius(psi) and is_fair(pos):
				if pos.y >= Park.now().wall_height + BALL_RADIUS and not landed:
					# Over the fence: keep flying so the full distance is known.
					if not home_run:
						home_run = true
						hr_cross = pos
				elif landed and not home_run and pos.y >= Park.now().wall_height + BALL_RADIUS:
					# It hit the ground first and bounced over the fence: a ground-rule double.
					ground_rule = true
					ended = true
					pts.append(pos)
					break
				elif not home_run:
					wall_hit = true
					if not landed:
						landed = true
						landing = pos
						landing_t = t
					ended = true
					pts.append(pos)
					break

		# Ground: bounce, then roll to a stop.
		if not rolling and pos.y <= BALL_RADIUS and v.y < 0.0:
			pos.y = BALL_RADIUS
			if not landed:
				landed = true
				landing = pos
				landing_t = t
			bounces += 1
			if home_run:
				ended = true
				pts.append(pos)
				break
			if absf(v.y) < 1.2 or bounces >= 6:
				v.y = 0.0
				rolling = true
			else:
				v.y = -v.y * 0.45
			v.x *= 0.90
			v.z *= 0.90
			sp *= 0.5
		if rolling:
			var h := Vector2(v.x, v.z)
			var sp_h := h.length()
			if sp_h < 0.25:
				ended = true
			else:
				var dec := minf(3.0 * DT, sp_h)
				h = h * (1.0 - dec / sp_h)
				v.x = h.x
				v.z = h.y
				v.y = 0.0
				pos.y = BALL_RADIUS
		if step_i % RECORD_EVERY == 0:
			pts.append(pos)
	pts.append(pos)

	var launch := launch_degrees(vel)
	var spray := spray_degrees(vel)
	var out := {
		"points": pts, "dt": DT * RECORD_EVERY, "total_time": t,
		"landing_pos": landing, "landing_time": landing_t, "rest_pos": pos,
		"apex": apex, "hang_time": landing_t,
		"distance": Vector2(landing.x, landing.z).length(),
		"fair": is_fair(landing) if landed else false,
		"home_run": home_run, "wall": wall_hit, "ground_rule": ground_rule, "bounces": bounces,
		"ev_mph": vel.length() * PitchPhysics.MPS_TO_MPH, "launch": launch, "spray": spray,
		"kind": hit_kind(launch),
	}
	if home_run:
		out["fair"] = true
		out["fence_cross"] = hr_cross
	return out
