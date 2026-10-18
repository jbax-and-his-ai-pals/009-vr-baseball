class_name BatterAI
extends RefCounted
## Decides whether to swing at a pitch and, if so, what the bat does.
##
## Everything is derived from a BatterProfile and from the pitch's actual flight:
##  1. PERCEIVE: the batter sees where the pitch will cross with noise (smaller for a
##     better eye, larger for pitches that move a lot or flutter).
##  2. DECIDE: swing probability from how far outside the zone it *looks*; aggression raises
##     it, a good eye makes chasing rare.
##  3. TIME: he swings for the pitch speed he expects (an average of recent pitches). The
##     part of a speed change he fails to read becomes an early/late swing, so changeups beat
##     low-recognition batters and a fastball after a changeup beats them again.
##  4. AIM: the bat plane and the point along the bat are aimed at the perceived location
##     with an error that shrinks with contact skill.
##  5. COLLIDE: compare the ball's real position with the bat. Vertical offset sets launch
##     angle and spin, timing sets spray direction, offset along the bat sets how well it
##     is struck. Whiff, foul tip, or a batted ball.
## The batter is right-handed (pull = left field, +X in this game's coordinates).

const R_SUM := 0.0685            # ball radius + barrel radius
const ZONE_HALF_W := PitchPhysics.ZONE_HALF_W + PitchPhysics.BALL_RADIUS
const ZONE_BOTTOM := PitchPhysics.ZONE_BOTTOM - PitchPhysics.BALL_RADIUS
const ZONE_TOP := PitchPhysics.ZONE_TOP + PitchPhysics.BALL_RADIUS
const MAX_EXIT_MPS := 53.0

var profile: BatterProfile
var rng := RandomNumberGenerator.new()
## The batter's running idea of how long a pitch takes to reach the plate.
var expected_time := 0.60
## Debug: always swing, with no timing or aim error, so a swing can be inspected.
var debug_perfect := false
## Tests: always (or never) bunt when given a situation.
var force_bunt := false
var force_no_bunt := false


func _init(p: BatterProfile = null) -> void:
	profile = p if p != null else BatterProfile.by_name("Journeyman")
	rng.randomize()


## Sacrifice bunt: a runner on first or second, fewer than two outs, fewer than two strikes,
## and a hitter who is no great threat to drive the ball. Returns false with no situation given.
func _wants_bunt(sit: Dictionary) -> bool:
	if sit.is_empty() or force_no_bunt:
		return false
	var on: Array = sit.get("bases", [false, false, false])
	if not (on[0] or on[1]):
		return false
	if int(sit.get("outs", 0)) >= 2 or int(sit.get("strikes", 0)) >= 2:
		return false
	var skill := 1.0 - clampf(profile.power, 0.0, 1.0)
	var p := 0.03 + 0.32 * skill * skill * (0.5 + 0.5 * profile.contact)
	if force_bunt:
		return true
	return rng.randf() < p


## The ball is bunted: a slow roller down one line, a pop-up when he gets under it, a foul when
## he gets only a piece of it.
func _bunt_contact(out: Dictionary, dx: float, dy: float, p: Vector3) -> Dictionary:
	out["kind"] = "hit"
	out["contact"] = true
	out["bat_target"] = p
	out["bunt"] = true
	var square := 1.0 - 0.5 * clampf(absf(dy) / R_SUM, 0.0, 1.0) - 0.4 * clampf(absf(dx) / 0.3, 0.0, 1.0)
	var fouled := absf(dx) > 0.16 or (absf(dy) > 0.7 * R_SUM and rng.randf() < 0.55)
	var speed := rng.randf_range(4.5, 9.0) * (0.6 + 0.4 * square)
	var la := rng.randf_range(-14.0, 4.0) - (dy / R_SUM) * 28.0
	if dy < -0.45 * R_SUM:
		la = rng.randf_range(32.0, 58.0)               # under it: a pop-up
	la = clampf(la, -30.0, 70.0)
	var psi := rng.randf_range(6.0, 28.0) * (1.0 if rng.randf() < 0.55 else -1.0)
	if fouled:
		psi = rng.randf_range(50.0, 72.0) * (1.0 if rng.randf() < 0.5 else -1.0)
	var psi_r := deg_to_rad(psi)
	var la_r := deg_to_rad(la)
	var dir_h := Vector3(sin(psi_r), 0.0, cos(psi_r))
	out["vel"] = dir_h * (speed * cos(la_r)) + Vector3.UP * (speed * sin(la_r))
	out["spin"] = dir_h.cross(Vector3.UP).normalized() * (600.0 * PitchPhysics.RPM_TO_RADS)
	out["ev"] = speed * PitchPhysics.MPS_TO_MPH
	out["la"] = la
	out["spray"] = psi
	out["bat_speed_mph"] = 8.0
	return out


## pitch: {release: Vector3, vel: Vector3, spin: Vector3, flutter_amp, flutter_seed,
##         analysis: PitchPhysics.analyze() result}
func evaluate(pitch: Dictionary) -> Dictionary:
	var a: Dictionary = pitch.analysis
	var out := {"swing": false, "contact": false, "kind": "take", "p_swing": 0.0}
	if not a.get("reached", false):
		return out
	var t_cross: float = a.time
	var plate: Vector3 = a.plate_pos
	var flutter: float = pitch.get("flutter_amp", 0.0)

	# 1. Perceive. Movement and flutter make a pitch harder to read; good recognition helps.
	# Judge movement beyond what a normal fastball does, and at a reference flight time
	# (break grows with flight time squared, so slow pitches break more for the same spin).
	var k_time := clampf(pow(t_cross / 0.6, 2.0), 0.6, 3.0)
	var ivb_n: float = a.get("ivb_in", 0.0) / k_time
	var hb_n: float = a.get("hb_in", 0.0) / k_time
	var move_in := sqrt(pow(ivb_n - 10.0, 2.0) + hb_n * hb_n)
	# Speed: less time to read and react. Relative to this game's ordinary pitch (~58 mph).
	var speed_diff := maxf(float(a.get("plate_mph", 58.0)) - 58.0, 0.0) * 0.010 * (1.2 - 0.4 * profile.timing)
	var diff := 1.0 + speed_diff + (1.0 - profile.recognition) * 0.04 * move_in \
		+ (flutter / 12.0) * lerpf(1.2, 0.5, profile.recognition)
	var sigma_p := lerpf(0.20, 0.035, profile.eye) * diff
	var perceived := Vector2(plate.x + rng.randfn(0.0, sigma_p), plate.y + rng.randfn(0.0, sigma_p))

	# 2. Decide. In a bunting situation he squares around instead of swinging away.
	var bunt := _wants_bunt(pitch.get("situation", {}))
	var dxo := maxf(absf(perceived.x) - ZONE_HALF_W, 0.0)
	var dyo := maxf(maxf(ZONE_BOTTOM - perceived.y, perceived.y - ZONE_TOP), 0.0)
	var d_out := sqrt(dxo * dxo + dyo * dyo)
	var p_swing: float
	if d_out <= 0.0:
		p_swing = lerpf(0.45, 0.92, profile.aggression)
	else:
		p_swing = pow(1.0 - profile.eye, 1.6) * lerpf(0.6, 1.4, profile.aggression) * exp(-d_out / 0.22)
	if bunt:
		# He offers at strikes and lets the rest go by.
		p_swing = 0.92 if d_out <= 0.0 else 0.04
	p_swing = clampf(p_swing, 0.0, 0.95)
	out["p_swing"] = p_swing
	out["bunt"] = bunt
	out["perceived"] = perceived
	out["d_out"] = d_out
	var swing := rng.randf() < p_swing or debug_perfect

	# Update what he expects either way: he sees every pitch.
	var prev_expected := expected_time
	expected_time = lerpf(expected_time, t_cross, 0.35)
	if not swing:
		return out
	out["swing"] = true
	out["kind"] = "whiff"

	# 3. Timing: systematic miss from a speed he did not adjust to, plus random jitter.
	# Squared: a batter who reads speed well adjusts almost completely; a poor one barely at all.
	var t_sys := (prev_expected - t_cross) * pow(1.0 - profile.recognition, 2.0)
	var sigma_t := lerpf(0.028, 0.006, profile.timing)
	var t_err := clampf(t_sys + rng.randfn(0.0, sigma_t), -0.25, 0.12)
	if debug_perfect:
		t_err = 0.0
	var t_contact := t_cross + t_err
	out["t_err"] = t_err
	out["contact_time"] = t_contact

	# 4. Aim the bat plane and the sweet spot.
	# He tracks the ball into the zone, so aim error is about bat control, not about the
	# first-glance estimate used for the swing decision.
	# Even the best bat control has a floor, and pitches off the heart of the zone are harder
	# to meet squarely.
	var true_dx := maxf(absf(plate.x) - ZONE_HALF_W, 0.0)
	var true_dy := maxf(maxf(ZONE_BOTTOM - plate.y, plate.y - ZONE_TOP), 0.0)
	var off_zone := sqrt(true_dx * true_dx + true_dy * true_dy)
	# Where in the zone it crosses: the middle is easy to square up, the edges and corners are
	# not. 0 is dead center, 1 is the edge of the strike zone (beyond that, off_zone takes over).
	var zone_mid_y := 0.5 * (PitchPhysics.ZONE_TOP + PitchPhysics.ZONE_BOTTOM)
	var zone_half_h := 0.5 * (PitchPhysics.ZONE_TOP - PitchPhysics.ZONE_BOTTOM)
	var edge := clampf(maxf(absf(plate.x) / PitchPhysics.ZONE_HALF_W, absf(plate.y - zone_mid_y) / zone_half_h), 0.0, 1.0)
	out["edge"] = edge
	# Better contact hitters are hurt less by the edges.
	var edge_penalty := lerpf(0.40, 0.20, profile.contact)
	var sigma_a := lerpf(0.078, 0.030, profile.contact) * diff * (1.0 + 2.5 * off_zone) 		* (1.0 - 0.10 + (edge_penalty + 0.10) * edge)
	var bat_y := plate.y + rng.randfn(0.0, sigma_a)
	var sweet_x := plate.x + rng.randfn(0.0, sigma_a * 1.5)
	if debug_perfect:
		bat_y = plate.y
		sweet_x = plate.x

	# 5. Collide. The barrel sweet spot reaches the plate plane at t_contact. The ball is then
	# at z_T; bat and ball close on each other, so they actually meet partway between, at z_m,
	# earlier along the ball's path when the swing was early. The bat travels on an upward
	# path (attack angle), so its height at the meeting point is bat_y + z_m * tan(attack),
	# while the ball is still descending; the mismatch of those two slopes is what makes
	# timing errors survivable.
	var bat_speed := lerpf(29.5, 38.5, profile.power)
	var flutter_seed: float = pitch.get("flutter_seed", 0.0)
	var at_swing := PitchPhysics.state_at(pitch.release, pitch.vel, pitch.spin, t_contact, flutter, flutter_seed)
	var z_t: float = at_swing.pos.z
	var speed_z := maxf(absf((at_swing.vel as Vector3).z), 5.0)
	var z_m := z_t * bat_speed / (bat_speed + speed_z)
	var t_meet := t_contact + (z_t - z_m) / speed_z
	var st := PitchPhysics.state_at(pitch.release, pitch.vel, pitch.spin, t_meet, flutter, flutter_seed)
	var p: Vector3 = st.pos
	var v_in: Vector3 = st.vel
	# Good hitters match their swing plane to how steeply the pitch is coming down (slow
	# pitches fall much more steeply than fast ones); weaker ones swing their usual way.
	var at_plate := PitchPhysics.state_at(pitch.release, pitch.vel, pitch.spin, t_cross, flutter, flutter_seed)
	var pv: Vector3 = at_plate.vel
	var descent := rad_to_deg(atan2(-pv.y, Vector2(pv.x, pv.z).length()))
	var matched := clampf(descent + (profile.attack_angle - 10.0) + 1.0, 0.0, 28.0)
	var attack := lerpf(profile.attack_angle, matched, 0.8 * profile.recognition) + rng.randfn(0.0, 2.0)
	var bat_at_meet := bat_y + z_m * tan(deg_to_rad(attack))
	var dy := p.y - bat_at_meet
	var dx := p.x - sweet_x
	out["dx"] = dx
	out["dy"] = dy
	out["z_m"] = z_m
	out["contact_pos"] = p
	out["contact_time"] = t_meet
	# Where the barrel's sweet spot is at the meeting time: on the ball for a hit, and where he
	# aimed for a whiff (so the swing visibly passes above, below or beside the ball).
	out["bat_target"] = Vector3(sweet_x, bat_at_meet, z_m)
	var reachable := absf(dx) <= 0.35 and z_m >= -0.40 and z_m <= 0.55
	if absf(dy) > R_SUM or not reachable:
		return out
	if bunt:
		return _bunt_contact(out, dx, dy, p)

	var grazing := absf(dy) > 0.88 * R_SUM or absf(dx) > 0.24
	if grazing:
		out["kind"] = "foul tip"
		out["contact"] = true
		out["bat_target"] = p
		var tip := rng.randf_range(8.0, 24.0)
		var vel := Vector3(rng.randf_range(-0.25, 0.25), 0.35, -0.9).normalized() * tip
		out["vel"] = vel
		out["spin"] = Vector3.ZERO
		out["ev"] = tip * PitchPhysics.MPS_TO_MPH
		out["la"] = BattedBall.launch_degrees(vel)
		out["spray"] = 180.0
		return out

	out["kind"] = "hit"
	out["contact"] = true
	out["bat_target"] = p
	var f_sweet := maxf(0.40, 1.0 - 4.5 * dx * dx)
	var f_vert := sqrt(maxf(0.0, 1.0 - pow(dy / R_SUM, 2.0)))
	var f_time := 1.0 - 0.4 * minf(absf(z_m), 0.4)
	# A pitch down the middle can be hit square; one on the corner is hit with less of the barrel.
	var f_loc := lerpf(1.08, 0.99, pow(float(out.get("edge", 0.0)), 1.5))
	var ev := 0.2 * v_in.length() + 1.2 * bat_speed * f_sweet * f_vert * f_time * f_loc
	ev = minf(ev, MAX_EXIT_MPS)
	var la := attack - (dy / R_SUM) * 46.0 + rng.randfn(0.0, 3.0)
	# Some contact is just under the ball or off the end of the bat: a lazy, high pop-up.
	if rng.randf() < 0.08:
		la += rng.randf_range(22.0, 38.0)
		ev *= 0.78
	la = clampf(la, -35.0, 78.0)
	var psi := (z_m / 0.30) * 35.0 + rng.randfn(0.0, 2.0)
	var psi_r := deg_to_rad(psi)
	var la_r := deg_to_rad(la)
	var dir_h := Vector3(sin(psi_r), 0.0, cos(psi_r))
	var vel_out := dir_h * (ev * cos(la_r)) + Vector3.UP * (ev * sin(la_r))
	# Backspin when the bat gets under the ball, topspin when it gets on top. A little
	# sidespin from striking away from the sweet spot.
	var back_rpm := clampf(1800.0 - (dy / R_SUM) * 2600.0, -1500.0, 4600.0)
	var side_rpm := clampf(dx / 0.15 * 600.0, -900.0, 900.0)
	var back_axis := dir_h.cross(Vector3.UP).normalized()
	var spin := back_axis * (back_rpm * PitchPhysics.RPM_TO_RADS) + Vector3.UP * (side_rpm * PitchPhysics.RPM_TO_RADS)
	out["vel"] = vel_out
	out["spin"] = spin
	out["ev"] = ev * PitchPhysics.MPS_TO_MPH
	out["la"] = la
	out["spray"] = psi
	out["bat_speed_mph"] = bat_speed * PitchPhysics.MPS_TO_MPH
	return out
