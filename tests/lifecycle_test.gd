extends SceneTree
## The batter's comings and goings: he leaves after an out or a walk, the next one walks on,
## pitching waits until he is in the box, and nothing gets stuck over a whole game.
## Run: godot --headless --path . -s res://tests/lifecycle_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_innings = 3
	root.add_child(bp)
	await process_frame

	_check(bp._batter_ready and bp._batter.visible, "the batter starts in the box, ready")
	var home: Transform3D = bp._batter_home

	var throw_timer := 0.0
	var waited_unready := 0
	var pa_seen := 0
	var last_faced := 0
	var max_unready_run := 0.0
	var unready_run := 0.0
	var thrown_while_unready := 0
	var invisible_frames := 0
	var ready_away_frames := 0
	var steps := 60 * 400                       # 400 s of game
	for i in steps:
		var dt := 1.0 / 60.0
		bp._process(dt)
		if bp._game.over:
			break
		throw_timer -= dt
		if throw_timer <= 0.0:
			throw_timer = 1.0
			if bp._batter_ready:
				bp._debug_throw()
			else:
				waited_unready += 1
		# Whenever the next batter is walking up or is ready, you must be able to see him.
		if (not bp._walk_on.is_empty() or bp._batter_ready) and not bp._batter.visible:
			invisible_frames += 1
			if invisible_frames == 1:
				var info := "ready=%s walk_on=%s aux=%s over=%s inning=%d outs=%d" % [bp._batter_ready, not bp._walk_on.is_empty(),
					not bp._aux_play.is_empty(), bp._game.over, bp._game.inning, bp._game.outs]
				for hh in bp._hits:
					info += " | hit result=%s shown=%s hidden=%s t=%.1f" % [hh.play.get("result", "?"), hh.result_shown, hh.plan.get("batter_hidden", "-"), hh.t]
				print("  INVISIBLE: ", info)
		if bp._batter_ready and bp._batter.transform.origin.distance_to(bp._batter_home.origin) > 0.1:
			ready_away_frames += 1
		if not bp._batter_ready:
			unready_run += dt
			max_unready_run = maxf(max_unready_run, unready_run)
			if absf(unready_run - 14.0) < dt * 0.6:
				var info := "aux=%s walk_on=%s" % [not bp._aux_play.is_empty(), not bp._walk_on.is_empty()]
				for h in bp._hits:
					info += " | hit result=%s shown=%s t=%.1f end=%.1f state=%s" % [h.play.get("result", "?"), h.result_shown, h.t, h.play_end, h.human_state]
				print("  STUCK? ", info)
		else:
			unready_run = 0.0
		if bp._game.batters_faced != last_faced:
			last_faced = bp._game.batters_faced
			pa_seen += 1
	print("  plate appearances: %d, throws held back: %d, longest wait for a batter: %.1f s" % [pa_seen, waited_unready, max_unready_run])
	_check(pa_seen >= 6, "several plate appearances happened (%d)" % pa_seen)
	_check(waited_unready > 0, "pitching waited for the batter at least once")
	_check(invisible_frames == 0, "the batter is never invisible while walking up or ready (%d frames)" % invisible_frames)
	_check(ready_away_frames == 0, "pitching is only allowed with him standing in the box (%d frames)" % ready_away_frames)
	_check(max_unready_run < 25.0, "the wait for the batter is bounded (%.1f s)" % max_unready_run)

	# Let everything settle, then the world must be at rest.
	for i in 60 * 30:
		bp._process(1.0 / 60.0)
	_check(bp._batter_ready or bp._game.over, "after settling the batter is ready (or the game is over)")
	if not bp._game.over:
		_check(bp._batter.visible, "the batter is visible in the box")
		_check(bp._batter.transform.origin.distance_to(bp._batter_home.origin) < 0.05, "he stands where his box is")
	var leaving := 0
	for lv in bp._leavers:
		if lv.visible:
			leaving += 1
	_check(leaving == 0, "nobody is still walking back to the dugout")
	_check(bp._aux_play.is_empty() and bp._walk_on.is_empty(), "no animation is left half-finished")
	# Dots belong to one batter: when the next one is walking up there are none.
	bp._zone_markers.add(0.0, 0.8, Color.GREEN)
	bp._begin_walk_on()
	_check(bp._zone_markers.entries().is_empty(), "the pitch dots are cleared when the next batter comes up")
	_check(not bp._runner.visible, "the batter-runner figure is put away")

	# A double play 4-6-3: each throw is made by the man who took the last one.
	var dp = LiveHit.new()
	dp.play = {"fielder": 4, "movements": [{"fielder": 4, "from": Vector3(8, 0, 30), "to": Vector3(8, 0, 30), "t0": 0.0, "t1": 1.0, "dive": false}]}
	dp.plan = {"throws": [
		{"from": Vector3(8, 0, 30), "to": Vector3(0, 1, 38.8), "t0": 1.0, "t1": 1.6, "base": 2},
		{"from": Vector3(0, 0, 38.8), "to": Vector3(-19.4, 1, 19.4), "t0": 1.9, "t1": 2.6, "base": 1}]}
	var chain: Array = bp._director.build_throws(dp)
	_check(chain.size() == 2 and int(chain[0].by) == 4 and int(chain[0].rec) == 6, "double play: the second baseman throws to the shortstop at second")
	_check(chain.size() == 2 and int(chain[1].by) == 6 and int(chain[1].rec) == 3, "double play: the shortstop, not the second baseman, throws on to first")
	# How a fielder takes the ball depends on where it is.
	_check(bp._director.catch_clip({"field_pos": Vector3(0, 0.2, 22)}, 6) == "scoop", "a ball on the ground is scooped")
	_check(bp._director.catch_clip({"field_pos": Vector3(0, 3.0, 60)}, 8) == "jump", "a ball over his head is a jump catch")
	_check(bp._director.catch_clip({"field_pos": Vector3(0, 1.4, 60)}, 8) == "catch", "a ball at chest height is a plain catch")
	_check(bp._director.catch_clip({"field_pos": Vector3(13.3, 0.2, 31.2)}, 6) == "backhand", "a ball far to the side is a backhand")
	_check(bp._director.is_tag_play({"runners": [{"out": true, "out_base": 4, "forced_out": false}]}, 4), "an out at the plate with no force is a tag")
	_check(not bp._director.is_tag_play({"runners": [{"out": true, "out_base": 2, "forced_out": true}]}, 2), "a force out is not a tag")
	var felt := {}
	for pulse in bp._haptics.history:
		felt[pulse.event] = true
	_check(felt.has("pop") and felt.has("contact"), "the game made the controllers buzz for the mitt and the bat (%s)" % str(felt.keys()))
	print("  sounds used: ", bp._audio.counts.keys())
	_check(bp._audio != null and bp._audio.played > 20, "a whole game makes sounds (%d played)" % (bp._audio.played if bp._audio else -1))
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
