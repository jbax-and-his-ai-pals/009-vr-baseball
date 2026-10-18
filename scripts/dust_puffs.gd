class_name DustPuffs
extends Node3D
## Little clouds of infield dirt: a slide, a ball that bounces in the dirt, a catcher dropping to
## block. A fixed pool of soft spheres drawn as one MultiMesh (one draw call), recycled oldest
## first, that rise, swell and fade. Nothing is allocated while the game runs.
##
##   puffs.puff(world_point, size, count)

const CAPACITY := 48
const LIFE := 0.75
const DIRT := Color(0.80, 0.64, 0.44)

var _mm := MultiMesh.new()
var _inst := MultiMeshInstance3D.new()
var _age := PackedFloat32Array()
var _size := PackedFloat32Array()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _next := 0
var _rng := RandomNumberGenerator.new()
var active := 0                       # puffs currently alive (tests read this)


func _init() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 7
	sphere.rings = 3
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = sphere
	_mm.instance_count = CAPACITY
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_inst.multimesh = _mm
	_inst.material_override = mat
	_inst.custom_aabb = AABB(Vector3(-60, -1, -10), Vector3(120, 8, 140))
	_inst.visible = false
	add_child(_inst)
	_age.resize(CAPACITY)
	_size.resize(CAPACITY)
	_pos.resize(CAPACITY)
	_vel.resize(CAPACITY)
	_age.fill(LIFE)                    # all spent
	_rng.randomize()


## A burst of `count` puffs about `at`, each about `size` metres across.
func puff(at: Vector3, size: float = 0.5, count: int = 3) -> void:
	for i in count:
		var k := _next
		_next = (_next + 1) % CAPACITY
		_age[k] = 0.0
		_size[k] = size * _rng.randf_range(0.7, 1.3)
		_pos[k] = Vector3(at.x + _rng.randf_range(-0.2, 0.2), maxf(at.y, 0.0) + 0.05, at.z + _rng.randf_range(-0.2, 0.2))
		_vel[k] = Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(0.25, 0.7), _rng.randf_range(-0.5, 0.5))
	_inst.visible = true


func _process(delta: float) -> void:
	if not _inst.visible:
		return
	var alive := 0
	for k in CAPACITY:
		if _age[k] >= LIFE:
			_mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
			continue
		_age[k] += delta
		alive += 1
		var u := clampf(_age[k] / LIFE, 0.0, 1.0)
		_pos[k] += _vel[k] * delta
		_vel[k] *= maxf(1.0 - 2.5 * delta, 0.0)
		var s: float = _size[k] * (0.45 + 1.1 * u)
		_mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(s, s * 0.7, s)), _pos[k]))
		_mm.set_instance_color(k, Color(DIRT.r, DIRT.g, DIRT.b, 0.55 * (1.0 - u) * (1.0 - u)))
	active = alive
	if alive == 0:
		_inst.visible = false
