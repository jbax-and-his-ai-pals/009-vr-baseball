class_name Comfort
extends RefCounted
## Small pure helpers for comfort and accessibility settings.

## The head height a standing pitcher is built around (metres above the floor the game assumes).
const STANDING_HEAD := 1.65
const MAX_LIFT := 0.8


## How far to lift the play space so a seated head (`head_y` above the tracked floor) sits where a
## standing one would. Never lowers, and never lifts more than MAX_LIFT (a head that is far lower than
## sitting is probably a tracking glitch, not a person).
static func seated_offset(head_y: float) -> float:
	return clampf(STANDING_HEAD - head_y, 0.0, MAX_LIFT)
