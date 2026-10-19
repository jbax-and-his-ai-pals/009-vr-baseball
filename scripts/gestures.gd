class_name Gestures
extends RefCounted
## Hand signals with your free (glove) hand, for the things a pitcher signals instead of throws:
##   a hand held high above the head for a moment  -> "intentional_walk" (wave him on)
##   a hand held at the ear, as if on a phone       -> "bullpen_phone"   (call for the reliever)
## Pure: feed it the head and hand positions each frame and it says when a signal is complete.
## Each signal must be held (HOLD seconds), is ignored while the other hand holds the ball, and
## needs a pause (COOLDOWN) before it can fire again, so a casual wave does nothing.

const HOLD := 0.9
const COOLDOWN := 3.0
const OVERHEAD_ABOVE := 0.12        # the hand this far above the head...
const OVERHEAD_REACH := 0.35        # ...and within this of straight over it
const EAR_MIN := 0.06               # at the ear: this far from the head's centre...
const EAR_MAX := 0.24               # ...but no further,
const EAR_HEIGHT := 0.14            # ...at about head height

var _up := 0.0
var _ear := 0.0
var _cool := 0.0


## Returns "" while nothing is complete, else "intentional_walk" or "bullpen_phone" (once per signal).
func update(delta: float, head: Vector3, hand: Vector3, busy: bool) -> String:
	if _cool > 0.0:
		_cool -= delta
	if busy or _cool > 0.0:
		_up = 0.0
		_ear = 0.0
		return ""
	var flat := Vector2(hand.x - head.x, hand.z - head.z).length()
	var dy := hand.y - head.y
	var overhead := dy > OVERHEAD_ABOVE and flat < OVERHEAD_REACH
	var d := hand.distance_to(head)
	var at_ear := flat >= EAR_MIN and d <= EAR_MAX and absf(dy) <= EAR_HEIGHT
	_up = _up + delta if overhead else 0.0
	_ear = _ear + delta if at_ear else 0.0
	if _up >= HOLD:
		_up = 0.0
		_cool = COOLDOWN
		return "intentional_walk"
	if _ear >= HOLD:
		_ear = 0.0
		_cool = COOLDOWN
		return "bullpen_phone"
	return ""


## How far along a signal is (0..1), for a progress cue.
func progress() -> float:
	return maxf(_up, _ear) / HOLD
