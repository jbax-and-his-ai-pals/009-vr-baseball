extends SceneTree
## The batter is a Doll holding a bat: the bat goes exactly where the swing says, the hands stay
## on it, the bat hangs low while he walks up, a bunt squares him around, and dropped bats and
## dust puffs behave.
## Run: godot --headless --path . -s res://tests/batter_rig_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	var b := CartoonBatter.new()
	b.position = Vector3(0.98, 0.0, 0.0)
	root.add_child(b)
	await _frames(3)

	# Contact: the sweet spot is on the point, to the frame.
	var worst := 0.0
	for p in [Vector3(0.0, 0.9, 0.2), Vector3(0.1, 0.7, 0.15), Vector3(-0.05, 1.1, 0.25), Vector3(0.0, 0.8, 0.0)]:
		b.swing_to(p, 0.3)
		b.snap_to_contact()
		worst = maxf(worst, b.sweet_spot_world().distance_to(p))
		b.reset()
	_check(worst < 0.03, "the sweet spot lands on the contact point (worst %.3f m)" % worst)

	# The hands hold the bat: lead hand near the low grip, top hand near the upper one.
	b.swing_to(Vector3(0.0, 0.9, 0.2), 0.3)
	b.snap_to_contact()
	await _frames(2)
	var low: Vector3 = b.to_global(b._h_low)
	var up: Vector3 = b.to_global(b._h_up)
	var d_low := b.doll.glove_world().distance_to(low)
	var d_up := b.doll.hand_world().distance_to(up)
	_check(d_low < 0.16 and d_up < 0.16, "both hands are on the bat at contact (%.3f, %.3f m)" % [d_low, d_up])
	b.reset()
	await _frames(2)

	# At rest, in the stance, the hands are on it too.
	d_low = b.doll.glove_world().distance_to(b.to_global(b._h_low))
	_check(d_low < 0.16, "hands on the bat in the stance (%.3f m)" % d_low)

	# Walking up the bat hangs low; in the box it is up.
	var up_y: float = b._bat.global_transform.basis.y.y
	b.set_carry(true, true)
	await _frames(2)
	var carried_y: float = b._bat.global_transform.basis.y.y
	_check(up_y > 0.5 and carried_y < -0.5, "the bat points up in the stance (%.2f) and down while he walks (%.2f)" % [up_y, carried_y])
	b.set_carry(false)
	for i in 40:
		b._process(1.0 / 30.0)
	_check(b._bat.global_transform.basis.y.y > 0.5, "the bat comes back up when he steps in")

	# A bunt squares him around further than a swing does at contact.
	b.bunt_to(Vector3(0.0, 0.8, 0.3), 0.5)
	b.snap_to_contact()
	_check(absf(b.doll.twist) > 75.0, "a bunt squares the shoulders to the pitcher (%.0f deg)" % b.doll.twist)
	b.reset()
	b.swing_to(Vector3(0.0, 0.9, 0.2), 0.3)
	b.snap_to_contact()
	_check(absf(b.doll.twist) < 75.0 and absf(b.doll.twist) > 55.0, "a swing turns him less (%.0f deg)" % b.doll.twist)
	b.reset()

	# A check swing goes part of the way and comes back.
	b.check_swing(Vector3(0.0, 0.9, 0.2), 0.3)
	for i in 6:
		b._process(1.0 / 30.0)
	var mid := absf(b.doll.twist)
	for i in 60:
		b._process(1.0 / 30.0)
	_check(mid > 3.0 and absf(b.doll.twist) < 1.0 and not b._active, "a check swing starts and stops (%.0f deg, then back)" % mid)

	# The bat can be dropped and put back.
	var xf := b.drop_bat()
	_check(not b._bat.visible and xf.origin.length() > 0.0, "dropping the bat hides his")
	b.reset()
	_check(b._bat.visible, "a new batter has a bat")

	# A left-hander is the mirror image: same contact accuracy, hands on the bat.
	var lb := CartoonBatter.new()
	lb.right_handed = false
	lb.position = Vector3(0.98, 0.0, 0.0)
	root.add_child(lb)
	await _frames(3)
	var lworst := 0.0
	for p in [Vector3(0.0, 0.9, 0.2), Vector3(-0.1, 0.7, 0.15), Vector3(0.05, 1.1, 0.25)]:
		lb.swing_to(p, 0.3)
		lb.snap_to_contact()
		lworst = maxf(lworst, lb.sweet_spot_world().distance_to(p))
		lb.reset()
	_check(lb.global_position.x < -0.5 and lworst < 0.03, "a left-hander stands at the other side and meets the ball (box x %.2f, worst %.3f m)" % [lb.global_position.x, lworst])
	lb.swing_to(Vector3(0.0, 0.9, 0.2), 0.3)
	lb.snap_to_contact()
	await _frames(2)
	var ld := lb.doll.glove_world().distance_to(lb.to_global(lb._h_low))
	var lu := lb.doll.hand_world().distance_to(lb.to_global(lb._h_up))
	_check(ld < 0.16 and lu < 0.16, "a left-hander's hands are on the bat (%.3f, %.3f m)" % [ld, lu])

	# The dust pool: a burst appears, fades and is gone; a flood never overflows the pool.
	var dust := DustPuffs.new()
	root.add_child(dust)
	dust.puff(Vector3(0, 0, 10), 0.5, 3)
	await _frames(3)
	_check(dust.active == 3, "three puffs alive after a burst (%d)" % dust.active)
	for i in 200:
		dust.puff(Vector3(1, 0, 10), 0.5, 5)
	await _frames(2)
	_check(dust.active <= DustPuffs.CAPACITY, "the pool never exceeds its capacity (%d)" % dust.active)
	var t := 0.0
	while t < DustPuffs.LIFE + 0.5:
		dust._process(0.1)
		t += 0.1
	_check(dust.active == 0, "puffs fade away (%d left)" % dust.active)

	# Every new clip exists and plays on both skins.
	for style in [Doll.Style.SOFT, Doll.Style.PAPER]:
		var d := Doll.create(root, Vector3(5, 0, 5), Color.RED, Color.WHITE, Color.BLUE, true, style)
		await _frames(2)
		var all_ok := true
		for clip in ["scoop", "backhand", "jump", "react", "tag", "fist_pump", "celebrate", "slide", "dive"]:
			d.play(clip, 0.5)
			if not d.busy():
				all_ok = false
			for i in 8:
				await process_frame
		_check(all_ok, "all the new clips play (%s)" % ["soft", "paper"][style])

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
