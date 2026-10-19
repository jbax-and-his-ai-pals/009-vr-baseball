extends SceneTree
func _init() -> void:
	ThrowLogger.disabled = true
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	for i in 40:
		bp.flight.debug_throw()
		for k in 30:
			bp._process(1.0 / 60.0)
	await process_frame
	var worst := 0.0
	var total := 0.0
	var n := 20
	for i in n:
		var t0 := Time.get_ticks_usec()
		bp.hud.refresh_hud()
		bp.hud.refresh_scoreboard()
		bp.hud.pitch_board._process(0.0)
		bp.hud.bat_board._process(0.0)
		bp.hud.info_board._process(0.0)
		bp._stadium._scoreboard._process(0.0)
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		total += dt
		worst = maxf(worst, dt)
		await process_frame
	print("board+scoreboard rebuild: mean %.2f ms, worst %.2f ms" % [total / n, worst])
	var cnt := 0
	for c in bp.get_children():
		pass
	print("Label3D total in tree: ", _count_labels(bp))
	quit()
func _count_labels(n: Node) -> int:
	var c := 1 if n is Label3D else 0
	for ch in n.get_children():
		c += _count_labels(ch)
	return c
