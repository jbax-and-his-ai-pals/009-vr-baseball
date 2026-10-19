class_name SessionRecorder
extends RefCounted
## What the game writes down for the logs (see GameLog and ThrowLogger): events of play, a snapshot of the whole situation for a
## flagged moment or a spike, the frame-time summary, and one line per throw you make. The scene (`host`) owns the game.

var host                                    # the bullpen scene (untyped: its members are reached by name)

var logger := ThrowLogger.new()
var perf_sum := 0.0
var perf_frames := 0
var perf_max := 0.0
var perf_spikes := 0
var mark_pressed := false


## A short picture of the game for a log line: inning, outs, count, who is on.
func brief() -> Dictionary:
	if host._game == null:
		return {}
	var on = ""
	for i in 3:
		on += str(i + 1) if host._game.bases[i] != null else "-"
	return {"inn": host._game.inning, "outs": host._game.outs, "count": "%d-%d" % [host._game.balls, host._game.strikes], "on": on,
		"score": "%d-%d" % [host._game.runs, host._game.home_score]}


## Everything a bug report might need.
func snapshot() -> Dictionary:
	var d = brief()
	if host._game == null:
		return d
	var names = []
	for i in 3:
		names.append(host._game.bases[i].name if host._game.bases[i] is Player else ("?" if host._game.bases[i] != null else ""))
	d["bases"] = names
	d["batter"] = host._batter_player.name if host._batter_player else ""
	d["pitches"] = host._game.pitch_count
	d["ready"] = host.flow.batter_ready
	d["batter_visible"] = host._batter.visible if host._batter else null
	d["walk_on"] = not host._walk_on.is_empty()
	d["aux"] = not host.flow.aux_play.is_empty()
	d["steal"] = not host.plays.steal.is_empty()
	d["hits_alive"] = host.flight.hits.size()
	d["plays_open"] = host.flow.play_in_progress()
	d["flights"] = host.plays.flights.size()
	d["unready_for"] = snappedf(host.flow.unready_for, 0.01)
	d["delivery_start"] = host._delivery_start
	d["last_delivery"] = snappedf(host._last_delivery, 0.01)
	d["leads"] = host.plays.leads
	d["since_throw"] = host.plays.since_throw
	d["mode"] = host._mode.name if host._mode else ""
	d["game_time"] = snappedf(host._game_time, 0.01)
	d["frame_ms"] = snappedf(host._governor.ema_ms, 0.1)
	d["quality_level"] = host._governor.level
	return d


func record(kind: String, data: Dictionary = {}) -> void:
	data["s"] = brief()
	GameLog.event(kind, data)


## Flag this moment in the log (B on your throwing hand, F on a desktop).
func mark_moment() -> void:
	GameLog.mark("player_flag", snapshot())
	host._sfx("ui_mark_moment")
	host.hud.show_notice("Marked this moment in the log", true)


## Frame times: a line every five seconds, and one for any frame over 60 ms with what was going on.
func log_frame(delta: float) -> void:
	perf_sum += delta
	perf_frames += 1
	perf_max = maxf(perf_max, delta)
	if delta > 0.06 and host._game_time > 3.0:
		perf_spikes += 1
		var d = snapshot()
		d["ms"] = snappedf(delta * 1000.0, 0.1)
		GameLog.event("spike", d)
	if perf_sum >= 5.0:
		GameLog.event("perf", {"fps": snappedf(perf_frames / perf_sum, 0.1),
			"ms_avg": snappedf(perf_sum / perf_frames * 1000.0, 0.1), "ms_max": snappedf(perf_max * 1000.0, 0.1),
			"spikes": perf_spikes, "draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
			"level": host._governor.level, "xr": host._xr_active, "hits": host.flight.hits.size(), "pitches": host.flight.pitches.size(), "s": brief()})
		perf_sum = 0.0
		perf_frames = 0
		perf_max = 0.0
		perf_spikes = 0


## One JSON line per throw (see HumanPitcher.log_entry): the scene supplies what only it knows.
func log_throw(pitch: LivePitch, from: Vector3, release_t: float, latency: float, r: Dictionary) -> void:
	var ctx = {"head_pos": host._camera.global_position, "head_fwd": -host._camera.global_transform.basis.z,
		"hand_fwd": (host._hand.global_transform.basis * HumanPitcher.FORWARD) if host._hand else HumanPitcher.FORWARD,
		"tag": host._current_tag(), "auto": host.release_mode == host.ReleaseMode.AUTO_PEAK, "batter_profile": host._batter_ai.profile.name,
		"game": {"inning": host._game.inning, "outs": host._game.outs, "balls": host._game.balls, "strikes": host._game.strikes,
			"bases": [host._game.bases[0] != null, host._game.bases[1] != null, host._game.bases[2] != null],
			"batter": host._batter_player.name if host._batter_player else ""}}
	logger.record(host._human.log_entry(ctx, pitch, from, release_t, latency, r.est, r.scaled, r.spin, r.funnel, r.shape))
