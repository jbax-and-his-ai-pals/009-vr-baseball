class_name Figure
extends RefCounted
## Helpers for building cartoon people and gear out of primitives, baked into one mesh.
## Limbs are described by their joint positions (a capsule between two points), which makes
## posing a fielder or a runner a matter of listing joints, not rotating nodes.


## A capsule from point a to point b (inclusive of rounded ends) added to the merger.
static func limb(m: MeshMerger, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 1e-4:
		return
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = maxf(length + radius * 2.0, radius * 2.0 + 0.001)
	cap.radial_segments = 8
	cap.rings = 2
	var basis := Basis(Quaternion(Vector3.UP, d / length))
	m.add(cap, Transform3D(basis, (a + b) * 0.5), color)


static func ball(m: MeshMerger, at: Vector3, radius: float, color: Color, squash: Vector3 = Vector3.ONE) -> void:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 10
	s.rings = 5
	m.add(s, Transform3D(Basis.IDENTITY.scaled(squash), at), color)


static func block(m: MeshMerger, at: Vector3, size: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var b := BoxMesh.new()
	b.size = size
	m.add_at(b, color, at, rot_deg)


## A solid of revolution about +Y from a profile of [y, radius, color] rows (bottom to top).
## Radius 0 rows close the ends. Used for the bat; cheap and smooth enough for a cartoon.
static func lathe(profile: Array, segments: int = 12) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var rows := profile.size()
	for r in rows:
		var y: float = profile[r][0]
		var rad: float = profile[r][1]
		var col: Color = profile[r][2]
		# Slope of the profile tilts the normal so shading follows the taper.
		var dr := 0.0
		if r + 1 < rows:
			dr = (float(profile[r + 1][1]) - rad) / maxf(float(profile[r + 1][0]) - y, 1e-4)
		elif r > 0:
			dr = (rad - float(profile[r - 1][1])) / maxf(y - float(profile[r - 1][0]), 1e-4)
		for s in segments:
			var ang := TAU * s / segments
			var c := cos(ang)
			var sn := sin(ang)
			verts.append(Vector3(c * rad, y, sn * rad))
			norms.append(Vector3(c, -dr, sn).normalized())
			cols.append(col)
	for r in rows - 1:
		for s in segments:
			var a := r * segments + s
			var b := r * segments + (s + 1) % segments
			var c2 := (r + 1) * segments + s
			var d := (r + 1) * segments + (s + 1) % segments
			idx.append_array([a, c2, b, b, c2, d])
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The bat: knob, taped handle, tapered barrel with a team stripe. Origin at the knob, axis +Y,
## 0.85 m long, sweet spot about 0.6 m up.
static func bat_mesh() -> ArrayMesh:
	var wood := Color(0.84, 0.64, 0.40)
	var dark := Color(0.55, 0.38, 0.22)
	var tape := Color(0.10, 0.10, 0.12)
	var red := Color(0.80, 0.12, 0.14)
	var profile := [
		[-0.012, 0.0, dark],
		[0.0, 0.030, dark], [0.022, 0.036, dark], [0.040, 0.020, dark],
		[0.060, 0.0125, tape], [0.28, 0.0130, tape],
		[0.30, 0.0150, wood], [0.40, 0.0225, wood], [0.46, 0.0285, red], [0.49, 0.0305, red],
		[0.52, 0.0330, wood], [0.70, 0.0365, wood], [0.80, 0.0370, wood], [0.84, 0.0345, dark],
		[0.85, 0.0, dark],
	]
	var m := MeshMerger.new()
	m.add(lathe(profile, 12), Transform3D.IDENTITY, Color.WHITE)
	# Two gloved fists baked on the handle so the hands always sit on the grip.
	ball(m, Vector3(0.0, 0.10, 0.0), 0.050, Color(0.95, 0.95, 0.95), Vector3(1.0, 1.1, 1.0))
	ball(m, Vector3(0.0, 0.22, 0.0), 0.050, Color(0.95, 0.95, 0.95), Vector3(1.0, 1.1, 1.0))
	return m.build()
