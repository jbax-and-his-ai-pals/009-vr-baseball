extends SceneTree
## Render the controller models (hand and glove, from two sides) to tools/shots/hands.png.
## Run (a window is needed): tools/godot.sh --position -3000,0 --resolution 1200x600 -s res://tools/hand_preview.gd


func _init() -> void:
	var root3 := Node3D.new()
	root.add_child(root3)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.75, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	root3.add_child(sun)
	var spots := [
		[Vector3(-0.55, 0.0, 0.0), HandModels.hand_mesh(true), 0.0],
		[Vector3(-0.2, 0.0, 0.0), HandModels.hand_mesh(false), 0.0],
		[Vector3(0.2, 0.0, 0.0), HandModels.glove_mesh(false), 0.0],
		[Vector3(0.55, 0.0, 0.0), HandModels.glove_mesh(true), 0.0],
		[Vector3(-0.375, -0.30, 0.0), HandModels.hand_mesh(true), 90.0],
		[Vector3(0.375, -0.30, 0.0), HandModels.glove_mesh(false), 90.0],
	]
	for s in spots:
		var n := Node3D.new()
		n.position = s[0]
		n.rotation_degrees = Vector3(-30.0, 215.0, 0.0) if float(s[2]) == 0.0 else Vector3(-70.0, 160.0, 0.0)
		root3.add_child(n)
		HandModels.attach(n, s[1])
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 0.2, 0.62), Vector3(0.0, -0.08, 0.0))
	cam.current = true
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png("C:/jbax-and-his-ai-pals/009-vr-baseball/tools/shots/hands.png")
	quit()
