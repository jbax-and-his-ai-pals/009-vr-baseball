extends SceneTree
## Guards against the kind of mistake unit tests miss: every sound the code asks for exists in the
## manifest, cosmetic code never touches the gameplay random numbers, the off-screen half inning
## replays from a seed, and the menu's audio behaves.
## Run: godot --headless --path . -s res://tests/hygiene_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## The body of one function (up to the next top-level func), for source-level checks.
func _body(src: String, fname: String) -> String:
	var a := src.find("func %s(" % fname)
	if a < 0:
		return ""
	var b := src.find("\nfunc ", a + 5)
	return src.substr(a, (b if b > 0 else src.length()) - a)


func _init() -> void:
	ThrowLogger.override_path = "user://test_throws.jsonl"
	var manifest: Dictionary = JSON.parse_string(_src("res://audio/manifest.json"))
	var ids := {}
	for s in manifest.sounds:
		ids[String(s.id)] = true

	# Every sound id the code asks for is in the manifest.
	var re := RegEx.new()
	re.compile("\"([a-z0-9]+(?:_[a-z0-9]+)+)\"")
	var prefixes := ["glove_", "bat_", "batter_", "ball_", "ump_", "crowd_", "ui_", "music_", "pa_", "step_", "organ_", "scoreboard_",
		"throw_", "tag_", "slide_", "base_", "catch_", "fielder_", "fence_", "seat_", "stadium_", "light_", "dugout_", "vendor_", "fan_",
		"arm_", "corner_", "zone_", "cloth_", "fireworks", "home_run_", "seventh_"]
	var calls := ["_sfx(", "_sfx_later(", "play_later(", "loop_on(", "play_music(", "ui_sound.emit("]
	var unknown: Array = []
	for f in ["res://scripts/bullpen.gd", "res://scripts/game_menu.gd", "res://scripts/audio_manager.gd"]:
		for line in _src(f).split("
"):
			var is_call := false
			for c in calls:
				if line.contains(c):
					is_call = true
			if not is_call:
				continue
			for m in re.search_all(line):
				var id: String = m.get_string(1)
				for p in prefixes:
					if id.begins_with(p) and not ids.has(id):
						unknown.append("%s in %s" % [id, f.get_file()])
						break
	_check(unknown.is_empty(), "every sound id the code plays is in the manifest (unknown: %s)" % str(unknown.slice(0, 6)))

	# Cosmetic choices use their own random numbers.
	var bp_src := _src("res://scripts/bullpen.gd")
	_check(not _body(bp_src, "_batter_takes").contains("_run_rng"), "the check swing does not draw from the gameplay random numbers")
	_check(not _body(bp_src, "_simulate_bottom_half").contains("get_ticks"), "the off-screen half inning is not seeded from the clock")

	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame

	# The off-screen half inning replays from the game seed.
	bp._game_seed = 1234
	var first: Array = []
	var second: Array = []
	for inn in range(1, 8):
		bp._home_order = 0
		var r1: Dictionary = bp._simulate_bottom_half(inn)
		first.append([r1.runs, r1.hits, bp._home_order])
	for inn in range(1, 8):
		bp._home_order = 0
		var r2: Dictionary = bp._simulate_bottom_half(inn)
		second.append([r2.runs, r2.hits, bp._home_order])
	_check(first == second, "the same seed gives the same bottom halves (%s)" % str(first))

	# A left-handed hitter stands on the other side, and pitches hit him there.
	var righty := CartoonBatter.home_transform(true)
	var lefty := CartoonBatter.home_transform(false)
	_check(righty.origin.x > 0.5 and lefty.origin.x < -0.5, "right-handers stand at +x, left-handers at -x")
	_check(PitchLocation.hits_batter(0.9, 0.8) and not PitchLocation.hits_batter(-0.9, 0.8)
		and PitchLocation.hits_batter(-0.9, 0.8, true) and not PitchLocation.hits_batter(0.9, 0.8, true), "a pitch at a lefty's body is on the other side")
	# His chest faces the plate and his lead side faces the pitcher, whichever side he bats.
	for xf in [righty, lefty]:
		var chest: Vector3 = xf.basis * Vector3(0, 0, 1)
		var lead: Vector3 = xf.basis * Vector3(1, 0, 0)
		_check(chest.x * xf.origin.x < 0.0 and lead.z > 0.5, "chest to the plate and lead side to the pitcher (box x %.2f)" % xf.origin.x)

	# Delayed sounds wait while the game is paused.
	var a: AudioManager = bp._audio
	a._pending.clear()
	a.play_later(0.5, "ui_select")
	a.set_paused(true)
	for i in 10:
		a._process(0.2)
	_check(a.pending_count() == 1, "a delayed sound does not fire while paused")
	a.set_paused(false)
	for i in 4:
		a._process(0.2)
	_check(a.pending_count() == 0, "...and fires once the game goes on")
	a.set_paused(true)
	var duck := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	var ui := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("UI"))
	a.set_paused(false)
	var live := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	_check(duck < live - 6.0 and ui > duck, "pausing ducks the game's sound but not the interface (%.1f vs %.1f dB)" % [duck, live])
	bp.queue_free()
	await process_frame

	# The main menu has its own music and no ballpark; a pause keeps the game's music, ducked.
	var bm: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	root.add_child(bm)
	await process_frame
	_check(bm._menu.is_open(), "the scene opens on the main menu")
	for i in 6:
		bm._audio_tick = 0.0
		bm._process(0.5)
		bm._audio._process(0.5)
	_check(bm._audio.music_id() == "music_menu" and bm._audio.paused, "the main menu plays its own theme")
	_check(bm._audio.bed_gain("crowd_bed_high") == 0.0 and not bm._audio.loop_active("wind"), "...with no crowd and no ballpark ambience")
	bm._menu.close()
	for i in 4:
		bm._audio_tick = 0.0
		bm._process(0.5)
		bm._audio._process(0.5)
	_check(bm._audio.music_id() == "music_game_base" and not bm._audio.paused, "closing the menu starts the game's music")
	bm._toggle_pause()
	bm._audio_tick = 0.0
	bm._process(0.5)
	_check(bm._audio.paused and bm._audio.music_id() == "music_game_base", "a pause keeps the game music, ducked")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
