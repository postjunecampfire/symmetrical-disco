class_name CardPlay
extends RefCounted
## End-to-end card-play flow for a battle (task P1·07): the controller that takes
## a unit, a card, and a chosen target, VALIDATES the play, SPENDS energy, RESOLVES
## the card's effects in order, and ROUTES the card to the correct pile by its
## keywords. It is the seam between input/UI and the combat spine: it orchestrates
## BattleState (per-character energy pools ADR-0025, combatants, resolve_targets, apply_effects) and
## Deck (hand/piles, play_from_hand) without re-implementing either.
##
## Two entry points share one validation+spend+resolve core:
##   * play_card(unit, card, target)   — a drawn deck card. After resolving, the
##     card is routed via Deck.play_from_hand (discard / exhaust / return per its
##     keywords, ADR-0006). It must be IN THE UNIT'S HAND to be playable.
##   * play_innate(unit, card, target) — an innate Strike/Defend (ADR-0005). It
##     lives on the character's action bar, NOT the deck: it still costs energy and
##     resolves effects, but is NEVER moved to a deck pile.
##
## Validation (all enforced before any energy is spent or effect applied):
##   1. Tag    — only the owning character (matching character_tag) or a `neutral`
##               card may be played by a given unit (ADR-0004).
##   2. Energy — card.energy_cost must not exceed the ACTING unit's own pool (ADR-0025).
##   3. Target — the chosen target must satisfy the card's TargetSpec.target_type
##               (positionless, by kind — ADR-0013). Single-target kinds (enemy /
##               ally) require a Combatant of the right allegiance; group kinds
##               (all_allies / all_enemies / random_enemy) need no specific pick;
##               self must target the acting unit.
##
## Detection vs. reporting: the tested play path NEVER push_error()s on a rejected
## play. It returns a PlayResult (ok + reason) so callers/UI can react.

## The card_tag value that any unit may play (ADR-0004).
const TAG_NEUTRAL: StringName = &"neutral"


## Outcome of a play attempt. `ok` is true only when `reason` is empty; on a
## rejected play, `reason` describes why so UI can surface it.
class PlayResult extends RefCounted:
	var ok: bool = true
	var reason: String = ""

	func _init(why: String = "") -> void:
		reason = why
		ok = why.is_empty()


## The live battle this controller drives. Injected so one CardPlay serves a whole
## battle.
var battle: BattleState


func _init(battle_state: BattleState) -> void:
	battle = battle_state


# ============================================================================
#  Public entry points
# ============================================================================

## Play `card` from `unit`'s hand at `target`. Validates tag, energy, and the
## TargetSpec; on success spends energy, resolves the card's effects against the
## resolved target set, and routes the card to its pile via Deck.play_from_hand.
## Returns a PlayResult; on any rejection nothing is spent or applied.
func play_card(unit: Combatant, card: CardData, target: Variant) -> PlayResult:
	if unit == null:
		return PlayResult.new("CardPlay: null unit")
	if card == null:
		return PlayResult.new("CardPlay: null card")
	if not battle.deck_of(unit).hand.has(card):
		return PlayResult.new("CardPlay: card '%s' is not in %s's hand" % [card.id, unit.display_name])

	var check := _validate(unit, card, target)
	if not check.ok:
		return check

	_spend_and_resolve(unit, card, target)
	battle.deck_of(unit).play_from_hand(card)
	# ADR-0029: a played consumable is CONSUMED — record it so the run layer
	# (finish_combat) removes one copy from the party inventory. The card itself
	# was just routed to exhaust by its `exhaust` keyword.
	if card.card_kind == &"consumable":
		battle.consumed_items.append(card.id)
	return PlayResult.new()


## Play an innate action (Strike / Defend, ADR-0005) from `unit`'s action bar at
## `target`. Same validation + spend + resolution as a deck card, but the card is
## NEVER moved to a deck pile. The card must be `innate` and declared on the unit's
## CharacterData.innate_actions.
func play_innate(unit: Combatant, card: CardData, target: Variant) -> PlayResult:
	if unit == null:
		return PlayResult.new("CardPlay: null unit")
	if card == null:
		return PlayResult.new("CardPlay: null card")
	if not card.innate:
		return PlayResult.new("CardPlay: card '%s' is not an innate action" % card.id)
	if not _unit_has_innate(unit, card):
		return PlayResult.new(
			"CardPlay: '%s' is not on %s's action bar" % [card.id, unit.display_name]
		)

	var check := _validate(unit, card, target)
	if not check.ok:
		return check

	_spend_and_resolve(unit, card, target)
	return PlayResult.new()


# ============================================================================
#  Validation core (shared by both entry points)
# ============================================================================

## Run the three gates in a fixed order: tag, then energy, then target. Returns
## the first failure, or an ok PlayResult when every gate passes. No state is
## mutated here — validation is pure so callers can pre-check a play.
func _validate(unit: Combatant, card: CardData, target: Variant) -> PlayResult:
	# ADR-0029: `unplayable` (curses) — a dead draw unless the card says
	# otherwise. Gated before anything is spent, mirroring the hand-UI guard.
	if card.keywords.has(&"unplayable"):
		return PlayResult.new("CardPlay: '%s' is unplayable" % card.id)
	if not _tag_allows(unit, card):
		return PlayResult.new(
			"CardPlay: %s may not play '%s' (tag '%s')"
			% [unit.display_name, card.id, card.character_tag]
		)
	# ADR-0025: the ACTING unit's own pool pays — never the other character's.
	if card.energy_cost > battle.energy_of(unit):
		return PlayResult.new(
			"CardPlay: not enough energy for '%s' (cost %d, %s's pool %d)"
			% [card.id, card.energy_cost, unit.display_name, battle.energy_of(unit)]
		)
	var target_check := _validate_target(unit, card, target)
	if not target_check.ok:
		return target_check
	return PlayResult.new()


## character_tag gate (ADR-0004): a `neutral` card is playable by anyone; a tagged
## card is playable only by the unit whose CharacterData.id matches the tag.
func _tag_allows(unit: Combatant, card: CardData) -> bool:
	if card.character_tag == TAG_NEUTRAL:
		return true
	var char_data := unit.source_data as CharacterData
	if char_data == null:
		return false
	# Member ids are no longer class ids (ADR-0024): a synthesized member sheet
	# carries its chosen class in `tags`, so class-tagged cards stay playable.
	return char_data.id == card.character_tag or char_data.tags.has(card.character_tag)


## Whether `card` is declared on `unit`'s CharacterData.innate_actions.
func _unit_has_innate(unit: Combatant, card: CardData) -> bool:
	var char_data := unit.source_data as CharacterData
	if char_data == null:
		return false
	return char_data.innate_actions.has(card.id)


# ============================================================================
#  Target validation against the card's TargetSpec (§2.1, positionless)
# ============================================================================

## Validate `target` against `card.target.target_type` (ADR-0013). Single-target
## kinds require a Combatant of the right allegiance; `self` requires the acting
## unit; group kinds need no specific pick. Returns a PlayResult describing the
## first violation.
func _validate_target(unit: Combatant, card: CardData, target: Variant) -> PlayResult:
	var spec := card.target
	if spec == null:
		return PlayResult.new("CardPlay: card '%s' has no TargetSpec" % card.id)

	match spec.target_type:
		&"self":
			if not (target is Combatant) or target != unit:
				return _type_error(&"self", "must target the acting unit itself")
		&"ally":
			if not (target is Combatant):
				return _type_error(&"ally", "must target a unit")
			if (target as Combatant).team != unit.team:
				return _type_error(&"ally", "must target a friendly unit")
		&"enemy":
			if not (target is Combatant):
				return _type_error(&"enemy", "must target a unit")
			if (target as Combatant).team == unit.team:
				return _type_error(&"enemy", "must target an enemy unit")
		&"all_allies", &"all_enemies", &"random_enemy":
			# Group / random kinds resolve their own set; no specific pick needed.
			pass
		_:
			return PlayResult.new(
				"CardPlay: unknown target_type '%s'" % spec.target_type
			)
	return PlayResult.new()


## A uniform target_type rejection message.
func _type_error(target_type: StringName, why: String) -> PlayResult:
	return PlayResult.new("CardPlay: target_type '%s': %s" % [target_type, why])


# ============================================================================
#  Spend + resolve (shared)
# ============================================================================

## Spend the card's energy from the shared pool, resolve the card's TargetSpec
## into a concrete target set, and apply the effects to it via
## BattleState.apply_effects (which folds in strength/weak for damage). Called
## only after _validate has passed.
func _spend_and_resolve(unit: Combatant, card: CardData, target: Variant) -> void:
	battle.spend_energy(unit, card.energy_cost)  # ADR-0025: owner pays
	# M3 on_card_played relics: count the play BEFORE resolution so the current
	# card is the Nth — "your 3rd and later cards each turn" includes the 3rd.
	battle.cards_played_this_turn += 1
	var targets: Array[Combatant] = battle.resolve_targets(card.target, unit, target)
	# EVERY player card scales with its actor's sheet (ADR-0014). The old
	# neutral-flat rule (ADR-0016) existed to dodge per-actor routing in the
	# SHARED deck; under per-member derived decks (ADR-0026) the actor is always
	# the deck's owner, so basics (Strike/Defend) scale like everything else —
	# without this, post-0026 Defend granted 0 block.
	battle.apply_effects(unit, targets, card.effects, true)
	# Bleed (M3): playing a card is an ACT — a bleeding caster pays in blood after
	# the card resolves (one proc per play, stacks as unblockable damage, then -1).
	battle.on_unit_acted(unit)
