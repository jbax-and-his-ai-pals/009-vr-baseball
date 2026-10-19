class_name ThrowPlan
extends RefCounted
## One throw on a play: from where to where, leaving at t0 and arriving at t1 (seconds after contact), to a base.
## PlayDirector turns these into throws between players and sets `by` and `rec` (who throws and who catches).

var from := Vector3.ZERO
var to := Vector3.ZERO
var t0 := 0.0
var t1 := 0.0
var base := 0
var by := 0                         # the fielder who throws (0 until the director knows)
var rec := 0                        # the fielder who catches it


static func make(from_pos: Vector3, to_pos: Vector3, t_leave: float, t_arrive: float, to_base: int) -> ThrowPlan:
	var t := ThrowPlan.new()
	t.from = from_pos
	t.to = to_pos
	t.t0 = t_leave
	t.t1 = t_arrive
	t.base = to_base
	return t
