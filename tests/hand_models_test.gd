extends SceneTree
## The controller models: a hand and a glove, each one mesh, cheap, the right size, and mirrored.
## Run: godot --headless --path . -s res://tests/hand_models_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _tris(mesh: ArrayMesh) -> int:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3


func _init() -> void:
	var rh := HandModels.hand_mesh(true)
	var lh := HandModels.hand_mesh(false)
	var g := HandModels.glove_mesh(false)
	for pair in [["right hand", rh], ["left hand", lh], ["glove", g]]:
		var mesh: ArrayMesh = pair[1]
		_check(mesh.get_surface_count() == 1, "%s is one surface (one draw call)" % pair[0])
		_check(_tris(mesh) > 100 and _tris(mesh) < 1500, "%s is cheap (%d triangles)" % [pair[0], _tris(mesh)])
		var box := mesh.get_aabb()
		_check(box.size.x < 0.35 and box.size.y < 0.25 and box.size.z < 0.4, "%s is a hand-sized object (%s)" % [pair[0], str(box.size)])
	_check(rh.get_aabb().position.x != lh.get_aabb().position.x or rh.get_aabb().end.x != lh.get_aabb().end.x, "the left hand is the mirror of the right (the thumb is on the other side)")
	var gb := g.get_aabb()
	_check(gb.has_point(Vector3(0.0, 0.0, -0.12)), "the glove's pocket is where the catch is judged (0.12 m in front of the controller)")
	_check(gb.position.z < -0.2, "and its fingers reach out in front of it")
	var holder := Node3D.new()
	root.add_child(holder)
	var inst := HandModels.attach(holder, rh)
	_check(inst.get_parent() == holder and inst.material_override != null and inst.name == "HandModel", "attach puts it on a controller with vertex colors")
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
