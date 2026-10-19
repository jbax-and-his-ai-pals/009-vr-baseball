class_name Tutorial
extends RefCounted
## A short lesson on pitching in the bullpen: learn your usual throw, then one gesture per pitch type,
## then throw strikes. It watches each pitch and moves on by itself. Pure: no scene, so it is testable.
##
##   var t := Tutorial.new()
##   t.prompt()                      # what to do now, with progress
##   var r := t.on_pitch("Slider", true)   # {"advanced": bool, "done": bool, "text": what to say}

## Each step: a goal pitch family (or "strike"), how many, the instruction.
const STEPS := [
	{"id": "fastball", "family": ["Fastball", "Four-seam", "Two-seam", "Sinker"], "count": 8, "title": "Your usual throw",
		"text": "Throw 8 fastballs your normal way. The game learns how you throw."},
	{"id": "strikes", "family": ["*strike"], "count": 3, "in_a_row": true, "title": "Throw strikes",
		"text": "Throw 3 strikes in a row. Aim by pointing your hand where the ball should go."},
	{"id": "changeup", "family": ["Changeup", "Splitter"], "count": 3, "title": "Changeup",
		"text": "Throw 3 changeups: the same arm motion, but clearly slower."},
	{"id": "slider", "family": ["Slider", "Cutter"], "count": 3, "title": "Slider",
		"text": "Throw 3 sliders: twist your wrist like turning a doorknob at release."},
	{"id": "curve", "family": ["Curveball", "Slurve"], "count": 3, "title": "Curveball",
		"text": "Throw 3 curveballs: flick your wrist hard at the end, or wind up bigger and higher."},
]

var step := 0                           # index into STEPS; STEPS.size() when done
var progress := 0                       # pitches counted toward this step
var pitches := 0                        # all pitches thrown in the lesson


func _init(start_step: int = 0) -> void:
	step = clampi(start_step, 0, STEPS.size())


func is_done() -> bool:
	return step >= STEPS.size()


## What to do now, for the board.
func prompt() -> String:
	if is_done():
		return "Lesson complete. Play > Pitching when you are ready."
	var s: Dictionary = STEPS[step]
	return "LESSON %d of %d - %s (%d/%d): %s" % [step + 1, STEPS.size(), s.title, progress, int(s.count), s.text]


## A pitch was thrown. `label` is the name the game gave it, `was_strike` whether it crossed the zone.
func on_pitch(label: String, was_strike: bool) -> Dictionary:
	pitches += 1
	if is_done():
		return {"advanced": false, "done": true, "text": prompt()}
	var s: Dictionary = STEPS[step]
	var fam: Array = s.family
	var counts := was_strike if fam == ["*strike"] else (label in fam)
	if counts:
		progress += 1
	elif bool(s.get("in_a_row", false)):
		progress = 0
	var text := ""
	if progress >= int(s.count):
		step += 1
		progress = 0
		text = "Done: %s!" % s.title
		if is_done():
			return {"advanced": true, "done": true, "text": text + " " + prompt()}
		return {"advanced": true, "done": false, "text": text + " Next: " + String(STEPS[step].title)}
	if not counts and fam != ["*strike"]:
		text = "That was a %s. %s" % [label, PitchLab.how_to(String(fam[0]))]
	return {"advanced": false, "done": false, "text": text}
