class_name Calibration
extends RefCounted
## What the game has learned about your arm, kept between games: your usual throw (the wrist model's
## baselines), your usual aim and how much it scatters, and your recent hand speeds (for your top speed).
## One record per throwing hand, saved to user://calibration.json. Without it every game would start from
## the recorded prior and relearn you over its first throws.
##
##   var d := Calibration.load_for("right")     # {} when you have not warmed up yet
##   human.apply_dict(d)
##   Calibration.save_for("right", human.to_dict())
##
## Tests never touch the player's file: a test run (ThrowLogger.override_path set) uses a scratch file and
## does not load it unless `override_path` is set explicitly.

const PATH := "user://calibration.json"
const TEST_PATH := "user://test_calibration.json"
const VERSION := 1

static var override_path := ""


static func path() -> String:
	if override_path != "":
		return override_path
	if ThrowLogger.override_path != "":
		return TEST_PATH
	return PATH


## Only a test that chose its own file reads a saved calibration; other test runs start uncalibrated.
static func may_load() -> bool:
	return override_path != "" or ThrowLogger.override_path == ""


static func _read() -> Dictionary:
	if not FileAccess.file_exists(path()):
		return {}
	var f := FileAccess.open(path(), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary or int(d.get("version", 0)) != VERSION:
		return {}
	return d


static func load_for(hand: String) -> Dictionary:
	if not may_load():
		return {}
	var d: Dictionary = _read().get("hands", {}).get(hand, {})
	return d


static func exists(hand: String) -> bool:
	return not load_for(hand).is_empty()


static func save_for(hand: String, data: Dictionary) -> void:
	var all := _read()
	var hands: Dictionary = all.get("hands", {})
	var rec := data.duplicate()
	rec["saved"] = Time.get_datetime_string_from_system()
	hands[hand] = rec
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"version": VERSION, "hands": hands}, "\t"))


## Forget one hand's calibration ("" forgets both).
static func clear(hand: String = "") -> void:
	if hand == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path()))
		return
	var all := _read()
	var hands: Dictionary = all.get("hands", {})
	hands.erase(hand)
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"version": VERSION, "hands": hands}, "\t"))
