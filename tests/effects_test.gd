extends SceneTree
## The little effects: dirt, chalk, kicked-up grass and a quick flash share one pool; each has its own
## color and life; the foul-line distance says when a ball hit the chalk.
## Run: godot --headless --path . -s res://tests/effects_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _run(d: DustPuffs, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		d._process(0.02)
		t += 0.02


func _init() -> void:
	var B = load("res://scripts/bullpen.gd")
	var d := DustPuffs.new()
	root.add_child(d)
	d.puff(Vector3(0, 0, 10), 0.5, 3, DustPuffs.CHALK)
	d._process(0.02)
	_check(d.active == 3 and d._col[0] == DustPuffs.CHALK, "a chalk burst has chalk's color")
	_run(d, DustPuffs.LIFE + 0.1)
	_check(d.active == 0, "chalk fades like dust")
	d.puff(Vector3(3, 0, 40), 0.3, 4, DustPuffs.GRASS, 0.5)
	_run(d, 0.3)
	_check(d.active == 4, "grass is still in the air at 0.3 s")
	_run(d, 0.3)
	_check(d.active == 0, "and gone by 0.6 s (a shorter life than dirt)")
	d.flash(Vector3(0, 0.9, 0.4), 0.3)
	d._process(0.02)
	_check(d.active == 1 and d._col[(d._next + DustPuffs.CAPACITY - 1) % DustPuffs.CAPACITY] == DustPuffs.FLASH, "a flash is one bright puff")
	_run(d, DustPuffs.FLASH_LIFE + 0.06)
	_check(d.active == 0, "that is gone in a blink")
	d.puff(Vector3(0, 0, 10), 0.5, 2)
	_check(d._col[d._next - 1] == DustPuffs.DIRT and is_equal_approx(d._life[d._next - 1], DustPuffs.LIFE), "the old call still means dirt")
	for i in 40:
		d.puff(Vector3(1, 0, 10), 0.5, 5, DustPuffs.GRASS, 0.5)
	_check(d.active <= DustPuffs.CAPACITY, "the pool never overflows with mixed effects")

	_check(B.foul_line_distance(Vector3(30.0, 0.0, 30.0)) < 0.01 and B.foul_line_distance(Vector3(-40.0, 0.0, 40.0)) < 0.01, "points on either foul line are on it")
	_check(B.foul_line_distance(Vector3(0.0, 0.0, 50.0)) > 30.0, "dead center is far from both")
	_check(is_equal_approx(B.foul_line_distance(Vector3(30.0, 0.0, 31.0)), 0.7071), "a meter inside the line is 0.71 m from it")
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
