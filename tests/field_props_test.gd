extends SceneTree
## FieldProps alone: delayed calls run on the clock they are given, a dropped bat falls, bounces
## (once announced) and comes to rest, and goes away after a while; dust follows a node.
## Run: godot --headless --path . -s res://tests/field_props_test.gd

var _failures := 0
var _bounces := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	var fp := FieldProps.new()
	root.add_child(fp)
	fp.bat_bounced.connect(func(_at): _bounces += 1)
	await process_frame

	var fired := [0]
	fp.later(0.5, func(): fired[0] += 1)
	for i in 4:
		fp.update(0.1)
	_check(fired[0] == 0 and fp.pending_count() == 1, "a delayed call waits")
	for i in 3:
		fp.update(0.1)
	_check(fired[0] == 1 and fp.pending_count() == 0, "and runs once on time")

	fp.drop_bat(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	_check(fp.bat_count() == 1, "a dropped bat exists")
	for i in 120:
		fp.update(1.0 / 60.0)
	_check(_bounces == 1, "its first bounce is announced once (%d)" % _bounces)
	var bat: Node3D = fp._bats[0].node
	_check(bat.global_position.y < 0.1 and int(fp._bats[0].bounces) >= 3, "it comes to rest on the ground (y %.2f)" % bat.global_position.y)
	for i in 600:
		fp.update(1.0 / 60.0)
	_check(fp.bat_count() == 0, "and is picked up after a while")

	var node := Node3D.new()
	root.add_child(node)
	node.global_position = Vector3(5, 0, 20)
	fp.dust._process(2.0)          # let the bat's own dust fade first
	fp.puff_at(node, 0.2, 0.5, 3)
	fp.update(0.1)
	_check(fp.dust.active == 0, "the puff waits for its moment")
	fp.update(0.15)
	fp.dust._process(0.016)
	_check(fp.dust.active == 3, "then three puffs rise at the node (%d)" % fp.dust.active)
	node.free()
	fp.puff_at(Node3D.new(), 0.1, 0.5, 3)    # a node that is never in the tree is harmless
	fp.update(0.2)

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
