class_name FieldProps
extends Node
## Small things on the field that come and go: dust puffs, bats that have been dropped, and a
## queue of "do this in a moment" calls that runs on game time. The scene calls update() each
## frame it is running (so all of it freezes with the game).
##
##   bat_bounced(at)   a dropped bat hit the ground for the first time (the sound of it)

signal bat_bounced(at: Vector3)

const BAT_LIFE := 8.0

var dust: DustPuffs
var _later: Array = []        # {"t": seconds left, "fn": Callable}
var _bats: Array = []         # bats that have been dropped: they fall, bounce and lie there


func _init() -> void:
	dust = DustPuffs.new()
	add_child(dust)
	set_process(false)         # the scene drives update(), so a menu stops everything


## Run `fn` after `seconds` of game time.
func later(seconds: float, fn: Callable) -> void:
	_later.append({"t": seconds, "fn": fn})


## A puff of dust now.
func puff(at: Vector3, size: float, count: int) -> void:
	dust.puff(at, size, count)


## A puff of dust where this node is, `seconds` from now (a slide kicks it up as he goes).
func puff_at(node: Node3D, seconds: float, size: float, count: int) -> void:
	later(seconds, func():
		if is_instance_valid(node):
			dust.puff(node.global_position, size, count))


## A bat falls from this transform: it tumbles, bounces and lies there until it times out.
func drop_bat(xf: Transform3D) -> void:
	var bat := MeshInstance3D.new()
	bat.mesh = Figure.bat_mesh()
	bat.material_override = MeshMerger.vertex_color_material()
	add_child(bat)
	bat.global_transform = xf
	_bats.append({"node": bat, "vel": Vector3(randf_range(-0.6, 0.6), 0.9, randf_range(-0.3, 1.0)),
		"spin": Vector3(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0), randf_range(-5.0, 5.0)), "t": 0.0, "bounces": 0})


func bat_count() -> int:
	return _bats.size()


func pending_count() -> int:
	return _later.size()


func update(delta: float) -> void:
	for i in range(_later.size() - 1, -1, -1):
		if i >= _later.size():
			continue
		var l: Dictionary = _later[i]
		l.t -= delta
		if l.t <= 0.0:
			_later.remove_at(i)
			(l.fn as Callable).call()
	for i in range(_bats.size() - 1, -1, -1):
		var b: Dictionary = _bats[i]
		b.t += delta
		var n: Node3D = b.node
		if b.t > BAT_LIFE or not is_instance_valid(n):
			if is_instance_valid(n):
				n.queue_free()
			_bats.remove_at(i)
			continue
		if int(b.bounces) >= 3:
			continue
		var v: Vector3 = b.vel
		v.y -= 9.8 * delta
		n.global_position += v * delta
		var sp: Vector3 = b.spin
		n.rotate_object_local(Vector3.RIGHT, sp.x * delta)
		n.rotate_object_local(Vector3.UP, sp.y * delta)
		n.rotate_object_local(Vector3.BACK, sp.z * delta)
		if n.global_position.y < 0.04 and v.y < 0.0:
			var gp := n.global_position
			gp.y = 0.04
			n.global_position = gp
			v = Vector3(v.x * 0.5, -v.y * 0.35, v.z * 0.5)
			b.spin = sp * 0.5
			b.bounces = int(b.bounces) + 1
			if int(b.bounces) == 1:
				bat_bounced.emit(gp)
			dust.puff(gp, 0.3, 1)
			if absf(v.y) < 0.5 or int(b.bounces) >= 3:
				b.bounces = 3
				var yaw := randf() * TAU
				n.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, Vector3(sin(yaw), 0.0, cos(yaw)))), gp)
		b.vel = v
