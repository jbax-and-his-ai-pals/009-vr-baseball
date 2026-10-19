class_name InningCard
extends RefCounted
## The little card between innings: what just happened, the score, who is due up. Pure: it reads counters.

const ORDINALS := ["", "1ST", "2ND", "3RD", "4TH", "5TH", "6TH", "7TH", "8TH", "9TH"]


static func ordinal(n: int) -> String:
	return ORDINALS[n] if n >= 1 and n < ORDINALS.size() else "%dTH" % n


## `before` and `now` are {"hits", "k", "bb", "runs"} for the side that pitched/fielded; `score` the game's runs.
static func lines(inning: int, before: Dictionary, now: Dictionary, away_runs: int, home_runs: int, due_up: String) -> Array:
	var out: Array = ["END OF THE %s" % ordinal(inning)]
	out.append("Away %d   Home %d" % [away_runs, home_runs])
	var bits: Array = []
	var runs := int(now.get("runs", 0)) - int(before.get("runs", 0))
	var hits := int(now.get("hits", 0)) - int(before.get("hits", 0))
	var ks := int(now.get("k", 0)) - int(before.get("k", 0))
	var bbs := int(now.get("bb", 0)) - int(before.get("bb", 0))
	bits.append("%d run%s" % [runs, "" if runs == 1 else "s"])
	bits.append("%d hit%s" % [hits, "" if hits == 1 else "s"])
	if ks > 0:
		bits.append("%d K" % ks)
	if bbs > 0:
		bits.append("%d walk%s" % [bbs, "" if bbs == 1 else "s"])
	out.append("This half: " + ", ".join(bits))
	if due_up != "":
		out.append("Due up: " + due_up)
	return out
