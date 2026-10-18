class_name CartoonBatter
extends Node3D
## A cartoon batter in the batter's box: a Doll (the shared skeleton) holding a bat in both hands,
## with the swing driven to wherever the ball actually is.
##
## Local frame: +Y up, +Z the way his chest faces (toward the plate), +X toward the pitcher
## (his lead side), -X toward the catcher. _ready turns the node so +Z points at the plate.
##
## Draw calls: the Doll (one skinned mesh) and the bat = 2.
##
## swing_to(point, contact_in) puts the bat's sweet spot at `point` (world space) exactly
## `contact_in` seconds from now. For a hit that point is the ball; for a whiff it is where he
## aimed, so the bat visibly passes above or below the ball. The bat is a prop that goes exactly
## where the game says; the arms are solved to hold it, so the picture never disagrees with the
## physics. Also: bunt_to (square around), check_swing (starts, stops), flinch, drop_bat, set_carry
## (the bat hangs at his side while he walks up).

@export var right_handed := true
@export var shirt_color := Color(0.84, 0.16, 0.18)
@export var pants_color := Color(0.92, 0.92, 0.94)
@export var helmet_color := Color(0.12, 0.17, 0.50)

const SHOULDER_Y := 1.57
const SWEET_SPOT := 0.60        # knob to sweet spot along the bat
const REACH := 0.62             # how far from the shoulders the hands can get
const T_CONTACT := 0.15         # seconds from the start of the swing to contact
const T_FOLLOW := 0.32          # ...to the end of the follow-through
const HOLD := 0.9               # seconds held in the follow-through before resetting
const RESET := 0.45
const FACE_PITCHER := 80.0      # degrees the head is turned from the chest toward the pitcher

const REST_HANDS := Vector3(-0.20, 1.50, 0.12)
const REST_DIR := Vector3(-0.42, 0.91, 0.0)
const CARRY_HANDS := Vector3(-0.24, 0.80, 0.14)
const CARRY_DIR := Vector3(-0.10, -0.92, 0.38)

var doll: Doll
var _bat: MeshInstance3D

var _active := false
var _carry := 0.0            # 0 bat up in the stance .. 1 bat hanging low, as he walks to the box
var _carry_goal := 0.0
var _t := 0.0
var _start_delay := 0.0
var _tc := T_CONTACT         # this swing's contact time and follow-through end (a bunt is slower)
var _tf := T_FOLLOW
var _mode := "swing"         # swing | bunt | check
var _contact_hands := REST_HANDS
var _contact_dir := REST_DIR
var _follow_hands := REST_HANDS
var _follow_dir := REST_DIR
var _yaw_contact := 0.0
var _yaw_follow := 0.0
var _h_low := Vector3.ZERO   # where each hand is on the bat, in this node's frame
var _h_up := Vector3.ZERO
var _wag := 0.0


## Where he stands in the box, as a transform. A right-hander is on the third-base side (+X) with
## his chest to the plate; a left-hander is the mirror image (the whole figure is flipped, so his
## lead side is still the one toward the pitcher and nothing else has to know).
static func home_transform(right: bool, x: float = 0.98) -> Transform3D:
	if right:
		return Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), Vector3(x, 0.0, 0.0))
	return Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)) * Basis.from_scale(Vector3(-1.0, 1.0, 1.0)), Vector3(-x, 0.0, 0.0))


func _ready() -> void:
	transform = home_transform(right_handed, absf(position.x))
	doll = Doll.create(self, Vector3.ZERO, shirt_color, pants_color, helmet_color, false, Doll.Style.SOFT, "batter")
	doll.crouch = 0.0
	doll.look_yaw = FACE_PITCHER
	_bat = MeshInstance3D.new()
	_bat.mesh = Figure.bat_mesh()
	_bat.material_override = MeshMerger.vertex_color_material()
	add_child(_bat)
	_apply_pose(REST_HANDS, REST_DIR, 0.0)


## Start a swing so the bat's sweet spot is at world_point contact_in seconds from now.
func swing_to(world_point: Vector3, contact_in: float) -> void:
	_plan(world_point, contact_in, "swing")


## Square around to bunt: the bat out in front, level, to meet the ball at world_point.
func bunt_to(world_point: Vector3, contact_in: float) -> void:
	_plan(world_point, contact_in, "bunt")


## Starts to swing and holds up: the bat comes about halfway and goes back.
func check_swing(world_point: Vector3, contact_in: float) -> void:
	_plan(world_point, contact_in, "check")


func _plan(world_point: Vector3, contact_in: float, mode: String) -> void:
	var p := to_local(world_point)
	var shoulders := Vector3(0.0, SHOULDER_Y - 0.12, 0.0)
	# Hands out in front of the chest toward the point, then the bat laid from the hands
	# through the point with the sweet spot exactly on it.
	var guess := shoulders + (p - shoulders).normalized() * 0.38
	var d := (p - guess).normalized()
	var hands := p - d * SWEET_SPOT
	var off := hands - shoulders
	if off.length() > REACH:                         # a pitch he cannot quite get to
		hands = shoulders + off.normalized() * REACH
		d = (p - hands).normalized()
	_mode = mode
	_contact_hands = hands
	_contact_dir = d
	_yaw_contact = deg_to_rad(70.0)
	_tc = T_CONTACT
	_tf = T_FOLLOW
	if mode == "bunt":
		# Level bat, feet and shoulders square to the pitcher; no follow-through.
		_yaw_contact = deg_to_rad(84.0)
		_tc = 0.30
		_tf = 0.42
		_follow_hands = hands
		_follow_dir = d
		_yaw_follow = _yaw_contact
	else:
		# Follow-through: the same pose swung on around the body.
		var around := Basis(Vector3.UP, deg_to_rad(85.0))
		_follow_hands = shoulders + around * (hands - shoulders)
		_follow_dir = (around * d + Vector3(0.0, 0.55, 0.0)).normalized()
		_yaw_follow = deg_to_rad(130.0)
	_start_delay = maxf(contact_in - _tc, 0.0)
	_t = -_start_delay
	_active = true


## World position of the bat's sweet spot right now (used to check the swing meets the ball).
func sweet_spot_world() -> Vector3:
	return to_global(_bat.position + _bat.basis.y.normalized() * SWEET_SPOT) if _bat else global_position


## The game decided contact happens now: put the bat exactly at its contact pose, so the picture
## agrees with the physics to the frame no matter where the frame boundary fell.
func snap_to_contact() -> void:
	if not _active or _mode == "check":
		return
	_t = _tc
	_apply_pose(_contact_hands, _contact_dir, _yaw_contact)


## A pitch at his body: he jerks away.
func flinch() -> void:
	if doll:
		doll.play("react", 0.5)


func reset() -> void:
	_active = false
	if _bat:
		_bat.visible = true
	_apply_rest()


## The bat leaves his hands (a hit, a walk). Returns its transform in the world so a prop can take over.
func drop_bat() -> Transform3D:
	var xf := _bat.global_transform if _bat else global_transform
	if _bat:
		_bat.visible = false
	return xf


## Walking to the box he lets the bat hang by his side; set false as he arrives and it comes up.
func set_carry(on: bool, instant: bool = false) -> void:
	_carry_goal = 1.0 if on else 0.0
	if instant:
		_carry = _carry_goal
		if not _active:
			_apply_rest()


func _apply_rest() -> void:
	var k := _carry * _carry * (3.0 - 2.0 * _carry)
	var dir := REST_DIR.normalized().slerp(CARRY_DIR.normalized(), k)
	var hands := REST_HANDS.lerp(CARRY_HANDS, k)
	# Waiting in the box he waggles the bat.
	var w := 1.0 - k
	hands += Vector3(0.0, sin(_wag * 2.6) * 0.022, sin(_wag * 1.9) * 0.02) * w
	dir = (dir + Vector3(sin(_wag * 2.1) * 0.05, 0.0, sin(_wag * 1.5) * 0.04) * w).normalized()
	_apply_pose(hands, dir, 0.0)


func _process(delta: float) -> void:
	_wag += delta
	if _carry != _carry_goal:
		_carry = move_toward(_carry, _carry_goal, delta * 2.2)
	if not _active:
		_apply_rest()
	else:
		_advance(delta)
	_hold_bat()


func _advance(delta: float) -> void:
	_t += delta
	if _t < 0.0:
		_apply_rest()
		return
	if _mode == "check":
		# Out and back: a hitch of the bat, not a swing.
		var span := _tc * 1.5
		if _t >= span + 0.15:
			reset()
			return
		var k := sin(clampf(_t / span, 0.0, 1.0) * PI) * 0.5
		_apply_pose(REST_HANDS.lerp(_contact_hands, k), REST_DIR.normalized().slerp(_contact_dir, k), lerpf(0.0, _yaw_contact, k))
		return
	var total := _tf + HOLD + RESET
	if _t >= total:
		reset()
		return
	var hands: Vector3
	var dir: Vector3
	var yaw: float
	if _t < _tc:
		var u := pow(_t / _tc, 1.7 if _mode == "swing" else 1.0)            # accelerating into the ball
		hands = REST_HANDS.lerp(_contact_hands, u)
		dir = REST_DIR.normalized().slerp(_contact_dir, u)
		yaw = lerpf(0.0, _yaw_contact, u)
	elif _t < _tf:
		var u2 := (_t - _tc) / (_tf - _tc)
		u2 = 1.0 - pow(1.0 - u2, 2.0)                  # decelerating through
		hands = _contact_hands.lerp(_follow_hands, u2)
		dir = _contact_dir.slerp(_follow_dir, u2)
		yaw = lerpf(_yaw_contact, _yaw_follow, u2)
	elif _t < _tf + HOLD:
		hands = _follow_hands
		dir = _follow_dir
		yaw = _yaw_follow
	else:
		var u3 := (_t - _tf - HOLD) / RESET
		u3 = u3 * u3 * (3.0 - 2.0 * u3)
		hands = _follow_hands.lerp(REST_HANDS, u3)
		dir = _follow_dir.slerp(REST_DIR.normalized(), u3)
		yaw = lerpf(_yaw_follow, 0.0, u3)
	_apply_pose(hands, dir, yaw)


func _apply_pose(hands: Vector3, dir: Vector3, yaw: float) -> void:
	var d := dir.normalized()
	_bat.transform = Transform3D(Basis(Quaternion(Vector3.UP, d)), hands)
	# Two hands on the grip: lower hand near the knob, upper hand a little further up.
	_h_low = hands + d * 0.06
	_h_up = hands + d * 0.20
	var deg := rad_to_deg(yaw)
	# A reach beyond his arms' length: he steps his body toward it instead of letting go of the bat.
	var turn := Basis(Vector3.UP, yaw)
	var excess := 0.0
	for hand_pt in [_h_low, _h_up]:
		for sx in [-0.21, 0.21]:
			var shoulder: Vector3 = turn * Vector3(sx, 1.45, 0.0)
			excess = maxf(excess, hand_pt.distance_to(shoulder) - 0.57)
	var toward := Vector3((_h_low.x + _h_up.x) * 0.5, 0.0, (_h_low.z + _h_up.z) * 0.5)
	doll.body_shift = toward.normalized() * clampf(excess, 0.0, 0.2) if toward.length() > 0.01 else Vector3.ZERO
	doll.twist = deg
	doll.look_yaw = FACE_PITCHER - deg                  # the head stays on the pitcher
	_hold_bat()


## The arms are solved to the grip every frame, because the whole node may be walking.
func _hold_bat() -> void:
	if doll == null:
		return
	doll.aim_glove(to_global(_h_low), 1.0)          # the lead (low) hand
	doll.aim_hand(to_global(_h_up), 1.0)            # the top hand
