extends SceneTree
## Ballparks: the fence and the wall are rules (homers differ by park), the colors and sky are the look,
## and the menu / config carry the choice.
## Run: godot --headless --path . -s res://tests/park_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


## A batted ball from the plate: exit speed (mph), launch angle, spray (degrees, + toward third base).
func _hit(ev_mph: float, la_deg: float, spray_deg: float) -> Dictionary:
	var v := ev_mph / PitchPhysics.MPS_TO_MPH
	var la := deg_to_rad(la_deg)
	var psi := deg_to_rad(spray_deg)
	var dir_h := Vector3(sin(psi), 0.0, cos(psi))
	var vel := dir_h * (v * cos(la)) + Vector3.UP * (v * sin(la))
	var spin := dir_h.cross(Vector3.UP).normalized() * (1800.0 * PitchPhysics.RPM_TO_RADS)
	return BattedBall.simulate(Vector3(0.0, 0.9, 0.4), vel, spin)


func _init() -> void:
	# The default is the old park.
	var harbor := Park.by_id("harbor")
	_check(is_equal_approx(harbor.fence_radius(0.0), 122.0) and is_equal_approx(harbor.fence_radius(45.0), 100.0) and is_equal_approx(harbor.fence_radius(-45.0), 100.0), "Harbor Field: 122 m to center, 100 down the lines")
	_check(is_equal_approx(harbor.fence_radius(180.0), 22.0) and harbor.fence_radius(90.0) > 22.0 and harbor.fence_radius(90.0) < 100.0, "and closes in behind the plate")
	_check(is_equal_approx(Stadium.fence_radius(0.0), 122.0), "Stadium.fence_radius still answers for the park in use")
	var cozy := Park.by_id("cozy")
	_check(is_equal_approx(cozy.fence_radius(45.0), 84.0) and is_equal_approx(cozy.fence_radius(-45.0), 94.0) and is_equal_approx(cozy.fence_radius(0.0), 110.0), "Cozy Yard has a short porch in left (84 m) and 94 in right")
	_check(cozy.fence_radius(20.0) < cozy.fence_radius(-20.0), "so the left-center gap is shorter than the right-center one")
	var canyon := Park.by_id("canyon")
	_check(canyon.night and canyon.wall_height > 4.0 and canyon.center > 130.0, "Canyon Park is a big night park with a tall wall")
	_check(Park.by_id("nonsense").id == "harbor", "an unknown park is the default")
	_check(Park.ids().size() == 4 and Park.by_id("cozy").describe().contains("Cozy Yard"), "four parks, each with a one-line description")
	# Continuity: no jump at 45 degrees.
	for p in [harbor, cozy, canyon]:
		_check(absf(p.fence_radius(44.99) - p.fence_radius(45.01)) < 0.5 and absf(p.fence_radius(-44.99) - p.fence_radius(-45.01)) < 0.5, "%s has no gap in the fence at 45 degrees" % p.name)

	# The rules: the same swing, different parks.
	var cozy_only := false
	var canyon_wall := false
	var harbor_more := false
	Park.current = harbor
	var base := {}
	var swings: Array = []
	for ev in [88.0, 92.0, 96.0, 100.0]:
		for la in [22.0, 26.0, 30.0, 34.0]:
			for spray in [-35.0, -15.0, 0.0, 15.0, 35.0]:
				swings.append([ev, la, spray])
	for s in swings:
		Park.current = harbor
		var h := _hit(s[0], s[1], s[2])
		Park.current = cozy
		var c := _hit(s[0], s[1], s[2])
		Park.current = canyon
		var k := _hit(s[0], s[1], s[2])
		if c.home_run and not h.home_run:
			cozy_only = true
		if h.home_run and not k.home_run:
			canyon_wall = true
		if h.home_run and c.home_run and not k.home_run:
			harbor_more = true
	Park.current = harbor
	_check(cozy_only, "some fly balls are homers in Cozy Yard and not in Harbor Field")
	_check(canyon_wall, "and some Harbor homers die in Canyon Park")
	_check(harbor_more, "including ones that Cozy Yard also gives up")
	# The wall height decides a line drive that is right at the fence.
	var low_wall := false
	for ev in [95.0, 100.0, 104.0]:
		for la in [14.0, 17.0, 20.0, 23.0]:
			Park.current = cozy
			var c2 := _hit(ev, la, 0.0)
			Park.current = canyon
			var k2 := _hit(ev, la, 0.0)
			if c2.home_run and not k2.home_run:
				low_wall = true
	Park.current = harbor
	_check(low_wall, "a hard line drive clears Cozy Yard's low wall and not Canyon Park's tall one")

	# Weather: thin air carries a fly ball, wind pushes it.
	Park.current = Park.by_id("harbor")
	var base_d: float = _hit(96.0, 28.0, 0.0).distance
	Park.current = Park.by_id("summit")
	var thin_d: float = _hit(96.0, 28.0, 0.0).distance
	_check(thin_d > base_d * 1.05, "a fly ball carries farther in the thin air of Summit Field (%.0f m vs %.0f m)" % [thin_d, base_d])
	Park.current = Park.by_id("harbor")
	Park.current.wind = Vector3(0.0, 0.0, 5.0)
	var out_d: float = _hit(96.0, 28.0, 0.0).distance
	Park.current.wind = Vector3(0.0, 0.0, -5.0)
	var in_d: float = _hit(96.0, 28.0, 0.0).distance
	Park.current.wind = Vector3(5.0, 0.0, 0.0)
	var cross: Dictionary = _hit(96.0, 28.0, 0.0)
	Park.current = Park.by_id("harbor")
	_check(out_d > base_d + 3.0 and in_d < base_d - 3.0, "wind blowing out adds distance and wind blowing in takes it away (%.0f / %.0f / %.0f m)" % [in_d, base_d, out_d])
	_check(float(cross.landing_pos.x) > 3.0, "a crosswind carries it sideways (%.1f m)" % float(cross.landing_pos.x))
	var w := Park.by_id("harbor")
	w.wind = Vector3(0.0, 0.0, 4.0)
	_check(w.wind_text() == "wind 9 mph, blowing out", "wind text: %s" % w.wind_text())
	w.wind = Vector3(0.0, 0.0, -4.0)
	_check(w.wind_text() == "wind 9 mph, blowing in", w.wind_text())
	w.wind = Vector3(3.0, 0.0, 3.0)
	_check(w.wind_text().contains("out to left"), w.wind_text())
	w.wind = Vector3(0.0, 0.0, 0.5)
	_check(w.wind_text() == "calm", "a breath of wind is calm")
	_check(Park.by_id("summit").describe().contains("thin air") and Park.by_id("canyon").describe().contains("blowing in"), "the park descriptions mention the weather")
	var d1 := GameConfig.daily_wind(20000)
	_check(d1 == GameConfig.daily_wind(20000) and d1 != GameConfig.daily_wind(20001) and d1.length() <= 5.5 and d1.y == 0.0, "the day's wind is the same for everybody and different tomorrow")

	# The league's parks.
	var lg := League.create(5, 6)
	_check(lg.park_of(0) == "harbor" and lg.park_of(5) == "summit" and lg.park_of(2) == "cozy" and lg.park_of(7) == "canyon" and lg.park_of(99) == "canyon", "every league team has a home park")
	var car := Career.create("Cal Reyes", "Balanced", 6, 3, 5)
	var at_home := car.game_park()
	car.matchday = 1
	_check(at_home == "harbor" and car.game_park() == car.league.park_of(car.opponent_index()), "a career plays at home on even matchdays and at the opponent's park on odd ones")
	for pid in lg.PARKS:
		_check(pid in Park.ids(), "park id %s exists" % pid)
		break

	# Config and menu.
	var c := GameConfig.new()
	c.park = "canyon"
	_check(c.normalized().park == "canyon" and GameConfig.from_dict(c.normalized().to_dict()).park == "canyon", "the park is part of the game config")
	c.park = "nowhere"
	_check(c.normalized().park == "harbor", "and an unknown one is the default")
	var d := GameConfig.new()
	d.park = "cozy"
	_check(d.normalized().leaderboard_key().contains("@cozy") and not GameConfig.new().normalized().leaderboard_key().contains("@"), "other parks have their own board; the default keeps the old keys")
	var m := MenuModel.new(Settings.new())
	m.stack = ["main", "play"]
	var pi := -1
	for i in m.items().size():
		if m.items()[i].id == "mode:Pitching":
			pi = i
	m.activate(pi)
	var idx := -1
	for i in m.items().size():
		if m.items()[i].id == "park":
			idx = i
	_check(idx >= 0 and m.items()[idx].value == "Harbor Field", "the setup page has a Park row")
	m.activate(idx)
	_check(m.config.park == "cozy" and m.items()[idx].value == "Cozy Yard", "choosing it cycles the park")

	# The park in the scene.
	ThrowLogger.override_path = "user://test_throws.jsonl"
	for pid in Park.ids():
		var gc := GameConfig.new()
		gc.park = pid
		var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
		bp.menu_on_start = false
		bp.apply_config(gc)
		root.add_child(bp)
		await process_frame
		_check(Park.now().id == pid and bp._current_config().park == pid, "the %s scene is built in its park" % pid)
		var env: Environment = null
		for ch in bp.get_children():
			if ch is WorldEnvironment:
				env = (ch as WorldEnvironment).environment
		_check(env != null and env.background_color.is_equal_approx(Park.now().sky), "with the park's sky")
		for i in 30:
			bp._process(1.0 / 60.0)
		bp.queue_free()
		await process_frame

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
