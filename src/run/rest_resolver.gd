class_name RestResolver
extends RefCounted
## Applies a rest-node choice to the RunState (run-structure.md §5, ADR-0012,
## P2·07). At a rest the player picks ONE of:
##   heal     — restore `BattleConfig.rest_heal` HP to each living party member.
##   upgrade  — replace one copy of a base card in run_deck with its upgraded
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


## Upgrade ONE copy of `base_card_id` in run_deck to its upgraded variant. Returns
## true if a base copy was present AND an upgrade variant exists; false otherwise
## (nothing changes). The first occurrence is replaced, preserving deck order.
func upgrade_card(run: RunState, base_card_id: StringName) -> bool:
	if _db == null:
		return false
	var idx: int = run.run_deck.find(base_card_id)
	if idx < 0:
		return false
	var upgrade: CardData = _db.get_upgrade_for(base_card_id)
	if upgrade == null:
		return false
	run.run_deck[idx] = upgrade.id
	return true


# --- Internals --------------------------------------------------------------

func _rest_heal() -> int:
	if _db == null:
		return 0
	var cfg: BattleConfig = _db.get_battle_config()
	return cfg.rest_heal if cfg != null else 0
