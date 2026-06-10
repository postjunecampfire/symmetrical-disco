class_name MetaProgress
extends RefCounted
## Cross-run meta logic (P3·08, ADR-0018): record acts cleared, decide when a
## cash-out is available, bank a chosen boon, and apply banked boons to a fresh
## run. Operates on a MetaState (persistent) + the ContentDatabase; the caller owns
## saving the MetaState. Boons are mostly-horizontal and apply to EVERY future run.

var db: ContentDatabase
var meta: MetaState


func _init(database: ContentDatabase, meta_state: MetaState) -> void:
	db = database
	meta = meta_state


func _threshold() -> int:
	var cfg: BattleConfig = db.get_battle_config()
	return cfg.meta_cash_out_acts if cfg != null else 9


## Record one cleared act (call on a run win).
func record_act_cleared() -> void:
	meta.acts_cleared += 1


## True when the player has earned a not-yet-claimed cash-out: the Nth boon unlocks
## after `meta_cash_out_acts * N` total acts cleared.
func cash_out_available() -> bool:
	return meta.acts_cleared >= _threshold() * (meta.boons.size() + 1)


## The boon options the player may choose from at a cash-out (all defined BoonData,
## sorted for a stable menu). The player picks ONE per available cash-out.
func boon_choices() -> Array[BoonData]:
	var out: Array[BoonData] = []
	for key: Variant in db.boons.keys():
		out.append(db.boons[key])
	out.sort_custom(func(a: BoonData, b: BoonData) -> bool: return String(a.id) < String(b.id))
	return out


## Bank `boon_id` if a cash-out is available and it's a real boon. Returns true on
## success (caller should then save the MetaState).
func cash_out(boon_id: StringName) -> bool:
	if not cash_out_available() or db.get_boon(boon_id) == null:
		return false
	meta.boons.append(boon_id)
	return true


## Apply every banked boon to a freshly-started `run` (call right after start_run):
##   relic -> run.relics; card -> the first member's skill collection (ADR-0026);
##   stat -> each member's allocated_stats
##   (so it flows through the assembler / effective-HP); unlock -> no run effect yet.
func apply_boons(run: RunState) -> void:
	for boon_id in meta.boons:
		var boon: BoonData = db.get_boon(boon_id)
		if boon == null:
			continue
		match boon.kind:
			&"relic":
				if boon.target != &"" and not run.relics.has(boon.target):
					run.relics.append(boon.target)
			&"card":
				if boon.target != &"":
					if not run.party.is_empty():
						var first: StringName = run.party[0]
						if not (run.skill_collections.get(first) is Array):
							run.skill_collections[first] = []
						if not (run.active_loadouts.get(first) is Array):
							run.active_loadouts[first] = []
						(run.skill_collections[first] as Array).append(boon.target)
						if (run.active_loadouts[first] as Array).size() < 10:
							(run.active_loadouts[first] as Array).append(boon.target)
			&"stat":
				for cid in run.party:
					if not run.allocated_stats.has(cid):
						run.allocated_stats[cid] = {&"str": 0, &"dex": 0, &"con": 0, &"int": 0}
					var a: Dictionary = run.allocated_stats[cid]
					a[boon.target] = int(a.get(boon.target, 0)) + boon.amount
			_:
				pass  # unlock: recorded only (no locked content yet)
