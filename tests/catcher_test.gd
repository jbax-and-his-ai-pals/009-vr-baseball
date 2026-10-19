extends SceneTree
## The catcher's glove goes where it is told (within reach), is as good as you can get when it is
## not, and the people behind the plate animate in the real game.
## Run: godot --headless --path . -s res://tests/catcher_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _hand(d: Doll) -> Vector3:
	var sk: Skeleton3D = d._skeleton
	var fore := sk.get_bone_global_pose(Doll.FORE_L)
	return sk.global_transform * (fore.origin + fore.basis * Vector3(0.0, -0.33, 0.0))


func _init() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0.0, 1.5, 6.0)
	for style in [Doll.Style.SOFT, Doll.Style.PAPER]:
		var name := "soft" if style == Doll.Style.SOFT else "paper"
		var d := Doll.create(root, Vector3(0.0, 0.0, -1.35), Color.DARK_BLUE, Color.GRAY, Color.DARK_BLUE, true, style, "catcher")
		await process_frame
		await process_frame
		var worst := 0.0
		for target in [Vector3(0.0, 0.8, -0.9), Vector3(0.25, 0.4, -0.9), Vector3(-0.2, 1.1, -0.85), Vector3(0.1, 0.25, -0.95)]:
			d.aim_glove(target, 1.0)
			for i in 6:
				await process_frame
			var h := _hand(d)
			# A paper doll shows its profile to the camera, so what counts is where the glove is on screen.
			var err := h.distance_to(target) if style == Doll.Style.SOFT else Vector2(h.x - target.x, h.y - target.y).length()
			print("    %s target %s -> hand %s (miss %.0f cm)" % [name, target, h, err * 100.0])
			worst = maxf(worst, err)
		_check(worst < 0.15, "a %s catcher puts his glove on a pitch location within reach (worst miss %.0f cm)" % [name, worst * 100.0])
		# Out of reach: he gets as close as he can and stops at arm's length.
		d.aim_glove(Vector3(0.0, 2.8, -0.9), 1.0)
		for i in 6:
			await process_frame
		var far := _hand(d)
		_check(far.distance_to(Vector3(0.0, 2.8, -0.9)) > 0.5 and far.y > 0.8, "an unreachable target is reached for, not teleported to (%s)" % name)
		# A deep squat is low, and standing is tall.
		d.set_squat(1.0, 0.05)
		for i in 10:
			await process_frame
		var low := _hand(d).y
		d.release_glove()
		d.set_squat(0.0, 0.05)
		for i in 10:
			await process_frame
		d.aim_glove(Vector3(0.0, 1.0, -0.9), 0.0)
		var tall: float = d._skeleton.get_bone_global_pose(Doll.HEAD).origin.y
		var crouched_head := 0.0
		d.set_squat(1.0, 0.05)
		for i in 10:
			await process_frame
		crouched_head = d._skeleton.get_bone_global_pose(Doll.HEAD).origin.y
		_check(crouched_head < tall - 0.3, "the squat lowers the head by more than 30 cm (%s: %.2f -> %.2f)" % [name, tall, crouched_head])
		d.queue_free()

	# In the real game: pitches are tracked and the umpire makes calls.
	ThrowLogger.disabled = true
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	var tracked := 0
	var ump_clips := {}
	for i in 12:
		bp.flight.batter_free_at = 1e9               # he takes everything, so every pitch ends at the catcher
		bp.flight.debug_throw()
		if not bp._crew._track.is_empty():
			tracked += 1
		for k in 90:
			bp._process(1.0 / 60.0)
			if bp._umpire._clip != "":
				ump_clips[bp._umpire._clip] = true
	_check(tracked >= 10, "the catcher tracks each pitch (%d of 12)" % tracked)
	_check(ump_clips.has("ump_strike"), "the umpire rings up strikes (%s)" % str(ump_clips.keys()))
	_check(bp._catcher._glove_weight > 0.0 and bp._catcher.position.distance_to(Vector3(0.0, 0.0, -1.35)) < 0.8,
		"and he is back behind the plate with his glove up")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
