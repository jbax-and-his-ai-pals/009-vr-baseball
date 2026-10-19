extends SceneTree
## Hitting mode in the scene: an AI pitcher throws, your bat (here a synthetic one) hits, misses or
## lets it go, and the game records it. Also the mode, the menu and the score.
## Run: godot --headless --path . -s res://tests/hitting_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


## Put the bat through the plate point where this pitch will cross, moving toward the pitcher; or miss it
## by `miss` metres above, or hold still (swing_speed 0).
func _set_bat(bp: Node3D, plate: Vector3, swing_speed: float, miss: float) -> void:
	var t: SwingTracker = bp.flight.tracker
	var through := Vector3(plate.x, plate.y + miss, 0.0)
	t.knob = through - Vector3(BatPhysics.SWEET, 0.0, 0.0)
	t.tip = t.knob + Vector3(BatPhysics.LENGTH, 0.0, 0.0)
	t.knob_vel = Vector3(0.0, 0.0, swing_speed * 0.5)
	t.tip_vel = Vector3(0.0, 0.0, swing_speed)


func _next_pitch(bp: Node3D, seen: Array) -> LivePitch:
	for i in 60 * 40:
		bp._process(1.0 / 60.0)
		for p in bp.flight.pitches:
			if not seen.has(p) and not p.landed:
				seen.append(p)
				return p
	return null


func _play_pitch(bp: Node3D, seen: Array, swing_speed: float, miss: float) -> LivePitch:
	var p := _next_pitch(bp, seen)
	if p == null:
		return null
	for i in 60 * 3:
		_set_bat(bp, p.analysis.plate_pos, swing_speed, miss)
		bp._process(1.0 / 60.0)
		if p.landed:
			break
	return p


func _init() -> void:
	_check(GameMode.by_name("hitting").human_batter and GameMode.by_name("hitting").supported, "Hitting is a playable mode")
	var cfg := GameConfig.new()
	cfg.mode = "Hitting"
	_check(cfg.normalized().mode == "Hitting" and cfg.normalized().leaderboard_key() == "Hitting/9inn/Standard", "it has its own leaderboard")
	_check(PlayerProfile.hitting_score({"h": 3, "hr": 1, "k": 1, "bb": 1, "r": 2}) == 50 + 18 + 8 + 3 + 4 - 4, "Hitting Score rewards hits, homers, walks and runs, punishes strikeouts")

	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	bp.game_mode_name = "Hitting"
	bp.game_innings = 1
	root.add_child(bp)
	await process_frame
	_check(bp._mode.human_batter and not bp._mode.human_pitcher and bp.flight.bat_view != null, "the scene is in Hitting mode with a bat in your hand")
	for i in 120:
		bp._process(1.0 / 60.0)
	_check(not bp._batter.visible, "the AI batter figure is not drawn: you are the batter")

	var seen: Array = []
	# 1. Let the first pitch go by: the umpire calls it.
	var p1 := _play_pitch(bp, seen, 0.0, 1.5)
	_check(p1 != null and p1.landed and not p1.bat.get("contact", false) and not p1.bat.get("swing", false), "a bat held still takes the pitch")
	var counted: int = bp._game.pitch_count
	_check(counted >= 1 and (bp._game.balls + bp._game.strikes >= 1 or bp._game.outs > 0 or bp._game.walks > 0 or bp._game.hit_by_pitches > 0), "and it is a ball or a strike on the count")

	# 2. Swing and miss (the bat goes well over it).
	var strikes_before: int = bp._game.strikes
	var p2 := _play_pitch(bp, seen, 30.0, 0.35)
	_check(p2 != null and p2.bat.get("swing", false) and not p2.bat.get("contact", false) and p2.bat.get("kind", "") == "whiff", "a fast swing that misses is a swing and a miss")
	_check(bp._game.strikes > strikes_before or bp._game.outs > 0 or bp._game.strikeouts > 0, "and it is a strike on you")

	# 3. A swing through the ball: a hit.
	var hit_found := false
	var best_ev := 0.0
	var tries := 0
	while tries < 12 and not hit_found:
		tries += 1
		var before: int = bp.flight.hits.size()
		var p3 := _play_pitch(bp, seen, 32.0, 0.0)
		if p3 != null and p3.bat.get("contact", false):
			hit_found = true
			best_ev = float(p3.bat.ev)
			_check(bp.flight.hits.size() > 0 and (bp.flight.hits[bp.flight.hits.size() - 1] as LiveHit).summary == p3.sim and p3.bat.kind in ["hit", "foul tip"], "a swing through the ball is contact (%s, %.0f mph)" % [p3.bat.kind, best_ev])
			_check(best_ev > 55.0 or p3.bat.kind == "foul tip", "and comes off the bat fast")
			_check(p3.sim.has("landing_pos") and not p3.play.is_empty(), "the batted ball is flown and the defense answers it")
		# let the play finish before the next pitch
		for i in 60 * 14:
			bp._process(1.0 / 60.0)
			if bp._batter_ready and bp._aux_play.is_empty() and bp.flight.hits.all(func(h): return h.result_shown):
				break
	_check(hit_found, "within a few pitches a swing through the ball made contact")

	# 4. The game finishes and is recorded as a hitting game.
	for i in 60 * 600:
		if bp._game.over:
			break
		var p := _next_pitch(bp, seen)
		if p == null:
			break
		for j in 60 * 3:
			_set_bat(bp, p.analysis.plate_pos, 32.0, 0.0)
			bp._process(1.0 / 60.0)
			if p.landed:
				break
		for j in 60 * 12:
			bp._process(1.0 / 60.0)
			if bp._batter_ready and bp._aux_play.is_empty():
				break
	_check(bp._game.over and bp.results.game_recorded, "the game ends and is recorded")
	var line: Dictionary = bp.results.hitting_line()
	_check(line.kind == "hitting" and line.pa > 0 and line.h >= 0, "your line is a batter's line (%s)" % str(line))
	_check(int(bp._profile.totals.get("h_games", 0)) == 1, "and it is in your history under hitting")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
