class_name HumanPitcher
extends RefCounted
## You throwing: reads the controller every frame, notices when you pick up the ball, start your
## delivery and let go, and turns the release into a pitch (speed, spin, where it should cross the
## plate). It also learns how YOU usually aim, so the funnel can measure each throw against your
## own scatter. It never launches anything: it hands the scene a description and the scene throws it.
##
## The tuning knobs stay on the scene (so they can be changed in the inspector); `knobs` is that scene.

const GRAB_THRESHOLD := 0.7
const RELEASE_THRESHOLD := 0.4
const HOLD_OFFSET := Vector3(0.0, -0.02, -0.06)
const FORWARD := Vector3(0.0, 0.0, -1.0)
## Assisted pitches never leave the hand slower than this (m/s), so a feeble throw does not become a 45-degree rainbow.
const MIN_ASSIST_SPEED := 12.0
## FUNNEL reads the hand's travel direction between these times before release. Chosen from recorded
## throws: much steadier than the instant of release, where the velocity direction swings ~1 degree per ms.
const FUNNEL_FROM := 0.19
const FUNNEL_TO := 0.04
const ZONE_CENTER := Vector2(0.0, (PitchPhysics.ZONE_BOTTOM + PitchPhysics.ZONE_TOP) * 0.5)
## Releases slower than this (m/s of hand speed) are not throws: the ball just drops.
const MIN_THROW_SPEED := 3.5
## Moving faster than this (m/s) with the ball in your hand is the start of your delivery.
const DELIVERY_SPEED := 1.6
## The aim scatter every player starts from (degrees right, up). At Standard and Pro a throw's aim is measured
## partly or wholly against it instead of your own scatter, so a steadier delivery lands closer to the glove.
const REFERENCE_SIGMA := Vector2(6.0, 5.5)
## Beyond this many standard deviations a miss grows at 0.4 the rate: a wild throw stays wild, not absurd.
const MISS_KNEE := 1.5
## Throwing harder than your usual speed + 1 sd costs this much extra spread at full overthrow (and tires the arm).
const OVERTHROW_SPREAD := 0.25
## BAND velocity: the pitcher's band in league miles per hour (what the radar shows) from the VEL rating. Your
## usual throw is the middle of it, your top throw the top.
const BAND_MID_AT_0 := 78.0
const BAND_MID_PER_POINT := 0.18
const BAND_WIDTH := 5.0
## Hand speeds remembered for your top speed (its 90th percentile), and how many before it is trusted.
const TOP_MEMORY := 30
const TOP_MIN_THROWS := 8

var knobs: Object                          # the scene: velocity_gain, funnel_spread_x, aim_mode, ...
var detector := ThrowDetector.new()
var wrist := WristModel.new()
## Learned usual aim direction (degrees right / up of straight at the plate) and how much it scatters.
## Start from a recorded player; the first throws calibrate them quickly.
var aim_mu := Vector2(4.4, -0.3)
var aim_sigma := REFERENCE_SIGMA
var aim_n := 0
var held := false                          # the ball is in your hand
var delivery_start := -1.0                 # when your motion began (seconds), -1 if it has not
var last_grip := 0.0
var _hand_prev := Vector3.ZERO
var _hand_prev_t := -1.0
## The career pitcher's VEL rating (50 for everyone else): where his velocity band sits.
var velocity_rating := 50.0
var _speeds: Array[float] = []              # recent hand speeds of real pitches (m/s), for your top speed


## Read the controller. Returns what happened, in order: {"type": "grab"}, {"type": "delivery_start"},
## {"type": "release", "t", "vel_latency", "spin_latency"} or {"type": "drop"}. `can_grab` is false
## while the batter is not in his box.
func poll(now: float, hand: XRController3D, can_grab: bool, auto_release: bool) -> Array:
	var events: Array = []
	if hand == null or not hand.get_is_active():
		return events
	var grip := hand.get_float("grip")
	last_grip = grip
	detector.add_sample(now, hand.global_position, hand.global_transform.basis.get_rotation_quaternion(), grip)
	if not held:
		if grip > GRAB_THRESHOLD and can_grab:
			held = true
			detector.clear()
			delivery_start = -1.0
			_hand_prev_t = -1.0
			events.append({"type": "grab"})
		return events
	# Your delivery starts when the arm gets going. The runners read it and break.
	var hp := hand.global_position
	if _hand_prev_t >= 0.0 and now > _hand_prev_t and delivery_start < 0.0:
		if hp.distance_to(_hand_prev) / (now - _hand_prev_t) > DELIVERY_SPEED:
			delivery_start = now
			events.append({"type": "delivery_start"})
	_hand_prev = hp
	_hand_prev_t = now
	if auto_release:
		var tp := detector.find_release_peak(6.0, 0.85, FORWARD)
		if tp > 0.0:
			events.append({"type": "release", "t": tp, "vel_latency": 0.0, "spin_latency": 0.0})
		elif grip < RELEASE_THRESHOLD:
			events.append({"type": "drop"})
	elif grip < RELEASE_THRESHOLD:
		events.append({"type": "release", "t": now, "vel_latency": float(knobs.velocity_latency), "spin_latency": float(knobs.spin_latency)})
	return events


## The ball leaves your hand (or is dropped). Clears the holding state and returns:
##   {"kind": "invalid"}                               nothing readable
##   {"kind": "drop", "started": bool}                 too soft to be a throw (a balk if you had started)
##   {"kind": "pickoff", "base", "err", "vel", "quick"} thrown toward a base ("quick": seconds from the start of the move)
##   {"kind": "pitch", "vel", "spin", "scaled", "est", "shape", "funnel", "hand_sign", "delivery",
##    "flutter", "knuckle", "overthrow"}               a pitch for the scene to launch
## `tired` is your arm's fatigue 0..1, `command_scale` the career pitcher's aim factor (1.0 otherwise),
## `camera_y` the head height (for the arm slot), `aim_center` where the catcher wants it (the funnel's middle).
func throw(release_t: float, vel_latency: float, spin_latency: float, from: Vector3, camera_y: float,
		tired: float, command_scale: float, runners_on: bool, aim_center: Vector2 = ZONE_CENTER) -> Dictionary:
	var est := detector.estimate(release_t, vel_latency)
	var spin_est := detector.estimate(release_t, spin_latency)
	var started := delivery_start >= 0.0
	var began_at := delivery_start
	drop()
	if not est.valid:
		return {"kind": "invalid"}
	if (est.velocity as Vector3).length() < MIN_THROW_SPEED:
		return {"kind": "drop", "started": started and runners_on}
	# Thrown toward a base: a throw over (a pickoff try).
	if from.z > 8.0:
		var pk := HumanFielding.pick_base(from, est.velocity, 26.0)
		if int(pk.base) in [1, 2, 3]:
			return {"kind": "pickoff", "base": int(pk.base), "err": float(pk.err), "vel": est.velocity as Vector3,
				"quick": clampf(release_t - began_at, 0.2, 2.0) if started else 0.7}
	var delivery := clampf(release_t - began_at, 0.25, 3.0) if started else 0.9
	var hand_speed := (est.velocity as Vector3).length()
	var vel: Vector3
	if int(knobs.get("velocity_mode") if knobs.get("velocity_mode") != null else 0) == 1:     # VelocityMode.BAND
		vel = (est.velocity as Vector3).normalized() * band_mph(hand_speed) * AIPitcher.GAME_SPEED / PitchPhysics.MPS_TO_MPH * (1.0 - 0.06 * tired)
	else:
		vel = (est.velocity as Vector3) * float(knobs.velocity_gain) * (1.0 - 0.06 * tired)
	var max_speed := float(knobs.max_mph) / PitchPhysics.MPS_TO_MPH
	if vel.length() > max_speed:
		vel = vel.normalized() * max_speed
	var spin_src: Vector3 = spin_est.spin if spin_est.valid else est.spin
	var hand_sign := 1.0 if knobs.throwing_hand == &"right_hand" else -1.0
	var shape := {}
	var spin: Vector3
	if knobs.spin_mode == 1:                                  # SpinMode.WRIST_MODEL
		wrist.technique_gain = float(knobs.technique_gain)
		wrist.fastball_backspin = float(knobs.fastball_backspin_rpm) * PitchPhysics.RPM_TO_RADS
		var slot := from.y - camera_y
		var extras := {"straight": detector.straightness(release_t)}
		var peak := detector.peak_height(release_t)
		if peak > -100.0:
			extras["wind_peak"] = peak - camera_y
		shape = wrist.shape(spin_src, est.velocity, slot, hand_sign, extras)
		spin = shape.spin
	else:
		spin = spin_src * float(knobs.spin_gain)
	var scaled := vel
	# Throwing harder than your usual costs command (judged before this throw teaches your top speed).
	var over := overthrow(hand_speed, wrist.mean_speed, wrist.sd_speed)
	_remember_speed(hand_speed)
	var funnel := {}
	match int(knobs.aim_mode):
		1:                                                    # AimMode.HAND_ASSIST
			vel = PitchPhysics.assist_velocity(from, vel, spin, float(knobs.aim_assist))
		2:                                                    # AimMode.FUNNEL
			funnel = funnel_target(release_t, tired, command_scale, aim_center, 1.0 + OVERTHROW_SPREAD * over)
			var target: Vector3 = funnel.target
			vel = PitchPhysics.solve_aim(from, maxf(vel.length(), MIN_ASSIST_SPEED), spin, target)
	return {"kind": "pitch", "vel": vel, "spin": spin, "scaled": scaled, "est": est, "shape": shape, "funnel": funnel,
		"hand_sign": hand_sign, "delivery": delivery, "flutter": float(shape.get("flutter", 0.0)), "knuckle": bool(shape.get("knuckle", false)),
		"overthrow": over}


## How far past your usual effort a throw was: 0 up to your usual speed + 1 sd, 1 at + 2 sd and beyond.
static func overthrow(hand_speed: float, usual: float, spread: float) -> float:
	var sd := maxf(spread, 1.0)
	return clampf((hand_speed - (usual + sd)) / sd, 0.0, 1.0)


## Your top hand speed: the 90th percentile of your recent pitches, or your usual + 1.28 sd until enough are in.
func top_speed() -> float:
	var usual := wrist.mean_speed
	if _speeds.size() < TOP_MIN_THROWS:
		return usual + 1.28 * wrist.sd_speed
	var s := _speeds.duplicate()
	s.sort()
	return maxf(float(s[int(floor(0.9 * (s.size() - 1)))]), usual + 1.0)


func _remember_speed(hand_speed: float) -> void:
	_speeds.append(hand_speed)
	if _speeds.size() > TOP_MEMORY:
		_speeds.remove_at(0)


## BAND velocity, in league miles per hour (the radar's): your usual hand speed is the middle of your
## pitcher's band and your top speed is its top. Slower throws scale down in proportion (a half-speed lob is
## half the speed); harder than your top keeps rising at half the rate, up to 3 mph more.
func band_mph(hand_speed: float) -> float:
	var mid := BAND_MID_AT_0 + BAND_MID_PER_POINT * velocity_rating
	var hi := mid + BAND_WIDTH
	var usual := maxf(wrist.mean_speed, 1.0)
	var top := maxf(top_speed(), usual + 0.5)
	if hand_speed <= usual:
		return mid * hand_speed / usual
	if hand_speed <= top:
		return lerpf(mid, hi, (hand_speed - usual) / (top - usual))
	return minf(hi + 0.5 * BAND_WIDTH * (hand_speed - top) / (top - usual), hi + 3.0)


## Your usual pitch speed in this game's miles per hour (the pitch namer judges a changeup against it).
func typical_mph() -> float:
	if int(knobs.get("velocity_mode") if knobs.get("velocity_mode") != null else 0) == 1:
		return (BAND_MID_AT_0 + BAND_MID_PER_POINT * velocity_rating) * AIPitcher.GAME_SPEED
	return wrist.typical_mph(float(knobs.velocity_gain))


## A left-hander starts from the mirror image of the usual aim (until his own throws teach it otherwise).
func mirror_aim() -> void:
	aim_mu.x = -aim_mu.x


## You let go (or the ball was dropped): nothing is held any more.
func drop() -> void:
	held = false
	delivery_start = -1.0
	_hand_prev_t = -1.0


## Where the pitch should cross the plate: `center` (the catcher's glove, or the zone center) plus how far
## this throw's aim differs from your usual aim, measured against a scatter between your own and the
## reference one (`aim_reference`), with the wild tail squeezed. Hands not travelling toward the plate give
## the center. Always returns a target. Also learns your usual aim. `effort` widens the miss (overthrowing).
func funnel_target(release_t: float, tired: float, command_scale: float, center: Vector2 = ZONE_CENTER, effort: float = 1.0) -> Dictionary:
	var a = detector.position_at(release_t - FUNNEL_FROM)
	var b = detector.position_at(release_t - FUNNEL_TO)
	var middle := Vector3(center.x, center.y, 0.0)
	if a == null or b == null:
		return {"target": middle, "fallback": true}
	var d: Vector3 = (b as Vector3) - (a as Vector3)
	var travel := d.length()
	if travel < 0.03 or d.z / travel > -0.2:
		return {"target": middle, "fallback": true}
	var x := Vector2(rad_to_deg(atan2(d.x, -d.z)), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))
	var z_raw := (x - aim_mu) / aim_sigma            # against your own scatter: decides what is learned
	var reference := float(knobs.get("aim_reference") if knobs.get("aim_reference") != null else 0.0)
	var z := miss_z(x, aim_mu, aim_sigma, reference)
	# A tired arm is less exact: the same wobble lands further from where you meant it.
	var wobble := (1.0 + 0.30 * tired) * effort
	var target := Vector3(
		clampf(center.x + z.x * float(knobs.funnel_spread_x) * wobble * command_scale, -2.0, 2.0),
		clampf(center.y + z.y * float(knobs.funnel_spread_y) * wobble * command_scale, 0.0, 2.6), 0.0)
	var out := {"target": target, "fallback": false, "angle": x, "z": z, "mu_before": aim_mu, "sigma_before": aim_sigma,
		"center": center, "reference": reference}
	# Learn. The first throws calibrate fast and accept nearly anything; later ones skip
	# deliberate outliers so a one-off wild throw does not redefine "usual".
	var gate := 5.0 if aim_n < 15 else 3.5
	if absf(z_raw.x) <= gate and absf(z_raw.y) <= gate:
		var rate := maxf(1.0 / (aim_n + 3.0), float(knobs.aim_learn_rate))
		var dev := x - aim_mu
		aim_mu += dev * rate
		var v := aim_sigma * aim_sigma
		v += (dev * dev - v) * rate
		aim_sigma = Vector2(maxf(2.0, sqrt(v.x)), maxf(2.0, sqrt(v.y)))
		aim_n += 1
	return out


## How far a throw's aim `angle` is from your `usual` one, in standard deviations of a scatter between your
## `own` and REFERENCE_SIGMA (`reference` 0 = yours, 1 = the reference, geometric in between), clamped at 4
## and squeezed beyond MISS_KNEE.
static func miss_z(angle: Vector2, usual: Vector2, own: Vector2, reference: float) -> Vector2:
	var r := clampf(reference, 0.0, 1.0)
	var sig := Vector2(pow(own.x, 1.0 - r) * pow(REFERENCE_SIGMA.x, r), pow(own.y, 1.0 - r) * pow(REFERENCE_SIGMA.y, r))
	var z := (angle - usual) / sig
	return Vector2(squeeze_miss(clampf(z.x, -4.0, 4.0)), squeeze_miss(clampf(z.y, -4.0, 4.0)))


## A miss of `z` standard deviations with the part beyond MISS_KNEE growing at 0.4 the rate.
static func squeeze_miss(z: float) -> float:
	if absf(z) <= MISS_KNEE:
		return z
	return signf(z) * (MISS_KNEE + 0.4 * (absf(z) - MISS_KNEE))


## One JSON line per throw: what the arm did, what the assist did, where it went. `ctx` is what the scene
## knows: head_pos, head_fwd, hand_fwd, tag, auto, batter_profile, game ({inning, outs, balls, strikes, bases, batter}).
func log_entry(ctx: Dictionary, pitch: LivePitch, from: Vector3, release_t: float, latency: float, est: Dictionary, scaled: Vector3, spin: Vector3, funnel: Dictionary, shape: Dictionary) -> Dictionary:
	var raw: Vector3 = est.velocity
	var series := []
	for back_ms in [0, 20, 40, 60, 80, 120, 160]:
		var e := detector.estimate(release_t, latency + back_ms / 1000.0)
		if e.valid:
			var ev: Vector3 = e.velocity
			series.append({"back_ms": back_ms, "speed": snappedf(ev.length(), 0.01),
				"elev": snappedf(ThrowLogger.elevation_deg(ev), 0.1), "azim": snappedf(ThrowLogger.azimuth_deg(ev), 0.1)})
	var samples := []
	for smp in detector.recent(release_t - 0.55):
		samples.append({"ms": roundi((smp.t - release_t) * 1000.0), "p": ThrowLogger.vec(smp.p),
			"f": ThrowLogger.vec(smp.f), "q": _quat(smp.q), "g": snappedf(smp.g, 0.01)})
	var head: Vector3 = ctx.head_pos
	var dir := scaled.normalized()
	var entry := {
		"time": Time.get_datetime_string_from_system(),
		"mode": "auto" if ctx.auto else "grip",
		"aim_mode": ["PURE", "HAND_ASSIST", "FUNNEL"][int(knobs.aim_mode)],
		"spin_mode": ["RAW", "WRIST_MODEL"][int(knobs.spin_mode)],
		"tag": ctx.tag,
		"pitch_name": pitch.label,
		"gains": {"velocity": knobs.velocity_gain, "spin": knobs.spin_gain, "assist": knobs.aim_assist,
			"funnel_x": knobs.funnel_spread_x, "funnel_y": knobs.funnel_spread_y, "velocity_latency": latency, "spin_latency": knobs.spin_latency},
		"release_pos": ThrowLogger.vec(from),
		"head_pos": ThrowLogger.vec(head),
		"hand_minus_head": ThrowLogger.vec(from - head),
		"head_fwd": ThrowLogger.vec(ctx.head_fwd),
		"hand_fwd": ThrowLogger.vec(ctx.hand_fwd),
		"grip_at_release": snappedf(last_grip, 0.01),
		"raw": {"vel": ThrowLogger.vec(raw), "speed": snappedf(raw.length(), 0.01),
			"elev": snappedf(ThrowLogger.elevation_deg(raw), 0.1), "azim": snappedf(ThrowLogger.azimuth_deg(raw), 0.1),
			"spin": ThrowLogger.vec(est.spin)},
		"series": series,
		"scaled_mph": snappedf(scaled.length() * PitchPhysics.MPS_TO_MPH, 0.1),
		"final_vel": ThrowLogger.vec(pitch.vel),
		"final_elev": snappedf(ThrowLogger.elevation_deg(pitch.vel), 0.1),
		"samples": samples,
	}
	if dir.z < -0.01:
		entry["pointed_plate"] = ThrowLogger.vec(from + dir * (from.z / -dir.z))
	var unassisted := PitchPhysics.fly_to_plate(from, scaled, spin, true, 3.0, -100.0)
	if unassisted.reached:
		entry["unassisted_plate"] = ThrowLogger.vec(unassisted.pos)
	if not shape.is_empty():
		entry["wrist"] = {"z_snap": snappedf(shape.z_snap, 0.01), "z_side": snappedf(shape.z_side, 0.01),
			"z_gyro": snappedf(shape.z_gyro, 0.01), "z_slot": snappedf(shape.z_slot, 0.01),
			"tilt_deg": snappedf(shape.tilt_deg, 0.1), "stiff": snappedf(shape.stiff, 0.01),
			"flutter": snappedf(shape.flutter, 0.01), "push": snappedf(shape.push, 0.01), "z_wind": snappedf(shape.z_wind, 0.01), "spin_rpm": snappedf(spin.length() / PitchPhysics.RPM_TO_RADS, 1.0),
			"technique_gain": knobs.technique_gain,
			"baseline": {"snap": snappedf(wrist.mean_snap, 0.001), "side": snappedf(wrist.mean_side, 0.001),
				"gyro": snappedf(wrist.mean_gyro, 0.001), "mag": snappedf(wrist.mean_mag, 0.001),
				"slot": snappedf(wrist.mean_slot, 0.001), "speed": snappedf(wrist.mean_speed, 0.001)}}
	if funnel.has("target"):
		var f := {"target": ThrowLogger.vec(funnel.target), "fallback": funnel.fallback}
		if funnel.has("center"):
			var c: Vector2 = funnel.center
			f["center"] = [snappedf(c.x, 0.001), snappedf(c.y, 0.001)]
			f["reference"] = funnel.reference
		if not funnel.fallback:
			var ang: Vector2 = funnel.angle
			var zz: Vector2 = funnel.z
			var mb: Vector2 = funnel.mu_before
			var sb: Vector2 = funnel.sigma_before
			f["az"] = snappedf(ang.x, 0.01)
			f["el"] = snappedf(ang.y, 0.01)
			f["z"] = [snappedf(zz.x, 0.01), snappedf(zz.y, 0.01)]
			f["mu_before"] = [snappedf(mb.x, 0.01), snappedf(mb.y, 0.01)]
			f["sigma_before"] = [snappedf(sb.x, 0.01), snappedf(sb.y, 0.01)]
		entry["funnel"] = f
	var bt: Dictionary = pitch.bat
	var bl := {"profile": ctx.batter_profile, "swing": bt.get("swing", false), "kind": bt.get("kind", "take"),
		"p_swing": snappedf(bt.get("p_swing", 0.0), 0.001)}
	if bt.get("swing", false):
		bl["t_err_ms"] = snappedf(float(bt.get("t_err", 0.0)) * 1000.0, 0.1)
		bl["dy"] = snappedf(bt.get("dy", 0.0), 0.001)
		bl["dx"] = snappedf(bt.get("dx", 0.0), 0.001)
		bl["z_m"] = snappedf(bt.get("z_m", 0.0), 0.001)
	if not pitch.sim.is_empty():
		var sm: Dictionary = pitch.sim
		bl["ev_mph"] = snappedf(sm.ev_mph, 0.1)
		bl["launch"] = snappedf(sm.launch, 0.1)
		bl["spray"] = snappedf(sm.spray, 0.1)
		bl["distance"] = snappedf(sm.distance, 0.1)
		bl["hang"] = snappedf(sm.hang_time, 0.01)
		bl["apex"] = snappedf(sm.apex, 0.1)
		bl["fair"] = sm.fair
		bl["home_run"] = sm.home_run
		if not pitch.play.is_empty():
			bl["play"] = pitch.play.get("result", "")
			bl["play_text"] = pitch.play.get("text", "")
	entry["batter"] = bl
	entry["game"] = ctx.game
	var a := pitch.analysis
	entry["result"] = {"reached": a.reached, "strike": a.get("strike", false),
		"plate": ThrowLogger.vec(a.plate_pos) if a.reached else null}
	return entry


## A rotation for the log, [x, y, z, w]: with it the wrist's roll can be recomputed from old logs (the pointing
## direction alone loses it).
static func _quat(q: Quaternion) -> Array:
	return [snappedf(q.x, 0.0001), snappedf(q.y, 0.0001), snappedf(q.z, 0.0001), snappedf(q.w, 0.0001)]
