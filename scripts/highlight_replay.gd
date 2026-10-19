class_name HighlightReplay
extends RefCounted
## A ghost replay of a big hit: after a home run (or a very long ball) the ball's flight is drawn again in the
## air in half speed, in gold, with its distance on it. It is in the world, not a camera cut, so there is no
## motion for your head to disagree with. One ball, one trail, one label.

const MIN_DISTANCE := 95.0         # m: a ball this far is a highlight even if it is not a homer
const SPEED := 0.5                 # replay speed
const HOLD := 2.5                  # s the finished flight stays up

var host                                    # the bullpen scene (untyped: its members are reached by name)
var _ball: MeshInstance3D
var _trail: MeshInstance3D
var _mesh := ImmediateMesh.new()
var _label: Label3D
var _points := PackedVector3Array()
var _dt := 1.0 / 120.0
var _t := 0.0
var _hold := 0.0
var active := false


static func worth_replaying(summary: Dictionary) -> bool:
	return bool(summary.get("home_run", false)) or float(summary.get("distance", 0.0)) >= MIN_DISTANCE


func on_play_announced(h: LiveHit, _text: String, _ev: Dictionary) -> void:
	if worth_replaying(h.summary):
		start(h.points, h.summary)


func start(points: PackedVector3Array, summary: Dictionary) -> void:
	if points.size() < 3:
		return
	_ensure_nodes()
	_points = points
	_t = 0.0
	_hold = 0.0
	active = true
	_ball.visible = true
	_trail.visible = true
	_label.text = "REPLAY  %.0f m" % float(summary.get("distance", 0.0))
	_label.visible = true
	_label.position = (summary.get("fence_cross", summary.get("landing_pos", points[points.size() - 1])) as Vector3) + Vector3(0.0, 6.0, 0.0)


func update(delta: float) -> void:
	if not active:
		return
	var last := (_points.size() - 1) * _dt
	if _t < last:
		_t = minf(_t + delta * SPEED, last)
		var idx := clampi(int(_t / _dt), 0, _points.size() - 2)
		var f := (_t - idx * _dt) / _dt
		_ball.global_position = _points[idx].lerp(_points[idx + 1], f)
		_mesh.clear_surfaces()
		if idx >= 2:
			_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			var k := 0
			while k <= idx:
				_mesh.surface_add_vertex(_points[k])
				k += 2
			_mesh.surface_add_vertex(_ball.global_position)
			_mesh.surface_end()
	else:
		_hold += delta
		if _hold >= HOLD:
			stop()


func stop() -> void:
	active = false
	if _ball != null:
		_ball.visible = false
		_trail.visible = false
		_label.visible = false


func _ensure_nodes() -> void:
	if _ball != null:
		return
	_ball = host.world.make_ball()
	_trail = MeshInstance3D.new()
	_trail.mesh = _mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.82, 0.2)
	_trail.material_override = m
	host.add_child(_trail)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.pixel_size = 0.0018
	_label.font_size = 72
	_label.outline_size = 16
	_label.modulate = Color(1.0, 0.85, 0.25)
	_label.no_depth_test = true
	host.add_child(_label)
