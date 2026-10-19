class_name PlayDirector
extends RefCounted
## Puts a play on the field: the fielders run, dive and throw; the ball goes from hand to glove;
## the batter-runner, the men on base and anyone who is out walking back all move along the plan
## the baserunning logic made; callouts, dust and sounds fire as their moments come.
## The scene owns the figures and hands them over in setup(); it listens for one thing:
##
##   batter_hidden(plan)   the batter-runner has left the box (the scene drops his bat and, if the
##                         plan says so, starts the next batter walking on)

signal batter_hidden(plan: Dictionary)

const BASE_STANDS := [Vector3(-18.5, 0.0, 19.0), Vector3(0.0, 0.0, 37.9), Vector3(18.5, 0.0, 19.0)]

var defense: Defense
var field_nodes: Dictionary
var runner: Doll
var base_runners: Array[Node3D]
var leavers: Array[Node3D]
var play_labels: Array[Label3D]
var leads: Array
var presenter: BatterPresenter
var crew: PlateCrew
var base_umps: BaseUmpires
var props: FieldProps
var sound: SoundDirector
var human_num := Callable()                 # () -> int: the position you play in Fielding mode (0 if none)
var refresh_base_runners := Callable()      # () -> void: put the base figures where the scorebook says


## Time (after contact) at which everything in the play has happened.
func play_end_time(play: Dictionary, path_end: float) -> float:
	var end := path_end
	if play.is_empty():
		return end
	if int(play.get("fielder", 0)) != 0 and play.get("result", "") not in ["home_run", "foul"]:
		# Once a fielder has it the play is decided: do not wait for the ball to stop rolling.
		end = float(play.field_time) + 0.5
	if play.has("throw"):
		end = maxf(end, float(play.throw.t1) + 0.5)
	var times: Array = play.get("run_times", Defense.RUNNER_TIMES)
	var bases := int(play.get("bases", 0))
	if play.result == "home_run":
		end = maxf(end, float(times[3]) * 0.8)
	elif bases >= 1:
		end = maxf(end, float(times[mini(bases, 4) - 1]) + 0.5)
	elif play.get("runner_out_at", 0) == 1:
		end = maxf(end, float(times[0]) + 0.5)
	return end


func ball_with_fielder(h: LiveHit) -> Vector3:
	var play := h.play
	var catch_p: Vector3 = play.field_pos
	var field_t: float = float(play.get("field_time", 0.0))
	# The throws in order (a double play or a relay is several); otherwise the one the defense planned.
	var throws: Array = h.throws
	if throws.is_empty():
		throws = h.plan.get("throws", [])
	if throws.is_empty() and play.has("throw"):
		throws = [play.throw]
	var release_t := field_t + 0.4
	if not throws.is_empty():
		release_t = maxf(float(throws[0].t0), field_t + 0.05)
	# In the hands: carried up from where it was caught (a grounder is in the dirt) to the
	# throwing hand, not teleported to chest height.
	var hand := Vector3(catch_p.x, 1.75, catch_p.z)
	var start := Vector3(catch_p.x, clampf(catch_p.y, 0.1, 2.4), catch_p.z)
	var u0 := clampf((h.t - field_t) / maxf(release_t - field_t, 0.05), 0.0, 1.0)
	var pos := start.lerp(hand, u0 * u0 * (3.0 - 2.0 * u0))
	for th in throws:
		var t0: float = th.t0
		var t1: float = maxf(th.t1, t0 + 0.05)
		if h.t < t0:
			break
		var u := clampf((h.t - t0) / (t1 - t0), 0.0, 1.0)
		var from: Vector3 = th.from
		var to: Vector3 = th.to
		var d := Vector2(from.x - to.x, from.z - to.z).length()
		# A throw is a lofted arc: higher the farther it goes, flat when it is short.
		var arc := clampf(0.07 * d, 0.2, 5.0) * 4.0 * u * (1.0 - u)
		pos = from.lerp(to, u) + Vector3(0.0, arc, 0.0)
		# It leaves the thrower's hand and ends in the receiver's glove, where it stays.
		var by = field_nodes.get(int(th.get("by", 0)))
		if by is Doll:
			pos = pos.lerp((by as Doll).hand_world(), 1.0 - smoothstep(0.0, 0.12, u))
		var rec = field_nodes.get(int(th.get("rec", 0)))
		if rec is Doll:
			pos = pos.lerp((rec as Doll).glove_world(), smoothstep(0.75, 0.97, u))
	return pos


## Who can take a throw at `base`, best first (the usual man, then whoever backs him up).
func receiver_candidates(base: int, thrower: int, from: Vector3) -> Array:
	match base:
		1:
			return [3, 1, 4]                # the first baseman, then the pitcher covering, then the second baseman
		2:
			if thrower == 6:
				return [4]
			if thrower == 4:
				return [6]
			return [6, 4] if from.x >= 0.0 else [4, 6]
		3:
			return [5, 6]
		_:
			return [2, 1]


## Who takes a throw at `base`, given who is throwing and from where.
func receiver_for(base: int, thrower: int, from: Vector3) -> int:
	return int(receiver_candidates(base, thrower, from)[0])


## Turn the planned throws (to a base position) into throws between players: each goes to the
## glove of the man covering that base, long ones through a cutoff man, with that man moving
## into place. Adds the receivers' and cutoff men's movements to the play.
func build_throws(h: LiveHit) -> Array:
	var raw: Array = h.plan.get("throws", [])
	if raw.is_empty() and h.play.has("throw"):
		raw = [h.play.throw]
	if raw.is_empty():
		return []
	var out: Array = []
	var moves: Array = (h.play.get("movements", []) as Array).duplicate()
	var has_move := {}
	for m in moves:
		has_move[int(m.fielder)] = true
	var thrower := int(h.play.get("fielder", 0))
	for th in raw:
		var base := int(th.get("base", 1))
		var spot: Vector3 = Baserunning.RECEIVE_SPOT[clampi(base, 1, 4)]
		var glove := spot + Vector3(0.0, 1.15, 0.0)
		var from_p: Vector3 = th.from
		var from := Vector3(from_p.x, 1.75, from_p.z)
		var t0: float = th.t0
		var t1: float = maxf(th.t1, t0 + 0.2)
		var dist := Vector2(from.x - glove.x, from.z - glove.z).length()
		# The man who took the last throw makes the next one (the pivot man at second in a double
		# play), and whoever covers a bag must be free to do it: not the thrower, not a man who is
		# already running elsewhere to make the play.
		var receiver := thrower
		for c in receiver_candidates(base, thrower, from_p):
			if c != thrower and not has_move.has(c) and field_nodes.get(c) != null:
				receiver = c
				break
		if dist > 62.0 and thrower != 0:
			# From the deep outfield: a cutoff man stands in line, about a third of the way in.
			var dir := Vector2(from.x - spot.x, from.z - spot.z).normalized()
			var rd := minf(30.0, dist * 0.4)
			var rp := Vector3(spot.x + dir.x * rd, 0.0, spot.z + dir.y * rd)
			var relay := 6 if rp.x >= 0.0 else 4
			if relay == receiver:
				relay = 4 if relay == 6 else 6
			var tm := t0 + (t1 - t0) * 0.62
			out.append({"from": from, "to": rp + Vector3(0.0, 1.15, 0.0), "t0": t0, "t1": tm, "base": base,
				"by": thrower, "rec": relay})
			out.append({"from": rp + Vector3(0.0, 1.75, 0.0), "to": glove, "t0": tm + 0.22, "t1": maxf(t1, tm + 0.7),
				"base": base, "by": relay, "rec": receiver})
			if not has_move.has(relay):
				var rf := defense.fielder_by_num(relay)
				moves.append({"fielder": relay, "from": rf.home, "to": rp, "t0": 0.2, "t1": maxf(tm - 0.25, 1.0), "dive": false})
				has_move[relay] = true
		else:
			out.append({"from": from, "to": glove, "t0": t0, "t1": t1, "base": base, "by": thrower, "rec": receiver})
		if receiver != thrower and not has_move.has(receiver):
			var rv := defense.fielder_by_num(receiver)
			if not rv.is_empty():
				moves.append({"fielder": receiver, "from": rv.home, "to": spot, "t0": 0.2,
					"t1": maxf(t0 - 0.2, 0.9), "dive": false})
				has_move[receiver] = true
		thrower = receiver
		# One more man goes behind the bag in case it gets by (the AI ones; you decide for yourself).
		var asg := Backup.assignment(base, int(h.play.get("fielder", 0)), from_p)
		var bnum := int(asg.fielder)
		var bnode: Node3D = field_nodes.get(bnum)
		if bnode != null and bnode.visible and not has_move.has(bnum) and bnum != receiver and bnum != int(human_num.call() if human_num.is_valid() else 0) \
				and t1 - t0 >= Backup.MIN_SECONDS:
			var bf := defense.fielder_by_num(bnum)
			if not bf.is_empty():
				var go_t := maxf(t1 - 0.2, 1.0)
				moves.append({"fielder": bnum, "from": bf.home, "to": Backup.reach(bf.home, asg.spot, float(bf.speed) * 0.9, go_t - 0.3),
					"t0": 0.3, "t1": go_t, "dive": false})
				has_move[bnum] = true
	h.play.movements = moves
	return out


func start_play(h: LiveHit) -> void:
	reset_fielders()
	runner.position = Vector3(0.98, 0.0, 0.0)
	runner.rotation.y = atan2(Defense.FIRST.x, Defense.FIRST.z)
	runner.visible = false
	for lab in play_labels:
		lab.visible = false
	# The men on base are already in place: they run when the plan says so.
	refresh_base_runners.call()


## Between plays the fielders walk to where the defense wants them (the infield comes in, or goes
## back), instead of jumping there. Call every frame while no play is on.
func drift_to_homes(delta: float) -> void:
	for f in defense.fielders:
		if int(f.num) == 2:
			continue
		var node: Node3D = field_nodes.get(f.num)
		if node == null or not node.visible:
			continue
		var home: Vector3 = f.home
		var d := Vector3(home.x - node.position.x, 0.0, home.z - node.position.z)
		if d.length() > 0.05:
			node.position += d.normalized() * minf(d.length(), 6.0 * delta)
			node.rotation.y = atan2(d.x, d.z)
			if int(f.num) == 1:
				node.position.y = PitchPhysics.MOUND_H * clampf(1.0 - d.length() / 3.0, 0.0, 1.0)
		else:
			node.rotation.y = atan2(-home.x, -home.z)


func reset_fielders() -> void:
	for f in defense.fielders:
		var node: Node3D = field_nodes.get(f.num)
		if node == null:
			continue
		var home: Vector3 = f.home
		node.position = Vector3(home.x, PitchPhysics.MOUND_H if f.num == 1 else 0.0, home.z if f.num != 2 else -1.35)
		node.rotation = Vector3.ZERO
		node.rotation.y = 0.0 if f.num == 2 else atan2(-home.x, -home.z)
	if runner:
		runner.visible = false
	for lab in play_labels:
		lab.visible = false


## Drive the fielders and the runner from the play's timeline.
func update_play(h: LiveHit) -> void:
	var play := h.play
	if play.is_empty():
		return
	var t := h.t
	if not h.anim_done.has("call") and t >= 0.9 and play.get("caught_in_air", false) and int(play.get("fielder", 0)) != 0 \
			and int(play.get("fielder", 0)) != human_num.call():
		h.anim_done["call"] = true               # he calls for it
		var caller = field_nodes.get(int(play.fielder))
		if caller is Node3D:
			sound.sfx("fielder_call_mine", (caller as Node3D).global_position + Vector3(0.0, 1.6, 0.0), -3.0)
	if not h.anim_done.has("react") and t >= 0.14:
		# The crack of the bat: everyone who is not running sinks and gets ready.
		h.anim_done["react"] = true
		var movers := {}
		for m in play.movements:
			movers[int(m.fielder)] = true
		for num in field_nodes:
			var rn: Node3D = field_nodes[num]
			if rn is Doll and rn.visible and num != 2 and not movers.has(int(num)):
				(rn as Doll).play("react", 0.55)
	for m in play.movements:
		var node: Node3D = field_nodes.get(int(m.fielder))
		if node == null:
			continue
		var from: Vector3 = m.from
		var to: Vector3 = m.to
		var span := maxf(float(m.t1) - float(m.t0), 0.05)
		var u := clampf((t - float(m.t0)) / span, 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)
		var pos := from.lerp(to, e)
		var moving := u > 0.0 and u < 1.0
		node.position = Vector3(pos.x, 0.07 * absf(sin(t * 11.0)) if moving else 0.0, pos.z)
		var dir := to - from
		if moving and dir.length() > 0.2:
			node.rotation.y = atan2(dir.x, dir.z)
		if u >= 1.0 and int(m.fielder) == int(play.get("fielder", 0)) and play.has("throw"):
			var aim: Vector3 = (play.throw.to as Vector3) - pos
			node.rotation.y = atan2(aim.x, aim.z)
		node.rotation.x = 0.0
		if bool(m.get("dive", false)) and u >= 0.72 and node is Doll and not h.anim_done.has("dive%d" % int(m.fielder)):
			h.anim_done["dive%d" % int(m.fielder)] = true
			h.anim_done["field"] = true              # the dive is the catch
			(node as Doll).play("dive", 0.95)
			sound.sfx_later(0.35, "catch_dive_thud", (node as Node3D).global_position + Vector3(0.0, 0.3, 0.0))
			sound.sfx_later(0.3, "cloth_rustle", (node as Node3D).global_position, -6.0)
	animate_plan(h.plan, h.t)
	play_throw_animations(h)


## Spot where a runner stands: the batter's box, or just off a base.
func stand_spot(base: int) -> Vector3:
	if base <= 0:
		return Vector3(presenter.home.origin.x, 0.0, presenter.home.origin.z)
	return stand_for(base)


## Where a runner on this base stands: beside the bag, and off it toward the next base by his lead.
func stand_for(base: int) -> Vector3:
	var stand: Vector3 = BASE_STANDS[base - 1]
	var next_pos: Vector3 = [Defense.SECOND, Defense.THIRD, Defense.HOME][base - 1]
	var toward: Vector3 = next_pos - (Baserunning.BASE_POS[base] as Vector3)
	toward.y = 0.0
	return stand + toward.normalized() * float(leads[base - 1])


## Where a runner is at time t, and which way he faces, from his planned arrivals.
func runner_at(r: Dictionary, t: float) -> Array:
	var spot: Vector3 = stand_spot(int(r.from))
	# A runner with keyframes (he hedged off the bag and came back, or waited for the ball to
	# land) follows them: [[time, position], ...].
	var kf: Array = r.get("keys", [])
	if not kf.is_empty():
		var first_p: Vector3 = spot
		var q_t: float = 0.0
		var q_p: Vector3 = first_p
		var face_k := atan2(Defense.FIRST.x - spot.x, Defense.FIRST.z - spot.z)
		for k in kf:
			var kt: float = k[0]
			var kp: Vector3 = k[1]
			var dk := kp - q_p
			if dk.length() > 0.01:
				face_k = atan2(dk.x, dk.z)
			if t <= kt:
				var uk := clampf((t - q_t) / maxf(kt - q_t, 0.001), 0.0, 1.0)
				return [q_p.lerp(kp, uk), face_k]
			q_t = kt
			q_p = kp
		return [q_p, face_k]
	var prev_t: float = maxf(float(r.t_start), 0.12 if int(r.from) == 0 else 0.0)
	var prev_p := spot
	var face := atan2(Defense.FIRST.x - spot.x, Defense.FIRST.z - spot.z)
	var keys: Array = r.arrivals.keys()
	keys.sort()
	if keys.is_empty() and bool(r.out) and int(r.out_base) == 0:
		# Caught in the air: he gets a few steps and pulls up.
		var span: float = float(Defense.RUNNER_TIMES[0]) / maxf(float(r.run_factor), 0.5) - prev_t
		var u0 := clampf((minf(t, float(r.t_out)) - prev_t) / maxf(span, 0.5), 0.0, 1.0)
		return [prev_p.lerp(Defense.FIRST, u0), face]
	for k in keys:
		var at: float = r.arrivals[k]
		var tgt: Vector3 = Defense.HOME if int(k) == 4 else (Baserunning.BASE_POS[int(k)] as Vector3)
		var d := tgt - prev_p
		if d.length() > 0.01:
			face = atan2(d.x, d.z)
		if t <= at:
			var u := clampf((t - prev_t) / maxf(at - prev_t, 0.05), 0.0, 1.0)
			return [prev_p.lerp(tgt, u), face]
		prev_t = at
		prev_p = tgt
	return [prev_p, face]


## Start each fielder's throw so the ball leaves his hand at the planned time, and the man
## receiving it puts his glove up as it arrives.
func play_throw_animations(h: LiveHit) -> void:
	var play := h.play
	var t := h.t
	var fielder := int(play.get("fielder", 0))
	if fielder != 0 and not h.anim_done.has("field"):
		var ft := float(play.get("field_time", 1e9))
		if t >= ft - 0.3:
			h.anim_done["field"] = true
			var fn = field_nodes.get(fielder)
			if fn is Doll:
				var how := catch_clip(play, fielder)
				(fn as Doll).play(how, 0.8)
				var at_glove: Vector3 = (fn as Node3D).global_position + Vector3(0.0, 0.8, 0.0)
				sound.sfx_later(0.3, "glove_catch_fly" if how in ["catch", "jump"] else "glove_scoop_ground", at_glove)
	for i in h.throws.size():
		var th: Dictionary = h.throws[i]
		var key := "t%d" % i
		if not h.anim_done.has(key) and t >= float(th.t0) - 0.42:
			h.anim_done[key] = true
			var by = field_nodes.get(int(th.get("by", 0)))
			if by is Doll:
				var from: Vector3 = th.from
				var to: Vector3 = th.to
				sound.sfx_later(0.42, "throw_whoosh", (by as Node3D).global_position + Vector3(0.0, 1.5, 0.0))
				if randf() < 0.3:
					sound.sfx_later(0.4, "throw_grunt", (by as Node3D).global_position + Vector3(0.0, 1.5, 0.0), -6.0)
				var d := Vector2(from.x - to.x, from.z - to.z).length()
				var kind := "overhand" if d > 30.0 else ("sidearm" if d > 12.0 else "underhand")
				(by as Doll).throw_to(to, kind, 0.75)
		var rkey := "r%d" % i
		if not h.anim_done.has(rkey) and t >= float(th.t1) - 0.3:
			h.anim_done[rkey] = true
			var rec = field_nodes.get(int(th.get("rec", 0)))
			if rec is Doll:
				var is_tag := is_tag_play(h.plan, int(th.get("base", 0)))
				(rec as Doll).play("tag" if is_tag else "catch", 0.6)
				sound.sfx_later(0.3, "tag_slap" if is_tag else "glove_catch_throw", (rec as Node3D).global_position + Vector3(0.0, 1.0, 0.0))


## How this fielder takes the ball: a scoop for a grounder, a backhand when he has to reach
## across himself for it, a jump for one over his head, otherwise the plain catch.
func catch_clip(play: Dictionary, fielder: int) -> String:
	var p: Vector3 = play.get("field_pos", Vector3.ZERO)
	if p.y > 2.3:
		return "jump"
	if p.y < 0.9:
		var f: Dictionary = defense.fielder_by_num(fielder)
		if not f.is_empty():
			var home: Vector3 = f.home
			var fwd := Vector2(-home.x, -home.z).normalized()
			var d := Vector2(p.x - home.x, p.z - home.z)
			var side := absf(d.x * fwd.y - d.y * fwd.x)
			if side > 2.0 and side > absf(d.dot(fwd)) * 1.1:
				return "backhand"
		return "scoop"
	return "catch"


## Is the out at this base a tag (not a force, not the batter beaten to first)?
func is_tag_play(plan: Dictionary, base: int) -> bool:
	if base == 1:
		return false
	for r in plan.get("runners", []):
		if bool(r.out) and int(r.out_base) == base and not bool(r.get("forced_out", false)):
			return true
	return false


## When the last runner who is out has walked back to the dugout.
func plan_anim_end(plan: Dictionary) -> float:
	if plan.is_empty():
		return 0.0
	var end := float(plan.get("end_time", 0.0))
	for r in plan.runners:
		if bool(r.out):
			var p: Vector3 = runner_at(r, float(r.t_out))[0]
			end = maxf(end, float(r.t_out) + 0.35 + p.distance_to(BatterPresenter.DUGOUT_ENTRY) / BatterPresenter.WALK_SPEED + 0.1)
		elif int(r.to) == 4 and r.arrivals.has(4):
			end = maxf(end, float(r.arrivals[4]) + 0.9)          # he stays for the celebration
	return end


## Run every runner on the plan at time t: the batter, the men already on base, and anyone
## who is out walking back to the dugout.
func animate_plan(plan: Dictionary, t: float) -> void:
	if plan.is_empty():
		return
	var hide_at: float = plan.get("hide_batter_at", 0.25)
	if t >= hide_at and not plan.get("batter_hidden", false):
		# Once per plan: an older play still walking its runners off must never hide the next
		# batter who has since come up.
		plan["batter_hidden"] = true
		batter_hidden.emit(plan)
	var out_i := 0
	for r in plan.runners:
		var from := int(r.from)
		var fig: Node3D = runner if from == 0 else base_runners[from - 1]
		if fig == null:
			continue
		if from == 0 and t < hide_at:
			fig.visible = false
			if bool(r.out):
				out_i += 1
			continue
		if bool(r.out):
			var lv: Node3D = leavers[mini(out_i, leavers.size() - 1)]
			out_i += 1
			var t_end := float(r.t_out) + 0.35
			if t >= t_end:
				fig.visible = false
				var start: Vector3 = (runner_at(r, float(r.t_out))[0] as Vector3)
				var d := BatterPresenter.DUGOUT_ENTRY - start
				var u := (t - t_end) / maxf(d.length() / BatterPresenter.WALK_SPEED, 0.1)
				if u >= 1.0:
					lv.visible = false
				else:
					lv.visible = true
					lv.position = Vector3(0.0, 0.05 * absf(sin(t * 9.0)), 0.0) + start.lerp(BatterPresenter.DUGOUT_ENTRY, u)
					lv.rotation.y = atan2(d.x, d.z)
				continue
		var done_at := INF
		if not bool(r.out) and int(r.to) == 4 and r.arrivals.has(4):
			done_at = float(r.arrivals[4]) + 0.9
		if t > done_at:
			fig.visible = false
			continue
		if fig is Doll and not r.get("slid", false) and (bool(r.out) or plan.get("steal", false)):
			var slide_base := int(r.out_base) if bool(r.out) else int(r.to)
			if slide_base in [2, 3, 4]:
				var t_there: float = float(r.t_out) if bool(r.out) else float(r.arrivals.get(slide_base, 1e9))
				if t >= t_there - 0.5:
					r["slid"] = true
					(fig as Doll).play("slide", 0.9)
					props.puff_at(fig, 0.2, 0.6, 3)
					props.puff_at(fig, 0.45, 0.8, 4)
					sound.sfx_later(0.15, "slide_dirt", (fig as Node3D).global_position)
		if fig is Doll:
			if r.get("dive", false) and not r.get("dived", false) and t >= 0.05:
				r["dived"] = true              # back to the bag head first
				(fig as Doll).play("dive", 0.85)
				props.puff_at(fig, 0.4, 0.7, 4)
			if not r.get("cheered", false) and not bool(r.out) and int(r.to) == 4 and r.arrivals.has(4) \
					and t >= float(r.arrivals[4]) - 0.05:
				r["cheered"] = true            # he scores: arms up
				(fig as Doll).play("celebrate", 0.9)
				sound.sfx("cloth_rustle", (fig as Node3D).global_position, -6.0)
			var hedge: Dictionary = r.get("hedge", {})
			(fig as Doll).watching = not hedge.is_empty() and t >= float(hedge.t_reach) and t < float(hedge.t_leave)
		fig.visible = true
		var at: Array = runner_at(r, t)
		var pos: Vector3 = at[0]
		var moving: bool = t > float(r.t_start) and (pos - stand_spot(from)).length() > 0.05
		fig.position = Vector3(pos.x, (0.05 * absf(sin(t * 12.0))) if moving else 0.0, pos.z)
		if moving:
			fig.rotation.y = float(at[1])
	# A base is reached or a tag made: the thump of the bag, the scoreboard when a run scores.
	for ei in plan.events.size():
		var se: Dictionary = plan.events[ei]
		var skey := "snd%d" % ei
		if t >= float(se.t) and not plan.get(skey, false):
			plan[skey] = true
			var sb := int(se.base)
			if sb >= 1 and sb <= 4 and se.kind != "run":
				sound.sfx("base_bag_thump", (Defense.HOME if sb == 4 else Baserunning.BASE_POS[sb]) as Vector3, -3.0)
	# The plate umpire rules on a play at home.
	for e in plan.events:
		if int(e.base) == 4 and t >= float(e.t) and not plan.get("ump_%s" % e.text, false):
			if e.text == "OUT":
				plan["ump_OUT"] = true
				crew.call_it("ump_out", 0.1, 1.0)
			elif e.text == "RUN" or e.text == "SAFE":
				plan["ump_%s" % e.text] = true
				if not plan.get("ump_safe_called", false):
					plan["ump_safe_called"] = true
					crew.call_it("ump_safe", 0.1, 1.0)
	# The base umpires rule on a play at their base.
	if base_umps != null:
		for ei in plan.events.size():
			var be: Dictionary = plan.events[ei]
			var eb := int(be.base)
			if eb >= 1 and eb <= 3 and (be.text == "OUT" or be.text == "SAFE") and t >= float(be.t):
				var bkey := "bu%d" % ei
				if not plan.get(bkey, false):
					plan[bkey] = true
					base_umps.call_it(eb, "ump_out" if be.text == "OUT" else "ump_safe")
	# Callouts: each event shows once its time has come.
	var shown := {}
	var slot := 0
	for e in plan.events:
		if t < float(e.t) or slot >= play_labels.size():
			continue
		var base := int(e.base)
		var where: Vector3 = Defense.HOME if base == 4 else (Baserunning.BASE_POS[base] as Vector3)
		if base == 0:
			where = (e.get("at", Defense.FIRST) as Vector3)
		var stack: int = shown.get(base, 0)
		shown[base] = stack + 1
		var color := Color(1.0, 0.35, 0.3)
		if e.kind == "safe" or e.kind == "run":
			color = Color(0.4, 1.0, 0.5)
		if e.text == "HOME RUN":
			color = Color(1.0, 0.85, 0.2)
		var lab := play_labels[slot]
		slot += 1
		# Label3D rebuilds its mesh on every assignment, even of the same value, so only touch
		# what actually changed (this runs every frame while a play is on).
		if lab.text != e.text:
			lab.text = e.text
		if lab.modulate != color:
			lab.modulate = color
		var lab_pos := Vector3(where.x, 3.0 + 0.5 * stack, where.z)
		if lab.position != lab_pos:
			lab.position = lab_pos
		if not lab.visible:
			lab.visible = true
	for i in range(slot, play_labels.size()):
		if play_labels[i].visible:
			play_labels[i].visible = false


func field_pos(play: Dictionary) -> Vector3:
	var p: Vector3 = play.get("field_pos", Vector3.ZERO)
	return Vector3(p.x, 0.0, p.z)
