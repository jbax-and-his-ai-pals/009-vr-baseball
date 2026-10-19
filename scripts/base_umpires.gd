class_name BaseUmpires
extends Node
## The three umpires out on the field: they stand where umpires stand (first and third in foul
## ground, second in the infield dirt behind the bag), watch the base they are responsible for, and
## give the out or safe call on a play there: a gesture and a voice. The plate umpire (PlateCrew)
## handles the plate; the scene hands the dolls over and calls `call_it(base, "ump_out")`.
##
##   umpire_voice(id, at)   what he says, and where he is standing (for the sound)

signal umpire_voice(id: String, at: Vector3)

## Where each stands (base number -> spot), and the base each faces.
const SPOTS := {
	1: Vector3(-22.5, 0.0, 15.5),
	2: Vector3(-3.5, 0.0, 36.5),
	3: Vector3(22.5, 0.0, 15.5),
}
const BASES := {
	1: Vector3(-19.4, 0.0, 19.4),
	2: Vector3(0.0, 0.0, 38.8),
	3: Vector3(19.4, 0.0, 19.4),
}

var umps: Dictionary = {}                 # base -> Doll
var _queue: Array = []                    # {"t", "base", "clip", "voice"}


func setup(first: Doll, second: Doll, third: Doll) -> void:
	umps = {1: first, 2: second, 3: third}
	for b in umps:
		var d: Doll = umps[b]
		d.position = SPOTS[b]
		d.rotation.y = _facing(int(b))


static func _facing(base: int) -> float:
	var to_base: Vector3 = (BASES[base] as Vector3) - (SPOTS[base] as Vector3)
	return atan2(to_base.x, to_base.z)


## The call at a base (1 to 3) after a short beat: a gesture and his voice ("ump_out" or "ump_safe").
func call_it(base: int, clip: String, delay: float = 0.15, seconds: float = 1.0) -> void:
	if not umps.has(base):
		return
	_queue.append({"t": delay, "base": base, "clip": clip, "dur": seconds})


func update(delta: float) -> void:
	for i in range(_queue.size() - 1, -1, -1):
		var q: Dictionary = _queue[i]
		q.t -= delta
		if q.t <= 0.0:
			_queue.remove_at(i)
			var d: Doll = umps[q.base]
			d.play(String(q.clip), float(q.dur))
			umpire_voice.emit(String(q.clip), d.global_position + Vector3(0.0, 1.5, 0.0))
