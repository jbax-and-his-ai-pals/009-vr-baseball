class_name Haptics
extends RefCounted
## Controller vibration for what you do and what happens to you: grabbing the ball, letting go
## (harder the faster you threw), the pop of the catcher's mitt, the bat meeting the ball, a glove
## catch, a balk's buzz, the menu's tick. One call per event, `play("pop", 0.8)`; the table in
## profile() says which hand and how hard, so feel can be tuned in one place.
##
## Nothing happens without a controller (desktop, tests); the pulses are still written to `history`
## so tests can check them. The player's setting scales everything ("Off" is silence).

const ACTION := "haptic"
const LEVELS := {"Off": 0.0, "Low": 0.5, "Normal": 1.0, "Strong": 1.5}

var hand: XRController3D             # the throwing hand
var off_hand: XRController3D         # the glove hand
var intensity := 1.0                 # LEVELS[setting]
## Every pulse asked for, newest last ({"event", "who", "amp", "dur", "freq"}); capped.
var history: Array = []


## The setting name from Settings ("Off", "Low", "Normal", "Strong").
func set_level(name: String) -> void:
	intensity = float(LEVELS.get(name, 1.0))


## What an event feels like. `strength` 0..1 is how big the thing was (a fast pitch, a hard hit).
## Returns {"throw": [amp, dur, freq] or null, "off": [...] or null}. Pure: no controllers needed.
static func profile(event: String, strength: float = 0.5) -> Dictionary:
	var s := clampf(strength, 0.0, 1.0)
	match event:
		"grab":
			return {"throw": [0.18, 0.04, 0.0], "off": null}
		"release":
			return {"throw": [0.30 + 0.60 * s, 0.07, 0.0], "off": null}
		"pop":                       # the catcher's mitt, felt in both hands, mostly the glove hand
			return {"throw": [0.12 + 0.25 * s, 0.07, 0.0], "off": [0.30 + 0.55 * s, 0.09, 0.0]}
		"contact":                   # the bat on the ball
			return {"throw": [0.30 + 0.55 * s, 0.12, 0.0], "off": [0.30 + 0.55 * s, 0.12, 0.0]}
		"catch":                     # your own glove closing on a batted ball
			return {"throw": null, "off": [0.85, 0.12, 0.0]}
		"throw":
			return {"throw": [0.45, 0.08, 0.0], "off": null}
		"rumble":                    # a home run, a strikeout, the end of a game
			return {"throw": [0.25 + 0.4 * s, 0.45, 80.0], "off": [0.25 + 0.4 * s, 0.45, 80.0]}
		"buzz":                      # a balk: you did something wrong
			return {"throw": [0.55, 0.30, 160.0], "off": [0.55, 0.30, 160.0]}
		"ui_hover":
			return {"throw": [0.12, 0.02, 0.0], "off": [0.12, 0.02, 0.0]}
		"ui_select":
			return {"throw": [0.35, 0.05, 0.0], "off": [0.35, 0.05, 0.0]}
		"ui_error":
			return {"throw": [0.40, 0.10, 120.0], "off": [0.40, 0.10, 120.0]}
	return {"throw": null, "off": null}


## Feel an event in the game (both hands as the profile says).
func play(event: String, strength: float = 0.5) -> void:
	var p := profile(event, strength)
	_pulse(event, "throw", hand, p["throw"])
	_pulse(event, "off", off_hand, p["off"])


## Feel an event in ONE controller (the one pointing at a menu row). Nothing if it is null.
func play_on(ctrl: XRController3D, event: String) -> void:
	var p := profile(event)
	var spec = p["throw"] if p["throw"] != null else p["off"]
	_pulse(event, "pointer", ctrl, spec)


func _pulse(event: String, who: String, ctrl: XRController3D, spec: Variant) -> void:
	if spec == null or intensity <= 0.0:
		return
	var amp := clampf(float(spec[0]) * intensity, 0.0, 1.0)
	history.append({"event": event, "who": who, "amp": amp, "dur": float(spec[1]), "freq": float(spec[2])})
	if history.size() > 60:
		history.pop_front()
	if ctrl != null and ctrl.get_is_active():
		ctrl.trigger_haptic_pulse(ACTION, float(spec[2]), amp, float(spec[1]), 0.0)
