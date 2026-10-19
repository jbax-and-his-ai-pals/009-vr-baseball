extends SceneTree
## Renders the bullpen scene for a while with a desktop camera and prints GPU-independent
## render stats (draw calls, objects, triangles) plus CPU frame times.
##
## Draw calls and triangles are what decide whether a scene fits a Quest, and they are the
## same on any machine, so this tells you something real even though the PC GPU is faster.
##
## Run via tools/perf.sh (adds --xr-mode off and parks the window off-screen):
##   godot --path . --xr-mode off -s res://tools/perf_probe.gd -- [--demo] [--frames=300] [--budget]

const WARMUP := 40

var _frames := 0
var _total := 150
var _check_budget := false
var _quest := false                 # the stricter, provisional budget for a standalone Quest (until it is measured on the device)
var _stats := {"draw": [], "objects": [], "tris": [], "frame_ms": []}
var _scene: Node
var _start_ms := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_total = int(a.substr(9))
		if a == "--budget":
			_check_budget = true
		if a == "--quest-budget":
			_check_budget = true
			_quest = true
	_scene = load("res://scenes/bullpen.tscn").instantiate()
	_scene.menu_on_start = false
	root.add_child(_scene)
	_start_ms = Time.get_ticks_msec()


func _process(delta: float) -> bool:
	_frames += 1
	if _frames > WARMUP:
		_stats.frame_ms.append(delta * 1000.0)
		_stats.draw.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_stats.objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		_stats.tris.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if _frames >= WARMUP + _total:
		_report()
		return true
	return false


func _mean(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / maxf(a.size(), 1.0)


func _max(a: Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, float(v))
	return m


func _count_nodes(n: Node, by_class: Dictionary) -> int:
	var c := 1
	by_class[n.get_class()] = by_class.get(n.get_class(), 0) + 1
	for ch in n.get_children():
		c += _count_nodes(ch, by_class)
	return c


func _report() -> void:
	var by_class := {}
	var nodes := _count_nodes(root, by_class)
	var draws := _mean(_stats.draw)
	var tris := _mean(_stats.tris)
	print("=== render stats over %d frames ===" % _total)
	print("draw calls   mean %5.0f  max %5.0f" % [draws, _max(_stats.draw)])
	print("objects      mean %5.0f  max %5.0f" % [_mean(_stats.objects), _max(_stats.objects)])
	print("triangles    mean %7.0f  max %7.0f" % [tris, _max(_stats.tris)])
	print("frame time   mean %5.2f ms  max %5.2f ms (this PC, vsync off: only for comparing runs; Quest budget at 90 Hz is 11.1 ms)" % [_mean(_stats.frame_ms), _max(_stats.frame_ms)])
	print("nodes        %d  (MeshInstance3D %d, MultiMeshInstance3D %d, Label3D %d)" % [
		nodes, by_class.get("MeshInstance3D", 0), by_class.get("MultiMeshInstance3D", 0), by_class.get("Label3D", 0)])
	print("video memory %.1f MB | static memory %.1f MB" % [
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	if _check_budget:
		var ok := true
		# Conservative Quest 3 targets at 90 Hz with MSAA on the mobile renderer. --quest-budget is stricter: the
		# numbers to stay under for a standalone Quest until they are calibrated on the device (ROADMAP Phase 1).
		var max_draw := 120.0 if _quest else 220.0
		var max_tris := 250000.0 if _quest else 350000.0
		var max_labels := 80 if _quest else 100000
		var max_vram := 160.0 if _quest else 1.0e9
		if _max(_stats.draw) > max_draw:
			print("OVER BUDGET: draw calls %.0f > %.0f" % [_max(_stats.draw), max_draw])
			ok = false
		if _max(_stats.tris) > max_tris:
			print("OVER BUDGET: triangles %.0f > %.0f" % [_max(_stats.tris), max_tris])
			ok = false
		if int(by_class.get("Label3D", 0)) > max_labels:
			print("OVER BUDGET: Label3D nodes %d > %d" % [int(by_class.get("Label3D", 0)), max_labels])
			ok = false
		var vram: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
		if vram > max_vram:
			print("OVER BUDGET: video memory %.1f MB > %.0f MB" % [vram, max_vram])
			ok = false
		print("BUDGET OK" if ok else "BUDGET FAILED")
		quit(0 if ok else 1)
