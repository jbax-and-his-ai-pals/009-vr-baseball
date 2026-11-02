class_name Grips
extends RefCounted
## Grip, then motion (docs/GAMEPLAY_NEXT.md A3): the grip picks the pitch, your body makes it. Each grip has a
## full shape (spin, from the AI pitchers' table where it has one) and a speed against your four-seamer; its
## own action (one reading of the wrist model, or arm speed for the changeup) decides how much of that
## shape you get. A good action gets all of it; no action gets the assist's floor; a wrong or lazy one makes
## it hang. The pitch is aimed as if it had its usual movement, so a hanging breaking ball stays up and a
## sharp one dives past where it was aimed. Pure: no scene, so it is testable.
##
##   var e := Grips.execution(Grips.action("Slider", shape, 1.0))   # in units of a full action
##   var m := Grips.movement(e, 0.6)                                  # share of the full shape (Standard floor)
##   var spin := Grips.spin("Slider", m, 1.0)                         # rad/s, world, thrown toward -Z

## name -> mph (real scale, against the four-seamer's 92), rpm (world frame for a right-hander throwing toward
## -Z: x = backspin (lift), y = sidespin (+ breaks to the glove side), z = gyro), the reading that is its action,
## and the stick family it is in.
const DEFS := {
	"Four-seam":   {"mph": 92.0, "rpm": Vector3(2300.0, 150.0, 0.0), "action": "", "family": "up"},
	"Cutter":      {"mph": 88.0, "rpm": Vector3(1600.0, 900.0, -1000.0), "action": "roll", "family": "up"},
	"Two-seam":    {"mph": 91.0, "rpm": Vector3(1900.0, -900.0, 0.0), "action": "slot", "family": "arm"},
	"Sinker":      {"mph": 90.0, "rpm": Vector3(1200.0, -1400.0, 0.0), "action": "slot", "family": "arm"},
	"Curveball":   {"mph": 78.0, "rpm": Vector3(-2000.0, 300.0, -800.0), "action": "snap", "family": "glove"},
	"Slider":      {"mph": 85.0, "rpm": Vector3(-300.0, 1200.0, -1500.0), "action": "twist", "family": "glove"},
	"Slurve":      {"mph": 80.0, "rpm": Vector3(-1300.0, 1300.0, -1000.0), "action": "snap_twist", "family": "glove"},
	"Changeup":    {"mph": 83.0, "rpm": Vector3(1500.0, -500.0, 0.0), "action": "arm_speed", "family": "down"},
	"Splitter":    {"mph": 84.0, "rpm": Vector3(600.0, -250.0, 0.0), "action": "arm_speed", "family": "down"},
	"Knuckleball": {"mph": 72.0, "rpm": Vector3(40.0, 0.0, 0.0), "action": "stiff", "family": "press"},
}
const FOUR_SEAM := "Four-seam"
## The stick: flick toward a family for its first grip, flick that way again for the next one in it.
const FAMILIES := {
	"up": ["Four-seam", "Cutter"],
	"arm": ["Two-seam", "Sinker"],
	"glove": ["Curveball", "Slider", "Slurve"],
	"down": ["Changeup", "Splitter"],
	"press": ["Knuckleball"],
}
## A full action, in standard deviations of your own wrist (or the arm-speed scale below).
const ACTION_FULL := 2.0
## Changeup and splitter: sold with your fastball's arm speed. Arm speed at 85% of your usual is no action;
## each 7.5% more (or less) is one unit.
const ARM_SPEED_FLAT := 0.85
const ARM_SPEED_UNIT := 0.075
## A grip you have not learned yet (career) moves less: its floor is cut and it never gets all of its shape.
const LEARNING_FLOOR := 0.6
const LEARNING_CAP := 0.85
## How much of the difference between the movement a pitch got and the movement it was aimed for becomes a miss
## (the rest you allow for, as a pitcher does). At Standard a curve with no action then crosses about 0.13 m high
## and a hanging one about 0.4 m; the whole difference was 0.26 and 0.9 m, too harsh for the hardest action to read.
const MISS_SHARE := 0.5
## A knuckleball's wobble at its full shape (m/s^2), as the wrist model's.
const FLUTTER_MAX := 12.0
## What the signs and the career call a fastball.
const ALIASES := {"Fastball": "Four-seam"}


static func names() -> Array:
	return DEFS.keys()


static func canonical(pitch_name: String) -> String:
	var n := String(ALIASES.get(pitch_name, pitch_name))
	return n if DEFS.has(n) else FOUR_SEAM


## How much of the action this throw had, in standard deviations (before ACTION_FULL). `shape` is the wrist
## model's reading of the throw; `arm_ratio` is its hand speed over your usual.
static func action(grip: String, shape: Dictionary, arm_ratio: float) -> float:
	var snap := float(shape.get("z_snap", 0.0)) + maxf(float(shape.get("z_wind", 0.0)), 0.0) + 0.5 * maxf(-float(shape.get("z_slot", 0.0)), 0.0)
	match String(DEFS.get(grip, {}).get("action", "")):
		"roll":
			return float(shape.get("z_gyro", 0.0))
		"slot":
			return -float(shape.get("z_slot", 0.0))
		"snap":
			return snap
		"twist":
			return float(shape.get("z_side", 0.0))
		"snap_twist":
			return maxf(snap, float(shape.get("z_side", 0.0)))
		"arm_speed":
			return (arm_ratio - ARM_SPEED_FLAT) / ARM_SPEED_UNIT
		"stiff":
			return 4.0 * maxf(float(shape.get("stiff", 0.0)), float(shape.get("push", 0.0))) - 1.0
	return ACTION_FULL          # the four-seamer has no action of its own: it is always all there


## The action as a share of a full one: 1 is full, 0 none, below 0 the wrong way or lazy.
static func execution(act: float) -> float:
	return clampf(act / ACTION_FULL, -1.0, 1.5)


## The share of the grip's full shape you get. `floor` is the assist's (Casual 1: the grip alone gives it all
## and the action can only add; Standard 0.6; Pro 0.35). Beyond a full action a little more, never much.
static func movement(e: float, floor: float) -> float:
	var extra := 0.15 * clampf(e - 1.0, 0.0, 0.5)
	if floor >= 1.0:
		return 1.0 + extra
	if e >= 0.0:
		return floor + (1.0 - floor) * minf(e, 1.0) + extra
	return floor * (1.0 + 0.6 * maxf(e, -1.0))


## What the pitch is aimed for: an ordinary execution (half way from the floor to the full shape).
static func expected(floor: float) -> float:
	return 1.0 if floor >= 1.0 else (1.0 + floor) * 0.5


## The movement the aim allows for, for a pitch that got `m`: MISS_SHARE of the way from what it was meant to get
## back to what it got, so only that share of a hanger's lost break (or a sharp one's extra) shows as a miss.
static func aimed_for(m: float, floor: float) -> float:
	return lerpf(expected(floor), m, 1.0 - MISS_SHARE)


## The spin for a share `m` of the grip's shape: from the four-seamer's spin toward the grip's, so a pitch with
## little of its shape spins like a slow fastball (that is what hanging is). rad/s, world frame; `hand_sign`
## +1 right-handed, -1 left-handed (side and gyro mirror).
static func spin(grip: String, m: float, hand_sign: float) -> Vector3:
	var fb: Vector3 = DEFS[FOUR_SEAM].rpm
	var g: Vector3 = DEFS.get(grip, DEFS[FOUR_SEAM]).rpm
	var rpm := fb + (g - fb) * m
	return Vector3(rpm.x, rpm.y * hand_sign, rpm.z * hand_sign) * PitchPhysics.RPM_TO_RADS


## Pitch speed against the four-seamer's.
static func speed_factor(grip: String) -> float:
	return float(DEFS.get(grip, DEFS[FOUR_SEAM]).mph) / float(DEFS[FOUR_SEAM].mph)


static func flutter(grip: String, m: float) -> float:
	return FLUTTER_MAX * clampf(m, 0.0, 1.2) if grip == "Knuckleball" else 0.0


## One word for the execution: sharp, good, flat or hanging (at a floor of 1 nothing hangs).
static func quality(e: float, floor: float) -> String:
	if e >= 1.0:
		return "sharp"
	if e >= 0.375:
		return "good"
	if e >= 0.0 or floor >= 1.0:
		return "flat"
	return "hanging"


## The grip a flick toward `family` gives: the next one in that family after `current` (the first if
## `current` is not in it), skipping grips not in `allowed` (empty allows all). Returns `current` if none.
static func flick(current: String, family: String, allowed: Array = []) -> String:
	var fam: Array = FAMILIES.get(family, [])
	var options := fam.filter(func(g): return allowed.is_empty() or g in allowed)
	if options.is_empty():
		return current
	var i := options.find(current)
	return String(options[(i + 1) % options.size()]) if i >= 0 else String(options[0])


## Which family a stick position points at, for a pitcher with `hand_sign` (+1 right-handed): the glove side is
## left for a right-hander. "" when the stick is near the middle.
static func family_of_stick(stick: Vector2, hand_sign: float, threshold: float = 0.7) -> String:
	if stick.length() < threshold:
		return ""
	if absf(stick.y) >= absf(stick.x):
		return "up" if stick.y > 0.0 else "down"
	return "glove" if stick.x * hand_sign < 0.0 else "arm"


## How to throw it, for the lab and the lesson.
static func how_to(grip: String) -> String:
	match String(DEFS.get(grip, {}).get("action", "")):
		"roll":
			return "Roll your wrist about the line of the throw, a little across your body."
		"slot":
			return "Drop your arm a little lower than usual as you let go."
		"snap":
			return "Snap your wrist over the top as you let go; a bigger, higher windup helps."
		"twist":
			return "Turn your wrist like a doorknob as you let go."
		"snap_twist":
			return "Snap over the top and turn the doorknob together."
		"arm_speed":
			return "Keep your fastball arm speed: the grip slows it, and a slow arm gives it away."
		"stiff":
			return "Push it with a stiff wrist: no spin at all."
	return "Your usual throw: the grip does the rest."


## What the action reading is called, for the lab.
static func action_words(grip: String) -> String:
	match String(DEFS.get(grip, {}).get("action", "")):
		"roll":
			return "wrist roll"
		"slot":
			return "lower arm slot"
		"snap":
			return "snap over the top"
		"twist":
			return "wrist twist"
		"snap_twist":
			return "snap and twist"
		"arm_speed":
			return "arm speed"
		"stiff":
			return "stiff wrist"
	return ""


## The pitch lab's lines for a grip pitch: what the action was and what it made of the pitch.
static func explain(info: Dictionary) -> Array[String]:
	var g := String(info.get("grip", FOUR_SEAM))
	var lines: Array[String] = []
	if g == FOUR_SEAM:
		lines.append("Four-seam grip: velocity and location are the whole pitch.")
		return lines
	var m := float(info.get("movement", 1.0))
	var q := String(info.get("quality", "flat"))
	lines.append("%s grip, %s %+.1f: %s, %.0f%% of its movement" % [g, action_words(g), float(info.get("action", 0.0)), q, 100.0 * m])
	if q == "hanging":
		lines.append("It hung: it stays up and does not break. " + how_to(g))
	elif q == "flat":
		lines.append("More action, more movement. " + how_to(g))
	if bool(info.get("learning", false)):
		lines.append("Still learning this grip: it moves less until you have thrown it often for strikes.")
	return lines
