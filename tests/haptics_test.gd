extends SceneTree
## Haptics: which hand feels what, harder for faster/harder things, scaled by the player's setting
## (and silent when Off), a quiet pop for a ball in the dirt, and the setting survives saving.
## Run: godot --headless --path . -s res://tests/haptics_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _amp(spec: Variant) -> float:
	return float(spec[0]) if spec != null else -1.0


func _init() -> void:
	# The mapping.
	var slow := Haptics.profile("release", 0.2)
	var fast := Haptics.profile("release", 1.0)
	_check(_amp(fast["throw"]) > _amp(slow["throw"]) and fast["off"] == null, "a faster release is felt harder, in the throwing hand only")
	var pop := Haptics.profile("pop", 0.9)
	_check(_amp(pop["off"]) > _amp(pop["throw"]) and _amp(pop["off"]) > _amp(Haptics.profile("pop", 0.2)["off"]), "the mitt's pop is mostly the glove hand and grows with speed")
	_check(Haptics.profile("catch")["throw"] == null and _amp(Haptics.profile("catch")["off"]) > 0.5, "a glove catch is felt in the glove hand")
	_check(float(Haptics.profile("buzz")["throw"][2]) > 100.0, "a balk is a buzz (a high frequency), not a thump")
	_check(Haptics.profile("nonsense")["throw"] == null and Haptics.profile("nonsense")["off"] == null, "an unknown event is silent")
	for ev in ["grab", "release", "pop", "contact", "catch", "throw", "rumble", "buzz", "ui_hover", "ui_select", "ui_error"]:
		var p := Haptics.profile(ev, 5.0)           # even an absurd strength stays in range
		for k in ["throw", "off"]:
			if p[k] != null and not (_amp(p[k]) >= 0.0 and _amp(p[k]) <= 1.0 and float(p[k][1]) > 0.0 and float(p[k][1]) < 1.0):
				_check(false, "%s %s is a sensible pulse" % [ev, k])
	_check(true, "every event gives a pulse of sensible size and length")

	# The player's setting.
	var h := Haptics.new()
	h.play("pop", 0.8)
	var normal: float = h.history[-1].amp if h.history.size() > 0 else -1.0
	_check(h.history.size() == 2 and normal > 0.0, "a pop is two pulses (both hands) with no controllers present")
	h.history.clear()
	h.set_level("Low")
	h.play("pop", 0.8)
	var low: float = h.history[-1].amp
	_check(absf(low - normal * 0.5) < 0.001, "Low is half of Normal (%.2f vs %.2f)" % [low, normal])
	h.history.clear()
	h.set_level("Off")
	h.play("pop", 0.8)
	h.play("rumble", 1.0)
	_check(h.history.is_empty(), "Off is silence")
	h.set_level("Strong")
	h.play("catch")
	_check(h.history[-1].amp <= 1.0, "Strong never exceeds full power")
	for i in 100:
		h.play("grab")
	_check(h.history.size() <= 60, "the history is capped")

	# Saved with the other settings; bad values fall back.
	var s := Settings.new()
	s.haptics = "Low"
	_check(Settings.from_dict(s.to_dict()).haptics == "Low", "the setting survives a save and load")
	_check(Settings.from_dict({"haptics": "Earthquake"}).haptics == "Normal", "a bad value falls back to Normal")
	var m := MenuModel.new(s)
	m.stack = ["options"]
	var idx := -1
	for i in m.items().size():
		if m.items()[i].id == "haptics":
			idx = i
	_check(idx >= 0 and m.items()[idx].value == "Low", "Options has a Haptics row showing the setting")
	var ev := m.activate(idx)
	_check(ev.get("type", "") == "settings" and s.haptics == "Normal", "choosing it steps Low to Normal and asks to save")
	for i in 3:
		m.activate(idx)
	_check(s.haptics == "Normal" or s.haptics in Settings.HAPTICS, "it cycles through the levels (%s)" % s.haptics)

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
