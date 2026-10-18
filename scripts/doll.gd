class_name Doll
extends Node3D
## A cartoon person on a small skeleton, in one of two styles that share the same rig and the
## same animation:
##
##   SOFT   rounded capsule body, a real 3D figure.
##   PAPER  flat cut-out cards with an outline, like a paper doll: it always turns its flat
##          side to the viewer (mirroring to face left or right) and bounces and squashes.
##
## One skinned mesh each, so a person is one draw call however many parts it has.
## Animation is procedural keyframes on the bones (see _CLIPS); locomotion comes from how the
## node is being moved, so the game only has to place it. Face it with rotation.y (+Z forward).
##
##   doll.throw_to(world_point, "overhand" | "sidearm" | "underhand", seconds)
##   doll.catch_ball(seconds)
##   doll.celebrate(seconds)

enum Style { SOFT, PAPER }

## A foot came down while he was running (the owner may make a sound of it).
signal footstep(at: Vector3)

const SKIN := Color(0.96, 0.78, 0.62)
const SHOE := Color(0.10, 0.10, 0.12)
const OUTLINE := Color(0.10, 0.10, 0.14)
const GEAR := Color(0.17, 0.18, 0.24)
const GLOVE := Color(0.50, 0.30, 0.13)

# Bone indices (parents come first).
const PELVIS := 0
const TORSO := 1
const HEAD := 2
const ARM_L := 3
const FORE_L := 4
const ARM_R := 5
const FORE_R := 6
const LEG_L := 7
const SHIN_L := 8
const LEG_R := 9
const SHIN_R := 10
const NAMES := ["pelvis", "torso", "head", "arm_l", "fore_l", "arm_r", "fore_r", "leg_l", "shin_l", "leg_r", "shin_r"]
const PARENTS := [-1, PELVIS, TORSO, TORSO, ARM_L, TORSO, ARM_R, PELVIS, LEG_L, PELVIS, LEG_R]
# Offsets from the parent's origin, character facing +Z, left = +X.
const OFFSETS := [
	Vector3(0.0, 0.92, 0.0), Vector3(0.0, 0.05, 0.0), Vector3(0.0, 0.60, 0.0),
	Vector3(0.21, 0.52, 0.0), Vector3(0.0, -0.28, 0.0), Vector3(-0.21, 0.52, 0.0), Vector3(0.0, -0.28, 0.0),
	Vector3(0.10, -0.02, 0.0), Vector3(0.0, -0.44, 0.0), Vector3(-0.10, -0.02, 0.0), Vector3(0.0, -0.44, 0.0)]

# Keyframes per clip: bone -> [[t, Vector3(x, y, z) in degrees], ...] with t in 0..1.
# x swings a limb forward (negative) / back (positive); y twists; z swings it sideways.
# Arm angles run past 180: 0 hanging, 90 back, 180 up, 270 forward, 360 hanging again.
const _CLIPS := {
	"overhand": {
		ARM_R: [[0.0, Vector3(0, 0, 0)], [0.35, Vector3(100, 0, -20)], [0.55, Vector3(225, 0, -10)], [0.8, Vector3(330, 0, 0)], [1.0, Vector3(360, 0, 0)]],
		FORE_R: [[0.0, Vector3(0, 0, 0)], [0.35, Vector3(-100, 0, 0)], [0.55, Vector3(-10, 0, 0)], [0.8, Vector3(-30, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		ARM_L: [[0.0, Vector3(0, 0, 0)], [0.35, Vector3(-60, 0, 25)], [0.55, Vector3(40, 0, 10)], [1.0, Vector3(0, 0, 0)]],
		TORSO: [[0.0, Vector3(0, 0, 0)], [0.35, Vector3(-5, -35, 0)], [0.55, Vector3(25, 25, 0)], [0.8, Vector3(30, 20, 0)], [1.0, Vector3(0, 0, 0)]],
		LEG_L: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(-55, 0, 0)], [0.55, Vector3(-25, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		SHIN_L: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(85, 0, 0)], [0.55, Vector3(15, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		LEG_R: [[0.0, Vector3(0, 0, 0)], [0.55, Vector3(12, 0, 0)], [1.0, Vector3(0, 0, 0)]],
	},
	"sidearm": {
		ARM_R: [[0.0, Vector3(0, 0, 0)], [0.25, Vector3(10, 0, -85)], [0.8, Vector3(-20, 0, -80)], [1.0, Vector3(0, 0, 0)]],
		FORE_R: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(-30, 0, 0)], [0.55, Vector3(-5, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		ARM_L: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(-40, 0, 40)], [0.6, Vector3(20, 0, 20)], [1.0, Vector3(0, 0, 0)]],
		TORSO: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(0, -55, 0)], [0.55, Vector3(12, 45, 0)], [0.85, Vector3(15, 40, 0)], [1.0, Vector3(0, 0, 0)]],
		LEG_L: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(-25, 0, 0)], [0.55, Vector3(-30, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		SHIN_L: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(30, 0, 0)], [0.55, Vector3(20, 0, 0)], [1.0, Vector3(0, 0, 0)]],
	},
	"underhand": {
		ARM_R: [[0.0, Vector3(0, 0, 0)], [0.35, Vector3(55, 0, 0)], [0.55, Vector3(-65, 0, 0)], [0.8, Vector3(-40, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		FORE_R: [[0.0, Vector3(0, 0, 0)], [0.35, Vector3(-20, 0, 0)], [0.55, Vector3(-30, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		ARM_L: [[0.0, Vector3(0, 0, 0)], [0.35, Vector3(-30, 0, 15)], [1.0, Vector3(0, 0, 0)]],
		TORSO: [[0.0, Vector3(0, 0, 0)], [0.35, Vector3(-8, 0, 0)], [0.55, Vector3(25, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		LEG_L: [[0.0, Vector3(0, 0, 0)], [0.55, Vector3(-30, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		SHIN_L: [[0.0, Vector3(0, 0, 0)], [0.55, Vector3(45, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		LEG_R: [[0.0, Vector3(0, 0, 0)], [0.55, Vector3(-10, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		SHIN_R: [[0.0, Vector3(0, 0, 0)], [0.55, Vector3(40, 0, 0)], [1.0, Vector3(0, 0, 0)]],
	},
	"catch": {
		ARM_L: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(-105, 0, 15)], [0.7, Vector3(-95, 0, 10)], [1.0, Vector3(0, 0, 0)]],
		FORE_L: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(-15, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		ARM_R: [[0.0, Vector3(0, 0, 0)], [0.4, Vector3(-60, 0, -15)], [0.7, Vector3(-50, 0, -10)], [1.0, Vector3(0, 0, 0)]],
		TORSO: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(10, 0, 0)], [1.0, Vector3(0, 0, 0)]],
	},
	"celebrate": {
		ARM_L: [[0.0, Vector3(0, 0, 0)], [0.2, Vector3(180, 0, 25)], [0.4, Vector3(180, 0, 10)], [0.6, Vector3(180, 0, 25)], [0.8, Vector3(180, 0, 10)], [1.0, Vector3(0, 0, 0)]],
		ARM_R: [[0.0, Vector3(0, 0, 0)], [0.2, Vector3(180, 0, -25)], [0.4, Vector3(180, 0, -10)], [0.6, Vector3(180, 0, -25)], [0.8, Vector3(180, 0, -10)], [1.0, Vector3(0, 0, 0)]],
	},
	"ump_strike": {
		ARM_R: [[0.0, Vector3(0, 0, 0)], [0.2, Vector3(-95, 0, -12)], [0.4, Vector3(-95, 0, -12)], [0.55, Vector3(-75, 0, -12)], [0.75, Vector3(-95, 0, -12)], [1.0, Vector3(0, 0, 0)]],
		FORE_R: [[0.0, Vector3(0, 0, 0)], [0.2, Vector3(-100, 0, 0)], [0.8, Vector3(-100, 0, 0)], [1.0, Vector3(0, 0, 0)]],
	},
	"ump_out": {
		ARM_R: [[0.0, Vector3(0, 0, 0)], [0.15, Vector3(-120, 0, -10)], [0.3, Vector3(-150, 0, -10)], [0.45, Vector3(-110, 0, -10)], [0.6, Vector3(-150, 0, -10)], [0.75, Vector3(-110, 0, -10)], [1.0, Vector3(0, 0, 0)]],
		FORE_R: [[0.0, Vector3(0, 0, 0)], [0.15, Vector3(-95, 0, 0)], [0.85, Vector3(-95, 0, 0)], [1.0, Vector3(0, 0, 0)]],
	},
	"ump_safe": {
		ARM_L: [[0.0, Vector3(0, 0, 0)], [0.2, Vector3(-60, 0, 80)], [0.75, Vector3(-60, 0, 80)], [1.0, Vector3(0, 0, 0)]],
		ARM_R: [[0.0, Vector3(0, 0, 0)], [0.2, Vector3(-60, 0, -80)], [0.75, Vector3(-60, 0, -80)], [1.0, Vector3(0, 0, 0)]],
	},
	"ump_foul": {
		ARM_L: [[0.0, Vector3(0, 0, 0)], [0.25, Vector3(185, 0, 12)], [0.8, Vector3(185, 0, 12)], [1.0, Vector3(0, 0, 0)]],
		ARM_R: [[0.0, Vector3(0, 0, 0)], [0.25, Vector3(185, 0, -12)], [0.8, Vector3(185, 0, -12)], [1.0, Vector3(0, 0, 0)]],
	},
	"ump_point": {
		ARM_R: [[0.0, Vector3(0, 0, 0)], [0.25, Vector3(-85, 25, -35)], [0.85, Vector3(-85, 25, -35)], [1.0, Vector3(0, 0, 0)]],
	},
	# A grounder: down low, glove out in front, then up with it.
	"scoop": {
		ARM_L: [[0.0, Vector3(-20, 0, 8)], [0.3, Vector3(-42, 0, 5)], [0.6, Vector3(-38, 0, 5)], [1.0, Vector3(-10, 0, 0)]],
		ARM_R: [[0.0, Vector3(-12, 0, -8)], [0.3, Vector3(-30, 0, -10)], [0.6, Vector3(-30, 0, -8)], [1.0, Vector3(-10, 0, 0)]],
		FORE_L: [[0.0, Vector3(-40, 0, 0)], [0.3, Vector3(-8, 0, 0)], [1.0, Vector3(-30, 0, 0)]],
		TORSO: [[0.0, Vector3(14, 0, 0)], [0.3, Vector3(52, 0, 0)], [0.65, Vector3(52, 0, 0)], [1.0, Vector3(14, 0, 0)]],
		HEAD: [[0.0, Vector3(-8, 0, 0)], [0.3, Vector3(-38, 0, 0)], [0.65, Vector3(-38, 0, 0)], [1.0, Vector3(-8, 0, 0)]],
		LEG_L: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(-32, 0, 0)], [0.65, Vector3(-32, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		LEG_R: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(-32, 0, 0)], [0.65, Vector3(-32, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		SHIN_L: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(52, 0, 0)], [0.65, Vector3(52, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		SHIN_R: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(52, 0, 0)], [0.65, Vector3(52, 0, 0)], [1.0, Vector3(0, 0, 0)]],
	},
	# A ball to the glove side that he has to reach across for.
	"backhand": {
		ARM_L: [[0.0, Vector3(-20, 0, 8)], [0.3, Vector3(-60, 0, -35)], [0.6, Vector3(-55, 0, -30)], [1.0, Vector3(-10, 0, 0)]],
		FORE_L: [[0.0, Vector3(-40, 0, 0)], [0.3, Vector3(-10, 0, 0)], [1.0, Vector3(-30, 0, 0)]],
		TORSO: [[0.0, Vector3(14, 0, 0)], [0.3, Vector3(44, -35, 0)], [0.65, Vector3(44, -35, 0)], [1.0, Vector3(14, 0, 0)]],
		HEAD: [[0.0, Vector3(-8, 0, 0)], [0.3, Vector3(-30, 25, 0)], [0.65, Vector3(-30, 25, 0)], [1.0, Vector3(-8, 0, 0)]],
		LEG_L: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(-28, 0, 0)], [0.65, Vector3(-28, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		LEG_R: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(10, 0, 0)], [0.65, Vector3(10, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		SHIN_L: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(40, 0, 0)], [0.65, Vector3(40, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		SHIN_R: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(30, 0, 0)], [0.65, Vector3(30, 0, 0)], [1.0, Vector3(0, 0, 0)]],
	},
	# A ball above his head: up on his toes with the glove stretched high.
	"jump": {
		ARM_L: [[0.0, Vector3(-20, 0, 8)], [0.3, Vector3(-190, 0, 8)], [0.6, Vector3(-190, 0, 8)], [1.0, Vector3(-10, 0, 0)]],
		ARM_R: [[0.0, Vector3(-12, 0, -8)], [0.3, Vector3(-150, 0, -25)], [0.6, Vector3(-150, 0, -25)], [1.0, Vector3(-10, 0, 0)]],
		TORSO: [[0.0, Vector3(14, 0, 0)], [0.3, Vector3(-8, 0, 0)], [0.6, Vector3(-8, 0, 0)], [1.0, Vector3(14, 0, 0)]],
		HEAD: [[0.0, Vector3(-8, 0, 0)], [0.3, Vector3(-30, 0, 0)], [0.6, Vector3(-30, 0, 0)], [1.0, Vector3(-8, 0, 0)]],
		LEG_L: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(-30, 0, 0)], [0.6, Vector3(-18, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		SHIN_L: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(60, 0, 0)], [0.6, Vector3(30, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		LEG_R: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(10, 0, 0)], [0.6, Vector3(10, 0, 0)], [1.0, Vector3(0, 0, 0)]],
		SHIN_R: [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(50, 0, 0)], [0.6, Vector3(30, 0, 0)], [1.0, Vector3(0, 0, 0)]],
	},
	# The crack of the bat: a quick sink and a spring toward the ball.
	"react": {
		TORSO: [[0.0, Vector3(14, 0, 0)], [0.3, Vector3(26, 0, 0)], [0.7, Vector3(18, 0, 0)], [1.0, Vector3(14, 0, 0)]],
		ARM_L: [[0.0, Vector3(-20, 0, 8)], [0.3, Vector3(-45, 0, 14)], [1.0, Vector3(-20, 0, 8)]],
		ARM_R: [[0.0, Vector3(-12, 0, -8)], [0.3, Vector3(-40, 0, -14)], [1.0, Vector3(-12, 0, -8)]],
	},
	# A tag: the glove sweeps down onto the runner.
	"tag": {
		ARM_L: [[0.0, Vector3(-20, 0, 8)], [0.25, Vector3(-120, 0, 5)], [0.45, Vector3(-40, 0, 5)], [1.0, Vector3(-10, 0, 0)]],
		FORE_L: [[0.0, Vector3(-40, 0, 0)], [0.25, Vector3(-10, 0, 0)], [0.45, Vector3(-5, 0, 0)], [1.0, Vector3(-30, 0, 0)]],
		TORSO: [[0.0, Vector3(14, 0, 0)], [0.4, Vector3(36, 0, 0)], [0.7, Vector3(30, 0, 0)], [1.0, Vector3(14, 0, 0)]],
	},
	# A fist pump: celebrating a strikeout or a run.
	"fist_pump": {
		ARM_R: [[0.0, Vector3(0, 0, 0)], [0.25, Vector3(-150, 0, -10)], [0.4, Vector3(-195, 0, -10)], [0.55, Vector3(-150, 0, -10)], [0.7, Vector3(-195, 0, -10)], [1.0, Vector3(0, 0, 0)]],
		FORE_R: [[0.0, Vector3(0, 0, 0)], [0.25, Vector3(-80, 0, 0)], [0.7, Vector3(-80, 0, 0)], [1.0, Vector3(0, 0, 0)]],
	},
}

# Pelvis height changes that go with a clip: [[t, metres], ...] (a crouch lowers him, a jump lifts him).
const _CLIP_BOB := {
	"scoop": [[0.0, 0.0], [0.3, -0.12], [0.65, -0.12], [1.0, 0.0]],
	"backhand": [[0.0, 0.0], [0.3, -0.10], [0.65, -0.10], [1.0, 0.0]],
	"jump": [[0.0, 0.0], [0.3, 0.48], [0.6, 0.42], [1.0, 0.0]],
	"react": [[0.0, 0.0], [0.3, -0.07], [0.7, 0.03], [1.0, 0.0]],
	"tag": [[0.0, 0.0], [0.4, -0.08], [1.0, 0.0]],
	"celebrate": [[0.0, 0.0], [0.2, 0.18], [0.4, 0.04], [0.6, 0.18], [0.8, 0.04], [1.0, 0.0]],
	"fist_pump": [[0.0, 0.0], [0.4, 0.10], [0.55, 0.0], [0.7, 0.10], [1.0, 0.0]],
}

# Whole-body poses that ease in and hold: bone -> target euler, "bob" the pelvis height change,
# "in" and "out" the fraction of the clip spent easing.
const _POSES := {
	"block": {"bones": {LEG_L: Vector3(-22, 0, 0), LEG_R: Vector3(-22, 0, 0), SHIN_L: Vector3(95, 0, 0), SHIN_R: Vector3(95, 0, 0),
		TORSO: Vector3(42, 0, 0), ARM_L: Vector3(-8, 0, 6), ARM_R: Vector3(-8, 0, -6), HEAD: Vector3(-20, 0, 0)}, "bob": -0.62, "in": 0.25, "out": 0.3},
	"slide": {"bones": {PELVIS: Vector3(-72, 0, 0), LEG_L: Vector3(-12, 0, 0), SHIN_L: Vector3(0, 0, 0), LEG_R: Vector3(-45, 0, 0),
		SHIN_R: Vector3(75, 0, 0), TORSO: Vector3(0, 0, 0), ARM_L: Vector3(110, 0, 0), ARM_R: Vector3(110, 0, 0)}, "bob": -0.50, "in": 0.22, "out": 0.4},
	"dive": {"bones": {PELVIS: Vector3(72, 0, 0), LEG_L: Vector3(5, 0, 0), LEG_R: Vector3(-5, 0, 0), SHIN_L: Vector3(15, 0, 0),
		SHIN_R: Vector3(30, 0, 0), ARM_L: Vector3(-165, 0, 0), ARM_R: Vector3(-165, 0, 0), HEAD: Vector3(-40, 0, 0)}, "bob": -0.50, "in": 0.2, "out": 0.4},
}

var style: int = Style.SOFT
var jersey := Color(0.12, 0.17, 0.50)
var pants := Color(0.62, 0.64, 0.70)
var cap := Color(0.12, 0.17, 0.50)
var has_glove := true
## How low he sits: 0 stands tall (a runner), 1 is a fielder's ready crouch.
var crouch := 1.0
## "player", "catcher" (gear, deep squat, a glove that follows the ball) or "umpire" (black uniform, leaning in).
var role := "player"
var locomotion := true          # false: no run cycle when he is shifted (a catcher sliding side to side)
var _squat := 0.0               # how deep the squat is (a catcher 1, an umpire 0.5)
var _squat_goal := 0.0
var _squat_rate := 3.0
var _glove_target := Vector3.ZERO
var _glove_weight := 0.0
var _hand_target := Vector3.ZERO            # the throwing hand's reach (a batter's top hand on the bat)
var _hand_weight := 0.0
## Overlays the owner sets: torso and hip twist (degrees about the vertical) and where the head looks.
var twist := 0.0
var pelvis_twist := 0.0
var look_yaw := 0.0
## The whole body leans/steps this far from where it stands (a batter reaching for a pitch), in his own frame.
var body_shift := Vector3.ZERO
## A runner on a base bounces on his toes; one waiting out a fly ball watches it with his head up.
var idle_bounce := false
var watching := false
var _last_yaw := 0.0
var _last_sin := 0.0
var _bank := 0.0

var _skeleton: Skeleton3D
var _visual: Node3D
var _last_pos := Vector3.ZERO
var _have_last := false
var _speed := 0.0
var _phase := 0.0
var _clip := ""
var _clip_t := 0.0
var _clip_dur := 1.0
var _hop := 0.0
var _t := 0.0


## A doll standing at `at` under `parent`. style < 0 picks one at random.
static func create(parent: Node, at: Vector3, jersey_c: Color, pants_c: Color, cap_c: Color, glove: bool = true,
		style_id: int = -1, role_name: String = "player") -> Doll:
	var d := Doll.new()
	d.jersey = jersey_c
	d.pants = pants_c
	d.cap = cap_c
	d.has_glove = glove
	d.role = role_name
	d.style = style_id if style_id >= 0 else (randi() % 2)
	match role_name:
		"catcher":
			d._squat = 1.0
			d._squat_goal = 1.0
			d.locomotion = false
		"umpire":
			d._squat = 0.55
			d._squat_goal = 0.55
			d.has_glove = false
		"batter":
			d._squat = 0.2
			d._squat_goal = 0.2
			d.has_glove = false
	d.position = at
	parent.add_child(d)
	return d


func _ready() -> void:
	_build()


# ------------------------------------------------------------------ the body
func _global_rest() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in NAMES.size():
		var local := Transform3D(Basis.IDENTITY, OFFSETS[i])
		out.append(local if PARENTS[i] < 0 else out[PARENTS[i]] * local)
	return out


func _build() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_skeleton = Skeleton3D.new()
	_visual.add_child(_skeleton)
	for i in NAMES.size():
		_skeleton.add_bone(NAMES[i])
	for i in NAMES.size():
		if PARENTS[i] >= 0:
			_skeleton.set_bone_parent(i, PARENTS[i])
		_skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, OFFSETS[i]))
	_skeleton.reset_bone_poses()

	var rest := _global_rest()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()

	var add_part := func(prim: PrimitiveMesh, xf: Transform3D, color: Color, bone: int) -> void:
		var arrays: Array = prim.get_mesh_arrays()
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var ix: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var nb := xf.basis.inverse().transposed()
		for k in v.size():
			verts.append(xf * v[k])
			norms.append((nb * n[k]).normalized())
			cols.append(color)
			bones.append_array([bone, 0, 0, 0])
			weights.append_array([1.0, 0.0, 0.0, 0.0])
		for k in ix:
			idx.append(base + k)

	if style == Style.SOFT:
		_soft_parts(add_part, rest)
	else:
		_paper_parts(add_part, rest)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var skin := Skin.new()
	for i in NAMES.size():
		skin.add_named_bind(NAMES[i], rest[i].affine_inverse())
	var inst := MeshInstance3D.new()
	_skeleton.add_child(inst)
	inst.mesh = mesh
	inst.skin = skin
	inst.skeleton = NodePath("..")
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if style == Style.PAPER:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	inst.material_override = mat
	inst.custom_aabb = AABB(Vector3(-1.5, -0.2, -1.5), Vector3(3.0, 2.6, 3.0))     # skinned: do not cull by rest pose


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0 + 0.001)
	c.radial_segments = 10
	c.rings = 3
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


func _cyl_x(r: float, thick: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = thick
	c.radial_segments = 16
	c.rings = 1
	return c


func _soft_parts(add: Callable, rest: Array[Transform3D]) -> void:
	var at := func(bone: int, local: Vector3) -> Transform3D:
		return Transform3D(Basis.IDENTITY, (rest[bone] as Transform3D).origin + local)
	add.call(_capsule(0.155, 0.34), at.call(PELVIS, Vector3(0, 0.0, 0)), pants, PELVIS)
	add.call(_capsule(0.165, 0.58), at.call(TORSO, Vector3(0, 0.25, 0)), jersey, TORSO)
	add.call(_sphere(0.128), at.call(HEAD, Vector3(0, 0.13, 0)), SKIN, HEAD)
	var capx: Transform3D = at.call(HEAD, Vector3(0, 0.20, 0))
	add.call(_sphere(0.138), Transform3D(Basis.from_scale(Vector3(1.0, 0.6, 1.0)), capx.origin), cap, HEAD)
	add.call(_box(0.2, 0.02, 0.14), at.call(HEAD, Vector3(0, 0.19, 0.15)), cap, HEAD)
	if role == "catcher":
		add.call(_box(0.42, 0.46, 0.30), at.call(TORSO, Vector3(0, 0.26, 0.02)), GEAR, TORSO)           # chest protector
		add.call(_sphere(0.155), at.call(HEAD, Vector3(0, 0.14, -0.02)), GEAR, HEAD)                   # helmet
		add.call(_box(0.21, 0.16, 0.05), at.call(HEAD, Vector3(0, 0.08, 0.14)), Color(0.82, 0.84, 0.9), HEAD)   # the mask
	elif role == "umpire":
		add.call(_box(0.40, 0.44, 0.28), at.call(TORSO, Vector3(0, 0.27, 0.02)), Color(0.22, 0.22, 0.26), TORSO)  # protector under the shirt
		add.call(_box(0.2, 0.16, 0.05), at.call(HEAD, Vector3(0, 0.24, 0.12)), Color(0.15, 0.15, 0.18), HEAD)      # mask pushed up
	for side in [-1, 1]:
		var upper_arm: int = ARM_L if side > 0 else ARM_R
		var lower_arm: int = FORE_L if side > 0 else FORE_R
		var upper_leg: int = LEG_L if side > 0 else LEG_R
		var lower_leg: int = SHIN_L if side > 0 else SHIN_R
		add.call(_capsule(0.058, 0.30), at.call(upper_arm, Vector3(0, -0.14, 0)), jersey, upper_arm)
		add.call(_capsule(0.050, 0.28), at.call(lower_arm, Vector3(0, -0.13, 0)), SKIN, lower_arm)
		var hand_r := 0.05
		var hand_c := SKIN
		if has_glove and side > 0:
			hand_r = 0.14 if role == "catcher" else 0.085       # a catcher's mitt is a big pillow
			hand_c = GLOVE
		add.call(_sphere(hand_r), at.call(lower_arm, Vector3(0, -0.29, 0.02)), hand_c, lower_arm)
		add.call(_capsule(0.082, 0.46), at.call(upper_leg, Vector3(0, -0.22, 0)), pants, upper_leg)
		var shin_c := Color(0.95, 0.95, 0.95)
		var shin_r := 0.066
		if role == "catcher":
			shin_c = GEAR
			shin_r = 0.085                                     # shin guards
		add.call(_capsule(shin_r, 0.44), at.call(lower_leg, Vector3(0, -0.21, 0)), shin_c, lower_leg)
		if role == "catcher":
			add.call(_sphere(0.095), at.call(lower_leg, Vector3(0, 0.0, 0.07)), GEAR, lower_leg)        # knee pad
		add.call(_box(0.11, 0.07, 0.24), at.call(lower_leg, Vector3(0, -0.43, 0.06)), SHOE, lower_leg)


func _paper_parts(add: Callable, rest: Array[Transform3D]) -> void:
	# Flat cards in the YZ plane (profile): +Z is the way he faces. Each card has a darker card
	# behind it a little bigger, which reads as the cut-out outline.
	var card := func(bone: int, local: Vector3, size: Vector2, color: Color, layer: float) -> void:
		var origin: Vector3 = (rest[bone] as Transform3D).origin + local + Vector3(layer, 0.0, 0.0)
		add.call(_box(0.006, size.x + 0.025, size.y + 0.025), Transform3D(Basis.IDENTITY, origin), OUTLINE, bone)
		add.call(_box(0.012, size.x, size.y), Transform3D(Basis.IDENTITY, origin), color, bone)
	var disc := func(bone: int, local: Vector3, r: float, color: Color, layer: float) -> void:
		var origin: Vector3 = (rest[bone] as Transform3D).origin + local + Vector3(layer, 0.0, 0.0)
		var b := Basis(Vector3.FORWARD, deg_to_rad(90.0))
		add.call(_cyl_x(r + 0.014, 0.006), Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(90.0)), origin), OUTLINE, bone)
		add.call(_cyl_x(r, 0.012), Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(90.0)), origin), color, bone)
	var far := 0.0           # layers: far limbs sit behind, near limbs in front
	var dark := func(c: Color) -> Color:
		return Color(c.r * 0.72, c.g * 0.72, c.b * 0.72)
	# Far side (the throwing arm and the right leg) first, behind the body.
	card.call(ARM_R, Vector3(0, -0.14, 0), Vector2(0.30, 0.095), dark.call(jersey), -0.020)
	card.call(FORE_R, Vector3(0, -0.13, 0), Vector2(0.28, 0.08), dark.call(SKIN), -0.020)
	disc.call(FORE_R, Vector3(0, -0.29, 0), 0.05, dark.call(SKIN), -0.020)
	card.call(LEG_R, Vector3(0, -0.22, 0), Vector2(0.46, 0.13), dark.call(pants), -0.020)
	card.call(SHIN_R, Vector3(0, -0.21, 0), Vector2(0.44, 0.10), dark.call(Color(0.95, 0.95, 0.95)), -0.020)
	card.call(SHIN_R, Vector3(0, -0.43, 0.06), Vector2(0.07, 0.24), SHOE, -0.020)
	# Body.
	card.call(PELVIS, Vector3(0, 0.0, 0), Vector2(0.30, 0.30), pants, 0.0)
	card.call(TORSO, Vector3(0, 0.25, 0), Vector2(0.60, 0.32), jersey, 0.004)
	disc.call(HEAD, Vector3(0, 0.14, 0), 0.14, SKIN, 0.006)
	card.call(HEAD, Vector3(0, 0.25, 0), Vector2(0.09, 0.30), cap, 0.010)
	card.call(HEAD, Vector3(0, 0.22, 0.17), Vector2(0.025, 0.16), cap, 0.010)       # the bill: shows which way he faces
	if role == "catcher":
		card.call(TORSO, Vector3(0, 0.26, 0.04), Vector2(0.44, 0.34), GEAR, 0.012)                      # chest protector
		card.call(HEAD, Vector3(0, 0.10, 0.15), Vector2(0.15, 0.05), Color(0.82, 0.84, 0.9), 0.014)    # the mask
	elif role == "umpire":
		card.call(TORSO, Vector3(0, 0.27, 0.04), Vector2(0.42, 0.30), Color(0.22, 0.22, 0.26), 0.012)
	# Near side (the glove arm and the left leg) in front.
	card.call(LEG_L, Vector3(0, -0.22, 0), Vector2(0.46, 0.13), pants, 0.020)
	card.call(SHIN_L, Vector3(0, -0.21, 0), Vector2(0.44, 0.10), GEAR if role == "catcher" else Color(0.95, 0.95, 0.95), 0.020)
	card.call(SHIN_L, Vector3(0, -0.43, 0.06), Vector2(0.07, 0.24), SHOE, 0.020)
	card.call(ARM_L, Vector3(0, -0.14, 0), Vector2(0.30, 0.095), jersey, 0.026)
	card.call(FORE_L, Vector3(0, -0.13, 0), Vector2(0.28, 0.08), SKIN, 0.026)
	if has_glove:
		disc.call(FORE_L, Vector3(0, -0.30, 0.03), 0.15 if role == "catcher" else 0.09, GLOVE, 0.030)
	else:
		disc.call(FORE_L, Vector3(0, -0.29, 0), 0.05, SKIN, 0.030)


# ------------------------------------------------------------------ animation
func throw_to(_target: Vector3, kind: String = "overhand", seconds: float = 0.7) -> void:
	_start_clip(kind if _CLIPS.has(kind) else "overhand", seconds)


func catch_ball(seconds: float = 0.5) -> void:
	_start_clip("catch", seconds)


func celebrate(seconds: float = 1.2) -> void:
	_start_clip("celebrate", seconds)


## Any clip by name (the umpire's calls, "block", "slide", "dive"...).
func play(clip: String, seconds: float = 0.8) -> void:
	if _CLIPS.has(clip) or _POSES.has(clip):
		_start_clip(clip, seconds)


## Crouch to this depth (0 standing .. 1 a catcher's squat) over `seconds`.
func set_squat(depth: float, seconds: float = 0.3) -> void:
	_squat_goal = clampf(depth, 0.0, 1.0)
	_squat_rate = absf(_squat_goal - _squat) / maxf(seconds, 0.05)


## Put the other hand on this world point (a batter's top hand on the bat).
func aim_hand(world_point: Vector3, weight: float = 1.0) -> void:
	_hand_target = world_point
	_hand_weight = clampf(weight, 0.0, 1.0)


func release_hand() -> void:
	_hand_weight = 0.0


## Put the glove hand on this world point (weight 0..1). The arm is solved to reach it.
func aim_glove(world_point: Vector3, weight: float = 1.0) -> void:
	_glove_target = world_point
	_glove_weight = clampf(weight, 0.0, 1.0)


## Where the glove pocket is in the world right now (a ball being caught sticks here).
func glove_world() -> Vector3:
	return _hand_world(FORE_L)


## Where the throwing hand is in the world right now (a ball being held or released).
func hand_world() -> Vector3:
	return _hand_world(FORE_R)


func _hand_world(bone: int) -> Vector3:
	if _skeleton == null:
		return global_position + Vector3(0.0, 1.2, 0.0)
	return _skeleton.global_transform * (_skeleton.get_bone_global_pose(bone) * Vector3(0.0, -0.29, 0.02))


func release_glove() -> void:
	_glove_weight = 0.0


## True if the glove can reach this world point from where he is now (arm's length).
func can_reach(world_point: Vector3) -> bool:
	if _skeleton == null:
		return false
	var shoulder := _skeleton.global_transform * _skeleton.get_bone_global_pose(ARM_L).origin
	return shoulder.distance_to(world_point) <= 0.60


func _start_clip(clip: String, seconds: float) -> void:
	_clip = clip
	_clip_t = 0.0
	_clip_dur = maxf(seconds, 0.1)


func busy() -> bool:
	return _clip != ""


## Piecewise-smooth value of a keyframe list at t.
static func _sample(keys: Array, t: float) -> Vector3:
	if t <= float(keys[0][0]):
		return keys[0][1]
	for i in range(1, keys.size()):
		var t1: float = keys[i][0]
		if t <= t1:
			var t0: float = keys[i - 1][0]
			var u := clampf((t - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			return (keys[i - 1][1] as Vector3).lerp(keys[i][1], u)
	return keys[keys.size() - 1][1]


static func _sample1(keys: Array, t: float) -> float:
	if t <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, keys.size()):
		var t1: float = keys[i][0]
		if t <= t1:
			var t0: float = keys[i - 1][0]
			var u := clampf((t - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			return lerpf(float(keys[i - 1][1]), float(keys[i][1]), u)
	return float(keys[keys.size() - 1][1])


func _process(delta: float) -> void:
	if _skeleton == null or delta <= 0.0:
		return
	_t += delta
	# How fast he is being moved (the game places him; we read it back).
	var p := global_position
	if _have_last:
		var d := p - _last_pos
		d.y = 0.0
		var v := d.length() / delta
		if d.length() > 3.0:
			v = 0.0                                   # a teleport, not a run
		_speed = lerpf(_speed, minf(v, 12.0), clampf(delta * 10.0, 0.0, 1.0))
	_last_pos = p
	_have_last = true

	if _clip != "":
		_clip_t += delta
		if _clip_t >= _clip_dur:
			_clip = ""
	var rot := {}                                     # bone -> Vector3 degrees
	var bob := 0.0
	var squash := 1.0

	# Locomotion: a run cycle scaled by speed, a ready stance when still.
	var moving := clampf(_speed / 3.0, 0.0, 1.0)
	_phase += delta * (4.0 + _speed * 1.6) * moving
	var s := sin(_phase)
	var c := cos(_phase)
	if moving > 0.55 and locomotion and (s > 0.0) != (_last_sin > 0.0) and visible:
		footstep.emit(global_position)
	_last_sin = s
	if not locomotion:
		moving = 0.0
	_squat = move_toward(_squat, _squat_goal, _squat_rate * delta)
	var sq := _squat * (1.0 - moving)
	var stance := crouch * (1.0 - moving) * (1.0 - clampf(sq * 1.5, 0.0, 1.0))
	rot[LEG_L] = Vector3(-s * 48.0 * moving - 14.0 * stance, 0, 0)
	rot[SHIN_L] = Vector3(maxf(0.0, -c) * 75.0 * moving + 26.0 * stance, 0, 0)
	rot[LEG_R] = Vector3(s * 48.0 * moving - 14.0 * stance, 0, 0)
	rot[SHIN_R] = Vector3(maxf(0.0, c) * 75.0 * moving + 26.0 * stance, 0, 0)
	rot[ARM_L] = Vector3(s * 55.0 * moving - 20.0 * stance, 0, 8.0 * stance)
	rot[ARM_R] = Vector3(-s * 55.0 * moving - 12.0 * stance, 0, -8.0 * stance)
	rot[FORE_L] = Vector3(-35.0 * moving - 40.0 * stance, 0, 0)
	rot[FORE_R] = Vector3(-35.0 * moving - 25.0 * stance, 0, 0)
	rot[TORSO] = Vector3(9.0 * moving + 14.0 * stance, 0, 0)
	rot[HEAD] = Vector3(-7.0 * moving - 8.0 * stance, 0, 0)
	rot[PELVIS] = Vector3(0, 0, 0)
	bob = absf(c) * 0.05 * moving - 0.07 * stance
	if sq > 0.0:
		# A deep squat (catcher) or a lean over the plate (umpire).
		var lean := 38.0 if role == "umpire" else 6.0
		rot[LEG_L] = (rot[LEG_L] as Vector3) + Vector3(-78.0 * sq, 0, 0)
		rot[LEG_R] = (rot[LEG_R] as Vector3) + Vector3(-78.0 * sq, 0, 0)
		rot[SHIN_L] = (rot[SHIN_L] as Vector3) + Vector3(112.0 * sq, 0, 0)
		rot[SHIN_R] = (rot[SHIN_R] as Vector3) + Vector3(112.0 * sq, 0, 0)
		rot[TORSO] = (rot[TORSO] as Vector3) + Vector3(lean * sq, 0, 0)
		rot[HEAD] = (rot[HEAD] as Vector3) + Vector3(-lean * 0.9 * sq, 0, 0)
		if role == "umpire":
			rot[ARM_L] = Vector3(-52.0 * sq * 1.8, 0, 6)
			rot[ARM_R] = Vector3(-52.0 * sq * 1.8, 0, -6)
			rot[FORE_L] = Vector3(-18.0, 0, 0)
			rot[FORE_R] = Vector3(-18.0, 0, 0)
		bob -= 0.40 * sq
	var breathe := sin(_t * 2.2) * 0.008 * (1.0 - moving)
	if idle_bounce and moving < 0.1 and _clip == "":
		# On his toes, rocking, ready to go.
		bob += sin(_t * 6.0) * 0.03 + 0.02
		rot[TORSO] = (rot[TORSO] as Vector3) + Vector3(8.0 + sin(_t * 3.0) * 3.0, 0, 0)
	if watching and moving < 0.1 and _clip == "":
		# Planted, eyes on a ball in the air.
		rot[HEAD] = Vector3(-34.0, 0, 0)
		rot[LEG_R] = (rot[LEG_R] as Vector3) + Vector3(14.0, 0, 0)
		rot[TORSO] = (rot[TORSO] as Vector3) + Vector3(-6.0, 0, 0)

	# A clip overrides the bones it keys.
	if _clip != "":
		var u := clampf(_clip_t / _clip_dur, 0.0, 1.0)
		var keys: Dictionary = _CLIPS.get(_clip, {})
		if _POSES.has(_clip):
			var pc: Dictionary = _POSES[_clip]
			var k := clampf(minf(u / float(pc["in"]), (1.0 - u) / float(pc["out"])), 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			for pb in pc["bones"]:
				rot[pb] = (rot.get(pb, Vector3.ZERO) as Vector3).lerp(pc["bones"][pb], k)
			bob = lerpf(bob, float(pc["bob"]), k)
		for bone in keys:
			var e: Vector3 = _sample(keys[bone], u)
			if rot.has(bone):
				# Add to the locomotion pose for the legs; replace for arms and torso.
				if bone in [LEG_L, LEG_R, SHIN_L, SHIN_R]:
					e = (rot[bone] as Vector3) * (1.0 - u * 0.0) + e
			rot[bone] = e
		if _clip in ["overhand", "sidearm", "underhand"]:
			# A hop into the throw, landing as the ball goes.
			bob += sin(u * PI) * 0.06
			squash = 1.0 - 0.06 * sin(u * PI * 2.0)
		if _CLIP_BOB.has(_clip):
			bob += _sample1(_CLIP_BOB[_clip], u)

	# Overlays: the body turns about its own vertical, the head keeps looking where it looks,
	# and a runner leans into a turn.
	var yaw_now := rotation.y
	var yaw_rate := wrapf(yaw_now - _last_yaw, -PI, PI) / delta
	_last_yaw = yaw_now
	var bank_goal := 0.0
	if style == Style.SOFT:
		bank_goal = clampf(-yaw_rate * 0.10, -16.0, 16.0) * clampf(_speed / 6.0, 0.0, 1.0)
	_bank = lerpf(_bank, bank_goal, clampf(delta * 8.0, 0.0, 1.0))
	if absf(_bank) > 0.05:
		rot[TORSO] = (rot[TORSO] as Vector3) + Vector3(0, 0, _bank)
	if twist != 0.0 or pelvis_twist != 0.0 or look_yaw != 0.0:
		rot[TORSO] = (rot[TORSO] as Vector3) + Vector3(0, twist, 0)
		rot[PELVIS] = (rot[PELVIS] as Vector3) + Vector3(0, pelvis_twist, 0)
		rot[HEAD] = (rot[HEAD] as Vector3) + Vector3(0, look_yaw, 0)

	# Paper dolls turn their flat side to you and show only the in-plane motion.
	var depth := 1.0 if style == Style.SOFT else 0.0
	if style == Style.PAPER:
		bob *= 1.7
		bob += absf(c) * 0.04 * moving
		# Flat to a fixed side-on axis (world X), never to where your head happens to be, so
		# looking around does not move anyone.
		var heading := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
		var vis_forward := Vector3.RIGHT if heading.x >= 0.0 else Vector3.LEFT
		_visual.rotation.y = atan2(vis_forward.x, vis_forward.z) - rotation.y
		if moving > 0.1:
			_visual.rotation.z = sin(_phase) * deg_to_rad(5.0) * moving     # a waddle
		else:
			_visual.rotation.z = 0.0
	else:
		_visual.rotation = Vector3.ZERO

	for i in NAMES.size():
		var e: Vector3 = rot.get(i, Vector3.ZERO)
		# Twists and sideways swings only exist for the 3D body.
		var euler := Vector3(e.x, e.y * depth, e.z * depth)
		var q := Quaternion.from_euler(Vector3(deg_to_rad(euler.x), deg_to_rad(euler.y), deg_to_rad(euler.z)))
		_skeleton.set_bone_pose_rotation(i, q)
	_skeleton.set_bone_pose_position(PELVIS, OFFSETS[PELVIS] + Vector3(0.0, bob + breathe, 0.0) + body_shift)
	_skeleton.set_bone_pose_scale(PELVIS, Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash)) if style == Style.PAPER else Vector3.ONE)
	if _glove_weight > 0.01:
		_solve_glove()
	if _hand_weight > 0.01:
		_solve_arm(ARM_R, FORE_R, _hand_target, _hand_weight)


func _solve_glove() -> void:
	_solve_arm(ARM_L, FORE_L, _glove_target, _glove_weight)


## Two-bone reach: put a hand on a world point. Done in the torso's frame, so a crouched,
## leaning body reaches from where its shoulder actually is. Paper dolls reach in their plane.
func _solve_arm(arm: int, fore: int, world_target: Vector3, weight: float) -> void:
	var left := arm == ARM_L
	_skeleton.force_update_all_bone_transforms()
	var torso_gp := _skeleton.get_bone_global_pose(TORSO)
	var to_torso := torso_gp.affine_inverse()
	var shoulder: Vector3 = to_torso * _skeleton.get_bone_global_pose(arm).origin
	var target: Vector3 = to_torso * (_skeleton.global_transform.affine_inverse() * world_target)
	if style == Style.PAPER:
		target.x = shoulder.x
	# A catcher who cannot reach it with his arm alone leans into it (a low pitch, a long stretch).
	if role == "catcher" and left:
		var need := (target - shoulder).length() - 0.60
		if need > 0.0:
			var lean := clampf(need * 2.2, 0.0, 1.1)
			_skeleton.set_bone_pose_rotation(TORSO, _skeleton.get_bone_pose_rotation(TORSO) * Quaternion(Vector3.RIGHT, lean))
			_skeleton.force_update_all_bone_transforms()
			torso_gp = _skeleton.get_bone_global_pose(TORSO)
			to_torso = torso_gp.affine_inverse()
			shoulder = to_torso * _skeleton.get_bone_global_pose(arm).origin
			target = to_torso * (_skeleton.global_transform.affine_inverse() * world_target)
			if style == Style.PAPER:
				target.x = shoulder.x
	var upper := 0.28
	var lower := 0.34
	var d := target - shoulder
	var dist := clampf(d.length(), 0.10, upper + lower - 0.01)
	var dir := d.normalized() if d.length() > 0.001 else Vector3(0, 0, 1)
	var alpha := acos(clampf((upper * upper + dist * dist - lower * lower) / (2.0 * upper * dist), -1.0, 1.0))
	var pole := Vector3(0.35 if left else -0.35, -1.0, -0.25)       # the elbow wants to be down, out and back
	if style == Style.PAPER:
		pole = Vector3(0.0, -1.0, -0.35)
	var perp := pole - dir * dir.dot(pole)
	perp = perp.normalized() if perp.length() > 0.001 else Vector3.DOWN
	var u := (dir * cos(alpha) + perp * sin(alpha)).normalized()
	var elbow := shoulder + u * upper
	var l := ((shoulder + dir * dist) - elbow).normalized()
	var q_up := _down_to(u)
	var q_fore := q_up.inverse() * _down_to(l)
	var w := weight
	_skeleton.set_bone_pose_rotation(arm, _skeleton.get_bone_pose_rotation(arm).slerp(q_up, w))
	_skeleton.set_bone_pose_rotation(fore, _skeleton.get_bone_pose_rotation(fore).slerp(q_fore, w))


## The rotation that turns a limb hanging straight down to point along `v`.
static func _down_to(v: Vector3) -> Quaternion:
	var vn := v.normalized()
	if vn.dot(Vector3.DOWN) < -0.9995:
		return Quaternion(Vector3.RIGHT, PI)
	return Quaternion(Vector3.DOWN, vn)
