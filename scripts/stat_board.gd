class_name StatBoard
extends Node3D
## A board hung in the world that shows stats and does not follow your head. Its top-center is
## the node's origin and its front is +Z, so aim it by rotating the node.
##
## Layout, top to bottom: a title bar, a row of big number tiles, a table, and footer lines.
## Every section is optional. All the panels, stripes and tiles are baked into ONE merged
## mesh, and each table column is ONE multi-line label, so a whole board is about 20 draw calls.
##
##   board.title = "PITCHING"; board.subtitle = "5.1 IP"
##   board.tiles = [["82", "PITCHES"], ["7", "K"]]
##   board.columns = [{"head": "PITCH", "w": 0.4, "align": "l"}, {"head": "MPH", "w": 0.2, "align": "r"}]
##   board.rows = [["Fastball", "68"], ["TOTAL", "66"]]       # the last row can be a total
##   board.lines = ["Last: Fastball 68 mph  STRIKE"]
##   board.refresh()                                            # rebuilds next frame

const PIXEL := 0.0021
const MARGIN := 0.07

@export var width := 2.5

var title := ""
var subtitle := ""
var accent := Color(0.12, 0.40, 0.78)
var tiles: Array = []
var columns: Array = []
var rows: Array = []
var total_row := true           # style the last row as a total
var lines: Array = []
## Recent pitches drawn on a strike-zone chart: [{x, y, color, halo}, ...], newest last.
var plot: Array = []
var show_plot := false
const PLOT_SCALE := 0.85        # board meters per real meter
const PLOT_Y0 := 0.15           # real height drawn at the bottom of the chart
const PLOT_Y1 := 1.65
const PLOT_HALF_W := 0.62

var _dirty := true
var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func refresh() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty and visible:
		_dirty = false
		_rebuild()


func _line_height(font_size: int, spacing: int) -> float:
	var f := ThemeDB.fallback_font
	return (f.get_height(font_size) + spacing) * PIXEL


func _text(text: String, size: int, pos: Vector3, align: int, color: Color, valign: int = VERTICAL_ALIGNMENT_CENTER,
		spacing: int = 0) -> Label3D:
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
	return l


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var m := MeshMerger.new()
	var inner := width - MARGIN * 2.0
	var left := -width * 0.5 + MARGIN
	var y := 0.0

	# --- Title bar.
	var bar_h := 0.26
	var bar_y := -bar_h * 0.5
	_panel(m, width, bar_h, accent, 0.0, bar_y, 0.004)
	_text(title, 58, Vector3(left, bar_y, 0.01), HORIZONTAL_ALIGNMENT_LEFT, Color.WHITE)
	if subtitle != "":
		_text(subtitle, 40, Vector3(-left, bar_y, 0.01), HORIZONTAL_ALIGNMENT_RIGHT, Color(0.92, 0.96, 1.0))
	y = -bar_h - 0.05

	# --- A strike-zone chart of the last pitches, color-coded by where they crossed.
	if show_plot:
		var pw := PLOT_HALF_W * 2.0 * PLOT_SCALE
		var ph := (PLOT_Y1 - PLOT_Y0) * PLOT_SCALE
		var pcx := 0.0
		var pcy := y - ph * 0.5 - 0.02
		_panel(m, pw + 0.04, ph + 0.04, Color(0.07, 0.10, 0.15), pcx, pcy, 0.004)
		# The middle of the zone (easy to hit) tinted amber, the rim (hard to hit) green.
		var zw := PitchPhysics.ZONE_HALF_W * 2.0 * PLOT_SCALE
		var zh := (PitchPhysics.ZONE_TOP - PitchPhysics.ZONE_BOTTOM) * PLOT_SCALE
		var zcy := pcy + ((PitchPhysics.ZONE_TOP + PitchPhysics.ZONE_BOTTOM) * 0.5 - (PLOT_Y0 + PLOT_Y1) * 0.5) * PLOT_SCALE
		_panel(m, zw, zh, Color(0.10, 0.30, 0.16), pcx, zcy, 0.006)
		_panel(m, zw * PitchLocation.GOOD, zh * PitchLocation.GOOD, Color(0.13, 0.22, 0.14), pcx, zcy, 0.007)
		_panel(m, zw * PitchLocation.MIDDLE, zh * PitchLocation.MIDDLE, Color(0.30, 0.22, 0.06), pcx, zcy, 0.008)
		var t := 0.008
		_panel(m, zw + t, t, Color(0.9, 0.93, 0.98), pcx, zcy + zh * 0.5, 0.01)
		_panel(m, zw + t, t, Color(0.9, 0.93, 0.98), pcx, zcy - zh * 0.5, 0.01)
		_panel(m, t, zh + t, Color(0.9, 0.93, 0.98), pcx - zw * 0.5, zcy, 0.01)
		_panel(m, t, zh + t, Color(0.9, 0.93, 0.98), pcx + zw * 0.5, zcy, 0.01)
		var n_pl := plot.size()
		for i in n_pl:
			var e: Dictionary = plot[i]
			var age := float(n_pl - 1 - i) / maxf(float(n_pl), 1.0)
			var px := pcx + clampf(float(e.x), -PLOT_HALF_W, PLOT_HALF_W) * PLOT_SCALE
			var py := pcy + (clampf(float(e.y), PLOT_Y0, PLOT_Y1) - (PLOT_Y0 + PLOT_Y1) * 0.5) * PLOT_SCALE
			var sz := lerpf(0.085, 0.055, age)
			var bright := lerpf(1.0, 0.5, age)
			var h: Color = e.halo
			if h.a > 0.0:
				_panel(m, sz * 1.7, sz * 1.7, Color(h.r * bright, h.g * bright, h.b * bright), px, py, 0.012)
			var c: Color = e.color
			_panel(m, sz, sz, Color(c.r * bright, c.g * bright, c.b * bright), px, py, 0.014)
		y = pcy - ph * 0.5 - 0.08

	# --- Tiles of big numbers.
	if not tiles.is_empty():
		var n := tiles.size()
		var gap := 0.04
		var tw := (inner - gap * (n - 1)) / n
		var th := 0.40
		for i in n:
			var cx := left + tw * 0.5 + i * (tw + gap)
			_panel(m, tw, th, Color(0.10, 0.14, 0.22), cx, y - th * 0.5, 0.004)
			_text(str(tiles[i][0]), 66, Vector3(cx, y - th * 0.36, 0.01), HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.92, 0.5))
			_text(str(tiles[i][1]), 28, Vector3(cx, y - th * 0.82, 0.01), HORIZONTAL_ALIGNMENT_CENTER, Color(0.65, 0.78, 0.95))
		y -= th + 0.06

	# --- The table: one label per column, the header as its first line.
	if not columns.is_empty():
		var size := 33
		var lh := _line_height(size, 5)
		var n_lines := rows.size() + 1
		var table_h := lh * n_lines + 0.04
		_panel(m, inner + 0.02, lh, Color(accent.r * 0.55, accent.g * 0.55, accent.b * 0.55), 0.0, y - lh * 0.5 - 0.01, 0.004)
		for i in rows.size():
			var ry := y - 0.01 - lh * (i + 1.5)
			var is_total := total_row and i == rows.size() - 1
			if is_total:
				_panel(m, inner + 0.02, lh, Color(0.20, 0.26, 0.36), 0.0, ry, 0.004)
			elif i % 2 == 1:
				_panel(m, inner + 0.02, lh, Color(0.11, 0.15, 0.23), 0.0, ry, 0.004)
		var x := left
		for c in columns.size():
			var col: Dictionary = columns[c]
			var cw: float = inner * float(col.w)
			var align: String = col.get("align", "l")
			var px := x if align == "l" else (x + cw if align == "r" else x + cw * 0.5)
			var ha := HORIZONTAL_ALIGNMENT_LEFT if align == "l" else (HORIZONTAL_ALIGNMENT_RIGHT if align == "r" else HORIZONTAL_ALIGNMENT_CENTER)
			var block := PackedStringArray([str(col.head)])
			for r in rows:
				block.append(str((r as Array)[c]) if c < (r as Array).size() else "")
			_text("\n".join(block), size, Vector3(px, y - 0.01, 0.01), ha, Color(0.93, 0.95, 1.0),
				VERTICAL_ALIGNMENT_TOP, 5)
			x += cw
		y -= table_h + 0.02

	# --- Footer lines.
	if not lines.is_empty():
		var fsize := 30
		var flh := _line_height(fsize, 4)
		_text("\n".join(PackedStringArray(lines)), fsize, Vector3(left, y - 0.01, 0.01), HORIZONTAL_ALIGNMENT_LEFT,
			Color(0.80, 0.86, 0.96), VERTICAL_ALIGNMENT_TOP, 4)
		y -= flh * lines.size() + 0.04

	# --- Backing panel and frame, sized to what was laid out.
	var total := -y + 0.03
	_panel(m, width, total, Color(0.03, 0.05, 0.09), 0.0, -total * 0.5 + 0.0, -0.004)
	_panel(m, width + 0.05, total + 0.05, Color(0.45, 0.50, 0.60), 0.0, -total * 0.5, -0.012)
	var inst := MeshInstance3D.new()
	inst.mesh = m.build()
	inst.material_override = _mat
	add_child(inst)


func _panel(m: MeshMerger, w: float, h: float, color: Color, x: float, y: float, z: float) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	m.add(q, Transform3D(Basis.IDENTITY, Vector3(x, y, z)), color)
