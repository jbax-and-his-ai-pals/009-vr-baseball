extends SceneTree
## The running game inside the real game: steals resolve and update the scorebook, a throw over
## can pick a runner off, a throw at an empty base is a balk, and nothing gets stuck.
## Run: godot --headless --path . -s res://tests/running_game_test.gd

var _failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_failures += 1


func _settle(bp: Node, seconds: float) -> void:
	for i in int(seconds * 60.0):
		bp._process(1.0 / 60.0)


func _fresh() -> Node:
	var bp: Node = load("res://scenes/bullpen.tscn").instantiate()
	bp.menu_on_start = false
	root.add_child(bp)
	return bp


func _init() -> void:
	ThrowLogger.disabled = true
	var bp := _fresh()
	await process_frame
	var fast := Player.new()
	fast.speed = 95.0
	fast.aggression = 85.0
	var middling := Player.new()
	middling.speed = 45.0
	middling.aggression = 95.0

	# --- A steal: it starts when the delivery starts and ends in the scorebook.
	var went := 0
	var made := 0
	var caught := 0
	for trial in 60:
		var who: Player = fast if trial % 2 == 0 else middling
		bp._game.bases = [who, null, null]
		bp._game.outs = 0
		bp.plays.steal = {}
		bp.flight.batter_free_at = 1e9          # he takes every pitch, so only the steal happens
		bp.flow.aux_play = {}
		bp.flow.refresh_base_runners()
		bp.flow.batter_ready = true
		bp._last_delivery = 0.45 + 0.07 * (trial % 12)
		for k in 1500:
			bp.plays.on_delivery_start()
			if not bp.plays.steal.is_empty():
				break
		_check(not bp.plays.steal.is_empty(), "a fast, aggressive runner eventually breaks (trial %d)" % trial) if trial == 0 else null
		if bp.plays.steal.is_empty():
			continue
		went += 1
		var sb: int = bp._game.stolen_bases
		var cs: int = bp._game.caught_stealing
		bp.flight.debug_throw()
		_settle(bp, 9.0)
		if bp._game.stolen_bases > sb:
			made += 1
		if bp._game.caught_stealing > cs:
			caught += 1
		# Whatever happened, the game is ready to go on.
		bp._game.outs = 0
	print("  %d steals: %d safe, %d caught" % [went, made, caught])
	_check(went > 20 and made + caught >= went - 6, "steal attempts end in the scorebook as stolen base or caught stealing (%d of %d)" % [made + caught, went])
	_check(made > 0 and caught > 0, "some are safe and some are out")

	# --- A throw to first with a big lead sometimes picks him off.
	var picked := 0
	var tries := 80
	for i in tries:
		bp._game.bases = [fast, null, null]
		bp._game.outs = 0
		bp.flow.aux_play = {}
		bp.plays.since_throw = [8, 8, 8]
		bp.flow.refresh_base_runners()
		var before: int = bp._game.pickoffs
		bp.plays.do_pickoff(1, Vector3(0.0, 2.1, 17.0), Vector3(-26.0, 0.0, 3.0), 2.0)
		if bp._game.pickoffs > before:
			picked += 1
		_settle(bp, 1.5)
	print("  throws over to first with a big lead: %d of %d picked off" % [picked, tries])
	_check(picked > 4 and picked < tries - 15, "a throw over sometimes gets him (%d of %d)" % [picked, tries])

	# --- A throw to an empty base with a runner on is a balk.
	bp._game.bases = [fast, null, null]
	bp._game.outs = 0
	bp.flow.aux_play = {}
	bp.flow.refresh_base_runners()
	var balks_before: int = bp._game.balks
	bp.plays.do_pickoff(3, Vector3(0.0, 2.1, 17.0), Vector3(26.0, 0.0, 3.0), 2.0)
	_check(bp._game.balks == balks_before + 1 and bp._game.bases[1] != null, "throwing to an empty base with a runner on is a balk and he moves up")

	# --- The leads grow while you ignore the runners.
	bp._game.bases = [fast, null, null]
	bp.plays.since_throw = [0, 0, 0]
	bp.flow.refresh_base_runners()
	var short_lead: float = bp.plays.leads[0]
	bp.plays.since_throw = [7, 7, 7]
	bp.flow.refresh_base_runners()
	_check(bp.plays.leads[0] > short_lead + 0.5, "his lead grows when you stop throwing over (%.1f -> %.1f m)" % [short_lead, bp.plays.leads[0]])

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
