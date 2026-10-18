class_name ZoneMarkers
extends Node3D
## The last few pitches drawn as dots on the strike zone, color-coded by where they crossed
## (see PitchLocation). Newest is largest and brightest. A halo marks the result: gold for a
## corner you did not get hit on, cyan for a ball in play, white for a swing and miss.
## One multimesh: one draw call for all of it.

const SLOTS := 10
const DOT := 0.058
const Z_FRONT := 0.035

var _mm := MultiMesh.new()
var _entries: Array = []        # newest last: {x, y, color, halo}


func _ready() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.004
	disc.radial_segments = 20
	disc.rings = 1
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = disc
	_mm.instance_count = SLOTS * 2
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = _mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	inst.material_override = mat
	add_child(inst)
	_redraw()


## The pitches shown, oldest first, for drawing the same thing elsewhere.
func entries() -> Array:
	return _entries


func clear() -> void:
	_entries.clear()
	_redraw()


## halo: a color with alpha 0 for none.
func add(x: float, y: float, color: Color, halo: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	_entries.append({"x": x, "y": y, "color": color, "halo": halo})
	while _entries.size() > SLOTS:
		_entries.pop_front()
	_redraw()


func _redraw() -> void:
	if _mm.instance_count == 0:
		return
	var n := _entries.size()
	var hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	# A disc faces +Z (toward the pitcher) once its axis is turned from Y to Z.
	var face := Basis(Vector3.RIGHT, deg_to_rad(90.0))
	for i in SLOTS:
		var halo_i := i * 2
		var dot_i := i * 2 + 1
		if i >= n:
			_mm.set_instance_transform(halo_i, hidden)
			_mm.set_instance_transform(dot_i, hidden)
			continue
		var e: Dictionary = _entries[n - 1 - i]       # i = 0 is the newest
		var age := float(i) / SLOTS
		var size := DOT * lerpf(1.25, 0.8, age)
		var bright := lerpf(1.0, 0.45, age)
		var pos := Vector3(e.x, e.y, Z_FRONT)
		_mm.set_instance_transform(dot_i, Transform3D(face * Basis.from_scale(Vector3(size, 1.0, size)), pos))
		var c: Color = e.color
		_mm.set_instance_color(dot_i, Color(c.r * bright, c.g * bright, c.b * bright))
		var h: Color = e.halo
		if h.a > 0.0:
			_mm.set_instance_transform(halo_i, Transform3D(face * Basis.from_scale(Vector3(size * 1.6, 1.0, size * 1.6)),
				Vector3(e.x, e.y, Z_FRONT - 0.01)))
			_mm.set_instance_color(halo_i, Color(h.r * bright, h.g * bright, h.b * bright))
		else:
			_mm.set_instance_transform(halo_i, hidden)
