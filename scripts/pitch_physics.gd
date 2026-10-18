class_name PitchPhysics
extends RefCounted
## Deterministic baseball flight model: gravity + quadratic drag + Magnus lift.
## Field coordinates: home plate center is the origin, the pitcher stands at
## +Z looking toward -Z, +X is to the pitcher's right, +Y is up. Units are SI.

const BALL_RADIUS := 0.0366
const BALL_MASS := 0.145
const AIR_DENSITY := 1.2
const DRAG_CD := 0.35
## Calibration on top of the textbook lift curve. Unscaled, a 92 mph / 2300 rpm
## fastball rises ~24 in vs gravity-only; tracked fastballs sit nearer 15-18 in.
const LIFT_SCALE := 0.75
const GRAVITY := Vector3(0.0, -9.81, 0.0)
const SIM_DT := 1.0 / 240.0
const AREA := PI * BALL_RADIUS * BALL_RADIUS

const MPS_TO_MPH := 2.23694
const RPM_TO_RADS := TAU / 60.0
const M_TO_IN := 39.3701

const MOUND_Z := 18.44
const MOUND_H := 0.254
## The strike zone is deliberately more generous than the rulebook's plate-width, knees-to-chest
## box (0.43 x 0.60 m): 0.60 m wide, 0.90 m tall. It makes a clean strike easier to see and
## judge, and leaves room for a pitch to be clearly, visibly bad.
const ZONE_HALF_W := 0.30
const ZONE_BOTTOM := 0.40
const ZONE_TOP := 1.30

## Spin in rpm as an axis-angle vector (right-hand rule). For a ball travelling
## toward -Z, +X is backspin, -X is topspin, +Y breaks the ball toward -X.
const CANNED := {
	"Fastball": {"mph": 92.0, "rpm": Vector3(2300.0, 150.0, 0.0)},
	"Curveball": {"mph": 78.0, "rpm": Vector3(-2000.0, 300.0, -800.0)},
	"Slider": {"mph": 85.0, "rpm": Vector3(-300.0, 1200.0, -1500.0)},
	"Changeup": {"mph": 83.0, "rpm": Vector3(1500.0, -500.0, 0.0)},
}


## Knuckleball wobble: slowly varying sideways / vertical force, deterministic in
## (time, seed) so the predicted path matches the flown path.
static func flutter_accel(t: float, amp: float, seed: float) -> Vector3:
	if amp <= 0.0:
		return Vector3.ZERO
	# Cosine accelerations start with zero net velocity, so the wobble oscillates around
	# the true path instead of drifting off it. Signs and frequencies come from the seed.
	var h1 := fposmod(sin(seed * 12.9898) * 43758.5453, 1.0)
	var h2 := fposmod(sin(seed * 78.233) * 43758.5453, 1.0)
	var h3 := fposmod(sin(seed * 39.346) * 43758.5453, 1.0)
	var h4 := fposmod(sin(seed * 11.135) * 43758.5453, 1.0)
	var sx := 1.0 if h1 > 0.5 else -1.0
	var sy := 1.0 if h3 > 0.5 else -1.0
	var fx := 0.8 + 0.9 * h2
	var fy := 0.8 + 0.9 * h4
	return Vector3(
		amp * sx * (0.7 * cos(TAU * fx * t) + 0.3 * cos(TAU * 2.1 * fx * t)),
		amp * sy * (0.7 * cos(TAU * fy * t) + 0.3 * cos(TAU * 2.1 * fy * t)),
		0.0)


static func acceleration(vel: Vector3, spin: Vector3, use_magnus: bool = true, extra: Vector3 = Vector3.ZERO) -> Vector3:
	var speed := vel.length()
	if speed < 0.01:
		return GRAVITY + extra
	var a := GRAVITY + extra
	a -= vel * (0.5 * AIR_DENSITY * DRAG_CD * AREA * speed / BALL_MASS)
	if use_magnus:
		var dir := spin.cross(vel)
		# Only spin perpendicular to travel makes lift; bullet (gyro) spin does not.
		var w := dir.length() / speed
		if w > 0.01 and dir.length_squared() > 1e-9:
			var s := BALL_RADIUS * w / speed
			var cl := LIFT_SCALE * s / (2.32 * s + 0.4)
			a += dir.normalized() * (0.5 * AIR_DENSITY * AREA * cl * speed * speed / BALL_MASS)
	return a


## One RK4 step. Returns [new_pos, new_vel].
static func step(pos: Vector3, vel: Vector3, spin: Vector3, dt: float, use_magnus: bool = true, t: float = 0.0, flutter_amp: float = 0.0, flutter_seed: float = 0.0) -> PackedVector3Array:
	var e_start := flutter_accel(t, flutter_amp, flutter_seed)
	var e_mid := flutter_accel(t + dt * 0.5, flutter_amp, flutter_seed)
	var e_end := flutter_accel(t + dt, flutter_amp, flutter_seed)
	var k1v := acceleration(vel, spin, use_magnus, e_start)
	var k1p := vel
	var v2 := vel + k1v * (dt * 0.5)
	var k2v := acceleration(v2, spin, use_magnus, e_mid)
	var k2p := v2
	var v3 := vel + k2v * (dt * 0.5)
	var k3v := acceleration(v3, spin, use_magnus, e_mid)
	var k3p := v3
	var v4 := vel + k3v * dt
	var k4v := acceleration(v4, spin, use_magnus, e_end)
	var k4p := v4
	return PackedVector3Array([
		pos + (k1p + 2.0 * k2p + 2.0 * k3p + k4p) * (dt / 6.0),
		vel + (k1v + 2.0 * k2v + 2.0 * k3v + k4v) * (dt / 6.0),
	])


## Fly until the ball crosses the plane z = 0. Returns {reached, pos, vel, time}.
static func fly_to_plate(pos: Vector3, vel: Vector3, spin: Vector3, use_magnus: bool = true, max_time: float = 2.5, floor_y: float = BALL_RADIUS, flutter_amp: float = 0.0, flutter_seed: float = 0.0) -> Dictionary:
	var t := 0.0
	while t < max_time:
		var s := step(pos, vel, spin, SIM_DT, use_magnus, t, flutter_amp, flutter_seed)
		if pos.z > 0.0 and s[0].z <= 0.0:
			var f := pos.z / (pos.z - s[0].z)
			return {"reached": true, "pos": pos.lerp(s[0], f), "vel": vel.lerp(s[1], f), "time": t + SIM_DT * f}
		pos = s[0]
		vel = s[1]
		t += SIM_DT
		if pos.y < floor_y:
			break
	return {"reached": false, "pos": pos, "vel": vel, "time": t}


static func is_strike(plate_pos: Vector3) -> bool:
	return absf(plate_pos.x) <= ZONE_HALF_W + BALL_RADIUS \
		and plate_pos.y >= ZONE_BOTTOM - BALL_RADIUS \
		and plate_pos.y <= ZONE_TOP + BALL_RADIUS


## Everything a pitch-lab readout needs. Break is measured against the same
## throw with Magnus lift removed, so it isolates what the spin did.
static func analyze(release_pos: Vector3, vel: Vector3, spin: Vector3, flutter_amp: float = 0.0, flutter_seed: float = 0.0) -> Dictionary:
	var real := fly_to_plate(release_pos, vel, spin, true, 2.5, BALL_RADIUS, flutter_amp, flutter_seed)
	var out := {
		"reached": real.reached,
		"speed_mph": vel.length() * MPS_TO_MPH,
		"spin_rpm": spin.length() / RPM_TO_RADS,
	}
	if not real.reached:
		return out
	var dry := fly_to_plate(release_pos, vel, spin, false)
	var p: Vector3 = real.pos
	out["plate_pos"] = p
	out["time"] = real.time
	out["plate_mph"] = (real.vel as Vector3).length() * MPS_TO_MPH
	out["strike"] = is_strike(p)
	if dry.reached:
		out["ivb_in"] = (p.y - (dry.pos as Vector3).y) * M_TO_IN
		out["hb_in"] = (p.x - (dry.pos as Vector3).x) * M_TO_IN
	return out


## Velocity vector that (iteratively) sends this ball through target.
static func solve_aim(release_pos: Vector3, speed: float, spin: Vector3, target: Vector3, use_magnus: bool = true) -> Vector3:
	var flat_t := maxf(release_pos.z, 1.0) / maxf(speed, 1.0)
	var aim := target + Vector3(0.0, 0.5 * 9.81 * flat_t * flat_t, 0.0)
	for i in 16:
		var v := (aim - release_pos).normalized() * speed
		var r := fly_to_plate(release_pos, v, spin, use_magnus)
		if not r.reached:
			aim.y += 0.5
			continue
		var err: Vector3 = target - (r.pos as Vector3)
		if err.length() < 0.002:
			break
		aim += err
	return (aim - release_pos).normalized() * speed


## Gravity assist. The ball is sent where the hand was pointing (a straight-line
## extrapolation to the plate), so nobody has to lob it. The solve ignores spin,
## so Magnus break lands on top of the pointed line. strength 0 = untouched
## physics; 1 = pointed line; in between blends the raw landing spot toward it.
static func assist_velocity(release_pos: Vector3, raw_vel: Vector3, spin: Vector3, strength: float) -> Vector3:
	var speed := raw_vel.length()
	if strength <= 0.0 or speed < 6.0:
		return raw_vel
	var dir := raw_vel / speed
	if dir.z > -0.2:
		return raw_vel
	var target := release_pos + dir * (release_pos.z / -dir.z)
	var raw_land := fly_to_plate(release_pos, raw_vel, spin, true, 3.0, -100.0)
	if raw_land.reached:
		target = (raw_land.pos as Vector3).lerp(target, strength)
	var solved := solve_aim(release_pos, speed, spin, target, false)
	if not fly_to_plate(release_pos, solved, spin).reached:
		return raw_vel
	return solved


## Ball state t seconds after release (RK4, same steps as the flown pitch, so this matches
## the pitch exactly). Returns {pos, vel}. Used to find where the ball is when a swing meets it.
static func state_at(release_pos: Vector3, vel: Vector3, spin: Vector3, t_target: float, flutter_amp: float = 0.0, flutter_seed: float = 0.0) -> Dictionary:
	var pos := release_pos
	var v := vel
	var t := 0.0
	while t + SIM_DT <= t_target:
		var s := step(pos, v, spin, SIM_DT, true, t, flutter_amp, flutter_seed)
		pos = s[0]
		v = s[1]
		t += SIM_DT
	var rem := t_target - t
	if rem > 1e-6:
		var s2 := step(pos, v, spin, rem, true, t, flutter_amp, flutter_seed)
		pos = s2[0]
		v = s2[1]
	return {"pos": pos, "vel": v}
