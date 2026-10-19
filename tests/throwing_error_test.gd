extends SceneTree
## Throwing errors: a routine throw to first sails about 1% of the time, more from a weak arm and a
## long throw; the runner is then safe and can take an extra base.
## Run: godot --headless --path . -s res://tests/throwing_error_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _rate(arm: float, n: int) -> Array:
	var team := Team.generate("D", 55.0, 3)
	for pos in range(1, 10):
		team.player_at(pos).arm = arm
		team.player_at(pos).hands = 95.0                # no fielding errors muddying it
	var errors := 0
	var extra := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for i in n:
		var d := Defense.from_team(team)
		d.rng.seed = i + 1
		var psi := deg_to_rad(rng.randf_range(-30.0, 30.0))
		var speed := rng.randf_range(24.0, 33.0)
		var vel := Vector3(sin(psi), 0.0, cos(psi)) * speed + Vector3(0, 0.6, 0)
		var sim := BattedBall.simulate(Vector3(0, 0.9, 0), vel, Vector3.ZERO)
		var p := d.resolve(sim, 1.0)
		if p.get("throwing_error", false):
			errors += 1
			if int(p.get("bases", 1)) >= 2:
				extra += 1
	return [errors, extra]


func _init() -> void:
	var weak := _rate(15.0, 2500)
	var strong := _rate(95.0, 2500)
	_check(weak[0] > strong[0] and weak[0] > 25, "a weak arm throws it away more often than a strong one (%d vs %d in 2,500 grounders)" % [weak[0], strong[0]])
	_check(weak[0] < 220, "but it stays an occasional thing (%d)" % weak[0])
	var d := Defense.from_team(Team.generate("D", 55.0, 3))
	var f := d.fielder_by_num(6)
	_check(d.throwing_error_chance(f, 30.0) > d.throwing_error_chance(f, 8.0), "a longer throw is riskier")
	_check(d.throwing_error_chance(f, 20.0) < 0.05, "and never a coin flip")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var team := Team.generate("D", 55.0, 3)
	var saw_text := false
	var batter_safe := true
	for i in 3000:
		var dd := Defense.from_team(team)
		dd.rng.seed = i + 100
		var vel := Vector3(sin(deg_to_rad(rng.randf_range(-25, 25))), 0.0, 0.9) * 28.0
		var sim := BattedBall.simulate(Vector3(0, 0.9, 0), vel, Vector3.ZERO)
		var p := dd.resolve(sim, 1.0)
		if p.get("throwing_error", false):
			saw_text = saw_text or String(p.text).begins_with("Throwing error")
			batter_safe = batter_safe and p.result == "error" and int(p.bases) >= 1
	_check(saw_text and batter_safe, "an error play says so and puts the batter on")
	print("  extra bases on throwing errors (weak arm): %d of %d" % [weak[1], weak[0]])

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
