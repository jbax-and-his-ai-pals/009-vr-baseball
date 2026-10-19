class_name PlanEvent
extends RefCounted
## A call or a label on a play at a moment: OUT, SAFE, RUN, HOME RUN, INFIELD FLY, STRIKEOUT...
## `kind` is "out", "safe" or "run" (it decides the color and the sound). `at` is where a base-0 label sits
## (INF means at the base). `who` is the runner a run belongs to.

var t := 0.0
var base := 0
var text := ""
var kind := ""
var at := Vector3.INF
var who: RunnerPlan = null


static func make(time: float, at_base: int, label: String, what: String, where := Vector3.INF, runner: RunnerPlan = null) -> PlanEvent:
	var e := PlanEvent.new()
	e.t = time
	e.base = at_base
	e.text = label
	e.kind = what
	e.at = where
	e.who = runner
	return e


func has_at() -> bool:
	return at != Vector3.INF
