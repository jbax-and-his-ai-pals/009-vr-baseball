class_name ThrowDetector
extends RefCounted
## Turns a stream of controller pose samples into a release velocity and spin.
## Samples come from the caller (not the XR runtime's velocity values) so the
## same code can be driven by synthetic data in tests.

const HISTORY_SEC := 0.6
const WINDOW_SEC := 0.05

var _t := PackedFloat64Array()
var _p: Array[Vector3] = []
var _q: Array[Quaternion] = []
var _g := PackedFloat32Array()


func clear() -> void:
	_t.clear()
	_p.clear()
	_q.clear()
	_g.clear()


func add_sample(t: float, pos: Vector3, rot: Quaternion, grip: float = 0.0) -> void:
	_t.append(t)
	_p.append(pos)
	_q.append(rot)
	_g.append(grip)
	while _t.size() > 2 and t - _t[0] > HISTORY_SEC:
		_t.remove_at(0)
		_p.remove_at(0)
		_q.remove_at(0)
		_g.remove_at(0)


## Linear velocity and angular velocity (rad/s, world frame, axis * rate) over a
## short window ending latency seconds before release_t. Buttons report a
## release later than the hand actually opened, so latency pulls the window back.
func estimate(release_t: float, latency: float) -> Dictionary:
	var t_end := release_t - latency
	var hi := -1
	for i in range(_t.size() - 1, -1, -1):
		if _t[i] <= t_end:
			hi = i
			break
	if hi < 1:
		return {"valid": false}
	var lo := hi - 1
	while lo > 0 and _t[hi] - _t[lo - 1] <= WINDOW_SEC:
		lo -= 1
	var dt := _t[hi] - _t[lo]
	if dt < 1e-4:
		return {"valid": false}
	var v := (_p[hi] - _p[lo]) / dt
	var rotvec := Vector3.ZERO
	for i in range(lo, hi):
		var dq := _q[i + 1] * _q[i].inverse()
		if dq.w < 0.0:
			dq = -dq
		rotvec += dq.get_axis() * dq.get_angle()
	return {"valid": true, "velocity": v, "spin": rotvec / dt, "speed": v.length()}


## Looks for a hand-speed peak that has since fallen off, which is where a natural
## throw lets go. Returns the time of that peak, or -1.0 if none yet.
func find_release_peak(min_speed: float, drop_ratio: float, forward: Vector3) -> float:
	var n := _t.size()
	if n < 6:
		return -1.0
	var speeds := PackedFloat32Array()
	speeds.resize(n)
	for i in range(2, n):
		var dt := _t[i] - _t[i - 2]
		speeds[i] = ((_p[i] - _p[i - 2]) / dt).length() if dt > 1e-4 else 0.0
	var peak := 2
	for i in range(2, n):
		if speeds[i] > speeds[peak]:
			peak = i
	if speeds[peak] < min_speed or speeds[n - 1] > drop_ratio * speeds[peak]:
		return -1.0
	var dtp := _t[peak] - _t[peak - 2]
	if dtp < 1e-4 or ((_p[peak] - _p[peak - 2]) / dtp).dot(forward) <= 0.0:
		return -1.0
	return _t[peak]


## Raw samples from the last seconds, oldest first, for the throw logger.
## Each is {t, p (position), f (pointing direction), g (grip)}.
func recent(since_t: float) -> Array:
	var out := []
	for i in _t.size():
		if _t[i] >= since_t:
			out.append({"t": _t[i], "p": _p[i], "f": _q[i] * Vector3(0.0, 0.0, -1.0), "g": _g[i]})
	return out


## Hand position at time t, interpolated between samples; null if t is outside the history.
func position_at(t: float) -> Variant:
	for i in range(_t.size() - 1):
		if _t[i] <= t and t <= _t[i + 1]:
			return _p[i].lerp(_p[i + 1], (t - _t[i]) / maxf(_t[i + 1] - _t[i], 1e-6))
	return null


## How straight the hand's path was over the last `back` seconds before release_t:
## chord length / path length, 1.0 = dead straight. A push is ~0.95+; a normal throw
## ~0.9; a big looping arm swing ~0.7. Returns -1.0 without enough samples.
func straightness(release_t: float, back: float = 0.34) -> float:
	var idx: Array[int] = []
	for i in _t.size():
		if _t[i] >= release_t - back and _t[i] <= release_t - 0.005:
			idx.append(i)
	if idx.size() < 6:
		return -1.0
	var path := 0.0
	for k in range(idx.size() - 1):
		path += _p[idx[k]].distance_to(_p[idx[k + 1]])
	if path < 0.05:
		return -1.0
	return _p[idx[0]].distance_to(_p[idx[idx.size() - 1]]) / path


## Highest hand position (y) in the last `back` seconds before release_t: the top of the
## windup. Returns -INF without samples.
func peak_height(release_t: float, back: float = 0.54) -> float:
	var best := -INF
	for i in _t.size():
		if _t[i] >= release_t - back and _t[i] <= release_t - 0.005:
			best = maxf(best, _p[i].y)
	return best
