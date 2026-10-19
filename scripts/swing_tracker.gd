class_name SwingTracker
extends RefCounted
## Turns the controller's pose each frame into a bat: where the knob and the tip are, and how fast each
## is moving (from the change in position and in orientation). Pure: feed it (time, position, rotation).
##
## The bat is held like the controller points: the knob is at the hand and the barrel extends along the
## controller's forward direction (-Z) by BatPhysics.LENGTH, tilted by `pitch_deg` so a natural wrist
## angle lays the bat up rather than straight out.

var pitch_deg := 35.0                    # raise the barrel this much above where the controller points
var knob := Vector3.ZERO
var tip := Vector3.ZERO
var knob_vel := Vector3.ZERO
var tip_vel := Vector3.ZERO
var _have := false
var _t := 0.0
var _smooth := 0.5                      # blend with the last velocity (controller poses are noisy)


func reset() -> void:
	_have = false
	knob_vel = Vector3.ZERO
	tip_vel = Vector3.ZERO


## The bat's direction for a controller rotation.
func direction(rot: Quaternion) -> Vector3:
	var fwd := rot * Vector3(0.0, 0.0, -1.0)
	var up := rot * Vector3.UP
	return (fwd * cos(deg_to_rad(pitch_deg)) + up * sin(deg_to_rad(pitch_deg))).normalized()


func update(t: float, pos: Vector3, rot: Quaternion) -> void:
	var dir := direction(rot)
	var new_knob := pos
	var new_tip := pos + dir * BatPhysics.LENGTH
	if _have and t > _t:
		var dt := t - _t
		var kv := (new_knob - knob) / dt
		var tv := (new_tip - tip) / dt
		knob_vel = knob_vel.lerp(kv, 1.0 - _smooth)
		tip_vel = tip_vel.lerp(tv, 1.0 - _smooth)
	knob = new_knob
	tip = new_tip
	_t = t
	_have = true


## How fast the barrel's middle is moving, in m/s (what a swing "is").
func barrel_speed() -> float:
	return BatPhysics.bat_point_velocity(knob_vel, tip_vel, BatPhysics.SWEET).length()
