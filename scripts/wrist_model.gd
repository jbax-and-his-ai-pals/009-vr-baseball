class_name WristModel
extends RefCounted
## Turns how you throw into ball spin, so pitch types come from technique, not menus.
##
## Recorded throws showed controller rotation at release is dominated by the natural
## forearm snap and scales with hand speed (r = 0.91), so raw rotation would make every
## hard throw a curveball. Instead we compare each throw to the player's own usual
## throw, using rotation *per unit of hand speed* in three directions:
##   snap  - forward flick over the top      (more than usual -> backspin fades -> topspin curve)
##   side  - turning the wrist like a doorknob (-> sidespin: slider / screwball)
##   gyro  - rolling about the throw line      (-> bullet spin, cutter-like)
## plus arm slot (hand height vs head: lower than usual tilts the spin axis toward the
## arm side -> sinker / two-seam run) and wrist stiffness (almost no rotation ->
## knuckleball). The player's usual throw is a plain fastball.
##
## Spin vectors are built in the throw frame: +right = backspin axis, up = sidespin axis,
## travel = gyro axis. Positive sidespin about up breaks toward -X (the right-hander's
## glove side); signs mirror for left-handers via hand_sign.

# Starting baselines from a recorded player (ratios are rad/s of rotation per m/s of hand
# speed). They are only a prior: the first throws recalibrate means AND spreads to the
# actual player, since technique varies a lot between people.
var mean_snap := 2.67
var sd_snap := 0.46
var mean_side := 0.76
var sd_side := 0.50
var mean_gyro := 0.39
var sd_gyro := 0.31
var mean_mag := 3.0
var sd_mag := 0.50
var mean_slot := -0.30
var sd_slot := 0.18
var mean_speed := 10.3
var sd_speed := 2.5
## Windup height: how far above the head the hand got before the throw (m), and how
## straight the hand's path was over the last third of a second.
var mean_wind := 0.19
var sd_wind := 0.06
var mean_straight := 0.91
var sd_straight := 0.03
## Steady-state learning rate (per ordinary throw) once calibrated.
var learn_rate := 0.04
## Throws used for fast calibration, accepting nearly anything.
var calibration_throws := 10
var throws_seen := 0
## Once calibrated, the baseline barely moves: your usual throw stays your usual throw even
## after a run of deliberate off-style pitches. (Recorded: with the faster steady-state
## rate, 80 mixed throws dragged "normal" from snap 2.7 / speed 10 m/s to 2.0 / 14 m/s.)
var anchor_baseline := true
var anchored_rate := 0.01
## Harder throws finish with the hand lower (recorded: -0.036 m per m/s of hand speed), so
## arm slot is judged against what this speed would give, not against a fixed height.
var slot_per_speed := -0.036
## A pushed pitch is a knuckleball: hand path nearly straight and slower than usual
## (recorded: pushes ~0.96 straight, normal throws ~0.89, big arm swings ~0.7). A slow
## throw with a normal arc stays a changeup.
var push_knuckle := true
## Sidearm throws sweep the controller sideways just by being sidearm; that sweep is not a
## deliberate slider twist, so it counts for less as the arm gets lower.
var sidearm_discount := true
## Detect a knuckleball as rotation per speed well below your normal, measured in units of
## your normal scatter, and never for slow throws (those are changeups).
var knuckle_by_sigma := true

# Tuning.
var technique_gain := 1.0        ## scales every deviation; raise if your wrist moves little
var fastball_backspin := 180.0   ## rad/s of backspin on a plain throw (~1700 rpm)
var snap_sd_to_zero := 1.2       ## extra snap (in std devs) that cancels backspin
var side_gain := 95.0            ## rad/s of sidespin per std dev of wrist twist
var gyro_gain := 60.0
var tilt_deg_per_sd := 22.0      ## spin-axis tilt per std dev of arm slot below usual (sinker run)
var cut_deg_per_sd := 12.0       ## glove-side axis tilt per std dev of gyro roll (cutter)
var max_spin := 340.0            ## rad/s, ~3250 rpm: nobody spins it faster
var flutter_max := 12.0          ## m/s^2 of knuckleball wobble at full stiffness


func typical_mph(velocity_gain: float) -> float:
	return mean_speed * velocity_gain * 2.23694


## omega: controller angular velocity (world, rad/s). vel: hand velocity (m/s).
## slot: hand height minus head height (m). hand_sign: +1 right-handed, -1 left-handed.
## Returns {spin, flutter, knuckle, z_snap, z_side, z_gyro, z_slot, tilt_deg, stiff}.
## extras (optional): "straight" = hand-path straightness, "wind_peak" = windup height above head.
func shape(omega: Vector3, vel: Vector3, slot: float, hand_sign: float, extras: Dictionary = {}) -> Dictionary:
	var speed := maxf(vel.length(), 5.0)
	var t := vel.normalized() if vel.length() > 0.01 else Vector3(0.0, 0.0, -1.0)
	var right := t.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.2 else Vector3.RIGHT

	var r_snap := -omega.dot(right) / speed
	var r_side := omega.dot(Vector3.UP) * hand_sign / speed
	var r_gyro := omega.dot(t) * hand_sign / speed
	var r_mag := omega.length() / speed

	var zr_snap := (r_snap - mean_snap) / sd_snap
	var zr_side := (r_side - mean_side) / sd_side
	var zr_gyro := (r_gyro - mean_gyro) / sd_gyro
	var slot_expected := mean_slot + slot_per_speed * (speed - mean_speed)
	var zr_slot := (slot - slot_expected) / maxf(sd_slot, 0.12 if slot_per_speed != 0.0 else 0.0)
	var wind: float = extras.get("wind_peak", -INF)
	var straight: float = extras.get("straight", -1.0)
	var has_wind := wind > -100.0
	var zr_wind := (wind - mean_wind) / maxf(sd_wind, 0.04) if has_wind else 0.0
	var z_snap := clampf(zr_snap * technique_gain, -3.0, 3.0)
	var z_side := clampf(zr_side * technique_gain, -3.0, 3.0)
	var z_gyro := clampf(zr_gyro * technique_gain, -3.0, 3.0)
	var z_slot := clampf(zr_slot, -3.0, 3.0)
	var z_wind := clampf(zr_wind * technique_gain, -3.0, 3.0)
	# A rolled controller (gyro) also yaws sideways a little; do not read all of that as a
	# slider twist. And a low arm sweeps sideways by itself.
	if sidearm_discount:
		z_side = maxf(z_side - 0.5 * maxf(z_gyro, 0.0), minf(z_side, 0.0))
		z_side *= 1.0 - smoothstep(1.0, 2.0, -z_slot)
	# The curve gesture is "more than usual over the top": an extra wrist flick on top of
	# the throw OR a bigger, higher windup (recorded: the flick alone barely changes the
	# rotation-per-speed ratio, but a big high windup is unmistakable).
	var z_arc := z_snap + maxf(z_wind, 0.0)

	var back := clampf(fastball_backspin * (1.0 - z_arc / snap_sd_to_zero), -1.1 * fastball_backspin, 1.4 * fastball_backspin)
	# Twisting the wrist turns backspin into sidespin (slider); a low arm slot gives up
	# backspin too (sinker).
	var twist := clampf(absf(z_side) / 2.0, 0.0, 1.0)
	var low := clampf(-z_slot, 0.0, 2.5)
	if back > 0.0:
		back *= (1.0 - 0.45 * twist) * (1.0 - 0.14 * low)
	var side := clampf(side_gain * z_side, -300.0, 300.0) * hand_sign
	var gyro := clampf(gyro_gain * z_gyro, -150.0, 150.0) * hand_sign
	var spin := right * back + Vector3.UP * side + t * gyro
	if spin.length() > max_spin:
		spin = spin.normalized() * max_spin
	# Axis tilt: positive = lift pushed toward the arm side. A low slot tilts toward the arm
	# side (sinker); a high slot barely tilts away; rolling the wrist about the throw line
	# tilts toward the glove side (cutter).
	var slot_tilt := (low * tilt_deg_per_sd) if z_slot < 0.0 else (-z_slot * 5.0)
	var tilt_deg := slot_tilt - z_gyro * cut_deg_per_sd
	spin = spin.rotated(t, deg_to_rad(tilt_deg) * hand_sign)

	# A nearly motionless wrist is a knuckleball: spin fades out, wobble fades in.
	var stiff: float
	if knuckle_by_sigma:
		var z_mag := (mean_mag - r_mag) / maxf(sd_mag, 0.30) * technique_gain
		stiff = smoothstep(1.5, 3.0, z_mag) * smoothstep(0.70, 0.88, speed / mean_speed)
	else:
		stiff = 1.0 - smoothstep(0.30, 0.65, (r_mag / mean_mag) * technique_gain)
	var push := 0.0
	if push_knuckle and straight > 0.0:
		var z_straight := (straight - mean_straight) / maxf(sd_straight, 0.02)
		push = smoothstep(1.2, 2.2, z_straight) * (1.0 - smoothstep(0.80, 1.0, speed / mean_speed))
		stiff = maxf(stiff, push)
	spin *= 1.0 - stiff

	# Learn. Early on, calibrate fast to whoever is throwing; afterwards only ordinary
	# throws teach it, so deliberate off-style pitches do not redefine "normal".
	if stiff < 0.2:
		var calibrating := throws_seen < calibration_throws
		var steady_rate := anchored_rate if anchor_baseline else learn_rate
		var rate := maxf(1.0 / (throws_seen + 3.0), steady_rate) if calibrating else steady_rate
		var gate := 6.0 if calibrating else (2.5 if anchor_baseline else 2.2)
		# Learn arm slot as it would be at the usual speed, so a hard throw does not
		# teach "low arm is normal".
		var slot_at_usual := slot - slot_per_speed * (speed - mean_speed)
		var f_snap := _learn(r_snap, mean_snap, sd_snap, 0.25, rate, gate)
		var f_side := _learn(r_side, mean_side, sd_side, 0.20, rate, gate)
		var f_gyro := _learn(r_gyro, mean_gyro, sd_gyro, 0.15, rate, gate)
		var f_mag := _learn(r_mag, mean_mag, sd_mag, 0.30, rate, gate)
		var f_slot := _learn(slot_at_usual, mean_slot, sd_slot, 0.08, rate, gate)
		var f_speed := _learn(speed, mean_speed, sd_speed, 1.0, rate, gate)
		if has_wind:
			var f_wind := _learn(wind, mean_wind, sd_wind, 0.04, rate, gate)
			mean_wind = f_wind.x
			sd_wind = f_wind.y
		if straight > 0.0:
			var f_str := _learn(straight, mean_straight, sd_straight, 0.02, rate, gate)
			mean_straight = f_str.x
			sd_straight = f_str.y
		mean_snap = f_snap.x
		sd_snap = f_snap.y
		mean_side = f_side.x
		sd_side = f_side.y
		mean_gyro = f_gyro.x
		sd_gyro = f_gyro.y
		mean_mag = f_mag.x
		sd_mag = f_mag.y
		mean_slot = f_slot.x
		sd_slot = f_slot.y
		mean_speed = f_speed.x
		sd_speed = f_speed.y
		throws_seen += 1

	return {
		"spin": spin, "flutter": stiff * flutter_max, "knuckle": stiff > 0.6,
		"z_snap": z_snap, "z_side": z_side, "z_gyro": z_gyro, "z_slot": z_slot, "z_wind": z_wind,
		"tilt_deg": tilt_deg, "stiff": stiff, "push": push,
	}


## One running mean / spread update. Skips values more than gate sd out (deliberate
## outliers). Returns (mean, sd).
func _learn(value: float, mean: float, sd: float, sd_floor: float, rate: float, gate: float) -> Vector2:
	var dev := value - mean
	if absf(dev) > gate * sd:
		return Vector2(mean, sd)
	var v := sd * sd
	v += (dev * dev - v) * rate
	return Vector2(mean + dev * rate, maxf(sd_floor, sqrt(v)))
