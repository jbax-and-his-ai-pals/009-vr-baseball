extends SceneTree
## Render every grip (the throwing hand holding the ball, with the grip's fingers) to tools/shots/grips.png.
## Run (a window is needed): tools/godot.sh --position -3000,0 --resolution 1500x700 -s res://tools/grip_preview.gd


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
	var names := Grips.names()
	for i in names.size():
		var n := Node3D.new()
		n.position = Vector3(-0.36 + 0.18 * (i % 5), 0.14 - 0.24 * (i / 5), 0.0)
		n.rotation_degrees = Vector3(-35.0, 200.0, 0.0)          # seen from the catcher's side, a little above
		root3.add_child(n)
		HandModels.attach(n, HandModels.hand_mesh(true))
		HandModels.attach(n, HandModels.grip_mesh(names[i], true))
		var ball := MeshInstance3D.new()
		ball.mesh = BallVisual.mesh()
		ball.material_override = BallVisual.material()
		ball.position = HumanPitcher.HOLD_OFFSET
		n.add_child(ball)
		var l := Label3D.new()
		l.text = names[i]
		l.pixel_size = 0.0005
		l.font_size = 32
		l.position = n.position + Vector3(0.0, -0.09, 0.05)
		root3.add_child(l)
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 0.10, 0.62), Vector3(0.0, 0.0, 0.0))
	cam.current = true
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png("C:/jbax-and-his-ai-pals/009-vr-baseball/tools/shots/grips.png")
	quit()
