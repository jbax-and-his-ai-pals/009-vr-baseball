class_name StealModel
extends RefCounted
## The running game, from the pitcher's side: when a runner goes, whether he makes it, how far
## off the bag he stands, and whether a throw over catches him. Pure functions.
##
## The pitcher's part is his DELIVERY TIME: from the moment he starts his motion until the ball
## leaves his hand. The runner breaks when the motion starts; the longer you take, the better
## his chance. Then the ball takes its flight time to reach the catcher, who needs his pop time
## to get it away and across to the base.

const POP_TIME := 1.85            # catcher's glove to the infielder's glove at second (seconds)
const POP_SIGMA := 0.12
const RUN_REACTION := 0.25        # a runner needs this long to read the motion and go
const LEAD_MIN := 1.6             # meters off the bag right after a throw over
const LEAD_MAX := 4.2


## Chance this runner takes off on this pitch. A runner on first with second open is the
## classic steal; a runner on second with third open is rarer; nobody steals home here.
static func steal_chance(runner: Player, base: int, outs: int, bases: Array, pitcher_fatigue: float = 0.0) -> float:
	if runner == null or base < 1 or base > 2:
		return 0.0
	if bases[base] != null:                 # the base ahead is occupied
		return 0.0
	var speed := runner.run_factor()
	var aggression := clampf(runner.aggression / 50.0, 0.4, 1.6)
	var p := 0.060 * pow(speed, 4.0) * aggression
	if base == 2:
		p *= 0.30
	if outs >= 2:
		p *= 1.25
	return clampf(p * (1.0 + 0.5 * pitcher_fatigue), 0.0, 0.35)


## A play called with the pitch (beyond a plain steal): "squeeze" (runner on third breaks on the
## delivery, the batter bunts him in: late, close, a hitter who is not a slugger) or "hit_and_run"
## (runner on first alone breaks, the batter must protect him: a contact hitter). "" for none.
## `margin` is the batting team's runs minus the fielding team's.
static func play_call(bases: Array, outs: int, strikes: int, inning: int, margin: int, batter: BatterProfile, rng: RandomNumberGenerator) -> String:
	if batter == null or strikes >= 2:
		return ""
	if bases[2] != null and outs < 2 and inning >= 6 and margin >= -1 and margin <= 0 and batter.power < 0.7:
		var p_sq := 0.14 * (0.5 + 0.5 * batter.contact) * (1.0 - batter.power)
		if rng.randf() < p_sq:
			return "squeeze"
	if bases[0] != null and bases[1] == null and bases[2] == null and outs < 2 and batter.contact >= 0.6:
		if rng.randf() < 0.07 * batter.contact:
			return "hit_and_run"
	return ""


## Seconds from the runner's first step to the next base from his lead.
static func run_time(runner: Player, from_base: int, lead: float) -> float:
	var rf := runner.run_factor() if runner != null else 1.0
	var d := 27.4 - lead
	# Speed matters, but a steal is mostly the jump and the lead, so it counts for half.
	return RUN_REACTION + d / (8.4 * (1.0 + (maxf(rf, 0.5) - 1.0) * 0.5))


## Does he make it? delivery_time + the ball's flight + the catcher's pop, against his run.
## Returns {"safe": bool, "t_ball": float, "t_run": float}.
static func resolve(delivery_time: float, flight_time: float, run_t: float, rng: RandomNumberGenerator,
		catcher_pop: float = POP_TIME) -> Dictionary:
	var t_ball := delivery_time + flight_time + catcher_pop + rng.randfn(0.0, POP_SIGMA)
	return {"safe": run_t <= t_ball, "t_ball": t_ball, "t_run": run_t}


## How far off his base a runner stands: a little more for a fast, aggressive runner, a lot more
## if you have not thrown over in a while, and he shrinks right after a throw.
static func lead(runner: Player, pitches_since_throw: int) -> float:
	var base_lead := 2.4
	if runner != null:
		base_lead += 0.6 * (runner.run_factor() - 1.0) * 3.0 + (runner.aggression - 50.0) * 0.008
	var growth := 0.22 * clampf(float(pitches_since_throw), 0.0, 8.0)
	if pitches_since_throw <= 0:
		base_lead -= 0.8
	return clampf(base_lead + growth, LEAD_MIN, LEAD_MAX)


## The lead he takes right after a throw over (short until he is sure again).
static func lead_after_throw() -> float:
	return LEAD_MIN


## Probability a throw over gets him: a bigger lead and a more accurate, harder throw both
## help. angle_error is how many degrees the throw was off the line to the base.
## `quick` is how long the move took from the start of his motion to the release (a snap throw is
## about half a second; a slow, telegraphed one a full second), `base` and `lefty` decide how well
## he hides it (see deception()).
static func pickoff_chance(lead_m: float, angle_error: float, throw_speed: float, runner: Player,
		quick: float = 0.7, base: int = 2, lefty: bool = false) -> float:
	var reach := clampf((lead_m - 1.8) / 2.2, 0.0, 1.0)             # no chance on a short lead
	var accuracy := clampf(1.0 - angle_error / 22.0, 0.0, 1.0)
	var arm := clampf(throw_speed / 28.0, 0.3, 1.0)
	var jump := clampf(1.15 - 0.15 * (runner.run_factor() if runner != null else 1.0) * 1.0, 0.7, 1.1)
	var snap := clampf(1.3 - 0.6 * quick, 0.7, 1.2)
	return clampf(0.32 * reach * accuracy * arm * jump * snap * deception(base, lefty), 0.0, 0.42)


## A left-hander faces first base, so the runner there cannot see the move start; a right-hander faces
## third. The other way round the runner reads the shoulder turn.
static func deception(base: int, lefty: bool) -> float:
	match base:
		1:
			return 1.25 if lefty else 0.95
		3:
			return 0.85 if lefty else 1.1
	return 1.0


## Does the AI pitcher step off or throw over before this pitch? More when a runner has wandered off
## and he has not been held on lately; almost never right after a throw.
static func ai_throws_over(lead_m: float, pitches_since_throw: int, rng: RandomNumberGenerator) -> bool:
	var p := clampf((lead_m - 2.8) * 0.10, 0.0, 0.30)
	if pitches_since_throw <= 1:
		p *= 0.15
	return rng.randf() < p


## What a throw over does, given the chance it gets him (`p_out`) and how far off the bag he was:
##   "out"                 picked off cleanly
##   "rundown_out"         caught between the bases and run down
##   "rundown_safe_back"   caught in a rundown but gets back to the bag
##   "rundown_safe_ahead"  caught in a rundown but beats it to the next base
##   "safe"                back in time, nothing more
## A long lead is what makes a rundown possible.
static func pickoff_outcome(p_out: float, lead: float, rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	if r < p_out * 0.55:
		return "out"
	if r < p_out:
		return "rundown_out"
	var p_trap := clampf((lead - 2.6) / 6.0, 0.0, 0.18)
	if rng.randf() < p_trap:
		return "rundown_safe_back" if rng.randf() < 0.6 else "rundown_safe_ahead"
	return "safe"


## Is this a balk? He started his motion (delivery_started) and then did not throw, with a
## runner on, or he threw to a base nobody was on.
static func is_balk(runners_on: bool, delivery_started: bool, released: bool, threw_to_empty_base: bool) -> bool:
	if not runners_on:
		return false
	if threw_to_empty_base:
		return true
	return delivery_started and not released
