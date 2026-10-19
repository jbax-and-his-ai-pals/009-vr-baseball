extends SceneTree
## Performance guards that run without a GPU or headset:
##  - the scene's estimated draw calls / triangles stay inside the Quest budget, both idle and
##    with a busy at-bat (many pitches and batted balls at once);
##  - the quality governor degrades under sustained slowness, ignores hitches, and recovers.
## Real GPU numbers come from tools/perf.sh (it needs a window).
## Run: godot --headless --path . -s res://tests/perf_test.gd

# Budgets for a Quest 3 at 90 Hz on the mobile renderer, with headroom for the rest of a full
# baseball sim (fielders, runners, umpires, UI) to be added.
const IDLE_DRAW_BUDGET := 60
const BUSY_DRAW_BUDGET := 100
const TRIANGLE_BUDGET := 250000

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


## Estimate (draw calls, triangles) from the scene tree: one draw per visible mesh surface /
## multimesh / label, triangles from mesh data times instance count.
func _estimate(n: Node, acc: Dictionary) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	if n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm and mm.mesh:
			acc.draws += 1
			acc.tris += _mesh_tris(mm.mesh) * mm.visible_instance_count if mm.visible_instance_count >= 0 else _mesh_tris(mm.mesh) * mm.instance_count
	elif n is MeshInstance3D:
		var mesh := (n as MeshInstance3D).mesh
		if mesh:
			acc.draws += mesh.get_surface_count()
			acc.tris += _mesh_tris(mesh)
	elif n is Label3D:
		acc.draws += 1
	for c in n.get_children():
		_estimate(c, acc)


func _mesh_tris(mesh: Mesh) -> int:
	var t := 0
	for i in mesh.get_surface_count():
		var arrays: Array
		if mesh is PrimitiveMesh:
			arrays = (mesh as PrimitiveMesh).get_mesh_arrays()
		else:
			arrays = mesh.surface_get_arrays(i)
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			t += (idx as PackedInt32Array).size() / 3
		else:
			t += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t


func _init() -> void:
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame

	var idle := {"draws": 0, "tris": 0}
	_estimate(bp, idle)
	print("idle: ~%d draw calls, ~%dk triangles" % [idle.draws, idle.tris / 1000])
	_check(idle.draws <= IDLE_DRAW_BUDGET, "idle draw calls within budget (%d <= %d)" % [idle.draws, IDLE_DRAW_BUDGET])
	_check(idle.tris <= TRIANGLE_BUDGET, "idle triangles within budget (%dk <= %dk)" % [idle.tris / 1000, TRIANGLE_BUDGET / 1000])

	# A busy moment: the maximum number of simultaneous pitches, plus batted balls.
	var peak := 0
	for i in 8:
		bp.flight.debug_throw()
	for frame in 90:
		bp._process(1.0 / 60.0)
		var acc := {"draws": 0, "tris": 0}
		_estimate(bp, acc)
		peak = maxi(peak, acc.draws)
	print("busy (8 pitches in the air, batter swinging): peak ~%d draw calls" % peak)
	_check(peak <= BUSY_DRAW_BUDGET, "busy draw calls within budget (%d <= %d)" % [peak, BUSY_DRAW_BUDGET])

	# Governor behavior.
	var g := PerfGovernor.new()
	g.set_refresh_rate(90.0)
	for i in 120:                       # two seconds at 20 ms: sustained slowness
		g.update(0.020)
	_check(g.level >= 1, "sustained slow frames lower the quality level (level %d)" % g.level)
	var after_slow := g.level
	var g2 := PerfGovernor.new()
	g2.set_refresh_rate(90.0)
	for i in 600:
		g2.update(0.0111)
		if i % 50 == 0:
			g2.update(0.4)              # an occasional 400 ms hitch
	_check(g2.level == 0, "isolated hitches do not trigger a downgrade")
	for i in 1500:                      # then 6+ seconds of very fast frames
		g.update(0.006)
	_check(g.level < after_slow, "quality climbs back when there is headroom (%d -> %d)" % [after_slow, g.level])
	var g3 := PerfGovernor.new()
	g3.set_refresh_rate(90.0)
	for i in 3000:
		g3.update(0.05)
	_check(g3.level == PerfGovernor.MAX_LEVEL, "the level never exceeds the maximum")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
