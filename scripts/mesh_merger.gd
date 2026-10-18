class_name MeshMerger
extends RefCounted
## Bakes many small primitives into ONE mesh with per-vertex colors, so a whole character,
## ball, or run of static props costs a single draw call instead of one per primitive.
## On a Quest the draw-call count is the budget that runs out first; triangles are cheap.
##
## Usage:
##   var m := MeshMerger.new()
##   m.add(capsule_mesh, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), Color.RED)
##   m.add(sphere_mesh, ...)
##   var inst := MeshInstance3D.new()
##   inst.mesh = m.build()
##   inst.material_override = MeshMerger.vertex_color_material()
##
## Parts keep their own colors, so one shared opaque material serves everything.

static var _shared_material: StandardMaterial3D

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


static func vertex_color_material() -> StandardMaterial3D:
	if _shared_material == null:
		_shared_material = StandardMaterial3D.new()
		_shared_material.vertex_color_use_as_albedo = true
		# Colors are authored like ordinary albedo colors (sRGB); without this they render washed out.
		_shared_material.vertex_color_is_srgb = true
	return _shared_material


func add(mesh: Mesh, xform: Transform3D, color: Color) -> void:
	var arrays: Array
	if mesh is PrimitiveMesh:
		arrays = (mesh as PrimitiveMesh).get_mesh_arrays()
	else:
		arrays = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	# A mesh that carries its own vertex colors (e.g. a lathe-turned bat) keeps them, tinted by color.
	var own_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var base := _verts.size()
	var normal_basis := xform.basis.inverse().transposed()
	for i in v.size():
		_verts.append(xform * v[i])
		_normals.append((normal_basis * n[i]).normalized() if i < n.size() else Vector3.UP)
		_colors.append(color * own_colors[i] if i < own_colors.size() else color)
	if idx.is_empty():
		for i in v.size():
			_indices.append(base + i)
	else:
		for i in idx:
			_indices.append(base + i)


## Convenience: place a part by position, Euler rotation (degrees) and scale.
func add_at(mesh: Mesh, color: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	add(mesh, Transform3D(b.scaled(scl), pos), color)


func is_empty() -> bool:
	return _verts.is_empty()


func triangle_count() -> int:
	return _indices.size() / 3


func build() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Build straight into a MeshInstance3D using the shared vertex-color material.
func build_instance(parent: Node, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = build()
	inst.material_override = vertex_color_material()
	inst.position = at
	parent.add_child(inst)
	return inst
