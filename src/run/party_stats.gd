class_name PartyStats
extends RefCounted
## Shared derivation of a party member's EFFECTIVE maximum HP from the run state —
## the single source of truth so every heal caps at the same ceiling (P2·12 review
## fix #1). A member's max HP is the class base plus the same bonuses the assembler
## stacks into a fight:
##   base       = CharacterData.max_hp (CON × hp_per_con, ADR-0014)
##   + race     = RaceData.con_mod × hp_per_con (ADR-0015)
##   + allocated = allocated CON points × hp_per_con (P3·05)
##   + relics   = sum of passive `max_hp_up` relic amounts (P2·12)
## Computed from RunState alone (races now persist there), so RunController and the
## event / rest resolvers all agree.


## Effective max HP of `cid` for the current `run`. Falls back to the class base
## (or 0 if the character is unknown).
static func effective_max_hp(db: ContentDatabase, run: RunState, cid: StringName) -> int:
	if db.get_character(cid) == null and not run.party.has(cid):
		return 0  # unknown id: neither a class-keyed legacy member nor in the party
	var ch: CharacterData = PartyMember.character_for(db, run, cid)
	if ch == null:
		return 0
	var cfg: BattleConfig = db.get_battle_config()
	var per_con: int = cfg.hp_per_con if cfg != null else 2

	var total: int = ch.max_hp

	var race: RaceData = db.get_race(run.party_races.get(cid, &""))
	if race != null:
		total += race.con_mod * per_con

	var alloc_v: Variant = run.allocated_stats.get(cid, {})
	if alloc_v is Dictionary:
		total += int((alloc_v as Dictionary).get(&"con", 0)) * per_con

	for rid in run.relics:
		var relic: RelicData = db.get_relic(rid)
		if relic != null and relic.trigger == &"passive" and relic.effect == &"max_hp_up":
			total += relic.amount

	return total
