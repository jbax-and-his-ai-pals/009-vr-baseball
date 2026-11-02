class_name Warmup
extends RefCounted
## The warm-up: the first thing a new pitcher does, and how anyone recalibrates. In the bullpen, with the
## catcher's glove in the middle and a batter who never swings: ten easy throws teach the game your usual
## throw (speed, wrist, aim), then three harder ones your top speed. It ends with what it learned, in words,
## and the game remembers it (Calibration). Pure: no scene, so it is testable.
##
##   var w := Warmup.new()
##   w.prompt()                                  # what to do now, with progress
##   var r := w.on_throw(84.0)                   # each thrown pitch's radar speed: {"advanced", "done", "text"}
##   w.summary(usual_mph, top_mph, aim_sigma)    # the closing card, once done

const EASY := 10
const HARD := 3
## The aim scatter (degrees, the larger of the two directions) that reads as each word, and the assist it suggests.
const STEADY := [[3.0, "very steady", "Pro"], [4.5, "steady", "Standard"], [6.5, "about average", "Standard"], [999.0, "still settling", "Casual"]]

const STEPS := [
	{"id": "easy", "count": EASY, "title": "Easy throws",
		"text": "Check you have room around you. Squeeze grip to pick up the ball, throw at the catcher's glove, let go of grip to release. Smooth and relaxed: your usual fastball, not your hardest."},
	{"id": "hard", "count": HARD, "title": "A little harder",
		"text": "Now as hard as is comfortable. Never so hard that it hurts: the game judges effort against your own arm."},
]

var step := 0                         # index into STEPS; STEPS.size() when done
var progress := 0
var easy_mph: Array[float] = []
var hard_mph: Array[float] = []


func is_done() -> bool:
	return step >= STEPS.size()


func prompt() -> String:
	if is_done():
		return "WARM-UP DONE"
	var s: Dictionary = STEPS[step]
	return "WARM-UP %d of %d - %s (%d/%d): %s" % [step + 1, STEPS.size(), s.title, progress, int(s.count), s.text]


## A pitch left your hand (a drop does not count). `radar_mph` is its speed as the radar shows it.
func on_throw(radar_mph: float) -> Dictionary:
	if is_done():
		return {"advanced": false, "done": true, "text": ""}
	var s: Dictionary = STEPS[step]
	if s.id == "easy":
		easy_mph.append(radar_mph)
	else:
		hard_mph.append(radar_mph)
	progress += 1
	if progress < int(s.count):
		return {"advanced": false, "done": false, "text": "%.0f mph" % radar_mph}
	step += 1
	progress = 0
	if is_done():
		return {"advanced": true, "done": true, "text": "Warm-up done!"}
	return {"advanced": true, "done": false, "text": "Done: %s. Next: %s" % [s.title, String(STEPS[step].title)]}


## How steady your aim is, in words, from the learned scatter (degrees).
static func steadiness(aim_sigma: Vector2) -> String:
	var worst := maxf(aim_sigma.x, aim_sigma.y)
	for row in STEADY:
		if worst <= float(row[0]):
			return String(row[1])
	return "still settling"


## The assist that suits that steadiness.
static func suggested_assist(aim_sigma: Vector2) -> String:
	var worst := maxf(aim_sigma.x, aim_sigma.y)
	for row in STEADY:
		if worst <= float(row[0]):
			return String(row[2])
	return "Casual"


## The closing card: what the game learned, and where to change it.
func summary(usual_mph: float, top_mph: float, aim_sigma: Vector2) -> Array[String]:
	return [
		"WARM-UP DONE - the game knows your arm now",
		"Your usual fastball: %.0f mph. Your top: %.0f mph." % [usual_mph, top_mph],
		"Your aim: %s (%.1f degrees of scatter). Suggested assist: %s." % [steadiness(aim_sigma), maxf(aim_sigma.x, aim_sigma.y), suggested_assist(aim_sigma)],
		"Saved for next time. Warm up again any time: Options > Recalibrate pitching.",
	]
