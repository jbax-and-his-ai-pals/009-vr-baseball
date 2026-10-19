extends SceneTree
## Infield in: when the defense wants it, what it changes (positions, reach to a ball hit at the
## infield, the run at the plate), and that the fielders walk there between plays.
## Run: godot --headless --path . -s res://tests/alignment_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	var third := [null, null, true]
	_check(Defense.wants_infield_in(0, third, 8, 0) and Defense.wants_infield_in(1, third, 9, 1) and Defense.wants_infield_in(1, third, 7, -1),
		"late, close, a man on third, fewer than two outs: infield in")
	_check(not Defense.wants_infield_in(2, third, 8, 0), "not with two outs")
	_check(not Defense.wants_infield_in(0, third, 4, 0), "not early")
	_check(not Defense.wants_infield_in(0, third, 8, 5) and not Defense.wants_infield_in(0, third, 8, -4), "not in a blowout either way")
	_check(not Defense.wants_infield_in(0, [true, true, null], 8, 0), "not without a man on third")

	var team := Team.generate("D", 50.0, 3)
	var d := Defense.from_team(team)
	var normal: Dictionary = {}
	for f in d.fielders:
		normal[f.num] = f.home
	d.set_infield_in(true)
	var closer := true
	for n in [3, 4, 5, 6]:
		closer = closer and (d.fielder_by_num(n).home as Vector3).z < (normal[n] as Vector3).z - 3.5
	var outfield_same := true
	for n in [2, 7, 8, 9]:
		outfield_same = outfield_same and d.fielder_by_num(n).home == normal[n]
	_check(closer and outfield_same and d.infield_in, "the four infielders move in at least three and a half metres; everyone else stays")
	d.set_infield_in(true)
	d.set_infield_in(false)
	var back := true
	for f in d.fielders:
		back = back and f.home == normal[f.num]
	_check(back and not d.infield_in, "and they go back exactly where they were")

	# A ball hit hard at the shortstop: he gets to it sooner when he is in.
	var sim := BattedBall.simulate(Vector3(0, 0.9, 0), Vector3(14.0, 1.5, 33.0) * 1.3, Vector3.ZERO)
	var d1 := Defense.from_team(team)
	d1.rng.seed = 1
	var p1 := d1.resolve(sim, 1.0)
	var d2 := Defense.from_team(team)
	d2.rng.seed = 1
	d2.set_infield_in(true)
	var p2 := d2.resolve(sim, 1.0)
	_check(float(p2.get("field_time", 9.0)) <= float(p1.get("field_time", 0.0)), "a grounder at the infield is fielded no later with the infield in (%.2f vs %.2f s)" % [p2.get("field_time", 0), p1.get("field_time", 0)])

	# Over many balls with a runner on third: more outs at the plate, but more balls get through.
	var hits_normal := 0
	var hits_in := 0
	var n := 300
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in n:
		var spray := rng.randf_range(-35.0, 35.0)
		var ev := rng.randf_range(70.0, 105.0)
		var la := rng.randf_range(-8.0, 6.0)
		var psi := deg_to_rad(spray)
		var la_r := deg_to_rad(la)
		var speed := ev / PitchPhysics.MPS_TO_MPH
		var vel := Vector3(sin(psi) * cos(la_r), sin(la_r), cos(psi) * cos(la_r)) * speed
		var s := BattedBall.simulate(Vector3(0, 0.9, 0), vel, Vector3.ZERO)
		var a := Defense.from_team(team)
		a.rng.seed = i
		var b := Defense.from_team(team)
		b.rng.seed = i
		b.set_infield_in(true)
		if a.resolve(s, 1.0).get("result", "") in ["single", "double", "triple"]:
			hits_normal += 1
		if b.resolve(s, 1.0).get("result", "") in ["single", "double", "triple"]:
			hits_in += 1
	_check(hits_in > hits_normal and hits_in - hits_normal < n * 0.14, "infield in lets more grounders through, but not wildly more (%d vs %d hits of %d)" % [hits_in, hits_normal, n])

	# In the scene: the alignment follows the game, and fielders walk to their spots between plays.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	bp._game.inning = 8
	bp._game.outs = 0
	bp._game.runs = 2
	bp._game.home_score = 2
	bp._game.bases = [null, null, bp._away.lineup[0]]
	bp.manager.update_alignment()
	_check(bp._defense.infield_in, "the scene puts the infield in")
	var ss: Node3D = bp._field_nodes[6]
	var target_z: float = bp._defense.fielder_by_num(6).home.z
	for i in 60 * 6:
		bp._process(1.0 / 60.0)
	_check(absf(ss.position.z - target_z) < 0.3, "and the shortstop walks in to his new spot (%.1f vs %.1f)" % [ss.position.z, target_z])
	bp._game.bases = [null, null, null]
	bp.manager.update_alignment()
	_check(not bp._defense.infield_in, "and goes back when the man on third is gone")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
