class_name PitchLab
extends RefCounted
## Explains a throw in plain words: what the pitch was, how it moved, and which part of YOUR motion made
## it that pitch (every pitch is measured against your own usual throw, so "1.8 x" means 1.8 times how
## much extra you did compared with normal). Pure: give it what the wrist model measured.
##
##   PitchLab.explain(label, analysis, shape)  ->  Array of short lines for a board
##   PitchLab.how_to(label)                    ->  one line on how to throw that pitch

## A deviation this big (in your own standard deviations) is "doing something".
const NOTICE := 0.9


## label: the pitch's name; analysis: PitchPhysics.analyze(); shape: WristModel.shape() ({} if none).
static func explain(label: String, analysis: Dictionary, shape: Dictionary) -> Array:
	var lines: Array = []
	if not analysis.get("reached", false):
		return ["%s: it did not reach the plate" % label]
	lines.append("%s  %.0f mph  %d rpm" % [label, float(analysis.speed_mph), roundi(float(analysis.spin_rpm))])
	if analysis.has("ivb_in"):
		var rise := float(analysis.ivb_in)
		var run := float(analysis.hb_in)
		lines.append("Moved %s %.0f in, and %.0f in %s" % ["up" if rise >= 0.0 else "down", absf(rise), absf(run), "to the right" if run >= 0.0 else "to the left"])
	if shape.is_empty():
		return lines
	var why := _reasons(shape)
	if why.is_empty():
		lines.append("Your usual throw: nothing special added")
	else:
		for w in why:
			lines.append(w)
	return lines


static func _reasons(shape: Dictionary) -> Array:
	var out: Array = []
	var snap := float(shape.get("z_snap", 0.0))
	var side := float(shape.get("z_side", 0.0))
	var gyro := float(shape.get("z_gyro", 0.0))
	var slot := float(shape.get("z_slot", 0.0))
	var wind := float(shape.get("z_wind", 0.0))
	if bool(shape.get("knuckle", false)) or float(shape.get("stiff", 0.0)) > 0.6:
		out.append("A dead wrist, no spin: knuckleball")
		return out
	if snap > NOTICE:
		out.append("Wrist flick %.1f x your normal: it dives (curve)" % (1.0 + snap * 0.5))
	elif snap < -NOTICE:
		out.append("A lazy wrist: backspin carries it (rises)")
	if absf(side) > NOTICE:
		out.append("Wrist twist %.1f x your normal: it breaks sideways (slider)" % (1.0 + absf(side) * 0.5))
	if absf(gyro) > NOTICE:
		out.append("Rolled wrist %.1f x your normal: it cuts (cutter)" % (1.0 + absf(gyro) * 0.5))
	if slot < -NOTICE:
		out.append("Arm slot lower than your normal: it runs and sinks")
	if wind > NOTICE:
		out.append("A bigger windup than normal: more arc, more dive")
	return out


## One line on how to throw each pitch.
static func how_to(label: String) -> String:
	match label:
		"Fastball", "Four-seam":
			return "Fastball: throw it your usual way, compact and smooth."
		"Changeup":
			return "Changeup: your usual arm motion, but clearly slower."
		"Slider":
			return "Slider: twist your wrist like turning a doorknob at release."
		"Curveball", "Slurve":
			return "Curveball: a hard wrist flick at the end of a moderate throw, or a bigger, higher windup."
		"Cutter":
			return "Cutter: roll the controller about its pointing line, like a screwdriver."
		"Sinker", "Two-seam":
			return "Sinker: a lower arm slot than usual."
		"Knuckleball":
			return "Knuckleball: a straight push with a dead wrist and almost no rotation."
	return "Throw it your own way; the game measures it against your usual throw."
