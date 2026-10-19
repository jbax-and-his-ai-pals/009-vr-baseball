class_name GameMenu
extends Node3D
## Draws a MenuModel as a panel floating in the world and lets you point at it: a laser from
## either controller and the trigger in VR; mouse, arrows and Enter on a desktop. It is only
## nodes while open, so it costs nothing during a game.
##
## Rows are plain quads and Label3Ds (about two draw calls per row), placed once in front of
## the player when opened.

signal chosen(event: Dictionary)
## A sound the menu wants played: "ui_hover", "ui_select", "ui_back", "ui_error".
signal ui_sound(id: String)
## The same moments for the controller that caused them (null for a mouse): "ui_hover", "ui_select", "ui_error".
signal ui_haptic(controller: XRController3D, event: String)

var _pointer: XRController3D          # the controller that is pointing (or just clicked)

const WIDTH := 1.5
const ROW_H := 0.15
const TITLE_H := 0.24
const DISTANCE := 1.8
const COL_BG := Color(0.04, 0.06, 0.11)
const COL_ROW := Color(0.14, 0.20, 0.33)
const COL_HOVER := Color(0.22, 0.46, 0.78)
const COL_OFF := Color(0.09, 0.11, 0.15)

var model: MenuModel
var camera: Camera3D
var controllers: Array[XRController3D] = []

var _open := false
var _hover := -1
var _rows: Array[Dictionary] = []
var _top := 0.0
var _built := Node3D.new()
var _footer: Label3D
var _lasers: Array[MeshInstance3D] = []
var _trigger_was: Dictionary = {}
var _mats := {}
var _needs_place := false
var _wait := 0.0


func _ready() -> void:
	add_child(_built)
	visible = false


func is_open() -> bool:
	return _open


func setup(m: MenuModel, cam: Camera3D, ctrls: Array[XRController3D]) -> void:
	model = m
	camera = cam
	controllers = ctrls
	for c in controllers:
		var beam := BoxMesh.new()
		beam.size = Vector3(0.004, 0.004, 4.0)
		var inst := MeshInstance3D.new()
		inst.mesh = beam
		inst.material_override = _mat(Color(0.4, 0.9, 1.0), true)
		inst.position = Vector3(0.0, 0.0, -2.0)
		inst.visible = false
		c.add_child(inst)
		_lasers.append(inst)


func open_main() -> void:
	model.open_main()
	_show()


func open_pause(game: GameConfig) -> void:
	model.open_pause(game)
	_show()


## Open a screen of the pause menu directly (a gesture asks for the leave-the-game question).
func goto(screen: String) -> void:
	model.stack.append(screen)
	_hover = -1
	_rebuild()


func close() -> void:
	_open = false
	visible = false
	for l in _lasers:
		l.visible = false


func _show() -> void:
	_open = true
	_hover = -1
	_wait = 0.0
	_rebuild()
	# In VR the head pose is not valid for the first frames after start: placing the panel
	# then puts it at the floor. Wait for a real head height, then place.
	_needs_place = true
	visible = false
	if _try_place():
		_needs_place = false
		visible = true


## True once the player's head is tracked at a believable height (always true off VR).
func _head_ready() -> bool:
	if not (camera is XRCamera3D):
		return true
	var base := camera.get_parent() as Node3D
	var base_y := base.global_position.y if base else 0.0
	return camera.global_position.y - base_y > 0.6


## In front of the player, at about eye level, turned to face them. Returns false while the
## head is not tracked yet (the caller tries again on a later frame).
func _try_place() -> bool:
	if camera == null:
		return true
	if not _head_ready() and _wait < 3.0:
		return false
	var cam_pos := camera.global_position
	# (If the runtime uses an eye-level reference space the head sits near the rig's origin;
	# after the wait we use wherever the head really is.)
	var fwd := -camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3(0.0, 0.0, 1.0)
	fwd = fwd.normalized()
	global_position = cam_pos + fwd * DISTANCE + Vector3(0.0, -0.05, 0.0)
	look_at(global_position + fwd, Vector3.UP)      # -Z away from the player, so the front faces them
	return true


func _mat(color: Color, unshaded: bool = true) -> StandardMaterial3D:
	var key := "%s%s" % [color, unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


func _quad(size: Vector2, color: Color, pos: Vector3) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var inst := MeshInstance3D.new()
	inst.mesh = q
	inst.material_override = _mat(color)
	inst.position = pos
	_built.add_child(inst)
	return inst


func _label(text: String, size: int, pos: Vector3, align: int, color: Color = Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0021
	l.outline_size = 8
	l.modulate = color
	l.horizontal_alignment = align
	l.position = pos
	_built.add_child(l)
	return l


func _rebuild() -> void:
	for c in _built.get_children():
		c.queue_free()
	_rows = model.items()
	var height := TITLE_H + ROW_H * _rows.size() + 0.30
	_top = height * 0.5
	_quad(Vector2(WIDTH + 0.1, height), COL_BG, Vector3(0.0, 0.0, -0.02))
	_label(model.title(), 72, Vector3(0.0, _top - TITLE_H * 0.5 - 0.02, 0.01), HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.92, 0.55))
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var y := _row_y(i)
		var col := COL_ROW
		if not r.enabled:
			col = COL_OFF
		elif i == _hover:
			col = COL_HOVER
		_quad(Vector2(WIDTH, ROW_H - 0.02), col, Vector3(0.0, y, 0.0))
		var text_col := Color.WHITE if r.enabled else Color(0.5, 0.52, 0.58)
		_label(r.label, 52, Vector3(-WIDTH * 0.5 + 0.05, y, 0.012), HORIZONTAL_ALIGNMENT_LEFT, text_col)
		if r.value != "":
			_label(r.value, 46, Vector3(WIDTH * 0.5 - 0.05, y, 0.012), HORIZONTAL_ALIGNMENT_RIGHT, Color(0.7, 0.9, 1.0))
	var note: String = ""
	if _hover >= 0 and _hover < _rows.size():
		note = _rows[_hover].note
	_footer = _label(note, 38, Vector3(0.0, -_top + 0.10, 0.01), HORIZONTAL_ALIGNMENT_CENTER, Color(0.75, 0.78, 0.85))


func _row_y(i: int) -> float:
	return _top - TITLE_H - ROW_H * (i + 0.5)


## Which row a ray points at (-1 for none).
func pick(origin: Vector3, dir: Vector3) -> int:
	var inv := global_transform.affine_inverse()
	var o := inv * origin
	var d := inv.basis * dir
	if absf(d.z) < 1e-5:
		return -1
	var t := -o.z / d.z
	if t < 0.0:
		return -1
	var hit := o + d * t
	if absf(hit.x) > WIDTH * 0.5:
		return -1
	for i in _rows.size():
		if absf(hit.y - _row_y(i)) <= (ROW_H - 0.02) * 0.5:
			return i
	return -1


func _set_hover(i: int) -> void:
	if i != _hover:
		_hover = i
		if i >= 0:
			ui_sound.emit("ui_hover")
			ui_haptic.emit(_pointer, "ui_hover")
		_rebuild()


func _click(i: int) -> void:
	if i < 0 or i >= _rows.size():
		return
	if not _rows[i].enabled:
		if not String(_rows[i].id).begins_with("info"):      # a line of text is not a button that failed
			ui_sound.emit("ui_error")
			ui_haptic.emit(_pointer, "ui_error")
		return
	var row_id: String = _rows[i].id
	ui_haptic.emit(_pointer, "ui_select")
	var ev := model.activate(i)
	if row_id in ["vignette", "snap_turn", "developer", "call_text", "seated", "colorblind", "gestures", "signs"]:
		var now_on: bool = bool(model.settings.get(row_id))
		ui_sound.emit("ui_toggle_on" if now_on else "ui_toggle_off")
	else:
		ui_sound.emit("ui_back" if row_id == "back" else "ui_select")
	_hover = -1
	if _open:
		_rebuild()
	if not ev.is_empty():
		chosen.emit(ev)


func _process(delta: float) -> void:
	if not _open:
		return
	if _needs_place:
		_wait += delta
		if _try_place():
			_needs_place = false
			visible = true
		else:
			return
	var vr := false
	var best := -1
	for k in controllers.size():
		var c := controllers[k]
		if not c.get_is_active():
			_lasers[k].visible = false
			continue
		vr = true
		_lasers[k].visible = true
		var idx := pick(c.global_position, -c.global_transform.basis.z)
		var down := c.is_button_pressed("trigger_click")
		if idx >= 0:
			best = idx
			_pointer = c
		if down and not _trigger_was.get(k, false) and idx >= 0:
			_click(idx)
		_trigger_was[k] = down
	if vr:
		_set_hover(best)


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseMotion and camera != null:
		var m := event as InputEventMouseMotion
		_set_hover(pick(camera.project_ray_origin(m.position), camera.project_ray_normal(m.position)))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and camera != null:
		var mb := event as InputEventMouseButton
		_click(pick(camera.project_ray_origin(mb.position), camera.project_ray_normal(mb.position)))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		var handled := true
		match k.keycode:
			KEY_ESCAPE:
				if model.screen() == "pause":
					chosen.emit({"type": "resume"})
				elif model.can_go_back():
					model.back()
					_hover = -1
					_rebuild()
			KEY_DOWN:
				_set_hover(mini(_hover + 1, _rows.size() - 1))
			KEY_UP:
				_set_hover(maxi(_hover - 1, 0))
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_click(_hover)
			KEY_BACKSPACE:
				if model.can_go_back():
					model.back()
					_hover = -1
					_rebuild()
			_:
				handled = false
		if handled:
			get_viewport().set_input_as_handled()
