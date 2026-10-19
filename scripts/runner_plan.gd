class_name RunnerPlan
extends RefCounted
## What one runner does on a play: where he starts, which bases he reaches and when, and whether he is put out.
## Bases are numbered 0 (the batter's box), 1, 2, 3 and 4 (home plate, scoring). Times are seconds after contact.
## Made by Baserunning, run by PlayDirector, read by the scorebook (GameState).

## A runner who goes part of the way to the next base on a ball in the air and waits to see it land.
class Hedge:
	extends RefCounted
	var to := 0                     # the base he is hedging toward
	var t_reach := 0.0              # when he gets as far as he dares
	var t_leave := 0.0              # when he commits (or turns back)
	var return_at := -1.0           # when he is back on his bag; negative if he goes on instead

	func has_return() -> bool:
		return return_at >= 0.0


var from := 0                       # the base he started from
var to := 0                         # the base he ends up on (from when he is out or stays)
var who = null                      # the Player (or `true` when only the presence of a runner matters)
var run_factor := 1.0
var out := false
var out_base := 0                   # the base he was put out at
var t_out := 0.0
var t_start := 0.0                  # when he leaves
var arrivals := {}                  # base number -> time he gets there
var scored := false
var forced_out := false             # put out on a force (not a tag)
var dive := false                   # goes back to his bag head first
var hedge: Hedge = null
var keys: Array = []                # keyframes [[time, position], ...] when he does not simply run from base to base
# What the figure has already done on this play (set by PlayDirector as it animates).
var slid := false
var dived := false
var cheered := false


static func make(from_base: int, runner, factor: float) -> RunnerPlan:
	var r := RunnerPlan.new()
	r.from = from_base
	r.to = from_base
	r.who = runner
	r.run_factor = factor
	return r
