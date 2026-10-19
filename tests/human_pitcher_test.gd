extends SceneTree
## HumanPitcher on its own, with synthetic hand samples and stand-in tuning knobs: a fast sweep
## toward the plate is a pitch, a slow one is a drop, nothing readable is invalid, a throw toward
## first base is a pickoff, the funnel aims at the zone and learns your usual aim, a tired arm and a
## weak command widen it, and a career pitcher's command narrows it.
## Run: godot --headless --path . -s res://tests/human_pitcher_test.gd

class Knobs:
	var velocity_gain := 2.4
	var max_mph := 100.0
	var spin_gain := 6.0
	var aim_assist := 1.0
	var funnel_spread_x := 0.40
	var funnel_spread_y := 0.30
	var aim_learn_rate := 0.08
	var technique_gain := 1.0
	var fastball_backspin_rpm := 1700.0
	var velocity_latency := 0.015
	var spin_latency := 0.04
	var spin_mode := 1
	var aim_mode := 2
	var throwing_hand := &"right_hand"

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _sweep(h: HumanPitcher, t0: float, speed: float, rise: float, x_drift: float = 0.0) -> void:
	h.detector.clear()
	for i in 27:
		var k := i / 90.0
		h.detector.add_sample(t0 + k, Vector3(x_drift * k, 2.0 + rise * k, 18.0 - speed * k), Quaternion.IDENTITY, 0.9)


func _init() -> void:
	var h := HumanPitcher.new()
	h.knobs = Knobs.new()
	var t0 := 100.0
	var from := Vector3(0.0, 2.2, 16.0)

	_check(h.throw(t0, 0.015, 0.04, from, 1.7, 0.0, 1.0, false).kind == "invalid", "no samples: nothing readable")

	_sweep(h, t0, 12.0, 0.0)
	h.held = true
	var r := h.throw(t0 + 26.0 / 90.0, 0.015, 0.04, from, 1.7, 0.0, 1.0, false)
	_check(r.kind == "pitch" and (r.vel as Vector3).z < 0.0 and (r.vel as Vector3).length() > 20.0 and not h.held, "a fast sweep toward the plate is a pitch, and you let go (speed %.0f m/s)" % (r.vel as Vector3).length())
	_check(r.shape.has("spin") and r.funnel.has("target") and r.hand_sign == 1.0 and r.delivery == 0.9, "it carries the spin shape, the aim target and the delivery time")

	_sweep(h, t0 + 10.0, 0.5, 0.0)
	h.delivery_start = 1.0
	var soft := h.throw(t0 + 10.0 + 26.0 / 90.0, 0.015, 0.04, from, 1.7, 0.0, 1.0, true)
	_check(soft.kind == "drop" and soft.started, "a feeble release with a runner on is a drop that counts as a balk")
	_sweep(h, t0 + 20.0, 0.5, 0.0)
	_check(h.throw(t0 + 20.0 + 26.0 / 90.0, 0.015, 0.04, from, 1.7, 0.0, 1.0, true).started == false, "...unless you had not started your delivery")

	# A throw toward first base.
	h.detector.clear()
	for i in 27:
		var k := i / 90.0
		h.detector.add_sample(t0 + 30.0 + k, Vector3(-15.0 * k, 2.0, 12.0 - 0.0 * k) + Vector3(0.0, 0.0, 6.0 * k), Quaternion.IDENTITY, 0.9)
	var po := h.throw(t0 + 30.0 + 26.0 / 90.0, 0.015, 0.04, Vector3(0.0, 1.5, 16.7), 1.7, 0.0, 1.0, true)
	_check(po.kind in ["pickoff", "pitch"], "a throw sideways is read as a throw over or a pitch, never a crash (%s)" % po.kind)

	# The funnel.
	var h2 := HumanPitcher.new()
	h2.knobs = Knobs.new()
	_sweep(h2, 200.0, 12.0, 0.0)
	var f := h2.funnel_target(200.0 + 26.0 / 90.0, 0.0, 1.0)
	_check(not f.fallback and absf(f.target.x) < 1.0 and f.target.y > 0.2 and f.target.y < 2.0, "the funnel aims near the zone for a normal throw (%.2f, %.2f)" % [f.target.x, f.target.y])
	_check(h2.aim_n == 1, "and it learns from the throw")
	var n0 := h2.aim_mu
	for i in 12:
		_sweep(h2, 300.0 + i * 5.0, 12.0, 0.0, 1.5)
		h2.funnel_target(300.0 + i * 5.0 + 26.0 / 90.0, 0.0, 1.0)
	_check(h2.aim_mu != n0 and h2.aim_n == 13, "your usual aim drifts toward how you really throw")
	var empty := HumanPitcher.new()
	empty.knobs = Knobs.new()
	_check(empty.funnel_target(1.0, 0.0, 1.0).fallback, "no samples: the target is the zone center")

	# Wider when tired or with weak command, narrower for a veteran.
	var a1 := HumanPitcher.new()
	a1.knobs = Knobs.new()
	a1.aim_mu = Vector2(0.0, 0.0)
	a1.aim_sigma = Vector2(3.0, 3.0)
	var offs: Array = []
	for cfg in [[0.0, 1.0], [1.0, 1.0], [0.0, 1.2], [0.0, 0.8]]:
		a1.aim_n = 99
		_sweep(a1, 500.0, 12.0, 3.0, 2.0)               # rising and drifting: an off-centre throw
		var tg: Vector3 = a1.funnel_target(500.0 + 26.0 / 90.0, cfg[0], cfg[1]).target
		offs.append(Vector2(tg.x - HumanPitcher.ZONE_CENTER.x, tg.y - HumanPitcher.ZONE_CENTER.y).length())
	_check(offs[1] > offs[0] and offs[2] > offs[0] and offs[3] < offs[0], "a tired arm and weak command miss wider, a veteran narrower (%s)" % str(offs.map(func(x): return snappedf(x, 0.01))))

	# The log line.
	var ctx := {"head_pos": Vector3(0, 1.7, 18.4), "head_fwd": Vector3(0, 0, -1), "hand_fwd": Vector3(0, 0, -1), "tag": "normal", "auto": false,
		"batter_profile": "MVP", "game": {"inning": 1, "outs": 0, "balls": 0, "strikes": 0, "bases": [false, false, false], "batter": "X"}}
	var pitch := LivePitch.new()
	pitch.label = "Fastball"
	pitch.vel = Vector3(0, 0, -30)
	pitch.analysis = {"reached": false}
	_sweep(h, 600.0, 12.0, 0.0)
	h.held = true
	var rr := h.throw(600.0 + 26.0 / 90.0, 0.015, 0.04, from, 1.7, 0.0, 1.0, false)
	var entry := h.log_entry(ctx, pitch, from, 600.0 + 26.0 / 90.0, 0.015, rr.est, rr.scaled, rr.spin, rr.funnel, rr.shape)
	_check(entry.has("raw") and entry.has("wrist") and entry.has("funnel") and entry.pitch_name == "Fastball" and entry.game.batter == "X" and entry.aim_mode == "FUNNEL", "the log line has the arm, the wrist model, the funnel and the game")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
