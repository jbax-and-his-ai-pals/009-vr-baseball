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

var knobs: Object                          # the scene: velocity_gain, funnel_spread_x, aim_mode, ...
var detector := ThrowDetector.new()
var wrist := WristModel.new()
## Learned usual aim direction (degrees right / up of straight at the plate) and how much it scatters.
## Start from a recorded player; the first throws calibrate them quickly.
var aim_mu := Vector2(4.4, -0.3)
var aim_sigma := Vector2(6.0, 5.5)
var aim_n := 0
var held := false                          # the ball is in your hand
var delivery_start := -1.0                 # when your motion began (seconds), -1 if it has not
var last_grip := 0.0
var _hand_prev := Vector3.ZERO
var _hand_prev_t := -1.0


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
##   {"kind": "pickoff", "base", "err", "vel"}         thrown toward a base
##   {"kind": "pitch", "vel", "spin", "scaled", "est", "shape", "funnel", "hand_sign", "delivery",
##    "flutter", "knuckle"}                            a pitch for the scene to launch
## `tired` is your arm's fatigue 0..1, `command_scale` the career pitcher's aim factor (1.0 otherwise),
## `camera_y` the head height (for the arm slot).
func throw(release_t: float, vel_latency: float, spin_latency: float, from: Vector3, camera_y: float,
		tired: float, command_scale: float, runners_on: bool) -> Dictionary:
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
			return {"kind": "pickoff", "base": int(pk.base), "err": float(pk.err), "vel": est.velocity as Vector3}
	var delivery := clampf(release_t - began_at, 0.25, 3.0) if started else 0.9
	var vel: Vector3 = (est.velocity as Vector3) * float(knobs.velocity_gain) * (1.0 - 0.06 * tired)
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
	var funnel := {}
	match int(knobs.aim_mode):
		1:                                                    # AimMode.HAND_ASSIST
			vel = PitchPhysics.assist_velocity(from, vel, spin, float(knobs.aim_assist))
		2:                                                    # AimMode.FUNNEL
			funnel = funnel_target(release_t, tired, command_scale)
			var target: Vector3 = funnel.target
			vel = PitchPhysics.solve_aim(from, maxf(vel.length(), MIN_ASSIST_SPEED), spin, target)
	return {"kind": "pitch", "vel": vel, "spin": spin, "scaled": scaled, "est": est, "shape": shape, "funnel": funnel,
		"hand_sign": hand_sign, "delivery": delivery, "flutter": float(shape.get("flutter", 0.0)), "knuckle": bool(shape.get("knuckle", false))}


## A left-hander starts from the mirror image of the usual aim (until his own throws teach it otherwise).
func mirror_aim() -> void:
	aim_mu.x = -aim_mu.x


## You let go (or the ball was dropped): nothing is held any more.
func drop() -> void:
	held = false
	delivery_start = -1.0
	_hand_prev_t = -1.0


## Where the pitch should cross the plate: the zone center plus how far this throw's aim differs from
## your usual aim, measured in units of your own scatter. Hands not travelling toward the plate give a
## centered target. Always returns a target. Also learns your usual aim.
func funnel_target(release_t: float, tired: float, command_scale: float) -> Dictionary:
	var a = detector.position_at(release_t - FUNNEL_FROM)
	var b = detector.position_at(release_t - FUNNEL_TO)
	var center := Vector3(ZONE_CENTER.x, ZONE_CENTER.y, 0.0)
	if a == null or b == null:
		return {"target": center, "fallback": true}
	var d: Vector3 = (b as Vector3) - (a as Vector3)
	var travel := d.length()
	if travel < 0.03 or d.z / travel > -0.2:
		return {"target": center, "fallback": true}
	var x := Vector2(rad_to_deg(atan2(d.x, -d.z)), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))
	var z_raw := (x - aim_mu) / aim_sigma
	# A very erratic throw is allowed to be very wrong: clamp wide, not tight.
	var z := Vector2(clampf(z_raw.x, -4.0, 4.0), clampf(z_raw.y, -4.0, 4.0))
	# A tired arm is less exact: the same wobble lands further from where you meant it.
	var wobble := 1.0 + 0.30 * tired
	var target := Vector3(
		clampf(ZONE_CENTER.x + z.x * float(knobs.funnel_spread_x) * wobble * command_scale, -2.0, 2.0),
		clampf(ZONE_CENTER.y + z.y * float(knobs.funnel_spread_y) * wobble * command_scale, 0.0, 2.6), 0.0)
	var out := {"target": target, "fallback": false, "angle": x, "z": z, "mu_before": aim_mu, "sigma_before": aim_sigma}
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
			"f": ThrowLogger.vec(smp.f), "g": snappedf(smp.g, 0.01)})
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
