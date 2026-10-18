class_name BatterPresenter
extends Node
## The batter as something you see: he walks up from the dugout with the bat low, steps into his
## box on the side he bats from, can let a pitch go (or hitch his bat, or flinch from one), and
## lets go of the bat when he is done. The scene tells it what the game decided; it moves the
## figure and says what it did through signals.
##
##   arrived()        he is in his box and the pitcher may throw
##   walk_step(at)    a footstep while he walks up

signal arrived
signal walk_step(at: Vector3)

const DUGOUT_ENTRY := Vector3(-9.0, 0.0, 5.2)
const WALK_SPEED := 4.0

var batter: CartoonBatter
var home := Transform3D.IDENTITY        # where he stands in his box
var walk := {}                          # the walk to the box in progress ({} when none)
var _steps_connected := false


## Builds the figure under `parent`.
func setup(parent: Node) -> void:
	batter = CartoonBatter.new()
	batter.position = Vector3(0.98, 0.0, 0.0)
	parent.add_child(batter)
	home = batter.transform
	_connect_steps()


func _connect_steps() -> void:
	# The figure builds itself when it enters the tree, so this may have to wait for the first walk.
	if batter.doll != null and not _steps_connected:
		_steps_connected = true
		batter.doll.footstep.connect(func(at: Vector3): walk_step.emit(at))


func is_walking() -> bool:
	return not walk.is_empty()


## He is (already) in the box: put him on the right side for how he bats.
func place_in_box(lefty: bool) -> void:
	home = CartoonBatter.home_transform(not lefty)
	batter.transform = home


## Back in the box right now (a new game, or the watchdog when a walk-on went wrong).
func snap_to_box(show: bool = true) -> void:
	walk = {}
	batter.visible = show or batter.visible
	batter.set_carry(false, true)
	batter.transform = home


## He starts his walk from the dugout. Returns how long it will take.
func begin_walk_on(lefty: bool) -> float:
	home = CartoonBatter.home_transform(not lefty)
	var at := home.origin
	var path: Array = [DUGOUT_ENTRY, Vector3(-3.0, 0.0, -2.4), Vector3(at.x, 0.0, at.z - 1.0), at]
	var length := 0.0
	for i in range(1, path.size()):
		length += (path[i] as Vector3).distance_to(path[i - 1])
	_connect_steps()
	walk = {"t": 0.0, "path": path, "duration": length / WALK_SPEED}
	batter.set_carry(true, true)          # the bat hangs at his side on the walk up
	batter.reset()
	batter.visible = true
	batter.transform = Transform3D(Basis(Vector3.UP, 0.0), DUGOUT_ENTRY)
	return length / WALK_SPEED


func update(delta: float) -> void:
	if walk.is_empty():
		return
	walk.t += delta
	var u := clampf(float(walk.t) / maxf(float(walk.duration), 0.1), 0.0, 1.0)
	var path: Array = walk.path
	var total := 0.0
	var seg_len: Array = []
	for i in range(1, path.size()):
		var l: float = (path[i] as Vector3).distance_to(path[i - 1])
		seg_len.append(l)
		total += l
	var d := u * total
	if total - d < 2.2:
		batter.set_carry(false)           # he raises the bat as he steps into the box
	var pos: Vector3 = path[path.size() - 1]
	var face := 0.0
	for i in seg_len.size():
		var l2: float = seg_len[i]
		var dir: Vector3 = (path[i + 1] as Vector3) - (path[i] as Vector3)
		face = atan2(dir.x, dir.z)
		if d <= l2 or i == seg_len.size() - 1:
			pos = (path[i] as Vector3).lerp(path[i + 1], clampf(d / maxf(l2, 0.001), 0.0, 1.0))
			break
		d -= l2
	if u >= 1.0:
		batter.transform = home
		walk = {}
		arrived.emit()
	else:
		batter.transform = Transform3D(Basis(Vector3.UP, face), pos + Vector3(0.0, 0.05 * absf(sin(float(walk.t) * 9.0)), 0.0))


## He lets a pitch go. A pitch at his body makes him jerk away; one near the zone sometimes draws a
## hitch of the bat. Returns "flinch", "check" or "" (so the scene can add the sound). `roll` is a
## random number 0..1 from the cosmetic generator.
func take(analysis: Dictionary, busy: bool, lefty: bool, roll: float) -> String:
	if not analysis.get("reached", false) or batter == null:
		return ""
	var p: Vector3 = analysis.get("plate_pos", Vector3(9.0, 9.0, 0.0))
	if PitchLocation.hits_batter(p.x, p.y, lefty):
		batter.flinch()
		return "flinch"
	if not busy and absf(p.x) < 0.55 and p.y > 0.3 and p.y < 1.5 and roll < 0.3:
		batter.check_swing(Vector3(p.x, p.y, 0.1), float(analysis.get("time", 0.5)))
		return "check"
	return ""


## The bat leaves his hands. Returns where it was (null if he is not on screen).
func drop_bat() -> Variant:
	if batter == null or not batter.visible:
		return null
	return batter.drop_bat()
