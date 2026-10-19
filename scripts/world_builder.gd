class_name WorldBuilder
extends RefCounted
## Puts the scene together: the park, the figures standing in it (fielders, runners, umpires, the batter), the boards, the zone
## and the ball, and the camera and controllers (the XR rig, or a plain camera on a desktop). Also hands out the figures' uniforms and
## styles. The scene (`host`) owns the pieces once they exist.

var host                                    # the bullpen scene (untyped: its members are reached by name)

var doll_demo: Array = []
var doll_styles := {}
var runner_styles := 0
var doll_demo_step := 0


## Soft or paper, decided once per player so a person always looks the same. `--doll-style=soft`
## or `paper` forces one for everybody.
func doll_style(key: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a == "--doll-style=soft":
			return Doll.Style.SOFT
		if a == "--doll-style=paper":
			return Doll.Style.PAPER
	if not doll_styles.has(key):
		doll_styles[key] = host._fx_rng.randi() % 2
	return doll_styles[key]


## The pitcher as a person on the mound (only when you are not him): he throws each pitch and covers first.
func ensure_pitcher_doll() -> void:
	if host._field_nodes.has(1):
		return
	var home: Vector3 = host._defense.fielder_by_num(1).home
	var d = Doll.create(host, Vector3(home.x, PitchPhysics.MOUND_H, home.z), host._home.jersey, Color(0.62, 0.64, 0.70), host._home.jersey, true, doll_style(1))
	d.footstep.connect(host._on_footstep)
	d.rotation.y = PI                    # facing home plate
	host._field_nodes[1] = d


func runner_doll(at: Vector3) -> Doll:
	runner_styles += 1
	var d = Doll.create(host, at, Color(0.84, 0.16, 0.18), Color(0.95, 0.95, 0.97), Color(0.12, 0.17, 0.50), false,
		doll_style(100 + runner_styles))
	d.crouch = 0.0
	d.footstep.connect(host._on_footstep)
	return d


## Debug: a row of soft and paper figures side by side, each looping through the clips.
func spawn_doll_demo() -> void:
	var navy = Color(0.12, 0.17, 0.50)
	var red = Color(0.84, 0.16, 0.18)
	for i in 8:
		var d = Doll.create(host, Vector3(-7.0 + i * 2.0, 0.0, 9.0), red if i % 2 == 0 else navy,
			Color(0.95, 0.95, 0.97) if i % 2 == 0 else Color(0.62, 0.64, 0.70), navy, true, i % 2)
		d.rotation.y = deg_to_rad(90.0) if i < 4 else deg_to_rad(-90.0)
		doll_demo.append(d)
	var timer = Timer.new()
	timer.wait_time = 2.4
	timer.autostart = true
	timer.timeout.connect(func():
		doll_demo_step += 1
		var kinds = ["overhand", "sidearm", "underhand", "catch", "scoop", "backhand", "jump", "react", "tag", "slide", "dive", "block",
			"ump_strike", "ump_safe", "ump_out", "celebrate", "fist_pump"]
		for k in doll_demo.size():
			var d: Doll = doll_demo[k]
			d.play(kinds[(doll_demo_step + k / 2) % kinds.size()], 1.1))
	host.add_child(timer)


func build_world() -> void:
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Park.now().sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = Park.now().ambient
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	host.add_child(world_env)

	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	if Park.now().night:
		sun.light_energy = 0.45
	host.add_child(sun)

	var mz = PitchPhysics.MOUND_Z
	var mh = PitchPhysics.MOUND_H
	# The park (grass, infield, stands, crowd, ...) and a batter standing in his box.
	host._stadium = Stadium.new()
	host.add_child(host._stadium)
	host._presenter = BatterPresenter.new()
	host.add_child(host._presenter)
	host._presenter.setup(host)
	host._batter = host._presenter.batter
	host._props = FieldProps.new()
	host.add_child(host._props)
	host._dust = host._props.dust
	host._props.bat_bounced.connect(func(at: Vector3): host._sfx("bat_drop", at))

	# Mound, plate, rubber, backstop wall and the cartoon catcher: one baked mesh, one draw call.
	var field = MeshMerger.new()
	var mound = CylinderMesh.new()
	mound.top_radius = 2.7
	mound.bottom_radius = 3.4
	mound.height = mh
	field.add_at(mound, Color(0.72, 0.52, 0.34), Vector3(0.0, mh * 0.5, mz))
	var plate = BoxMesh.new()
	plate.size = Vector3(0.432, 0.02, 0.432)
	field.add_at(plate, Color.WHITE, Vector3(0.0, 0.015, 0.0))
	var rubber = BoxMesh.new()
	rubber.size = Vector3(0.61, 0.03, 0.15)
	field.add_at(rubber, Color.WHITE, Vector3(0.0, mh + 0.015, mz))
	var backstop = BoxMesh.new()
	backstop.size = Vector3(24.0, 3.0, 0.3)
	field.add_at(backstop, Color(0.2, 0.35, 0.25), Vector3(0.0, 1.5, host.BACKSTOP_Z - 0.2))
	field.build_instance(host)
	var navy_c = host._home.jersey
	host._catcher = Doll.create(host, Vector3(0.0, 0.0, -1.35), navy_c, Color(0.62, 0.64, 0.70), navy_c, true, doll_style(2), "catcher")
	host._field_nodes[2] = host._catcher
	host._umpire = Doll.create(host, Vector3(0.0, 0.0, PlateCrew.UMP_HOME_Z), Color(0.20, 0.20, 0.25), Color(0.38, 0.38, 0.43),
		Color(0.08, 0.08, 0.10), false, doll_style(3), "umpire")
	# The base umpires: first and third in foul ground, second behind the bag (one draw call each).
	for i in 3:
		host._base_ump_dolls.append(Doll.create(host, Vector3.ZERO, Color(0.20, 0.20, 0.25), Color(0.38, 0.38, 0.43),
			Color(0.08, 0.08, 0.10), false, doll_style(40 + i), "base_umpire"))
	# The rest of the defense: one draw call each. The pitcher is the player, so he is abstract.
	var navy = host._home.jersey
	for f in host._defense.fielders:
		if f.visible and f.num != 2:
			var node = Doll.create(host, f.home, navy, Color(0.62, 0.64, 0.70), navy, true, doll_style(f.num))
			node.footstep.connect(host._on_footstep)
			node.rotation.y = atan2(-f.home.x, -f.home.z)
			host._field_nodes[f.num] = node
	if not host._mode.human_pitcher:
		ensure_pitcher_doll()           # nobody to throw for you: the pitcher is a person on the mound
	if not host._mode.human_fielders.is_empty():
		var me: Node3D = host._field_nodes.get(int(host._mode.human_fielders[0]))
		if me:
			me.visible = false
	# The batter becomes a runner once he hits it.
	host._runner = runner_doll(Vector3(0.98, 0.0, 0.0))
	host._runner.visible = false
	for i in 3:
		var lv = runner_doll(Vector3.ZERO)
		lv.visible = false
		host._leavers.append(lv)
	# SAFE / OUT / RUN callouts: several can be up at once on a double play.
	for i in 4:
		var lab = Label3D.new()
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.fixed_size = true
		lab.pixel_size = 0.0016
		lab.font_size = 80
		lab.outline_size = 16
		lab.no_depth_test = true
		lab.visible = false
		host.add_child(lab)
		host._play_labels.append(lab)

	# Translucent strike zone at the front of the plate, facing the pitcher.
	var zone = QuadMesh.new()
	var zone_h = PitchPhysics.ZONE_TOP - PitchPhysics.ZONE_BOTTOM
	zone.size = Vector2(PitchPhysics.ZONE_HALF_W * 2.0, zone_h)
	var zone_inst = add_mesh(zone, Color(1.0, 1.0, 1.0, 0.22), Vector3(0.0, PitchPhysics.ZONE_BOTTOM + zone_h * 0.5, 0.0))
	var zone_mat = zone_inst.material_override as StandardMaterial3D
	zone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	zone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	zone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	host.manager.sign_label = Label3D.new()
	host.manager.sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	host.manager.sign_label.fixed_size = true
	host.manager.sign_label.pixel_size = 0.0014
	host.manager.sign_label.font_size = 64
	host.manager.sign_label.outline_size = 14
	host.manager.sign_label.modulate = Color(0.55, 0.95, 1.0)
	host.manager.sign_label.no_depth_test = true
	host.manager.sign_label.position = Vector3(0.75, 0.45, -1.25)
	host.manager.sign_label.visible = false
	host.add_child(host.manager.sign_label)
	var marker_mesh = SphereMesh.new()
	marker_mesh.radius = 0.045
	marker_mesh.height = 0.09
	host.manager.sign_marker = add_mesh(marker_mesh, Color(0.4, 0.95, 1.0, 0.55), Vector3(0.0, 0.85, 0.02))
	var marker_mat = host.manager.sign_marker.material_override as StandardMaterial3D
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	host.manager.sign_marker.visible = false
	host._call_label = Label3D.new()
	host._call_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	host._call_label.fixed_size = true
	host._call_label.pixel_size = 0.0021
	host._call_label.font_size = 96
	host._call_label.outline_size = 22
	host._call_label.no_depth_test = true
	host._call_label.position = Vector3(0.0, 3.5, -1.6)
	host._call_label.visible = false
	host.add_child(host._call_label)
	host._zone_markers = ZoneMarkers.new()
	host.add_child(host._zone_markers)

	# Shared ball mesh: a stitched baseball, one draw call for every ball (held, pitched, batted).
	host.flight.ball_mesh = BallVisual.mesh()
	host.flight.trail_mat = StandardMaterial3D.new()
	host.flight.trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	host.flight.trail_mat.albedo_color = Color(1.0, 0.9, 0.2)
	host.flight.held_ball = make_ball()
	host.flight.held_ball.visible = false

	host.hud.build_boards()


func add_mesh(mesh: Mesh, color: Color, at: Vector3, parent: Node = null) -> MeshInstance3D:
	var inst = MeshInstance3D.new()
	inst.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	inst.material_override = mat
	inst.position = at
	(parent if parent else host).add_child(inst)
	return inst


func make_ball() -> MeshInstance3D:
	var ball = MeshInstance3D.new()
	ball.mesh = host.flight.ball_mesh
	ball.material_override = BallVisual.material()
	host.add_child(ball)
	return ball


## True when this run was asked not to touch the headset: `--xr-mode off` (Godot's own flag,
## which also keeps OpenXR from starting) or `--no-xr`. Tests, screenshots and profiling use it so
## they never grab the Virtual Desktop session.
static func xr_disabled_by_args() -> bool:
	var args = OS.get_cmdline_args()
	if "--no-xr" in args:
		return true
	var i = args.find("--xr-mode")
	return i >= 0 and i + 1 < args.size() and args[i + 1] == "off"


func setup_xr() -> void:
	var mz = PitchPhysics.MOUND_Z
	var mh = PitchPhysics.MOUND_H
	var xr = XRServer.find_interface("OpenXR")
	if xr_disabled_by_args():
		xr = null
	if xr and (xr.is_initialized() or xr.initialize()):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		host.get_viewport().use_xr = true
		host._xr_active = true
		host._xr_interface = xr
		print("XR: started on %s | render target %s | view count %d | tuning %s" % [
			xr.get_name(), xr.get_render_target_size(), xr.get_view_count(), "ON" if host.xr_tuning else "off"])
		if host.xr_tuning:
			# Quest-oriented render settings, by name so a runtime that lacks one is harmless.
			host.get_viewport().vrs_mode = Viewport.VRS_XR
			xr.set("display_refresh_rate", 90.0)
			xr.set("render_target_size_multiplier", 1.0)
			xr.set("foveation_level", 2)
			xr.set("foveation_dynamic", true)
			host._governor.set_refresh_rate(90.0)
		var origin = XROrigin3D.new()
		origin.position = Vector3(0.0, mh, mz) if host._mode.human_pitcher else Vector3(3.5, 0.0, -5.0)
		if not host._mode.human_fielders.is_empty():
			var spot: Vector3 = host._defense.fielder_by_num(int(host._mode.human_fielders[0])).home
			origin.position = Vector3(spot.x, 0.0, spot.z)
			origin.rotation.y = atan2(spot.x, spot.z)       # face home plate
			if int(host._mode.human_fielders[0]) == 1:
				origin.position = Vector3(1.4, 0.0, spot.z + 0.2)       # beside the rubber, out of the AI's delivery
		if host._mode.human_batter:
			# You stand just outside your box, square to the pitcher.
			var side = 1.0 if host._settings.hand == "right" else -1.0
			origin.position = Vector3(side * 1.2, 0.0, -0.1)
			origin.rotation.y = PI
		host._origin = origin
		host.add_child(origin)
		var cam = XRCamera3D.new()
		origin.add_child(cam)
		host._camera = cam
		for hand_name in [&"left_hand", &"right_hand"]:
			var ctrl = XRController3D.new()
			ctrl.tracker = hand_name
			origin.add_child(ctrl)
			var is_right: bool = hand_name == &"right_hand"
			if hand_name == host.throwing_hand:
				host._hand = ctrl
				HandModels.attach(ctrl, HandModels.hand_mesh(is_right))
			else:
				host._off_hand = ctrl
				if host._mode.human_batter:
					HandModels.attach(ctrl, HandModels.hand_mesh(is_right))         # both hands are on the bat
				else:
					HandModels.attach(ctrl, HandModels.glove_mesh(is_right))        # the glove goes on the hand that does not throw
	else:
		var cam = Camera3D.new()
		var args = OS.get_cmdline_user_args()
		var cam_arg = ""
		for a in args:
			if a.begins_with("--cam="):
				cam_arg = a.substr(6)
		if cam_arg != "":
			# Debug: --cam=x,y,z:lx,ly,lz  (position : look-at)
			var halves = cam_arg.split(":")
			var pp = halves[0].split(",")
			var ll = halves[1].split(",")
			cam.position = Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
			host.add_child(cam)
			cam.look_at(Vector3(float(ll[0]), float(ll[1]), float(ll[2])))
		elif "--overview" in args:
			cam.position = Vector3(-46.0, 38.0, -34.0)
			host.add_child(cam)
			cam.look_at(Vector3(0.0, 4.0, 40.0))
		elif "--behind-plate" in args:
			cam.position = Vector3(0.0, 1.6, -5.5)
			host.add_child(cam)
			cam.look_at(Vector3(0.0, 1.5, 30.0))
		elif "--infield" in args:
			cam.position = Vector3(-26.0, 13.0, 2.0)
			host.add_child(cam)
			cam.look_at(Vector3(0.0, 0.5, 26.0))
		elif "--outfield" in args:
			cam.position = Vector3(-30.0, 22.0, 20.0)
			host.add_child(cam)
			cam.look_at(Vector3(5.0, 0.0, 80.0))
		elif "--hit" in args:
			cam.position = Vector3(-2.5, 2.2, -3.0)
			host.add_child(cam)
			cam.look_at(Vector3(0.0, 8.0, 40.0))
		elif "--batter" in args:
			cam.position = Vector3(-1.2, 1.5, 4.0)
			host.add_child(cam)
			cam.look_at(Vector3(0.9, 1.1, 0.0))
		elif not host._mode.human_fielders.is_empty():
			var fspot: Vector3 = host._defense.fielder_by_num(int(host._mode.human_fielders[0])).home
			if int(host._mode.human_fielders[0]) == 1:
				fspot = Vector3(1.4, 0.0, fspot.z + 0.2)
			cam.position = Vector3(fspot.x, 1.7, fspot.z)
			host.add_child(cam)
			cam.look_at(Vector3(0.0, 1.0, 0.0))
		elif not host._mode.human_pitcher:
			cam.position = Vector3(3.5, 1.7, -5.0)
			host.add_child(cam)
			cam.look_at(Vector3(0.0, 1.5, 18.0))
		else:
			cam.position = Vector3(0.0, mh + 1.7, mz + 0.5)
			host.add_child(cam)
			cam.look_at(Vector3(0.0, 1.0, 0.0))
		cam.current = true
		host._camera = cam
