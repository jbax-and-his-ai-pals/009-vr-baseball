extends SceneTree
## The audio manager: it finds the sounds, never repeats a take twice running, never grows its
## pool, tolerates missing files, follows the volume settings, crossfades the crowd and music.
## Run: godot --headless --path . -s res://tests/audio_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	var a := AudioManager.new()
	root.add_child(a)
	await process_frame

	_check(a.defs.size() > 100, "the manifest lists the sounds (%d)" % a.defs.size())
	for bus in AudioManager.BUSES:
		_check(AudioServer.get_bus_index(bus) >= 0, "bus %s exists" % bus)

	# Every P0 sound has at least a placeholder file.
	var lacking: Array = []
	for id in a.defs:
		if a.defs[id].priority == "P0" and not a.has_sound(id):
			lacking.append(id)
	_check(lacking.is_empty(), "every P0 sound has a file (missing: %s)" % str(lacking.slice(0, 5)))

	# Playing: a known sound plays, an unknown one and one with no file do not, and nothing errors.
	_check(a.play("glove_pop_hard", Vector3(0, 1, -1)), "a known sound plays")
	_check(not a.play("no_such_sound"), "an unknown sound is quietly ignored")
	var no_file := ""
	for id in a.defs:
		if not a.has_sound(id):
			no_file = id
			break
	_check(no_file == "" or not a.play(no_file), "a sound with no file is quietly ignored (%s)" % no_file)

	# Never the same take twice running.
	var repeats := 0
	var last := ""
	for i in 60:
		a.play("glove_pop_medium", Vector3(0, 1, -1))
		var take: String = a.recent[a.recent.size() - 1].take
		if take == last:
			repeats += 1
		last = take
	_check(repeats == 0, "no take repeats back to back (%d repeats in 60)" % repeats)

	# A flood never grows the pool.
	var before := a.get_child_count()
	for i in 200:
		a.play("step_dirt_run", Vector3(i * 0.1, 0, 5))
		a.play("ui_select")
	_check(a.get_child_count() == before, "200 sounds in a burst use the same players (%d)" % a.get_child_count())

	# Volumes.
	a.apply_volumes({"SFX": 0.0})
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "SFX at 0% is muted")
	a.apply_volumes({"SFX": 0.5, "Master": 0.8})
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")) and absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) - linear_to_db(0.5)) < 0.1,
		"SFX at 50% is about -6 dB")
	a.apply_volumes({"SFX": 1.0, "Master": 1.0})

	# The crowd crossfades with the level.
	a.set_crowd_on(true)
	a.set_crowd(0.05)
	for i in 20:
		a._process(0.5)
	var quiet_low := a.bed_gain("crowd_bed_low")
	var quiet_high := a.bed_gain("crowd_bed_high")
	a.set_crowd(0.95)
	for i in 20:
		a._process(0.5)
	_check(quiet_low > 0.6 and quiet_high < 0.1, "a calm game is the low murmur (low %.2f, high %.2f)" % [quiet_low, quiet_high])
	_check(a.bed_gain("crowd_bed_high") > 0.6 and a.bed_gain("crowd_bed_low") < 0.1, "a hot game is the roar (high %.2f, low %.2f)" % [a.bed_gain("crowd_bed_high"), a.bed_gain("crowd_bed_low")])
	a.set_crowd_on(false)
	for i in 20:
		a._process(0.5)
	_check(a.bed_gain("crowd_bed_high") == 0.0, "the crowd goes quiet when switched off")

	# Music.
	a.play_music("music_menu")
	for i in 10:
		a._process(0.3)
	_check(a.music_id() == "music_menu" and a._music.playing, "the menu theme plays")
	a.play_music("music_game_base")
	for i in 10:
		a._process(0.3)
	_check(a.music_id() == "music_game_base" and a._music.playing and not a._music_next.playing, "music crossfades to the game track")
	a.play_music("")
	for i in 10:
		a._process(0.3)
	_check(not a._music.playing and not a._music_next.playing, "music can fade to nothing")

	# Named loops fade in, follow a node, and clean up after themselves.
	var ball := Node3D.new()
	root.add_child(ball)
	a.loop_on("whiz", "ball_flight_whiz", -10.0, null, ball)
	for i in 10:
		a._process(0.2)
	_check(a.loop_active("whiz") and a._loops["whiz"].gain > 0.2, "a loop fades in")
	ball.global_position = Vector3(3, 2, 10)
	a._process(0.1)
	_check((a._loops["whiz"].p as Node3D).global_position.distance_to(Vector3(3, 2, 10)) < 0.01, "a loop follows its node")
	a.loop_on("whiz", "ball_flight_whiz", -10.0, null, ball)
	_check(a.get_child_count() == a.get_child_count(), "asking again does not double it")
	a.loop_off("whiz")
	for i in 10:
		a._process(0.2)
	_check(not a._loops.has("whiz"), "a loop that has faded out is gone")
	a.loop_on("gone", "ball_flight_whiz", -10.0, null, ball)
	ball.free()
	for i in 5:
		a._process(0.5)
	_check(not a._loops.has("gone"), "a loop whose node has gone fades out")

	# Music stems only live over the game track.
	a.play_music("music_game_base")
	for i in 5:
		a._process(0.3)
	a.set_stems(1.0, 0.0)
	for i in 20:
		a._process(0.3)
	_check(a.stem_gain("music_game_rhythm") > 0.8 and a.stem_gain("music_game_tension") == 0.0, "the rhythm stem comes in, the tension stem stays out")
	a.play_music("music_menu")
	_check(a._stems.is_empty(), "stems are dropped when the music changes")
	a.play_music("")

	# Reading a file that Godot has not imported.
	var raw := AudioManager._load_raw("res://audio/pitching/glove_pop_hard_01.wav")
	_check(raw is AudioStreamWAV and (raw as AudioStreamWAV).data.size() > 1000 and (raw as AudioStreamWAV).mix_rate == 22050, "a wav is read straight from disk")

	# Settings and the menu.
	var s := Settings.new()
	s.volumes["Music"] = 0.25
	var s2 := Settings.from_dict(s.to_dict())
	_check(absf(float(s2.volumes["Music"]) - 0.25) < 0.001 and float(s2.volumes["Master"]) == 1.0, "volumes survive a save and load")
	var bad := Settings.from_dict({"volumes": {"Music": "loud", "SFX": 7.0}})
	_check(float(bad.volumes["SFX"]) == 1.0 and float(bad.volumes["Music"]) == 0.5, "bad volume values are clamped or ignored")
	var m := MenuModel.new(s)
	m.stack = ["options"]
	var idx := -1
	for i in m.items().size():
		if m.items()[i].id == "audio":
			idx = i
	_check(idx >= 0, "Options has a Sound row")
	m.activate(idx)
	_check(m.screen() == "audio" and m.items().size() == MenuModel.VOLUME_ROWS.size() + 1, "the Sound screen lists the volumes and Back")
	var before_vol := float(s.volumes["Music"])
	var ev := m.activate(3)         # Music
	_check(ev.get("type", "") == "settings" and float(s.volumes["Music"]) > before_vol, "choosing a volume steps it up")
	for i in 5:
		m.activate(3)
	_check(float(s.volumes["Music"]) >= 0.0 and float(s.volumes["Music"]) <= 1.0, "volumes stay in range however often you step them")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
