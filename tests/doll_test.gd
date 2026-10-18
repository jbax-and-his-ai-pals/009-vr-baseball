extends SceneTree
## The two figure styles share one rig: both build, both animate, both are one draw call.
## Run: godot --headless --path . -s res://tests/doll_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0.0, 1.6, 8.0)
	var soft := Doll.create(root, Vector3(-1.0, 0.0, 0.0), Color.RED, Color.WHITE, Color.BLUE, true, Doll.Style.SOFT)
	var paper := Doll.create(root, Vector3(1.0, 0.0, 0.0), Color.RED, Color.WHITE, Color.BLUE, true, Doll.Style.PAPER)
	await process_frame
	await process_frame
	for d in [soft, paper]:
		var meshes := 0
		var skeletons := 0
		for n in d.find_children("*", "", true, false):
			if n is MeshInstance3D:
				meshes += 1
			if n is Skeleton3D:
				skeletons += 1
		_check(meshes == 1 and skeletons == 1, "a %s doll is one skinned mesh (one draw call)" % ("soft" if d == soft else "paper"))
	var sk_soft: Skeleton3D = soft.find_children("*", "Skeleton3D", true, false)[0]
	_check(sk_soft.get_bone_count() == Doll.NAMES.size(), "the rig has %d bones" % Doll.NAMES.size())

	# A throw moves the throwing arm a long way and then gives it back.
	var rest_q := sk_soft.get_bone_pose_rotation(Doll.ARM_R)
	soft.throw_to(Vector3(0, 0, 20), "overhand", 0.8)
	var max_angle := 0.0
	for i in 60:
		await process_frame
		var q := sk_soft.get_bone_pose_rotation(Doll.ARM_R)
		max_angle = maxf(max_angle, rest_q.angle_to(q))
	_check(max_angle > deg_to_rad(60.0), "an overhand throw swings the arm well away from rest (%.0f deg)" % rad_to_deg(max_angle))
	for i in 90:
		await process_frame
	_check(not soft.busy(), "the clip ends by itself")
	var end_q := sk_soft.get_bone_pose_rotation(Doll.ARM_R)
	_check(rest_q.angle_to(end_q) < deg_to_rad(40.0), "and the arm comes back down")

	# Running reads from how it is moved: legs swing when the node moves, not when it stands.
	var sk_p: Skeleton3D = paper.find_children("*", "Skeleton3D", true, false)[0]
	var still_a := sk_p.get_bone_pose_rotation(Doll.LEG_L)
	var swing := 0.0
	for i in 40:
		paper.position.z += 0.1
		await process_frame
		swing = maxf(swing, still_a.angle_to(sk_p.get_bone_pose_rotation(Doll.LEG_L)))
	_check(swing > deg_to_rad(25.0), "moving a doll runs it (legs swing %.0f deg)" % rad_to_deg(swing))

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
