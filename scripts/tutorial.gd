class_name Tutorial
extends RefCounted
## A short lesson on pitching in the bullpen. With grips (the default): strikes with the four-seamer, then one grip
## at a time, each counted only when its own action was good. In Freestyle: your usual throw, then one gesture
## per pitch type. It watches each pitch and moves on by itself. Pure: no scene, so it is testable.
## (Your arm is learned by the warm-up, which runs first if the game does not know it yet.)
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

## With grips: the lesson for each grip, counted when the grip's own action was good or sharp.
const GRIP_STEPS := [
	{"id": "strikes", "family": ["*strike"], "count": 3, "in_a_row": true, "title": "Four-seam strikes",
		"text": "Your usual throw with the four-seam grip (stick up): 3 strikes in a row at the catcher's glove."},
	{"id": "changeup", "family": ["Changeup", "Splitter"], "count": 3, "quality": true, "title": "Changeup",
		"text": "Flick the stick down: changeup grip. Throw 3 good ones with your fastball arm speed: the grip slows it."},
	{"id": "curve", "family": ["Curveball", "Slurve"], "count": 3, "quality": true, "title": "Curveball",
		"text": "Flick the stick toward your glove side: curveball grip. Throw 3 good ones: snap your wrist over the top."},
	{"id": "slider", "family": ["Slider"], "count": 3, "quality": true, "title": "Slider",
		"text": "Flick toward your glove side again: slider grip. Throw 3 good ones: turn your wrist like a doorknob."},
	{"id": "sinker", "family": ["Two-seam", "Sinker"], "count": 3, "quality": true, "title": "Sinker",
		"text": "Flick toward your arm side: two-seam grip (again for the sinker). Throw 3 good ones: drop your arm a little lower."},
]

var steps: Array = STEPS                # this lesson's steps (STEPS or GRIP_STEPS: the same length)
var step := 0                           # index into steps; steps.size() when done
var progress := 0                       # pitches counted toward this step
var pitches := 0                        # all pitches thrown in the lesson


func _init(start_step: int = 0, grips: bool = false) -> void:
	steps = GRIP_STEPS if grips else STEPS
	step = clampi(start_step, 0, steps.size())


func is_done() -> bool:
	return step >= steps.size()


## What to do now, for the board.
func prompt() -> String:
	if is_done():
		return "Lesson complete. Play > Pitching when you are ready."
	var s: Dictionary = steps[step]
	return "LESSON %d of %d - %s (%d/%d): %s" % [step + 1, steps.size(), s.title, progress, int(s.count), s.text]


## A pitch was thrown. `label` is the name the game gave it, `was_strike` whether it crossed the zone, `quality`
## how well a grip's own action was done ("sharp", "good", "flat", "hanging"; "" in Freestyle).
func on_pitch(label: String, was_strike: bool, quality: String = "") -> Dictionary:
	pitches += 1
	if is_done():
		return {"advanced": false, "done": true, "text": prompt()}
	var s: Dictionary = steps[step]
	var fam: Array = s.family
	var counts := was_strike if fam == ["*strike"] else (label in fam)
	var flat := counts and bool(s.get("quality", false)) and not (quality in ["good", "sharp"])
	if flat:
		counts = false
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
		return {"advanced": true, "done": false, "text": text + " Next: " + String(steps[step].title)}
	if flat:
		text = "A %s %s: it needs more. %s" % [quality, label.to_lower(), Grips.how_to(label)]
	elif not counts and fam != ["*strike"]:
		text = "That was a %s. %s" % [label, Grips.how_to(String(fam[0])) if steps == GRIP_STEPS else PitchLab.how_to(String(fam[0]))]
	return {"advanced": false, "done": false, "text": text}
