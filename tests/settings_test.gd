extends SceneTree
## Settings and GameConfig: defaults, persistence, repair of bad data, leaderboard keys.
## Run: godot --headless --path . -s res://tests/settings_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	var path := "user://test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# --- Defaults are what the game has always played like.
	var s := Settings.new()
	var std := s.assist_values()
	_check(s.assist == "Standard" and is_equal_approx(std.funnel_x, 0.40) and is_equal_approx(std.funnel_y, 0.30),
		"the default assist is the current game feel")
	_check(s.throwing_hand_name() == &"right_hand", "right-handed by default")
	_check(Settings.load_from(path).assist == "Standard", "a missing file gives defaults")

	# --- Round trip.
	s.hand = "left"
	s.assist = "Pro"
	s.quality = "Quest"
	s.developer = true
	s.last_game = {"mode": "Fielding", "position": 5}
	_check(s.save(path), "settings save")
	var r := Settings.load_from(path)
	_check(r.hand == "left" and r.assist == "Pro" and r.quality == "Quest" and r.developer and r.last_game.get("position") == 5,
		"settings survive a save and load")
	_check(r.throwing_hand_name() == &"left_hand", "left-handed throws with the left hand")

	# --- Bad data never breaks it.
	var bad := Settings.from_dict({"hand": "ambidextrous", "assist": "Impossible", "quality": 5, "last_game": 7})
	_check(bad.hand == "right" and bad.assist == "Standard" and bad.quality == "Auto" and bad.last_game == {},
		"unknown values fall back to defaults")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ not json")
	f = null
	_check(Settings.load_from(path).assist == "Standard", "a damaged file gives defaults")

	# --- Assist presets are ordered by how much help they give.
	var c := Settings.ASSIST_VALUES.Casual
	var p := Settings.ASSIST_VALUES.Pro
	_check(c.funnel_x < std.funnel_x and std.funnel_x < p.funnel_x and c.catch_radius > std.catch_radius and std.catch_radius > p.catch_radius
		and c.throw_cone > std.throw_cone and std.throw_cone > p.throw_cone, "Casual helps most, Pro least, on every axis")

	# --- Game config.
	var g := GameConfig.new()
	_check(g.leaderboard_key() == "Pitching/9inn/Standard", "a standard 9-inning pitching game has its own board (%s)" % g.leaderboard_key())
	g.assist = "Casual"
	_check(g.leaderboard_key() != GameConfig.new().leaderboard_key(), "assist levels never share a leaderboard")
	var fld := GameConfig.from_dict({"mode": "Fielding", "position": 5, "innings": 3, "assist": "Pro"})
	_check(fld.leaderboard_key() == "Fielding5/3inn/Pro", "fielding boards are per position (%s)" % fld.leaderboard_key())
	var prac := GameConfig.from_dict({"mode": "Pitching", "activity": "Practice", "batter": "MVP"})
	_check(prac.leaderboard_key() == "" and not prac.is_scored(), "practice is not scored")
	var spec := GameConfig.from_dict({"mode": "Spectate", "activity": "Practice"})
	_check(spec.activity == "Game" and not spec.is_scored(), "spectating is a game you watch, and is not scored")
	var weird := GameConfig.from_dict({"mode": "Hitting", "position": 42, "innings": 5, "batter": "Nobody", "assist": "??"})
	_check(weird.mode == "Pitching" and weird.position == 9 and weird.innings == 9 and weird.batter == "Contact Hitter" and weird.assist == "Standard",
		"a nonsense config is repaired")
	var bp := GameConfig.from_dict({"mode": "Fielding", "activity": "Bullpen"})
	_check(bp.activity == "Game", "there is no fielding bullpen")
	_check(GameConfig.from_dict(fld.to_dict()).to_dict() == fld.to_dict(), "a config round-trips")
	_check(fld.title().contains("3B"), "the title names the position (%s)" % fld.title())

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
