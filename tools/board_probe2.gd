extends SceneTree
func _init() -> void:
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	for i in 600:
		bp._process(1.0 / 60.0)
		if i % 90 == 0 and bp._batter_ready:
			bp._debug_throw()
	await process_frame
	await process_frame
	for b in [bp._pitch_board, bp._bat_board, bp._info_board]:
		var mesh_h := 0.0
		var min_y := 0.0
		for c in b.get_children():
			if c is MeshInstance3D:
				var bb := (c as MeshInstance3D).get_aabb()
				mesh_h = bb.size.y
				min_y = bb.position.y
		var low := 0.0
		for c in b.get_children():
			if c is Label3D:
				var l := c as Label3D
				var ab := l.get_aabb()
				low = minf(low, l.position.y + ab.position.y)
				if l.text.count("\n") >= 4:
					print("   ", b.title, " label lines=", l.text.count("\n") + 1, " pos.y=", l.position.y, " aabb.y=", ab.position.y, " size=", ab.size.y)
		print(b.title, ": panel from y=", min_y, " height=", mesh_h, "  lowest text y=", low, "  lines=", b.lines.size(), " rows=", b.rows.size())
	quit()
