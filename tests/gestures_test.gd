extends SceneTree
## Hand signals: a hand held overhead is an intentional walk, a hand at the ear calls the bullpen;
## a casual wave, a hand at the chest or an occupied hand do nothing; each fires once and then rests.
## Run: godot --headless --path . -s res://tests/gestures_test.gd

var _failures := 0
const HEAD := Vector3(0.0, 1.7, 18.4)


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


## Hold a hand position for `seconds` and return every signal that fired.
func _hold(g: Gestures, hand: Vector3, seconds: float, busy := false) -> Array:
	var fired: Array = []
	var t := 0.0
	while t < seconds:
		var s := g.update(1.0 / 60.0, HEAD, hand, busy)
		if s != "":
			fired.append(s)
		t += 1.0 / 60.0
	return fired


func _init() -> void:
	var overhead := HEAD + Vector3(0.05, 0.3, 0.0)
	var ear := HEAD + Vector3(0.14, 0.0, 0.0)
	var chest := HEAD + Vector3(0.1, -0.4, -0.2)

	var g := Gestures.new()
	_check(_hold(g, overhead, 0.5).is_empty(), "a quick wave overhead does nothing")
	_check(_hold(g, chest, 0.3).is_empty() and g.progress() == 0.0, "lowering the hand starts it over")
	_check(_hold(g, overhead, 1.1) == ["intentional_walk"], "held overhead it is an intentional walk, once")
	_check(_hold(g, overhead, 2.0).is_empty(), "and it rests before it can fire again")
	_check(_hold(g, overhead, 3.5) == ["intentional_walk"], "then it can")

	var g2 := Gestures.new()
	_check(_hold(g2, ear, 0.5).is_empty(), "a brush past the ear does nothing")
	_check(_hold(g2, ear, 1.1) == ["bullpen_phone"], "a hand held at the ear calls the bullpen")

	var g3 := Gestures.new()
	_check(_hold(g3, chest, 3.0).is_empty(), "a hand at the chest does nothing, however long")
	_check(_hold(g3, HEAD + Vector3(0.0, 0.0, 0.0), 3.0).is_empty(), "nor a hand at the middle of the face")
	_check(_hold(g3, HEAD + Vector3(0.0, 0.3, 0.9), 3.0).is_empty(), "nor one raised far out in front")
	_check(_hold(g3, overhead, 3.0, true).is_empty(), "nor while the other hand holds the ball")

	var g4 := Gestures.new()
	_hold(g4, overhead, 0.5)
	var half := g4.progress()
	_check(half > 0.4 and half < 0.7, "progress shows how far along it is (%.2f)" % half)

	# The pause menu can open straight on the leave question.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	bp.menus.toggle_pause()
	bp._menu.model.can_leave = true
	bp._menu.goto("confirm_leave")
	_check(bp._menu.is_open() and bp._menu.model.screen() == "confirm_leave", "the bullpen signal opens the pause menu on its confirmation")
	bp._menu.model.back()
	_check(bp._menu.model.screen() == "pause", "and Back returns to the pause menu")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
