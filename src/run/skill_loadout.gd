class_name SkillLoadout
extends RefCounted
## Derived decks from active skill loadouts (ADR-0026). The player curates
## SKILLS, not cards: each member has a skill COLLECTION (every skill acquired
## this run), an ACTIVE LOADOUT (up to `BattleConfig.skill_slots` skill ids
## chosen from the collection), and a DERIVED DECK — the deterministic
## projection of the loadout into card ids:
##
##   * each skill contributes copies by its card's rarity (common 3 / uncommon 2
##     / rare 1 — scarcity and ADR-0020 power tiers line up by construction);
##   * if the result is short of `BattleConfig.derived_deck_floor` (20), it is
##     auto-filled with alternating basic Strike/Defend copies — the floor IS
##     the no-playable-card insurance, and thinning it out is the run's arc;
##   * basics are SLOTLESS: they enter only as auto-fill, never via the loadout;
##   * an injected non-skill layer (ADR-0029) rides on top of the projection:
##     per-member CURSES count toward the floor (displacing fill basics) and the
##     party CONSUMABLE inventory injects on top of it.
##
## A skill IS a CardData id (no separate entity): rarity lives on the card, and
## upgrading a skill swaps the id in the collection/loadout, upgrading every
## derived copy at once. All knobs live on BattleConfig (ADR-0003).

## The slotless auto-fill basics (ADR-0026 reverses ADR-0005: these are ordinary
## common cards now, not innate actions).
const FILL_BASICS: Array[StringName] = [&"strike", &"defend"]


## Copies contributed by one skill of `rarity` (the per-skill cooldown dial).
static func copies_for_rarity(rarity: StringName, config: BattleConfig) -> int:
	match rarity:
		&"rare":
			return config.copies_rare
		&"uncommon":
			return config.copies_uncommon
		_:
			return config.copies_common


## Project `loadout` (skill/card ids, order preserved) into the derived deck:
## copies by rarity, then alternating Strike/Defend auto-fill up to the floor.
## Unknown ids are skipped (id validity is the loader's job). Deterministic:
## same loadout + same data => same list (the battle Deck shuffles separately).
##
## Injected card layer (ADR-0029):
##   * `curses` COUNT toward the floor — below the floor each curse DISPLACES one
##     Strike/Defend auto-fill card (alternation preserved for the remainder);
##     at/above the floor they add on top (the deck swells). Removal restores a
##     basic, which is what makes shop curse-removal a real service.
##   * `consumables` inject ON TOP — never counted toward the floor, so items
##     never crowd out the draw economy's basics.
##   * `floor_reduction` (relic `floor_reduction` effects, summed by the caller)
##     lowers the auto-fill floor, clamped at config.derived_deck_floor_min —
##     the earned path back to the small-deck archetype.
##
## M3 derivation-modifier relics (summed/queried by the caller via RelicEngine):
##   * `extra_rare` — each RARE skill in the loadout contributes +N extra copies
##     (extra_copy_rare).
##   * `extra_first` — the FIRST resolvable loadout entry contributes +N extra
##     copies (extra_copy_first; "choose a skill" UI deliberately deferred — the
##     first active skill is the v1 pick).
##   * `upgraded_basics` — the auto-fill basics derive as their upgraded variants
##     (strike+ / defend+ via ContentDatabase.get_upgrade_for); missing upgrade
##     cards fall back to the base id, so the flag is always safe.
static func derive_deck(
	loadout: Array[StringName],
	db: ContentDatabase,
	curses: Array[StringName] = [],
	consumables: Array[StringName] = [],
	floor_reduction: int = 0,
	extra_rare: int = 0,
	extra_first: int = 0,
	upgraded_basics: bool = false
) -> Array[StringName]:
	var config: BattleConfig = db.get_battle_config()
	var out: Array[StringName] = []
	var first_seen: bool = false
	for skill_id in loadout:
		var card: CardData = db.get_card(skill_id)
		if card == null:
			continue
		var copies: int = copies_for_rarity(card.rarity, config)
		if card.rarity == &"rare":
			copies += maxi(0, extra_rare)
		if not first_seen:
			copies += maxi(0, extra_first)
			first_seen = true
		for _i in range(copies):
			out.append(skill_id)
	# Curses BEFORE the fill loop: they occupy floor slots (displacement).
	for curse_id in curses:
		if db.get_card(curse_id) != null:
			out.append(curse_id)
	var floor_target: int = effective_floor(config, floor_reduction)
	var fill_ids: Array[StringName] = []
	for base_id in FILL_BASICS:
		var fill_id: StringName = base_id
		if upgraded_basics:
			var up: CardData = db.get_upgrade_for(base_id)
			if up != null:
				fill_id = up.id
		fill_ids.append(fill_id)
	var fill_i: int = 0
	while out.size() < floor_target:
		out.append(fill_ids[fill_i % fill_ids.size()])
		fill_i += 1
	# Consumables AFTER the fill loop: always on top of the floor.
	for item_id in consumables:
		if db.get_card(item_id) != null:
			out.append(item_id)
	return out


## The auto-fill floor after relic floor_reduction (ADR-0029), never below
## config.derived_deck_floor_min.
static func effective_floor(config: BattleConfig, floor_reduction: int) -> int:
	return maxi(
		config.derived_deck_floor_min,
		config.derived_deck_floor - maxi(0, floor_reduction)
	)


## Add `skill_id` to a member's collection (and auto-activate it while the
## loadout has a free slot — the v1 policy until the loadout screen lands).
## Duplicates are allowed in the collection (a second copy of a skill is a
## second loadout candidate). Returns true if the skill was also activated.
static func acquire(
	collection: Array[StringName],
	loadout: Array[StringName],
	skill_id: StringName,
	config: BattleConfig
) -> bool:
	collection.append(skill_id)
	if loadout.size() < config.skill_slots:
		loadout.append(skill_id)
		return true
	return false


## Replace every copy of `old_id` with `new_id` in collection + loadout (skill
## upgrade: all derived copies upgrade at once, ADR-0026). Returns the number of
## collection entries swapped.
static func replace_skill(
	collection: Array[StringName], loadout: Array[StringName],
	old_id: StringName, new_id: StringName
) -> int:
	var swapped: int = 0
	for i in range(collection.size()):
		if collection[i] == old_id:
			collection[i] = new_id
			swapped += 1
	for i in range(loadout.size()):
		if loadout[i] == old_id:
			loadout[i] = new_id
	return swapped


## Remove ONE copy of `skill_id` from collection (and loadout if active).
## Returns true if a copy was removed.
static func remove_skill(
	collection: Array[StringName], loadout: Array[StringName], skill_id: StringName
) -> bool:
	var idx: int = collection.find(skill_id)
	if idx == -1:
		return false
	collection.remove_at(idx)
	var lidx: int = loadout.find(skill_id)
	if lidx != -1:
		loadout.remove_at(lidx)
	return true
