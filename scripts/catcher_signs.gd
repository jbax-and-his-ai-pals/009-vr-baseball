class_name CatcherSigns
extends RefCounted
## The catcher calls the pitch: a pitch type and a spot, chosen from the count, the runners and who is
## up, shown to you before you throw. You may shake him off for another. A pitch that is the right
## type and lands near the spot is a "sign hit"; it is counted and shown, so the gestures you throw
## have something to aim at. Pure: no scene, no clock; give it a random number generator.
##
##   var sign := CatcherSigns.call_pitch(situation, repertoire, rng)   # {"pitch", "cell", "target", "words"}
##   var r := CatcherSigns.grade(sign, "Slider", plate_x, plate_y)     # {"type", "loc", "perfect"}

const LOW := 0.55
const MID := 0.85
const HIGH := 1.15
const IN_OUT := 0.22                  # inside / away columns, metres from the middle of the plate
const NEAR := 0.30                    # how close to the spot counts as hitting it, metres

const FASTBALLS := ["Fastball", "Four-seam", "Two-seam", "Sinker"]
const FAMILIES := {
	"Fastball": ["Fastball", "Four-seam", "Two-seam", "Sinker"],
	"Curveball": ["Curveball", "Slurve"],
	"Slider": ["Slider", "Cutter"],
	"Changeup": ["Changeup", "Splitter"],
	"Knuckleball": ["Knuckleball"],
}


## Where a cell is, for a batter who stands on the `batter_side` (+1 the third-base side, a right-hander;
## -1 a left-hander). "Away" is the side from him, "in" is toward him.
static func cell_target(cell: String, batter_side: float) -> Vector2:
	var away := -batter_side * IN_OUT
	var inside := batter_side * IN_OUT
	match cell:
		"low-away":
			return Vector2(away, LOW)
		"low-in":
			return Vector2(inside, LOW)
		"low-mid":
			return Vector2(0.0, LOW)
		"mid-away":
			return Vector2(away, MID)
		"mid-in":
			return Vector2(inside, MID)
		"middle":
			return Vector2(0.0, MID)
		"high-away":
			return Vector2(away, HIGH)
		"high-in":
			return Vector2(inside, HIGH)
		"high-mid":
			return Vector2(0.0, HIGH)
		"chase-low-away":
			return Vector2(-batter_side * 0.40, 0.30)
		"chase-high":
			return Vector2(0.0, 1.48)
		"chase-away":
			return Vector2(-batter_side * 0.45, MID)
	return Vector2(0.0, MID)


static func cell_words(cell: String) -> String:
	return cell.replace("chase-", "off the plate, ").replace("-", " and ").replace("mid and", "middle and").replace("low and mid", "low and middle")


## Choose a pitch and a spot. situation: {balls, strikes, outs, bases: [bool x3], batter_side: +1/-1}.
static func call_pitch(situation: Dictionary, repertoire: Array, rng: RandomNumberGenerator) -> Dictionary:
	var balls := int(situation.get("balls", 0))
	var strikes := int(situation.get("strikes", 0))
	var bases: Array = situation.get("bases", [false, false, false])
	var side := float(situation.get("batter_side", 1.0))
	var outs := int(situation.get("outs", 0))
	var no_dirt := bool(bases[2]) and outs < 2             # a runner on third: nothing in the dirt
	var kind := "Fastball"
	var cell := "mid-away"
	if balls >= 3:
		kind = "Fastball"
		cell = _pick(["low-away", "mid-away", "middle"], rng)       # he has to throw a strike
	elif strikes == 2 and not no_dirt:
		if rng.randf() < 0.7:
			kind = _pick(["Curveball", "Slider", "Changeup"], rng)
			cell = "chase-low-away"
		else:
			kind = "Fastball"
			cell = "chase-high"
	elif strikes > balls:
		kind = _pick(["Curveball", "Slider", "Changeup", "Fastball"], rng)
		cell = _pick(["low-away", "low-in", "mid-away"], rng)
	elif balls > strikes:
		kind = "Fastball"
		cell = _pick(["mid-away", "mid-in", "low-away", "middle"], rng)
	else:
		var r := rng.randf()
		kind = "Fastball" if r < 0.5 else ("Slider" if r < 0.7 else ("Curveball" if r < 0.85 else "Changeup"))
		cell = _pick(["low-away", "mid-away", "high-in", "low-in", "mid-in"], rng)
	if no_dirt and cell.begins_with("low"):
		cell = "mid-away"
	# Stay inside what the pitcher actually throws.
	if not _can_throw(kind, repertoire):
		kind = "Fastball"
	var target := cell_target(cell, side)
	return {"pitch": kind, "cell": cell, "target": target, "words": "%s, %s" % [kind, cell_words(cell)]}


static func _pick(options: Array, rng: RandomNumberGenerator) -> String:
	return String(options[rng.randi() % options.size()])


static func _can_throw(kind: String, repertoire: Array) -> bool:
	if repertoire.is_empty():
		return true
	for name in FAMILIES.get(kind, [kind]):
		if name in repertoire:
			return true
	return kind in repertoire


## How a thrown pitch compares with the sign: the type (same family) and the location (near the spot).
static func grade(sign: Dictionary, thrown_name: String, plate_x: float, plate_y: float) -> Dictionary:
	if sign.is_empty():
		return {"type": false, "loc": false, "perfect": false}
	var family: Array = FAMILIES.get(String(sign.pitch), [String(sign.pitch)])
	var type_ok := thrown_name in family
	var target: Vector2 = sign.target
	var loc_ok := Vector2(plate_x, plate_y).distance_to(target) <= NEAR
	return {"type": type_ok, "loc": loc_ok, "perfect": type_ok and loc_ok}
