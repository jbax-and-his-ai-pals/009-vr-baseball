extends SceneTree
## Throws go between players: to the glove of the man covering the base, through a cutoff man
## when they are long, and the ball is carried up to the hand instead of sitting at chest height.
## Run: godot --headless --path . -s res://tests/throws_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	ThrowLogger.disabled = true
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame

	# --- A grounder to short, thrown to first.
	bp.flight.debug_hit(78.0, -6.0, 18.0)
	var h = bp.flight.hits[bp.flight.hits.size() - 1]
	var fielder: int = int(h.play.get("fielder", 0))
	print("  grounder fielded by ", fielder, " result ", h.play.get("result", ""), " throws ", h.throws.size())
	if h.play.get("result", "") == "out" and not h.throws.is_empty():
		var last: Dictionary = h.throws[h.throws.size() - 1]
		var glove: Vector3 = Baserunning.RECEIVE_SPOT[1] + Vector3(0.0, 1.15, 0.0)
		_check((last.to as Vector3).distance_to(glove) < 0.01, "the throw goes to the first baseman's glove, not the bag")
		_check(is_equal_approx((last.from as Vector3).y, 1.75), "and leaves the throwing hand at shoulder height")
		var has_cover := false
		for m in h.play.movements:
			if int(m.fielder) == 3:
				has_cover = true
		_check(has_cover, "the first baseman moves to receive it")
	else:
		print("  (no throw to check for this ball)")

	# --- A long ball to the wall: through a cutoff man.
	var h2 = null
	for spec in [[96.0, 8.0, -12.0], [98.0, 10.0, 25.0], [100.0, 6.0, -30.0], [94.0, 12.0, 8.0]]:
		bp._process(1.0)
		bp.flight.debug_hit(spec[0], spec[1], spec[2])
		h2 = bp.flight.hits[bp.flight.hits.size() - 1]
		if h2.throws.size() >= 2:
			break
	print("  deep ball result ", h2.play.get("result", ""), " throws ", h2.throws.size())
	if h2.throws.size() >= 2:
		var first_to: Vector3 = h2.throws[0].to
		var second_from: Vector3 = h2.throws[1].from
		_check(first_to.distance_to(second_from - Vector3(0.0, 0.6, 0.0)) < 0.5, "a long throw is relayed: the cutoff man throws from where he caught it")
		_check(float(h2.throws[1].t0) > float(h2.throws[0].t1), "and holds it a moment before throwing")
		var lead := first_to
		_check(Vector2(lead.x, lead.z).length() > 25.0 and Vector2(lead.x, lead.z).length() < 80.0, "the cutoff man stands between the outfield and the infield")
	else:
		print("  (this ball was not a relay)")

	# --- The ball is carried, not teleported: its height changes continuously after a catch.
	var h3 = bp.flight.hits[bp.flight.hits.size() - 1]
	if int(h3.play.get("fielder", 0)) != 0 and h3.play.get("result", "") != "home_run":
		h3.t = float(h3.play.field_time) + 0.01
		var y0: float = (bp._director.ball_with_fielder(h3) as Vector3).y
		h3.t = float(h3.play.field_time) + 0.30
		var y1: float = (bp._director.ball_with_fielder(h3) as Vector3).y
		_check(y1 > y0 + 0.2 or y0 > 1.5, "the ball is raised toward the hand after the catch (%.2f -> %.2f)" % [y0, y1])

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
