class_name RestResolver
extends RefCounted
## Applies a rest-node choice to the RunState (run-structure.md §5, ADR-0012,
## P2·07). At a rest the player picks ONE of:
##   heal     — restore `BattleConfig.rest_heal` HP to each living party member.
##   upgrade  — upgrade a SKILL (ADR-0026): swap the base id for its upgraded
##              variant (the card whose `upgrade_of` points at the base).
##
## Like the other run-layer resolvers (CardReward / EventResolver) it depends only
## on the content registry (a ContentDatabase) and mutates the RunState in place;
## it never touches combat. Heal caps at a member's base max HP and skips downed
## members, matching the event heal and post-combat heal conventions.

var _db: ContentDatabase


func _init(database: ContentDatabase = null) -> void:
	_db = database


# --- Public API -------------------------------------------------------------

## Heal each living member by `BattleConfig.rest_heal` (capped at base max HP, or
## current if already higher). Downed members are not healed by a rest.
func heal(run: RunState) -> void:
	var amount: int = _rest_heal()
	if amount <= 0:
		return
	for cid in run.party:
		var cur: int = int(run.party_hp.get(cid, 0))
		if cur <= 0:
			continue
		var cap: int = maxi(PartyStats.effective_max_hp(_db, run, cid), cur)
		run.party_hp[cid] = mini(cap, cur + amount)


## Upgrade the SKILL `base_card_id` (ADR-0026): every copy in the derived deck
## upgrades at once because copies are projections of the single collection
## entry. Searches the party in order for the owning member. Returns
## true if a base copy was present AND an upgrade variant exists; false otherwise
## (nothing changes). The first occurrence is replaced, preserving deck order.
func upgrade_card(run: RunState, base_card_id: StringName) -> bool:
	if _db == null:
		return false
	var idx: int = -1
	var owner: StringName = &""
	for cid in run.party:
		var coll: Variant = run.skill_collections.get(cid, [])
		if coll is Array and (coll as Array).has(base_card_id):
			owner = cid
			idx = 0
			break
	if idx < 0:
		return false
	var upgrade: CardData = _db.get_upgrade_for(base_card_id)
	if upgrade == null:
		return false
	var collection: Array = run.skill_collections.get(owner, [])
	var loadout: Array = run.active_loadouts.get(owner, [])
	for i in range(collection.size()):
		if StringName(String(collection[i])) == base_card_id:
			collection[i] = upgrade.id
			break  # upgrade ONE skill entry; its derived copies all follow
	for i in range(loadout.size()):
		if StringName(String(loadout[i])) == base_card_id:
			loadout[i] = upgrade.id
	return true


# --- Internals --------------------------------------------------------------

func _rest_heal() -> int:
	if _db == null:
		return 0
	var cfg: BattleConfig = _db.get_battle_config()
	return cfg.rest_heal if cfg != null else 0
