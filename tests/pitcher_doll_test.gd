extends SceneTree
## When you are not the pitcher there is a pitcher on the mound: he throws each pitch, covers first
## on a ball to the first baseman, and walks back; when you are the pitcher there is none.
## Run: godot --headless --path . -s res://tests/pitcher_doll_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	ThrowLogger.override_path = "user://test_throws.jsonl"

	# Pitching mode: you are him.
	var you: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	you.menu_on_start = false
	root.add_child(you)
	await process_frame
	_check(not you._field_nodes.has(1), "when you pitch there is no pitcher figure")
	var normal_first: Array = you._director.receiver_candidates(1, 6, Vector3(0.0, 0.0, 30.0))
	_check(normal_first[0] == 3, "first base is still the first baseman's")
	you.queue_free()
	await process_frame

	# Spectate: an AI pitcher on the mound.
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_mode_name = "Spectate"
	root.add_child(bp)
	await process_frame
	var p: Node3D = bp._field_nodes.get(1)
	_check(p is Doll and p.visible and absf(p.position.z - 17.2) < 1.3 and absf(p.position.y - PitchPhysics.MOUND_H) < 0.01,
		"there is a pitcher standing on the mound (%s %s %s)" % [p is Doll, p.position if p else "-", p.visible if p else "-"])
	var threw := false
	for i in 60 * 8:
		bp._process(1.0 / 60.0)
		if (p as Doll).busy():
			threw = true
			break
	_check(threw, "he goes through his motion when the AI pitches")
	var pitched: int = bp._game.pitch_count
	var thrown := false
	for i in 60 * 14:
		bp._process(1.0 / 60.0)
		if bp._game.pitch_count > pitched or bp.flight.pitches.size() > 0:
			thrown = true
			break
	_check(thrown, "and the pitch is thrown after the windup")

	# A grounder to the first baseman: the pitcher covers first and takes the throw.
	var h := LiveHit.new()
	h.play = {"fielder": 3, "movements": [{"fielder": 3, "from": Vector3(-17.5, 0, 22.5), "to": Vector3(-14.0, 0, 20.0), "t0": 0.0, "t1": 1.0, "dive": false}]}
	h.plan = PlayPlan.new()
	h.plan.add_throw(Vector3(-14.0, 0, 20.0), Vector3(-19.4, 1, 19.4), 1.4, 1.9, 1)
	var chain: Array = bp._director.build_throws(h)
	_check(chain.size() == 1 and int(chain[0].rec) == 1, "the pitcher is the one who takes the throw at first (%s)" % str(chain.map(func(c): return c.rec)))
	var covers := false
	for m in h.play.movements:
		if int(m.fielder) == 1:
			covers = true
	_check(covers, "and he runs over to cover the bag")
	bp.flight.play_hit = null
	bp._director.reset_fielders()
	_check(absf(p.position.y - PitchPhysics.MOUND_H) < 0.01, "back on the mound he stands on it")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
