extends SceneTree
## BatterPresenter alone: the walk from the dugout ends in the box on the right side with the bat
## up, announces his arrival once, flinches from a pitch at his body, hitches on a close take, and
## drops his bat once.
## Run: godot --headless --path . -s res://tests/batter_presenter_test.gd

var _failures := 0
var _arrived := 0
var _steps := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	var bp := BatterPresenter.new()
	root.add_child(bp)
	bp.setup(root)
	bp.arrived.connect(func(): _arrived += 1)
	bp.walk_step.connect(func(_at): _steps += 1)
	await process_frame

	for lefty in [false, true]:
		_arrived = 0
		var dur := bp.begin_walk_on(lefty)
		_check(dur > 2.0 and dur < 12.0 and bp.is_walking(), "the walk takes a few seconds (%.1f s)" % dur)
		_check(bp.batter.global_position.distance_to(BatterPresenter.DUGOUT_ENTRY) < 0.1, "he starts at the dugout")
		var t := 0.0
		var carried_low := false
		while bp.is_walking() and t < 20.0:
			bp.update(0.05)
			t += 0.05
			if bp.batter._carry > 0.9:
				carried_low = true
		_check(carried_low, "the bat hangs low while he walks")
		_check(_arrived == 1 and not bp.is_walking(), "he arrives once (%d)" % _arrived)
		_check(bp.batter.global_position.distance_to(bp.home.origin) < 0.01 and (bp.home.origin.x < 0.0) == lefty,
			"in his own box (%s, x %.2f)" % ["left" if lefty else "right", bp.home.origin.x])
		_check(bp.batter._carry_goal == 0.0, "with the bat coming up")

	# Taking a pitch.
	var at_body := {"reached": true, "plate_pos": Vector3(0.9, 0.8, 0.0), "time": 0.45}
	var close := {"reached": true, "plate_pos": Vector3(0.3, 0.9, 0.0), "time": 0.45}
	var far := {"reached": true, "plate_pos": Vector3(0.0, 3.0, 0.0), "time": 0.45}
	_check(bp.take(at_body, false, false, 0.9) == "flinch", "a pitch at a righty's body makes him flinch")
	_check(bp.take(at_body, false, true, 0.9) == "", "...but not at a lefty's")
	_check(bp.take(close, false, false, 0.1) == "check" and bp.take(close, false, false, 0.9) == "", "a close take sometimes draws a check swing")
	_check(bp.take(close, true, false, 0.1) == "", "not while he is still finishing a swing")
	_check(bp.take(far, false, false, 0.1) == "" and bp.take({"reached": false}, false, false, 0.0) == "", "a pitch nowhere near is just taken")

	# The bat.
	bp.snap_to_box()
	var xf = bp.drop_bat()
	_check(xf is Transform3D and not bp.batter._bat.visible, "he lets go of the bat")
	bp.batter.visible = false
	_check(bp.drop_bat() == null, "nothing to drop when he is off screen")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
