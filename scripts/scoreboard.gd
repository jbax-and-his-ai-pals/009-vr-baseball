class_name Scoreboard
extends Node3D
## The center-field board, laid out like a ballpark's: a line score by inning with R H E, the
## ball / strike / out lights, who is at bat, who is pitching, and the speed of the last pitch.
##
## Local frame: +Z is the face (the node is turned to look at home plate), +X the viewer's
## right, origin at the middle. 26 m x 9 m. Panels and lights are baked into one merged mesh;
## text is one label per column, so the whole board is about 25 draw calls.
##
## State (a Dictionary):
##   inning, innings, inning_runs (Array[int]), runs, hits, errors,
##   balls, strikes, outs, batter, batter_line, pitcher, last_kind, last_mph, final (bool)

const W := 26.0
const H := 9.0
const GREEN := Color(0.035, 0.17, 0.10)
const GRID := Color(0.85, 0.88, 0.80)
const AMBER := Color(1.0, 0.78, 0.15)
const WHITE := Color(0.96, 0.97, 0.93)
const DIM := Color(0.10, 0.14, 0.10)
const PIXEL := 0.0105

var state := {}
var _dirty := true
var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func apply(s: Dictionary) -> void:
	state = s
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty and is_inside_tree():
		_dirty = false
		_rebuild()


func _text(text: String, size: int, pos: Vector3, align: int, color: Color,
		valign: int = VERTICAL_ALIGNMENT_CENTER, spacing: int = 0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = PIXEL
	l.outline_size = 0
	l.modulate = color
	l.horizontal_alignment = align
	l.vertical_alignment = valign
	l.line_spacing = spacing
	l.shaded = false
	l.position = pos
	add_child(l)


## Lines of one column, one per row: the line pitch is set to the row height.
func _rows_text(lines: PackedStringArray, pos: Vector3, align: int, color: Color, row_h: float) -> void:
	var size := 84
	var font_h := ThemeDB.fallback_font.get_height(size)
	var spacing := int(round(row_h / PIXEL - font_h))
	# The text block's top is the board row's top; the glyphs sit in the middle of the line.
	_text("
".join(lines), size, pos, align, color, VERTICAL_ALIGNMENT_TOP, spacing)


func _quad(m: MeshMerger, w: float, h: float, x: float, y: float, color: Color, z: float = 0.0) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	m.add(q, Transform3D(Basis.IDENTITY, Vector3(x, y, z)), color)


func _light(m: MeshMerger, x: float, y: float, r: float, color: Color) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 0.08
	c.radial_segments = 14
	c.rings = 1
	# A cylinder's axis is Y; turn it so the flat face looks out of the board (+Z).
	m.add(c, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3(x, y, 0.06)), color)


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var s := state
	var m := MeshMerger.new()
	var inning: int = int(s.get("inning", 1))
	var innings: int = int(s.get("innings", 9))
	var runs_by: Array = s.get("inning_runs", [])
	var home_by: Array = s.get("home_inning_runs", [])
	var final: bool = bool(s.get("final", false))

	# --- Face and frame lines.
	_quad(m, W, H, 0.0, 0.0, GREEN, 0.0)
	_quad(m, W - 0.5, 0.12, 0.0, H * 0.5 - 0.25, GRID, 0.02)
	_quad(m, W - 0.5, 0.12, 0.0, -H * 0.5 + 0.25, GRID, 0.02)

	# --- Title strip.
	_text("VR BASEBALL", 120, Vector3(-W * 0.5 + 0.8, 3.55, 0.05), HORIZONTAL_ALIGNMENT_LEFT, AMBER)
	_text("FINAL" if final else "INNING %d" % mini(inning, innings), 100,
		Vector3(W * 0.5 - 0.8, 3.55, 0.05), HORIZONTAL_ALIGNMENT_RIGHT, WHITE)

	# --- The line score: team names, then one column per inning, then R H E.
	var x0 := -12.2
	var name_w := 3.6
	var col_w := 1.25
	var top := 2.5
	var row_h := 1.3
	var rows_y := [top - row_h * 0.5, top - row_h * 1.5, top - row_h * 2.5]     # header, away, home
	# Grid cells.
	var grid_w := name_w + col_w * innings + 0.5 + col_w * 3.0
	for r in 3:
		_quad(m, grid_w, row_h - 0.1, x0 + grid_w * 0.5, rows_y[r], Color(0.06, 0.24, 0.14) if r > 0 else Color(0.10, 0.30, 0.18), 0.02)
	# The current inning's column glows.
	if inning <= innings and not final:
		var cx := x0 + name_w + col_w * (inning - 0.5)
		_quad(m, col_w - 0.08, row_h * 3.0 - 0.1, cx, top - row_h * 1.5, Color(0.30, 0.24, 0.04), 0.03)
	# Every column is a three-line label with the same font and a line pitch equal to the row
	# height, so each line sits in its own row whatever it says.
	var names := PackedStringArray(["", "AWAY", "HOME"])
	_rows_text(names, Vector3(x0 + 0.25, top, 0.1), HORIZONTAL_ALIGNMENT_LEFT, WHITE, row_h)
	for i in innings:
		var cx2 := x0 + name_w + col_w * (i + 0.5)
		var away := ""
		if i < runs_by.size():
			away = str(runs_by[i])
		elif i < inning - 1 or (i == inning - 1 and not final):
			away = "0"
		var home := ""
		if i < home_by.size():
			home = str(home_by[i])
		elif final and i == inning - 1:
			home = "X"                       # the home team did not need its last turn
		_rows_text(PackedStringArray([str(i + 1), away, home]),
			Vector3(cx2, top, 0.1), HORIZONTAL_ALIGNMENT_CENTER, WHITE, row_h)
	var tx := x0 + name_w + col_w * innings + 0.5
	var totals := [["R", str(int(s.get("runs", 0))), str(int(s.get("home_runs", 0)))],
		["H", str(int(s.get("hits", 0))), str(int(s.get("home_hits", 0)))],
		["E", "0", str(int(s.get("errors", 0)))]]
	for i in 3:
		var cx3: float = tx + col_w * (i + 0.5)
		_rows_text(PackedStringArray(totals[i]), Vector3(cx3, top, 0.1), HORIZONTAL_ALIGNMENT_CENTER, AMBER, row_h)

	# --- Ball / strike / out lights.
	var lx := 9.0
	var rows := [["B", int(s.get("balls", 0)), 3, Color(0.25, 0.95, 0.35), 2.3],
		["S", int(s.get("strikes", 0)), 2, AMBER, 0.9],
		["O", int(s.get("outs", 0)), 2, Color(1.0, 0.22, 0.18), -0.5]]
	for r in rows:
		_text(r[0], 110, Vector3(lx, r[4], 0.1), HORIZONTAL_ALIGNMENT_CENTER, WHITE)
		for k in r[2]:
			_light(m, lx + 1.5 + k * 1.15, r[4], 0.42, r[3] if k < r[1] else DIM)

	# --- Bottom strip: at bat, pitching, last pitch.
	var by := -3.3
	_quad(m, W - 1.0, 1.9, 0.0, by, Color(0.06, 0.24, 0.14), 0.02)
	var line := str(s.get("batter_line", ""))
	_text("AT BAT" + ("   " + line if line != "" else ""), 52, Vector3(-W * 0.5 + 0.8, by + 0.55, 0.1),
		HORIZONTAL_ALIGNMENT_LEFT, AMBER)
	_text(str(s.get("batter", "")).to_upper(), 86, Vector3(-W * 0.5 + 0.8, by - 0.25, 0.1), HORIZONTAL_ALIGNMENT_LEFT, WHITE)
	_text("PITCHING", 52, Vector3(3.2, by + 0.55, 0.1), HORIZONTAL_ALIGNMENT_CENTER, AMBER)
	_text(str(s.get("pitcher", "")).to_upper(), 70, Vector3(3.2, by - 0.25, 0.1), HORIZONTAL_ALIGNMENT_CENTER, WHITE)
	var mph := float(s.get("last_mph", 0.0))
	_text(("%.0f MPH" % mph) if mph > 0.0 else "---", 110, Vector3(W * 0.5 - 0.8, by - 0.1, 0.1),
		HORIZONTAL_ALIGNMENT_RIGHT, AMBER)
	_text(str(s.get("last_kind", "")).to_upper(), 46, Vector3(W * 0.5 - 0.8, by + 0.62, 0.1),
		HORIZONTAL_ALIGNMENT_RIGHT, Color(0.75, 0.92, 0.80))

	var inst := MeshInstance3D.new()
	inst.mesh = m.build()
	inst.material_override = _mat
	add_child(inst)
