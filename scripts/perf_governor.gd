class_name PerfGovernor
extends RefCounted
## Watches frame time and steps visual quality down (and back up) so the game holds its
## refresh rate instead of dropping frames, which in VR is far worse than looking a bit plainer.
##
## It never touches gameplay: only things the player is not judging pitches by - crowd density,
## the backstop netting, render resolution and foveation. Levels:
##   0 full | 1 half crowd, no netting | 2 sparse crowd, 85% resolution | 3 minimal crowd, 70% resolution
##
## Frame spikes over HITCH_MS (a stream hiccup, a level load) are ignored so a single stall does
## not trigger a downgrade; sustained slowness does.

signal level_changed(level: int)

const MAX_LEVEL := 3
const HITCH_MS := 100.0

var level := 0
var target_ms := 11.1             # 90 Hz; set from the display's refresh rate
var enabled := true
var ema_ms := 0.0
var _over_s := 0.0
var _under_s := 0.0


func set_refresh_rate(hz: float) -> void:
	target_ms = 1000.0 / maxf(hz, 30.0)


## Call once per frame with the frame delta in seconds.
func update(delta: float) -> void:
	if not enabled:
		return
	var ms := delta * 1000.0
	if ms > HITCH_MS:
		return
	ema_ms = ms if ema_ms == 0.0 else lerpf(ema_ms, ms, 0.05)
	if ema_ms > target_ms * 1.2:
		_over_s += delta
		_under_s = 0.0
		if _over_s > 1.0 and level < MAX_LEVEL:
			_over_s = 0.0
			_set_level(level + 1)
	elif ema_ms < target_ms * 0.75:
		_under_s += delta
		_over_s = 0.0
		# Climb back slowly so it does not oscillate.
		if _under_s > 6.0 and level > 0:
			_under_s = 0.0
			_set_level(level - 1)
	else:
		_over_s = 0.0
		_under_s = 0.0


func _set_level(new_level: int) -> void:
	level = new_level
	level_changed.emit(level)


static func crowd_fraction(lvl: int) -> float:
	return [1.0, 0.5, 0.2, 0.08][clampi(lvl, 0, MAX_LEVEL)]


static func render_scale(lvl: int) -> float:
	return [1.0, 1.0, 0.85, 0.70][clampi(lvl, 0, MAX_LEVEL)]
