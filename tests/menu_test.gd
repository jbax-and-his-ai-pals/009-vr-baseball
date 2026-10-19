extends SceneTree
## The menu flow as data, and where a pointer lands on the panel.
## Run: godot --headless --path . -s res://tests/menu_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _find(m: MenuModel, id: String) -> int:
	var rows := m.items()
	for i in rows.size():
		if rows[i].id == id:
			return i
	return -1


func _init() -> void:
	var s := Settings.new()
	var m := MenuModel.new(s)

	# --- Main menu: no Continue until a game has been played.
	_check(m.screen() == "main" and _find(m, "continue") == -1, "a first launch has no Continue")
	_check(_find(m, "stats") >= 0 and m.items()[_find(m, "stats")].enabled, "stats and leaderboards are on the main menu")

	# --- Play -> Pitching -> Start.
	m.activate(_find(m, "play"))
	_check(m.screen() == "play", "Play opens the mode list")
	var hit := m.items()[_find(m, "mode:Hitting")]
	_check(not hit.enabled, "hitting is disabled")
	_check(m.activate(_find(m, "mode:Hitting")).is_empty() and m.screen() == "play", "choosing a disabled row does nothing")
	m.activate(_find(m, "mode:Pitching"))
	_check(m.screen() == "setup" and m.config.mode == "Pitching", "choosing Pitching opens its setup")
	_check(_find(m, "position") == -1 and _find(m, "innings") >= 0, "pitching setup has innings and no position")
	var ev := m.activate(_find(m, "start"))
	_check(ev.type == "start" and ev.config.mode == "Pitching" and ev.config.activity == "Game" and ev.config.innings == 9,
		"Start begins a nine-inning pitching game")
	_check(not s.last_game.is_empty(), "starting remembers the game for Continue")

	# --- Session cycles: Game -> Practice shows a batter and hides innings; Bullpen hides both.
	m.open_main()
	_check(_find(m, "continue") == 0, "Continue is first once a game has been played")
	m.activate(_find(m, "play"))
	m.activate(_find(m, "mode:Pitching"))
	m.activate(_find(m, "activity"))
	_check(m.config.activity == "Practice" and _find(m, "batter") >= 0 and _find(m, "innings") == -1, "practice shows the batter")
	m.activate(_find(m, "batter"))
	_check(m.config.batter == "Slugger", "the batter row cycles to the next profile")
	m.activate(_find(m, "activity"))
	_check(m.config.activity == "Bullpen" and _find(m, "batter") == -1, "bullpen has no batter")
	_check(m.items()[_find(m, "start")].note == "not scored", "practice and bullpen are not scored")
	m.activate(_find(m, "activity"))
	_check(m.config.activity == "Game" and m.items()[_find(m, "start")].note.begins_with("scored: Pitching/9inn"), "a game shows its leaderboard")

	# --- Fielding has a position and no bullpen.
	m.back()
	m.activate(_find(m, "mode:Fielding"))
	_check(_find(m, "position") >= 0, "fielding setup has a position")
	for i in 3:
		m.activate(_find(m, "position"))
	_check(m.config.position == 9, "position cycles 6 -> 9 (right field)")
	m.activate(_find(m, "position"))
	_check(m.config.position == 3, "and wraps to first base")
	m.activate(_find(m, "activity"))
	m.activate(_find(m, "activity"))
	m.activate(_find(m, "activity"))
	_check(m.config.activity == "Game", "fielding sessions cycle Game, Practice, Drill and back (no Bullpen)")
	ev = m.activate(_find(m, "start"))
	_check(ev.config.mode == "Fielding" and ev.config.position == 3, "Start carries the position")

	# --- Spectate has innings and no session or batter.
	m.open_main()
	m.activate(_find(m, "play"))
	m.activate(_find(m, "mode:Spectate"))
	_check(_find(m, "activity") == -1 and _find(m, "innings") >= 0, "spectate has innings only")

	# --- Options change settings and ask to be saved.
	m.open_main()
	m.activate(_find(m, "options"))
	ev = m.activate(_find(m, "hand"))
	_check(ev.type == "settings" and s.hand == "left", "the hand option flips handedness")
	ev = m.activate(_find(m, "assist_opt"))
	_check(ev.type == "settings" and s.assist == "Pro", "assist cycles Standard -> Pro")
	m.activate(_find(m, "assist_opt"))
	_check(s.assist == "Casual", "and wraps to Casual")
	m.activate(_find(m, "developer"))
	_check(s.developer, "developer options toggle")
	m.back()
	_check(m.screen() == "main" and not m.can_go_back(), "Back returns to the main menu")

	# --- Pause menu.
	var game := GameConfig.new()
	m.open_pause(game)
	_check(m.screen() == "pause" and m.activate(_find(m, "resume")).type == "resume", "pause resumes")
	_check(m.activate(_find(m, "restart")).type == "restart" and m.activate(_find(m, "main_menu")).type == "main_menu",
		"pause can restart or leave to the main menu")

	# --- The pause menu can order an intentional walk, in a pitching game only.
	var pitching_game := GameConfig.new()
	m.open_pause(pitching_game)
	_check(_find(m, "ibb") >= 0 and m.activate(_find(m, "ibb")).type == "intentional_walk", "pause offers an intentional walk in a game you pitch")
	var field_game := GameConfig.from_dict({"mode": "Fielding"})
	m.open_pause(field_game)
	_check(_find(m, "ibb") == -1, "but not when you are fielding")

	# --- Where a pointer lands.
	var menu := GameMenu.new()
	var cam := Camera3D.new()
	root.add_child(cam)
	root.add_child(menu)
	await process_frame
	cam.global_position = Vector3(0.0, 1.6, 0.0)
	cam.look_at(Vector3(0.0, 1.6, 10.0))
	menu.setup(MenuModel.new(Settings.new()), cam, [] as Array[XRController3D])
	menu.open_main()
	var origin := cam.global_position
	print("  menu at ", menu.global_position, " cam at ", cam.global_position, " fwd ", -cam.global_transform.basis.z, " row0 ", menu._row_y(0), " rows ", menu._rows.size())
	_check(menu.pick(origin, Vector3(0.0, 0.0, 1.0)) >= -1, "a ray at the panel does not fail")
	var p0 := menu.to_global(Vector3(0.0, menu._row_y(0), 0.0))
	var p1 := menu.to_global(Vector3(0.0, menu._row_y(1), 0.0))
	_check(menu.pick(origin, (p0 - origin).normalized()) == 0, "a ray through the first row picks row 0")
	_check(menu.pick(origin, (p1 - origin).normalized()) == 1, "a ray through the second row picks row 1")
	_check(menu.pick(origin, Vector3(0.0, 0.0, -1.0)) == -1, "a ray pointing away picks nothing")
	_check(menu.pick(origin, (menu.to_global(Vector3(2.0, 0.0, 0.0)) - origin).normalized()) == -1, "a ray beside the panel picks nothing")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
