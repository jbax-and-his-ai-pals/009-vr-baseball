extends SceneTree
## The animated crowd: the fans' shader loads, the park's excitement jumps on a big moment and settles
## over a few seconds, and the scene picks how excited by what happened.
## Run: godot --headless --path . -s res://tests/crowd_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _init() -> void:
	var shader: Shader = load("res://shaders/crowd.gdshader")
	_check(shader != null and shader.code.contains("excite") and shader.code.contains("TIME"), "the crowd shader loads and moves with time and excitement")
	var st := Stadium.new()
	st.crowd_count = 200
	root.add_child(st)
	await process_frame
	_check(st._crowd_mats.size() == 2, "fans and heads each have the shader material")
	_check(st._crowd_mm.material_override is ShaderMaterial and st._heads_mm.material_override is ShaderMaterial, "and they are on the two multimeshes")
	_check(float(st._crowd_mats[1].get_shader_parameter("anchor_y")) > 0.5 and float(st._crowd_mats[0].get_shader_parameter("anchor_y")) == 0.0, "heads are anchored above the body so they rise with it")
	_check(st.excitement() == 0.0, "a calm crowd to start")
	st.pulse(1.0)
	_check(st.excitement() == 1.0 and float(st._crowd_mats[0].get_shader_parameter("excite")) == 1.0, "a homer puts them on their feet at once")
	st.pulse(0.3)
	_check(st.excitement() == 1.0, "a smaller moment does not calm them")
	st._process(2.5)
	var mid := st.excitement()
	_check(mid > 0.3 and mid < 0.8, "they settle gradually (%.2f after 2.5 s)" % mid)
	st._process(4.0)
	_check(st.excitement() == 0.0 and float(st._crowd_mats[1].get_shader_parameter("excite")) == 0.0, "and are sitting again after about six seconds")
	st.pulse(5.0)
	_check(st.excitement() == 1.0, "excitement is capped at 1")
	st.queue_free()

	ThrowLogger.override_path = "user://test_throws.jsonl"
	var bp: Node3D = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	await process_frame
	_check(bp.flow.crowd_excitement({"result": "home_run"}) == 1.0 and bp.flow.crowd_excitement({"result": "double"}) == 0.5 and bp.flow.crowd_excitement({"result": "strikeout"}) == 0.3, "the scene picks how excited: homer, double, strikeout")
	_check(bp.flow.crowd_excitement({"result": "single", "runs": 1}) == 0.6 and bp.flow.crowd_excitement({"result": "out"}) == 0.0, "a run scores a cheer, an ordinary out nothing")
	bp.flow.after_event({"result": "home_run", "runs": 1, "pa_over": false, "half_over": false, "game_over": false, "text": "", "batter": null})
	_check(bp._stadium.excitement() == 1.0, "a home run in the game gets the crowd up")
	bp.queue_free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
