extends SceneTree
## PlateCrew on its own, with no game around it: the catcher blocks a dirt ball and says so, the
## umpire's call arrives after its beat with the right voice, he steps aside and comes back, and a
## pop throw waits for its time.
## Run: godot --headless --path . -s res://tests/plate_crew_test.gd

var _failures := 0
var _blocks := 0
var _voices: Array = []
var _throws := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	var catcher := Doll.create(root, PlateCrew.CATCHER_HOME, Color.DARK_BLUE, Color.WHITE, Color.DARK_BLUE, true, Doll.Style.SOFT, "catcher")
	var ump := Doll.create(root, Vector3(0, 0, PlateCrew.UMP_HOME_Z), Color.BLACK, Color.GRAY, Color.BLACK, false, Doll.Style.SOFT, "umpire")
	var crew := PlateCrew.new()
	root.add_child(crew)
	crew.setup(catcher, ump)
	crew.blocked.connect(func(_at): _blocks += 1)
	crew.umpire_voice.connect(func(id: String): _voices.append(id))
	crew.throw_started.connect(func(_at): _throws += 1)
	await process_frame

	# A pitch in the dirt: he blocks it.
	crew.begin_pitch({"reached": true, "time": 0.4, "plate_pos": Vector3(0.1, 0.05, 0.0)}, 99.0)
	for i in 40:
		crew.update(0.02)
	_check(_blocks == 1, "a ball in the dirt is blocked, once (%d)" % _blocks)

	# A strike: the call comes after its beat, with the usual voice; a strike three has its own.
	crew.call_it("ump_strike", 0.3, 0.9)
	crew.update(0.1)
	_check(_voices.is_empty(), "the call waits for its beat")
	for i in 5:
		crew.update(0.1)
	_check(_voices == ["ump_strike"], "then he says strike (%s)" % str(_voices))
	crew.call_it("ump_out", 0.1, 1.0, "ump_strike_three")
	crew.call_it("ump_point", 0.1, 1.0)
	for i in 5:
		crew.update(0.1)
	_check(_voices == ["ump_strike", "ump_strike_three"], "strike three has its own call, and a point is silent (%s)" % str(_voices))

	# A ball in play: he steps aside to the side it went, and comes back.
	crew.step_aside(10.0)
	for i in 60:
		crew.update(0.05)
	_check(ump.position.x < -1.0, "he steps aside (x %.2f)" % ump.position.x)
	crew.return_to_plate()
	for i in 80:
		crew.update(0.05)
	_check(ump.position.distance_to(Vector3(0, 0, PlateCrew.UMP_HOME_Z)) < 0.05, "and is back behind the plate")

	# The pop throw waits for its time.
	crew.pop_throw_in(0.5, Vector3(0, 1, 38))
	for i in 3:
		crew.update(0.1)
	_check(_throws == 0, "the throw has not started yet")
	for i in 4:
		crew.update(0.1)
	_check(_throws == 1, "it starts on time")

	# A wild pitch sends him after it, and he comes back.
	crew.chase()
	_check(crew.is_chasing(), "a wild pitch sends the catcher after it")
	for i in 90:
		crew.update(0.05)
	_check(not crew.is_chasing(), "and he is back (%.2f from home)" % catcher.position.distance_to(PlateCrew.CATCHER_HOME))

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
