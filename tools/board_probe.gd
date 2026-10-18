extends SceneTree
func _init() -> void:
	var b := StatBoard.new()
	root.add_child(b)
	await process_frame
	b.title = "T"
	b.tiles = [["1", "A"], ["2", "B"]]
	b.columns = [{"head": "PITCH", "w": 0.5, "align": "l"}, {"head": "#", "w": 0.5, "align": "r"}]
	b.rows = [["a", 1], ["b", 2], ["c", 3], ["d", 4], ["e", 5], ["f", 6]]
	b.lines = ["line one", "line two", "line three"]
	b.refresh()
	await process_frame
	await process_frame
	var f := ThemeDB.fallback_font
	print("font height 33: ", f.get_height(33), " computed lh: ", (f.get_height(33) + 5) * StatBoard.PIXEL)
	for c in b.get_children():
		if c is Label3D:
			var l := c as Label3D
			var n := l.text.count("\n") + 1
			print("label '", l.text.replace("\n", "/").substr(0, 24), "' lines=", n, " aabb.y=", l.get_aabb().size.y, " per line=", l.get_aabb().size.y / n, " font=", l.font_size, " spacing=", l.line_spacing)
	quit()
