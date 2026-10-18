class_name BallVisual
extends RefCounted
## What the ball looks like: a white sphere with real baseball stitching (the two-lobed seam
## with its tick stitches), drawn into one small texture so it costs one draw call and the
## seams are visible rolling and spinning.
##
## The seam is the standard "tennis ball curve" on a sphere:
##   x = a cos t + b cos 3t,  y = a sin t - b sin 3t,  z = c sin 2t,   c = 2 sqrt(ab)
## which stays on a sphere of radius a + b.

const VISUAL_RADIUS := 0.052        # a bit bigger than the real 0.0366 so it reads at pitching distance
const TEX_W := 1024
const TEX_H := 512
const SEAM_A := 0.64
const SEAM_B := 0.36

static var _texture: ImageTexture
static var _material: StandardMaterial3D


static var _turn := Basis.IDENTITY
static var _turn_ready := false


static func _raw_point(t: float) -> Vector3:
	var c := 2.0 * sqrt(SEAM_A * SEAM_B)
	var p := Vector3(SEAM_A * cos(t) + SEAM_B * cos(3.0 * t), SEAM_A * sin(t) - SEAM_B * sin(3.0 * t), c * sin(2.0 * t))
	return p.normalized()


## Turn the seam so the texture's poles sit as far from it as possible (stitches stretch to
## nothing at the poles of a latitude/longitude texture, so keep them out of there).
static func _seam_turn() -> Basis:
	if _turn_ready:
		return _turn
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var best_dir := Vector3.UP
	var best_gap := -1.0
	for k in 600:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var closest := 2.0
		for i in 96:
			closest = minf(closest, d.distance_to(_raw_point(TAU * i / 96.0)))
		for i in 96:
			closest = minf(closest, (-d).distance_to(_raw_point(TAU * i / 96.0)))
		if closest > best_gap:
			best_gap = closest
			best_dir = d
	_turn = Basis(Quaternion(best_dir, Vector3.UP))
	_turn_ready = true
	return _turn


static func _seam_point(t: float) -> Vector3:
	return _seam_turn() * _raw_point(t)


## Unit-sphere point -> texture pixel (longitude around Y, latitude from the +Y pole).
static func _pixel(p: Vector3) -> Vector2i:
	var lon := atan2(p.z, p.x)                       # -pi..pi
	var u := fposmod(lon / TAU, 1.0)
	var v := acos(clampf(p.y, -1.0, 1.0)) / PI
	return Vector2i(int(u * TEX_W) % TEX_W, clampi(int(v * TEX_H), 0, TEX_H - 1))


static func _stamp(img: Image, p: Vector3, radius_px: int, color: Color) -> void:
	var c := _pixel(p)
	# Stretch horizontally toward the poles so a stamp stays round on the sphere.
	var lat_scale := 1.0 / maxf(sqrt(maxf(1.0 - p.y * p.y, 0.0)), 0.15)
	var rx := int(ceil(radius_px * minf(lat_scale, 6.0)))
	for dy in range(-radius_px, radius_px + 1):
		for dx in range(-rx, rx + 1):
			if (float(dx) / maxf(lat_scale, 1.0)) * (float(dx) / maxf(lat_scale, 1.0)) + dy * dy > radius_px * radius_px:
				continue
			var x := posmod(c.x + dx, TEX_W)
			var y := clampi(c.y + dy, 0, TEX_H - 1)
			img.set_pixel(x, y, color)


static func texture() -> ImageTexture:
	if _texture != null:
		return _texture
	var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGB8)
	img.fill(Color(0.97, 0.96, 0.93))
	var red := Color(0.78, 0.09, 0.10)
	var steps := 1600
	# The seam line.
	for i in steps:
		var t := TAU * i / steps
		_stamp(img, _seam_point(t), 2, red)
	# Stitches: short ticks crossing the seam, leaning alternately like the real V stitches.
	var ticks := 108
	for i in ticks:
		var t := TAU * i / ticks
		var p := _seam_point(t)
		var tangent := (_seam_point(t + 0.002) - _seam_point(t - 0.002)).normalized()
		var side := p.cross(tangent).normalized()
		var lean := 0.018 if i % 2 == 0 else -0.018
		for k in range(-6, 7):
			var f := k / 6.0
			var q := (p + side * (0.085 * f) + tangent * (lean * f)).normalized()
			_stamp(img, q, 1, red)
	img.generate_mipmaps()
	_texture = ImageTexture.create_from_image(img)
	return _texture


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_texture = texture()
		_material.roughness = 0.85
		_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return _material


## A UV sphere that matches _pixel(): u = longitude around Y, v = latitude from the +Y pole.
static func mesh(radius: float = VISUAL_RADIUS, lon_n: int = 32, lat_n: int = 16) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in range(lat_n + 1):
		var v := float(j) / lat_n
		var theta := v * PI
		for i in range(lon_n + 1):
			var u := float(i) / lon_n
			var lon := u * TAU
			var p := Vector3(sin(theta) * cos(lon), cos(theta), sin(theta) * sin(lon))
			verts.append(p * radius)
			norms.append(p)
			uvs.append(Vector2(u, v))
	for j in lat_n:
		for i in lon_n:
			var a := j * (lon_n + 1) + i
			var b := a + lon_n + 1
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## The texture as a PNG, for looking at the stitching without a window.
static func save_preview(path: String) -> void:
	texture().get_image().save_png(path)
