extends SceneTree
## The base umpires: they stand where umpires stand, face their base, make the call after a beat,
## and in the real scene rule on a play at first.
## Run: godot --headless --path . -s res://tests/base_umpires_test.gd

var _failures := 0
var _heard: Array = []


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	var dolls: Array[Doll] = []
	for i in 3:
		dolls.append(Doll.create(root, Vector3.ZERO, Color.BLACK, Color.GRAY, Color.BLACK, false, Doll.Style.SOFT, "base_umpire"))
	var bu := BaseUmpires.new()
	root.add_child(bu)
	bu.setup(dolls[0], dolls[1], dolls[2])
	bu.umpire_voice.connect(func(id: String, at: Vector3): _heard.append([id, at]))
	await process_frame

	_check(dolls[0].position.x < -20.0 and dolls[2].position.x > 20.0 and absf(dolls[1].position.x) < 6.0, "first and third base umpires in foul ground, second in the infield")
	for i in 3:
		var base: int = i + 1
		var fwd := Vector3(sin(dolls[i].rotation.y), 0.0, cos(dolls[i].rotation.y))
		var to_base: Vector3 = ((BaseUmpires.BASES[base] as Vector3) - dolls[i].position).normalized()
		_check(fwd.dot(to_base) > 0.99, "umpire %d faces his base" % base)
	bu.call_it(1, "ump_out")
	bu.update(0.05)
	_check(_heard.is_empty() and not dolls[0].busy(), "the call waits for its beat")
	bu.update(0.2)
	_check(_heard.size() == 1 and _heard[0][0] == "ump_out" and (_heard[0][1] as Vector3).x < -20.0 and dolls[0].busy(), "then he gestures and calls it from where he stands")
	bu.call_it(2, "ump_safe")
	bu.call_it(3, "ump_safe")
	bu.update(0.5)
	_check(_heard.size() == 3 and dolls[1].busy() and dolls[2].busy(), "each base has his own umpire")
	bu.call_it(4, "ump_out")
	bu.update(1.0)
	_check(_heard.size() == 3, "home plate is not his to call")

	# In the scene: a grounder to short, out at first: the first base umpire rules on it.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	var calls: Array = []
	bp._base_umps.umpire_voice.connect(func(id: String, at: Vector3): calls.append([id, at]))
	bp.flight.debug_hit(78.0, -6.0, 18.0)
	for i in 60 * 14:
		bp._process(1.0 / 60.0)
		if not calls.is_empty():
			break
	_check(not calls.is_empty() and (calls[0][1] as Vector3).x < -20.0, "the first base umpire calls the play at first (%s)" % str(calls.map(func(c): return c[0])))
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
