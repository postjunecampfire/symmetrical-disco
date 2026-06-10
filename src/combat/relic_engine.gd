class_name RelicEngine
extends RefCounted
## Applies relic effects at their triggers (run-structure.md §7/§8, P2·12). This is
## an ADDITIVE wrapper around an assembled battle — it never edits BattleState's
## resolved rules; the assembler calls the combat_start / passive hooks once,
## EncounterBattle calls the turn_start hook at each player turn, and the M3
## combat-trigger hooks (on_kill / on_curse_drawn / hp_threshold /
## on_status_applied / on_card_played) fire from BattleState's virtual seams via
## EncounterBattle's overrides.
##
## It depends only on BattleState + RelicData (no run layer), so it lives in
## src/combat. Each hook ignores relics whose trigger doesn't match, so the same
## relic list can be handed to every hook. RUN-LAYER effects (economy / sight /
## derivation) are STATIC queries summed here and consumed where the run system
## needs them (the `floor_reduction` pattern) — no battle involved.

## on_card_played: the play index (1-based, per player turn) from which
## combo_damage relics add their bonus — "your 3rd and later cards each turn".
const COMBO_THRESHOLD: int = 3
## shop_discount stacks across relics but is capped so prices never hit zero-ish.
const SHOP_DISCOUNT_CAP: int = 60
## curse_removal_discount cap (applies after shop_discount).
const CURSE_REMOVAL_DISCOUNT_CAP: int = 90

## on_status_applied effect id -> the status it amplifies.
const AMPLIFY_EFFECTS: Dictionary = {
	&"amplify_burn": &"burn",
	&"amplify_bleed": &"bleed",
	&"amplify_poison": &"poison",
}


## combat_start relics: gain_block / add_strength to each living party member.
func apply_combat_start(battle: BattleState, relics: Array) -> void:
	for relic in relics:
		if relic == null or relic.trigger != &"combat_start":
			continue
		match relic.effect:
			&"gain_block":
				for unit in battle.living_players():
					unit.block += relic.amount
			&"add_strength":
				for unit in battle.living_players():
					unit.add_status_stacks(&"strength", relic.amount)
			_:
				pass


## passive relics: max_hp_up raises each member's max HP (and current HP so a fresh
## spawn stays full). Applied before carried HP so the carried value clamps to the
## raised max. (The other `passive` effects are run-layer queries — see the statics.)
func apply_passive(battle: BattleState, relics: Array) -> void:
	for relic in relics:
		if relic == null or relic.trigger != &"passive":
			continue
		if relic.effect == &"max_hp_up":
			for unit in battle.living_players():
				unit.max_hp += relic.amount
				unit.hp += relic.amount


## turn_start relics: gain_energy / draw_extra, applied after the base
## start_player_turn has refilled energy and drawn the hand.
func apply_turn_start(battle: BattleState, relics: Array) -> void:
	for relic in relics:
		if relic == null or relic.trigger != &"turn_start":
			continue
		match relic.effect:
			&"gain_energy":
				# ADR-0025 provisional: a party-level energy relic credits the
				# FIRST living player (the origin character) until relics get
				# holders — crediting every pool would double its value.
				battle.add_energy(relic.amount)
			&"draw_extra":
				battle.draw_cards(relic.amount)
			_:
				pass


# --- M3 combat triggers -------------------------------------------------------

## on_kill relics: fired once per ENEMY death (any cause — attacks, DoTs, Charm
## executes). gain_block credits the whole living party; gain_energy credits the
## first pool (the party-level provisional, ADR-0025); gain_gold banks run gold
## (finish_combat credits it).
func apply_on_kill(battle: BattleState, relics: Array) -> void:
	for relic in relics:
		if relic == null or relic.trigger != &"on_kill":
			continue
		match relic.effect:
			&"gain_block":
				for unit in battle.living_players():
					battle.add_block(unit, relic.amount)
			&"gain_energy":
				battle.add_energy(relic.amount)
			&"gain_gold":
				battle.add_gold(relic.amount)
			_:
				pass


## on_curse_drawn relics: fired when a player unit draws a `curse` card — the
## softener that turns junk draws into tempo. Credits the DRAWER (their pool /
## their block), not the party.
func apply_on_curse_drawn(battle: BattleState, relics: Array, unit: Combatant) -> void:
	if unit == null:
		return
	for relic in relics:
		if relic == null or relic.trigger != &"on_curse_drawn":
			continue
		match relic.effect:
			&"gain_energy":
				battle.add_energy(relic.amount, unit)
			&"gain_block":
				battle.add_block(unit, relic.amount)
			_:
				pass


## hp_threshold relics: fired the FIRST time a member falls below half HP each
## combat (BattleState tracks the once-per-unit latch). Credits THAT member.
func apply_hp_threshold(battle: BattleState, relics: Array, unit: Combatant) -> void:
	if unit == null:
		return
	for relic in relics:
		if relic == null or relic.trigger != &"hp_threshold":
			continue
		match relic.effect:
			&"gain_block":
				battle.add_block(unit, relic.amount)
			&"add_strength":
				unit.add_status_stacks(&"strength", relic.amount)
			_:
				pass


## on_status_applied: the extra stacks to add when `status_id` lands on an enemy
## (amplify_burn / amplify_bleed / amplify_poison). The caller adds the bonus via
## Combatant.add_status_stacks DIRECTLY (not apply_status) so the bonus never
## re-triggers itself.
static func status_bonus(relics: Array, status_id: StringName) -> int:
	var total: int = 0
	for relic in relics:
		if relic == null or relic.trigger != &"on_status_applied":
			continue
		if AMPLIFY_EFFECTS.get(relic.effect, &"") == status_id:
			total += maxi(0, relic.amount)
	return total


## on_card_played: the flat damage bonus for the current play, given how many
## cards the party has played this turn (1-based, including the current one).
## Zero until the COMBO_THRESHOLD'th play.
static func combo_bonus(relics: Array, cards_played_this_turn: int) -> int:
	if cards_played_this_turn < COMBO_THRESHOLD:
		return 0
	var total: int = 0
	for relic in relics:
		if relic != null and relic.trigger == &"on_card_played" \
				and relic.effect == &"combo_damage":
			total += maxi(0, relic.amount)
	return total


# --- Run-layer queries (passive effects, no battle involved) -------------------

## Total derived-deck floor reduction the run's relics grant (ADR-0029, the
## `floor_reduction` passive effect). Consumed at deck DERIVATION — RunController
## sums it here and hands it to SkillLoadout.derive_deck, which clamps at
## BattleConfig.derived_deck_floor_min. Static: no battle is involved.
static func floor_reduction_total(relics: Array) -> int:
	return _sum_effect(relics, &"floor_reduction")


## Extra derived copies for each RARE skill in a loadout (extra_copy_rare).
static func extra_rare_copies(relics: Array) -> int:
	return _sum_effect(relics, &"extra_copy_rare")


## Extra derived copies for each member's FIRST active skill (extra_copy_first —
## the choose-a-skill UI is deliberately deferred; "first active" is the v1 pick).
static func extra_first_copies(relics: Array) -> int:
	return _sum_effect(relics, &"extra_copy_first")


## Whether auto-fill basics derive as their upgraded variants (upgrade_basics).
static func upgrades_basics(relics: Array) -> bool:
	return _has_effect(relics, &"upgrade_basics")


## Extra run gold after each WON combat (gold_on_win; RunController.finish_combat).
static func gold_on_win_total(relics: Array) -> int:
	return _sum_effect(relics, &"gold_on_win")


## Run gold granted at each rest node (gold_on_rest; RunController.resolve_rest).
static func gold_on_rest_total(relics: Array) -> int:
	return _sum_effect(relics, &"gold_on_rest")


## Percentage bonus to treasure gold piles (gold_pile_bonus; Shop.treasure_roll).
static func gold_pile_bonus_percent(relics: Array) -> int:
	return _sum_effect(relics, &"gold_pile_bonus")


## Total shop discount percentage (shop_discount), capped at SHOP_DISCOUNT_CAP.
## Shop.build_offer applies it to every price on the shelf.
static func shop_discount_percent(relics: Array) -> int:
	return mini(SHOP_DISCOUNT_CAP, _sum_effect(relics, &"shop_discount"))


## Extra discount on the shop curse-removal service (curse_removal_discount),
## applied AFTER shop_discount, capped at CURSE_REMOVAL_DISCOUNT_CAP.
static func curse_removal_discount_percent(relics: Array) -> int:
	return mini(CURSE_REMOVAL_DISCOUNT_CAP, _sum_effect(relics, &"curse_removal_discount"))


## Whether hidden ("?") map nodes render revealed (reveal_map; map_view fog check).
static func reveals_map(relics: Array) -> bool:
	return _has_effect(relics, &"reveal_map")


## Whether the act's boss encounter is previewed on the map header (reveal_boss).
static func reveals_boss(relics: Array) -> bool:
	return _has_effect(relics, &"reveal_boss")


# --- Internals ------------------------------------------------------------------

static func _sum_effect(relics: Array, effect: StringName) -> int:
	var total: int = 0
	for relic in relics:
		if relic != null and relic.effect == effect:
			total += maxi(0, relic.amount)
	return total


static func _has_effect(relics: Array, effect: StringName) -> bool:
	for relic in relics:
		if relic != null and relic.effect == effect:
			return true
	return false
