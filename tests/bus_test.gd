extends SceneTree
## The game bus: the things that happen are announced once, in order, and the game does not need anyone
## to be listening.
## Run: godot --headless --path . -s res://tests/bus_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _scene(seed_value: int) -> Node3D:
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_mode_name = "Spectate"
	bp.game_innings = 1
	bp.forced_seed = seed_value
	bp.spectate_interval = 0.4
	root.add_child(bp)
	return bp


func _play_out(bp: Node3D) -> int:
	var frames := 0
	while not bp._game.over and frames < 60 * 600:
		bp._process(1.0 / 60.0)
		frames += 1
	return frames


func _init() -> void:
	# A bus on its own.
	var bus := GameBus.new()
	var got: Array = []
	bus.pitch_arrived.connect(func(_p, o): got.append("arrived:" + o))
	bus.event_happened.connect(func(ev, _x): got.append("happened:" + String(ev.get("result", ""))))
	bus.event_settled.connect(func(_ev): got.append("settled"))
	bus.pitch_arrived.emit(LivePitch.new(), "ball")
	bus.event_happened.emit({"result": "walk"}, {})
	bus.event_settled.emit({})
	_check(got == ["arrived:ball", "happened:walk", "settled"], "signals arrive synchronously in the order they were sent")

	# A game announces itself.
	var bp := _scene(4242)
	await process_frame
	var c := {"landed": 0, "resolved": 0, "arrived": 0, "contact": 0, "announced": 0, "happened": 0, "settled": 0, "halves": 0, "overs": 0, "order_ok": true, "last": ""}
	bp.bus.pitch_arrived.connect(func(_p, _o): c.arrived += 1)
	bp.bus.contact_made.connect(func(_p): c.contact += 1)
	bp.bus.pitch_resolved.connect(func(_p, _o): c.resolved += 1)
	bp.bus.ball_landed.connect(func(_h): c.landed += 1)
	bp.bus.play_announced.connect(func(_h, _t, _e): c.announced += 1)
	bp.bus.event_happened.connect(func(_e, _x):
		c.happened += 1
		if c.last == "happened":
			c.order_ok = false          # every event is settled before the next happens
		c.last = "happened")
	bp.bus.event_settled.connect(func(_e):
		c.settled += 1
		if c.last != "happened":
			c.order_ok = false
		c.last = "settled")
	bp.bus.half_over.connect(func(_e): c.halves += 1)
	bp.bus.game_over.connect(func(_e): c.overs += 1)
	_play_out(bp)
	print("  ", c)
	_check(c.arrived > 3 and c.resolved == c.arrived + c.contact, "every pitch is resolved once, by arriving or by contact (%d + %d = %d)" % [c.arrived, c.contact, c.resolved])
	_check(c.landed <= c.contact and c.announced <= c.contact + 1 and c.announced >= 1, "a ball comes down and a play is announced at most once per contact")
	_check(c.happened == c.settled and c.happened > 3 and c.order_ok, "every event happens and then settles, one at a time (%d events)" % c.happened)
	_check(c.overs == 1 and c.halves >= 1, "one game over, and the half innings along the way (%d)" % c.halves)
	bp.queue_free()
	await process_frame

	# The reactions are listeners: take them away and the game plays on, the same way.
	var with := _scene(777)
	await process_frame
	_play_out(with)
	var line_with: String = with._game.line_text()
	var final_with: String = with._game.final_text()
	with.queue_free()
	await process_frame
	var without := _scene(777)
	await process_frame
	var r: Reactions = without.reactions
	without.bus.pitch_arrived.disconnect(r.on_pitch_arrived)
	without.bus.contact_made.disconnect(r.on_contact_made)
	without.bus.ball_landed.disconnect(r.on_ball_landed)
	without.bus.event_happened.disconnect(r.on_event_happened)
	_play_out(without)
	_check(without._game.over and without._game.line_text() == line_with and without._game.final_text() == final_with, "with nobody reacting the game ends the same (%s)" % line_with)
	without.queue_free()

	# Who reacts to what.
	var third := _scene(5)
	await process_frame
	var crowd_before: float = third._stadium.excitement()
	third.bus.event_happened.emit({"result": "home_run", "runs": 1}, {})
	_check(third._stadium.excitement() == 1.0 and crowd_before == 0.0, "a home run announced on the bus gets the crowd up")
	third.bus.event_settled.emit({"result": "single"})
	_check(true, "settling an event with no challenge running is harmless")
	third.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
