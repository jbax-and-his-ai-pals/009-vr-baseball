class_name PitchNamer
extends RefCounted
## Names a thrown pitch from how it moved. This labels what you threw; it never
## picks a pitch for you.


const REFERENCE_TIME := 0.60

## a: PitchPhysics.analyze() result. arm_sign: +1 if the arm side is +X (right-hander).
static func name_pitch(a: Dictionary, typical_mph: float, arm_sign: float, knuckle: bool) -> String:
	if knuckle:
		return "Knuckleball"
	if not a.get("reached", false) or not a.has("ivb_in"):
		return "Pitch"
	# Break grows with flight time squared, so a slow pitch breaks more for the same spin.
	# Judge movement as it would be at a reference flight time (~62 mph, a typical pitch in this game), so a mild wrist
	# variation on a 55 mph pitch is not called a slider.
	var k := clampf(pow(float(a.time) / REFERENCE_TIME, 2.0), 0.6, 3.0)
	var ivb: float = a.ivb_in / k
	var run: float = a.hb_in * arm_sign / k  # positive = toward the arm side
	var slow: bool = a.speed_mph < typical_mph * 0.8
	if slow and ivb > -9.0:
		return "Changeup"
	if ivb <= -10.0:
		return "Slurve" if run <= -11.0 else "Curveball"
	if run <= -11.0:
		return "Slider"
	if run <= -7.0 and ivb < 12.0:
		return "Cutter"
	if run >= 8.0:
		return "Sinker" if ivb < 10.0 else "Two-seam"
	if ivb >= 9.0:
		return "Four-seam"
	if ivb < 2.0 and a.spin_rpm < 1500.0:
		return "Splitter"
	return "Fastball"
