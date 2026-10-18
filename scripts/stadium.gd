class_name Stadium
extends Node3D
## The park around the field: grass, infield, bases, chalk, fence, stands, crowd, dugouts,
## light towers, scoreboard. Cartoony and cheap on purpose (Quest): ring structures and the
## crowd are MultiMesh instances, so each is one draw call.
##
## Coordinates match the rest of the game: home plate at the origin, the mound at +Z
## (18.44 m), center field out along +Z, third base on +X, first base on -X.

@export_range(0, 3000, 50) var crowd_count := 1100
@export var seed_value := 7

const BASE_DIST := 27.432          # 90 ft
const INFIELD_RADIUS := 28.9       # 95 ft from the mound
const TIER_COUNT := 4
const TIER_HEIGHT := 2.4
const TIER_STEP := 2.6
const TIER_DEPTH := 3.4

var _mats := {}
## Opaque static props are baked into one vertex-colored mesh (one draw call).
var _static := MeshMerger.new()
var _crowd_mm: MultiMeshInstance3D
var _crowd_placed := 0
var _net: MeshInstance3D
var _scoreboard: Scoreboard
var _heads_mm: MultiMeshInstance3D
var _heads_placed := 0
var _clouds: MultiMeshInstance3D


## Distance from home plate to the outfield fence / stand edge in direction psi
## (degrees from straight out to center field). ~122 m to dead center, 100 m down the
## lines, closing to ~22 m behind home plate.
static func fence_radius(psi_deg: float) -> float:
	var a := absf(psi_deg)
	if a <= 45.0:
		return 100.0 + 22.0 * cos(deg_to_rad(a) * 2.0)
	var t := (180.0 - a) / 135.0
	return 22.0 + 78.0 * pow(t, 3.0)


## How many stand tiers exist in direction psi: full stands behind the plate and down the
## lines, bleachers in the outfield.
static func tiers_for(psi_deg: float) -> int:
	var a := absf(psi_deg)
	if a > 100.0:
		return TIER_COUNT
	if a > 60.0:
		return 3
	return 2


func _ready() -> void:
	_build_ground()
	_build_infield()
	_build_chalk()
	_build_fence_and_track()
	_build_stands()
	_build_crowd()
	_build_dugouts_and_netting()
	_build_lights_and_scoreboard()
	_build_details()
	_static.build_instance(self)


# --------------------------------------------------------------------------- ground

func _build_ground() -> void:
	var grass := PlaneMesh.new()
	grass.size = Vector2(420.0, 420.0)
	_add(grass, Color(0.30, 0.62, 0.30), Vector3(0.0, 0.0, 40.0))

	# Mowing stripes across the outfield: one MultiMesh.
	var stripe := BoxMesh.new()
	stripe.size = Vector3(1.0, 0.01, 1.0)
	var count := 14
	var mm := _multimesh(stripe, count, false)
	for i in count:
		var width := 9.0
		var x := (i - count * 0.5 + 0.5) * width * 1.0
		var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(width * 0.5, 1.0, 70.0)), Vector3(x, 0.006, 88.0))
		mm.multimesh.set_instance_transform(i, xf)
	mm.material_override = _mat(Color(0.36, 0.70, 0.34))
	add_child(mm)


func _build_infield() -> void:
	var mz := PitchPhysics.MOUND_Z
	# Big dirt circle around the mound, a smaller one around the plate.
	var dirt := CylinderMesh.new()
	dirt.top_radius = INFIELD_RADIUS
	dirt.bottom_radius = INFIELD_RADIUS
	dirt.height = 0.01
	dirt.radial_segments = 48
	_add(dirt, Color(0.72, 0.52, 0.34), Vector3(0.0, 0.004, mz))
	var home_dirt := CylinderMesh.new()
	home_dirt.top_radius = 4.6
	home_dirt.bottom_radius = 4.6
	home_dirt.height = 0.01
	home_dirt.radial_segments = 32
	_add(home_dirt, Color(0.72, 0.52, 0.34), Vector3(0.0, 0.006, 0.0))

	# Infield grass: the diamond between the bases, with base paths cut through it.
	var diamond := BoxMesh.new()
	diamond.size = Vector3(BASE_DIST - 1.4, 0.01, BASE_DIST - 1.4)
	_add(diamond, Color(0.27, 0.58, 0.27), Vector3(0.0, 0.008, BASE_DIST * 0.7071), 45.0)

	# Base paths and bases.
	var corner := BASE_DIST * 0.7071
	var path := BoxMesh.new()
	path.size = Vector3(BASE_DIST, 0.01, 1.5)
	var segs := [
		[Vector3(-corner * 0.5, 0.010, corner * 0.5), 45.0],
		[Vector3(corner * 0.5, 0.010, corner * 0.5), -45.0],
		[Vector3(-corner * 0.5, 0.010, corner * 1.5), -45.0],
		[Vector3(corner * 0.5, 0.010, corner * 1.5), 45.0],
	]
	for s in segs:
		_add(path, Color(0.72, 0.52, 0.34), s[0], s[1])
	var base := BoxMesh.new()
	base.size = Vector3(0.38, 0.08, 0.38)
	for b in [Vector3(-corner, 0.05, corner), Vector3(0.0, 0.05, corner * 2.0), Vector3(corner, 0.05, corner)]:
		_add(base, Color.WHITE, b, 45.0)
	# Pitcher's-circle dirt under the existing mound is drawn by the bullpen scene.


func _build_chalk() -> void:
	var chalk := Color(0.97, 0.97, 0.97)
	# Foul lines to the poles (100 m down each line).
	var line := BoxMesh.new()
	line.size = Vector3(0.11, 0.012, 100.0)
	for s in [-1.0, 1.0]:
		_add(line, chalk, Vector3(s * 35.35, 0.014, 35.35), s * 45.0)
		# Foul pole.
		var pole := CylinderMesh.new()
		pole.top_radius = 0.12
		pole.bottom_radius = 0.12
		pole.height = 14.0
		pole.radial_segments = 8
		_add(pole, Color(1.0, 0.85, 0.1), Vector3(s * 70.7, 7.0, 70.7))
	# Batter's boxes: 4 ft x 6 ft, 6 inches off the plate, one each side.
	var thick := 0.07
	for s in [-1.0, 1.0]:
		var cx: float = s * (0.2159 + 0.1524 + 0.61)
		var long := BoxMesh.new()
		long.size = Vector3(thick, 0.012, 1.83)
		var short := BoxMesh.new()
		short.size = Vector3(1.22, 0.012, thick)
		_add(long, chalk, Vector3(cx - 0.61, 0.014, 0.0))
		_add(long, chalk, Vector3(cx + 0.61, 0.014, 0.0))
		_add(short, chalk, Vector3(cx, 0.014, 0.915))
		_add(short, chalk, Vector3(cx, 0.014, -0.915))
	# On-deck circles are skipped; the catcher's box is a small outline.
	var cbox := BoxMesh.new()
	cbox.size = Vector3(1.2, 0.012, thick)
	_add(cbox, chalk, Vector3(0.0, 0.014, -0.55))


# --------------------------------------------------------------------------- rings

## One MultiMesh of box segments laid end to end around the park following fence_radius().
## offset pushes them outward from the fence line (meters, negative = inside).
## tier_filter(psi) -> bool skips segments (e.g. fewer tiers in the outfield).
func _ring(size: Vector3, color: Color, offset: float, base_y: float, segments: int = 96, min_tier: int = -1, palette: Array = []) -> MultiMeshInstance3D:
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var xforms: Array[Transform3D] = []
	for i in segments:
		var psi_a := -180.0 + 360.0 * i / segments
		var psi_b := -180.0 + 360.0 * (i + 1) / segments
		var pa := _fence_point(psi_a)
		var pb := _fence_point(psi_b)
		if min_tier >= 0 and tiers_for((psi_a + psi_b) * 0.5) <= min_tier:
			continue
		var tangent := pb - pa
		var length := tangent.length() * 1.04
		var t_n := tangent.normalized()
		var out := Vector3(-t_n.z, 0.0, t_n.x)
		var center := (pa + pb) * 0.5 + out * (offset + size.z * 0.5)
		center.y = base_y + size.y * 0.5
		var basis := Basis(t_n * length, Vector3.UP * size.y, out * size.z)
		xforms.append(Transform3D(basis, center))
	var mm := _multimesh(unit, xforms.size(), not palette.is_empty())
	for i in xforms.size():
		mm.multimesh.set_instance_transform(i, xforms[i])
		if not palette.is_empty():
			mm.multimesh.set_instance_color(i, palette[i % palette.size()])
	mm.material_override = _instance_color_material() if not palette.is_empty() else _mat(color)
	add_child(mm)
	return mm


func _fence_point(psi_deg: float) -> Vector3:
	var r := fence_radius(psi_deg)
	return Vector3(r * sin(deg_to_rad(psi_deg)), 0.0, r * cos(deg_to_rad(psi_deg)))


func _build_fence_and_track() -> void:
	# Warning track just inside the fence, the fence itself, and a bright cap.
	_ring(Vector3(1.0, 0.012, 5.0), Color(0.72, 0.52, 0.34), -5.0, 0.0)
	_ring(Vector3(1.0, 3.0, 0.5), Color(0.10, 0.28, 0.20), 0.0, 0.0)
	_ring(Vector3(1.0, 0.18, 0.7), Color(1.0, 0.85, 0.1), -0.1, 3.0)


func _build_stands() -> void:
	var tier_colors := [Color(0.22, 0.32, 0.65), Color(0.70, 0.20, 0.24), Color(0.22, 0.32, 0.65), Color(0.90, 0.78, 0.28)]
	for k in TIER_COUNT:
		var base_y := 1.0 + k * TIER_STEP
		_ring(Vector3(1.0, TIER_HEIGHT, TIER_DEPTH), tier_colors[k], 1.5 + k * TIER_DEPTH * 0.92, base_y, 96, k)
	# A back wall behind the top tier so the sky does not show through behind the crowd.
	_ring(Vector3(1.0, 14.0, 0.6), Color(0.30, 0.30, 0.36), 1.5 + TIER_COUNT * TIER_DEPTH * 0.92 + 0.2, 0.0, 96, 2)


func _build_crowd() -> void:
	if crowd_count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var fan := CapsuleMesh.new()
	fan.radius = 0.22
	fan.height = 0.95
	fan.radial_segments = 6
	fan.rings = 1
	var mm := _multimesh(fan, crowd_count, true)
	var palette := [
		Color(0.95, 0.30, 0.30), Color(0.25, 0.45, 0.95), Color(0.98, 0.85, 0.30),
		Color(0.95, 0.95, 0.95), Color(0.30, 0.80, 0.45), Color(0.95, 0.55, 0.20), Color(0.70, 0.35, 0.85),
	]
	var placed := 0
	var guard := 0
	while placed < crowd_count and guard < crowd_count * 20:
		guard += 1
		# Bias toward behind the plate and down the lines, where the stands are full.
		var psi := rng.randf_range(-180.0, 180.0)
		var weight := 1.0 if absf(psi) > 100.0 else (0.55 if absf(psi) > 60.0 else 0.2)
		if rng.randf() > weight:
			continue
		var tiers := tiers_for(psi)
		var k := rng.randi_range(0, tiers - 1)
		var r := fence_radius(psi) + 1.5 + k * TIER_DEPTH * 0.92 + rng.randf_range(0.4, TIER_DEPTH - 0.4)
		var p := Vector3(r * sin(deg_to_rad(psi)), 1.0 + k * TIER_STEP + TIER_HEIGHT + 0.5, r * cos(deg_to_rad(psi)))
		# Cheer: a little height jitter, and face the field.
		p.y += rng.randf_range(0.0, 0.25)
		var face := Vector3(-p.x, 0.0, -p.z).normalized()
		var basis := Basis.looking_at(face, Vector3.UP)
		mm.multimesh.set_instance_transform(placed, Transform3D(basis, p))
		mm.multimesh.set_instance_color(placed, palette[rng.randi() % palette.size()])
		placed += 1
	mm.multimesh.visible_instance_count = placed
	_crowd_mm = mm
	_crowd_placed = placed
	mm.material_override = _instance_color_material()
	add_child(mm)

	# Heads on the bodies: a second multimesh so fans read as people, not capsules.
	var head := SphereMesh.new()
	head.radius = 0.15
	head.height = 0.30
	head.radial_segments = 6
	head.rings = 3
	var hm := _multimesh(head, placed, true)
	var skin := [Color(0.96, 0.78, 0.62), Color(0.85, 0.62, 0.46), Color(0.62, 0.43, 0.30), Color(0.45, 0.30, 0.20), Color(0.98, 0.84, 0.72)]
	for i in placed:
		var xf: Transform3D = mm.multimesh.get_instance_transform(i)
		xf.origin += Vector3(0.0, 0.62, 0.0)
		hm.multimesh.set_instance_transform(i, xf)
		hm.multimesh.set_instance_color(i, skin[(i * 7 + 3) % skin.size()])
	hm.material_override = _instance_color_material()
	add_child(hm)
	_heads_mm = hm
	_heads_placed = placed


# --------------------------------------------------------------------------- props

func _build_dugouts_and_netting() -> void:
	for s in [-1.0, 1.0]:
		var pit := BoxMesh.new()
		pit.size = Vector3(10.0, 2.4, 3.2)
		_add(pit, Color(0.18, 0.18, 0.22), Vector3(s * 13.5, 1.2, 4.0))
		var roof := BoxMesh.new()
		roof.size = Vector3(10.6, 0.25, 4.0)
		_add(roof, Color(0.75, 0.2, 0.2) if s < 0.0 else Color(0.2, 0.3, 0.75), Vector3(s * 13.5, 2.55, 3.7))
		var bench := BoxMesh.new()
		bench.size = Vector3(8.0, 0.4, 0.7)
		_add(bench, Color(0.65, 0.5, 0.3), Vector3(s * 13.5, 0.6, 5.4))
	# Backstop netting above the physical wall in the bullpen scene (wall top is 3 m).
	var net := QuadMesh.new()
	net.size = Vector2(30.0, 11.0)
	var inst := _add(net, Color(1.0, 1.0, 1.0, 0.16), Vector3(0.0, 8.5, -8.4), 0.0, true)
	_net = inst
	var m := inst.material_override as StandardMaterial3D
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for x in [-15.0, 15.0]:
		var post := CylinderMesh.new()
		post.top_radius = 0.15
		post.bottom_radius = 0.15
		post.height = 14.0
		post.radial_segments = 6
		_add(post, Color(0.25, 0.25, 0.3), Vector3(x, 7.0, -8.4))


func _build_lights_and_scoreboard() -> void:
	# All floodlight panels are baked into one emissive mesh (one draw call): a 3 x 2 bank per tower.
	var panels := MeshMerger.new()
	for p in [Vector3(-78.0, 0.0, 78.0), Vector3(78.0, 0.0, 78.0), Vector3(-62.0, 0.0, -30.0), Vector3(62.0, 0.0, -30.0)]:
		var pole := CylinderMesh.new()
		pole.top_radius = 0.5
		pole.bottom_radius = 0.7
		pole.height = 42.0
		pole.radial_segments = 6
		_add(pole, Color(0.45, 0.45, 0.5), p + Vector3(0.0, 21.0, 0.0))
		var frame_box := BoxMesh.new()
		frame_box.size = Vector3(16.0, 8.4, 0.7)
		var look := Vector3(-p.x, 0.0, 30.0 - p.z).normalized()
		var yaw := atan2(look.x, look.z)
		_add(frame_box, Color(0.30, 0.30, 0.34), p + Vector3(0.0, 43.0, 0.0), rad_to_deg(yaw))
		var lens := BoxMesh.new()
		lens.size = Vector3(4.6, 3.4, 0.5)
		for ix in 3:
			for iy in 2:
				var local := Vector3((ix - 1) * 5.0, 43.0 + (iy - 0.5) * 3.9, 0.55)
				var basis := Basis(Vector3.UP, yaw)
				panels.add(lens, Transform3D(basis, p + basis * Vector3((ix - 1) * 5.0, 0.0, 0.55) + Vector3(0.0, local.y, 0.0)), Color.WHITE)
	var lamp := MeshInstance3D.new()
	lamp.mesh = panels.build()
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(1.0, 0.98, 0.85)
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.95, 0.75)
	lm.emission_energy_multiplier = 1.6
	lamp.material_override = lm
	add_child(lamp)

	# Scoreboard in dead center, above the fence, facing home plate.
	var z := fence_radius(0.0) + 3.0
	var board := BoxMesh.new()
	board.size = Vector3(26.0, 9.0, 1.2)
	_add(board, Color(0.08, 0.10, 0.12), Vector3(0.0, 10.5, z))
	var frame := BoxMesh.new()
	frame.size = Vector3(27.5, 10.5, 0.9)
	_add(frame, Color(0.55, 0.55, 0.6), Vector3(0.0, 10.5, z + 0.3))
	# The face: a real ballpark board (line score, B/S/O lights, batter, pitch speed).
	_scoreboard = Scoreboard.new()
	_scoreboard.position = Vector3(0.0, 10.5, z - 0.62)
	_scoreboard.rotation_degrees.y = 180.0        # +Z is the face: turn it to look at home plate
	add_child(_scoreboard)


# --------------------------------------------------------------------------- details

func _build_details() -> void:
	# Outfield wall ad boards: alternating colored panels on the face of the fence.
	var ads := [Color(0.85, 0.15, 0.15), Color(0.95, 0.80, 0.15), Color(0.15, 0.40, 0.85), Color(0.95, 0.95, 0.95),
		Color(0.15, 0.65, 0.35), Color(0.90, 0.45, 0.10)]
	_ring(Vector3(1.0, 1.7, 0.15), Color.WHITE, -0.12, 0.5, 48, -1, ads)

	# Railings: a light strip on the front of each tier, one multimesh for all of them.
	for k in TIER_COUNT:
		_ring(Vector3(1.0, 0.35, 0.12), Color(0.85, 0.86, 0.9), 1.5 + k * TIER_DEPTH * 0.92 - 0.12, 1.0 + k * TIER_STEP + TIER_HEIGHT, 96, k)

	# A roof over the top tiers behind home plate and down the lines, to shade the good seats.
	_ring(Vector3(1.0, 0.5, TIER_DEPTH * 2.4), Color(0.88, 0.88, 0.92), 1.5 + (TIER_COUNT - 2) * TIER_DEPTH * 0.92, 1.0 + TIER_COUNT * TIER_STEP + TIER_HEIGHT + 2.2, 96, 3)

	# On-deck circles and the coaches' boxes (chalk and dirt), baked with the static scenery.
	for s in [-1.0, 1.0]:
		var circle := CylinderMesh.new()
		circle.top_radius = 1.2
		circle.bottom_radius = 1.2
		circle.height = 0.012
		circle.radial_segments = 20
		_add(circle, Color(0.80, 0.62, 0.42), Vector3(s * 9.0, 0.016, -4.5))
		var box := BoxMesh.new()
		box.size = Vector3(3.0, 0.012, 3.0)
		_add(box, Color(0.97, 0.97, 0.97), Vector3(s * 20.0, 0.015, 7.0))
		var inner := BoxMesh.new()
		inner.size = Vector3(2.7, 0.014, 2.7)
		_add(inner, Color(0.72, 0.52, 0.34), Vector3(s * 20.0, 0.016, 7.0))

	# A few soft clouds: flattened spheres, one multimesh.
	var cloud := SphereMesh.new()
	cloud.radius = 1.0
	cloud.height = 2.0
	cloud.radial_segments = 8
	cloud.rings = 4
	_clouds = _multimesh(cloud, 14, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 99
	for i in 14:
		var pos := Vector3(rng.randf_range(-260.0, 260.0), rng.randf_range(90.0, 150.0), rng.randf_range(-60.0, 300.0))
		var sc := Vector3(rng.randf_range(18.0, 40.0), rng.randf_range(4.0, 7.0), rng.randf_range(10.0, 22.0))
		_clouds.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(sc), pos))
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(1.0, 1.0, 1.0)
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_clouds.material_override = cm
	add_child(_clouds)


# --------------------------------------------------------------------------- helpers

var _inst_mat: StandardMaterial3D


## Material for multimeshes that carry a color per instance (fans, ad boards).
func _instance_color_material() -> StandardMaterial3D:
	if _inst_mat == null:
		_inst_mat = StandardMaterial3D.new()
		_inst_mat.vertex_color_use_as_albedo = true
		_inst_mat.vertex_color_is_srgb = true
	return _inst_mat


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html(true)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		_mats[key] = m
	return _mats[key]


## Add a static prop. Opaque props are merged into one mesh and this returns null; props that
## need their own material (transparent, emissive) get a MeshInstance3D and it is returned.
func _add(mesh: Mesh, color: Color, at: Vector3, rot_y_deg: float = 0.0, unique: bool = false) -> MeshInstance3D:
	if not unique and color.a >= 0.99:
		_static.add(mesh, Transform3D(Basis(Vector3.UP, deg_to_rad(rot_y_deg)), at), color)
		return null
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	inst.material_override = m
	inst.position = at
	inst.rotation_degrees.y = rot_y_deg
	add_child(inst)
	return inst


func _multimesh(mesh: Mesh, count: int, with_colors: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = with_colors
	mm.mesh = mesh
	mm.instance_count = count
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	return inst


## Quality steps used by PerfGovernor: fewer fans, then no netting (the only large transparent
## surface). Nothing here affects play.
func set_quality(level: int) -> void:
	if _crowd_mm:
		_crowd_mm.multimesh.visible_instance_count = int(_crowd_placed * PerfGovernor.crowd_fraction(level))
	if _heads_mm:
		_heads_mm.multimesh.visible_instance_count = int(_heads_placed * PerfGovernor.crowd_fraction(level))
	if _clouds:
		_clouds.visible = level < 3
	if _net:
		_net.visible = level < 1


## What the center-field board shows (see Scoreboard for the keys).
func set_scoreboard(state: Dictionary) -> void:
	if _scoreboard:
		_scoreboard.apply(state)
