class_name PlayPlan
extends RefCounted
## Everything that happens on the bases on one play: each runner's timeline, the throws, the calls, the
## score and the outs it adds, where everybody ends up and when it is all over. Made by Baserunning from
## what the defense did, read by the scorebook (GameState) and played by PlayDirector.
## Times are seconds after contact.

## A fielder who moves to cover a bag because of the throw (the second baseman covering second on a force).
class Cover:
	extends RefCounted
	var fielder := 0
	var to := Vector3.ZERO
	var t := 0.0


var runners: Array[RunnerPlan] = []
var events: Array[PlanEvent] = []
var throws: Array[ThrowPlan] = []
var runs := 0
var outs_added := 0
var suffix := ""                    # appended to the scorebook's text: " (double play)"
var text := ""                      # the play's own words when the baserunning decided them ("" if not)
var result := ""                    # the play's result when the baserunning changed it ("" if not)
var hold := false                   # a human fielder has the ball: nobody is decided yet
var batter_safe := false
var end_time := 0.0
var final_bases: Array = [null, null, null]
var runs_voided := false            # the third out came before he scored
var time_play := false              # a run counts although the third out was made
var hide_batter_at := 0.25          # when the batter figure leaves the box (a large number: never)
var keep_bat := false               # a batter who struck out carries his bat back
var walk_on_when_hidden := false    # the next batter starts walking up once this one is gone
var steal := false
var rundown := false
var turns: Array = []               # a rundown: the times the runner reverses
var fielders_at: Array = []         # a rundown: the two bases the fielders stand at
var end_safe_base := 0
var cover: Cover = null
var shown_from: Array = []          # the bases as they were before the play (the figures show them until it is over)
# What the director has already done on this play.
var batter_hidden_done := false
var fired := {}                     # named things done once: "snd0", "ump_OUT", "bu1"...


## The runner who is going to `base`, if any.
func runner_to(base: int) -> RunnerPlan:
	for r in runners:
		if not r.out and r.to == base and r.arrivals.has(base):
			return r
	return null


## Add an event and return it.
func add_event(time: float, at_base: int, label: String, what: String, where := Vector3.INF, runner: RunnerPlan = null) -> PlanEvent:
	var e := PlanEvent.make(time, at_base, label, what, where, runner)
	events.append(e)
	return e


func add_throw(from_pos: Vector3, to_pos: Vector3, t_leave: float, t_arrive: float, to_base: int) -> ThrowPlan:
	var t := ThrowPlan.make(from_pos, to_pos, t_leave, t_arrive, to_base)
	throws.append(t)
	return t
