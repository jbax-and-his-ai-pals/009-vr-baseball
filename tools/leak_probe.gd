extends SceneTree
## Runs a long game headless and reports what grows: nodes, objects, orphans, memory, step cost.
func _init() -> void:
	ThrowLogger.override_path = "user://test_throws.jsonl"
	ThrowLogger.disabled = true
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_innings = 9
	root.add_child(bp)
	await process_frame
	var t_throw := 0.0
	var wall := Time.get_ticks_usec()
	var step_us := 0.0
	var steps := 0
	for i in 60 * 60 * 20:                 # 20 minutes of game time
		var t0 := Time.get_ticks_usec()
		bp._process(1.0 / 60.0)
		step_us += Time.get_ticks_usec() - t0
		steps += 1
		t_throw -= 1.0 / 60.0
		if t_throw <= 0.0 and bp._batter_ready:
			t_throw = 1.0
			bp._debug_throw()
		if bp._game.over:
			bp._game_over_timer = 0.01
		if i % (60 * 120) == 0:
			print("t=%4ds | nodes %d | objects %d | orphans %d | static %.1f MB | hits %d pitches %d | step %.0f us" % [
				i / 60, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
				Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
				bp._hits.size(), bp._pitches.size(), step_us / maxf(steps, 1)])
			step_us = 0.0
			steps = 0
		if i % 30 == 0:
			await process_frame            # let queued frees run, like a real frame
	quit()
