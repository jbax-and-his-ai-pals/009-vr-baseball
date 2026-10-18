extends SceneTree
## The names and colors for where a pitch crossed the plate.
## Run: godot --headless --path . -s res://tests/pitch_location_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	var mid_y := 0.5 * (PitchPhysics.ZONE_TOP + PitchPhysics.ZONE_BOTTOM)
	var hw := PitchPhysics.ZONE_HALF_W
	var hh := 0.5 * (PitchPhysics.ZONE_TOP - PitchPhysics.ZONE_BOTTOM)
	_check(PitchLocation.classify(0.0, mid_y).kind == "middle", "dead center is MIDDLE")
	_check(PitchLocation.classify(hw * 0.5, mid_y).kind == "zone", "halfway to the edge is just in the zone")
	_check(PitchLocation.classify(hw * 0.7, mid_y).kind == "good", "near the edge is a good location")
	var corner := PitchLocation.classify(hw * 0.95, mid_y + hh * 0.95)
	_check(corner.kind == "corner" and corner.strike and corner.halo, "a corner is a strike with a halo")
	_check(PitchLocation.classify(hw + 0.1, mid_y).kind == "just_off" and not PitchLocation.classify(hw + 0.1, mid_y).strike,
		"a hand's width off the plate is JUST OFF")
	_check(PitchLocation.classify(hw + 0.3, mid_y).kind == "ball", "farther off is a ball")
	_check(PitchLocation.classify(hw + 0.8, mid_y).kind == "way_off", "far off is WAY OFF")
	# What is shown must agree with the umpire.
	var agree := true
	for ix in range(-12, 13):
		for iy in range(-6, 22):
			var x := ix * 0.05
			var y := iy * 0.1
			var umpire := absf(x) <= hw + PitchPhysics.BALL_RADIUS and y >= PitchPhysics.ZONE_BOTTOM - PitchPhysics.BALL_RADIUS \
				and y <= PitchPhysics.ZONE_TOP + PitchPhysics.BALL_RADIUS
			if PitchLocation.classify(x, y).strike != umpire:
				agree = false
	_check(agree, "the colors agree with the strike call everywhere")
	# Green means strike, red means ball, amber means middle.
	var g: Color = PitchLocation.classify(hw * 0.7, mid_y).color
	var r: Color = PitchLocation.classify(hw + 0.3, mid_y).color
	_check(g.g > g.r and r.r > r.g, "strikes read green and balls read red")
	_check(PitchLocation.hits_batter(0.9, 0.8) and not PitchLocation.hits_batter(0.0, 0.8) and not PitchLocation.hits_batter(0.9, 1.9)
		and not PitchLocation.hits_batter(-0.9, 0.8), "a pitch at the batter's body hits him; one over the plate, over his head or on the other side does not")
	_check(not PitchLocation.classify(0.9, 0.8).strike, "a pitch that hits him is not a strike")
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
