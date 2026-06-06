class_name CardPlay
extends RefCounted
## End-to-end card-play flow for a battle (task P1·07): the controller that takes
## a unit, a card, and a chosen target, VALIDATES the play, SPENDS energy, RESOLVES
## the card's effects in order, and ROUTES the card to the correct pile by its
## keywords. It is the seam between input/UI and the already-built combat spine:
## it orchestrates BattleState (shared energy pool, combatants, grid, apply_effects)
## and Deck (hand/piles, play_from_hand) without re-implementing either.
##
## Two entry points share one validation+spend+resolve core:
##   * play_card(unit, card, target)   — a drawn deck card. After resolving, the
##     card is routed via Deck.play_from_hand (discard / exhaust / return per its
##     keywords, ADR-0006). It must be IN THE UNIT'S HAND to be playable.
##   * play_innate(unit, card, target) — an innate Strike/Defend (ADR-0005). It
##     lives on the character's action bar, NOT the deck: it still costs energy and
##     resolves effects, but is NEVER moved to discard/exhaust/hand. The card must
##     be declared on the unit's CharacterData.innate_actions.
##
## Validation (all enforced before any energy is spent or effect applied):
##   1. Energy   — card.energy_cost must not exceed the shared BattleState pool.
##   2. Tag      — only the owning character (matching character_tag) or a
##                 `neutral` card may be played by a given unit (ADR-0004).
##   3. Target   — the chosen target must satisfy the card's TargetSpec:
##                 correct target_type (self / ally / enemy / any_unit / tile /
##                 empty_tile) AND within `range` tiles (orthogonal / Manhattan
##                 distance, consistent with the 4-connected grid) of the unit.
##
## Detection vs. reporting: the tested play path NEVER push_error()s on a rejected
## play. It returns a PlayResult (ok + reason) so callers/UI can react, mirroring
## the ContentDatabase / EffectResolver detection-vs-report split.

## The TargetSpec.target_type values (data-schemas.md §2.1). Named so the
## validation reads as semantics, not loose strings, and the set lives in one place.
const TARGET_SELF: StringName = &"self"
const TARGET_ALLY: StringName = &"ally"
const TARGET_ENEMY: StringName = &"enemy"
const TARGET_ANY_UNIT: StringName = &"any_unit"
const TARGET_TILE: StringName = &"tile"
const TARGET_EMPTY_TILE: StringName = &"empty_tile"

## The card_tag value that any unit may play (ADR-0004).
const TAG_NEUTRAL: StringName = &"neutral"


## Outcome of a play attempt. `ok` is true only when `reason` is empty; on a
## rejected play, `reason` describes why so UI can surface it. Building one never
## emits an engine error, so the rejection paths stay unit-testable.
class PlayResult extends RefCounted:
	var ok: bool = true
	var reason: String = ""

	func _init(why: String = "") -> void:
		reason = why
		ok = why.is_empty()


## The live battle this controller drives. Owns the shared energy pool, the
## combatants, the grid, the deck, and apply_effects() — all of which the play
## flow reads and mutates. Injected so one CardPlay serves a whole battle.
var battle: BattleState


func _init(battle_state: BattleState) -> void:
	battle = battle_state


# ============================================================================
#  Public entry points
# ============================================================================

## Play `card` from `unit`'s hand at `target`. Validates energy, character_tag,
## and the TargetSpec; on success spends energy, resolves the card's effects in
## order, and routes the card to its pile via Deck.play_from_hand (discard /
## exhaust / return per keywords). Returns a PlayResult; on any rejection nothing
## is spent or applied and ok == false with a reason.
func play_card(unit: Combatant, card: CardData, target: Variant) -> PlayResult:
	if unit == null:
		return PlayResult.new("CardPlay: null unit")
	if card == null:
		return PlayResult.new("CardPlay: null card")
	# A deck card must actually be in the hand to be playable.
	if not battle.deck.hand.has(card):
		return PlayResult.new("CardPlay: card '%s' is not in hand" % card.id)

	var check := _validate(unit, card, target)
	if not check.ok:
		return check

	_spend_and_resolve(unit, card, target)
	# Route the card by its keywords (discard / exhaust / return), ADR-0006.
	battle.deck.play_from_hand(card)
	return PlayResult.new()


## Play an innate action (Strike / Defend, ADR-0005) from `unit`'s action bar at
## `target`. Same validation + energy spend + effect resolution as a deck card,
## but the card is NEVER moved to a deck pile (it does not live in the deck). The
## card must be `innate` and declared on the unit's CharacterData.innate_actions.
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
	# Innate actions never touch the deck (no discard / exhaust / hand routing).
	return PlayResult.new()


# ============================================================================
#  Validation core (shared by both entry points)
# ============================================================================

## Run the three gates in a fixed order: tag, then energy, then target. Returns
## the first failure, or an ok PlayResult when every gate passes. No state is
## mutated here — validation is pure so callers can pre-check a play (e.g. to grey
## out an illegal card) without side effects.
func _validate(unit: Combatant, card: CardData, target: Variant) -> PlayResult:
	if not _tag_allows(unit, card):
		return PlayResult.new(
			"CardPlay: %s may not play '%s' (tag '%s')"
			% [unit.display_name, card.id, card.character_tag]
		)
	if card.energy_cost > battle.energy:
		return PlayResult.new(
			"CardPlay: not enough energy for '%s' (cost %d, pool %d)"
			% [card.id, card.energy_cost, battle.energy]
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
	return char_data.id == card.character_tag


## Whether `card` is declared on `unit`'s CharacterData.innate_actions. Identifies
## the card by its id so a Combatant built from data recognises its own innates.
func _unit_has_innate(unit: Combatant, card: CardData) -> bool:
	var char_data := unit.source_data as CharacterData
	if char_data == null:
		return false
	return char_data.innate_actions.has(card.id)


# ============================================================================
#  Target validation against the card's TargetSpec (§2.1)
# ============================================================================

## Validate `target` against `card.target`: the resolved tile must be in range
## (orthogonal / Manhattan distance from the unit), and the target_type must be
## satisfied (a unit of the right allegiance for unit types; an empty/any tile for
## tile types). Returns a PlayResult describing the first violation.
func _validate_target(unit: Combatant, card: CardData, target: Variant) -> PlayResult:
	var spec := card.target
	if spec == null:
		return PlayResult.new("CardPlay: card '%s' has no TargetSpec" % card.id)

	var resolved: Variant = _target_tile(target)
	if resolved == null:
		return PlayResult.new("CardPlay: target is neither a unit nor a tile")
	# `resolved` is a Variant from _target_tile; past the null guard it is known to
	# be a Vector2i. Bind it to a typed local so the Vector2i-typed helpers below
	# receive a statically-typed value (Godot rejects Variant -> typed-param flow
	# at load time).
	var tile: Vector2i = resolved

	# Range: orthogonal (Manhattan) distance from the acting unit. range 0 means
	# self / no range (only the unit's own tile qualifies). Consistent with the
	# grid's 4-connected movement (no diagonals).
	var dist: int = _orthogonal_distance(unit.grid_position, tile)
	if dist > spec.range:
		return PlayResult.new(
			"CardPlay: target out of range (%d > %d) for '%s'"
			% [dist, spec.range, card.id]
		)

	# target_type: unit-typed specs require a Combatant of the right allegiance;
	# tile-typed specs require a tile (and, for empty_tile, an unoccupied one).
	return _validate_target_type(unit, spec.target_type, target, tile)


## Enforce the target_type discriminator (§2.1).
func _validate_target_type(
	unit: Combatant, target_type: StringName, target: Variant, tile: Vector2i
) -> PlayResult:
	match target_type:
		TARGET_SELF:
			if not (target is Combatant) or target != unit:
				return _type_error(target_type, "must target the acting unit itself")
		TARGET_ALLY:
			if not _is_unit(target):
				return _type_error(target_type, "must target a unit")
			var ally := target as Combatant
			if ally.team != unit.team:
				return _type_error(target_type, "must target a friendly unit")
		TARGET_ENEMY:
			if not _is_unit(target):
				return _type_error(target_type, "must target a unit")
			var foe := target as Combatant
			if foe.team == unit.team:
				return _type_error(target_type, "must target an enemy unit")
		TARGET_ANY_UNIT:
			if not _is_unit(target):
				return _type_error(target_type, "must target a unit")
		TARGET_TILE:
			# Any in-bounds tile (occupied or not) is valid.
			if not battle.grid.in_bounds(tile):
				return _type_error(target_type, "tile is out of bounds")
		TARGET_EMPTY_TILE:
			if not battle.grid.in_bounds(tile):
				return _type_error(target_type, "tile is out of bounds")
			if battle.grid.is_occupied(tile) or battle.grid.is_blocked(tile):
				return _type_error(target_type, "tile must be empty")
		_:
			return PlayResult.new(
				"CardPlay: unknown target_type '%s'" % target_type
			)
	return PlayResult.new()


## Whether `target` is a live unit reference.
func _is_unit(target: Variant) -> bool:
	return target is Combatant


## A uniform target_type rejection message.
func _type_error(target_type: StringName, why: String) -> PlayResult:
	return PlayResult.new("CardPlay: target_type '%s': %s" % [target_type, why])


## The grid tile a target occupies, or null if the target is neither a unit nor a
## tile. A Combatant resolves to its grid_position; a Vector2i is the tile itself.
func _target_tile(target: Variant) -> Variant:
	if target is Combatant:
		return (target as Combatant).grid_position
	if target is Vector2i:
		return target
	return null


## Orthogonal (Manhattan) distance between two tiles. This is the tile distance on
## a 4-connected grid (no diagonals), matching GridModel.neighbors / the
## pathfinder's heuristic, so `range` is measured the same way movement is.
func _orthogonal_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


# ============================================================================
#  Spend + resolve (shared)
# ============================================================================

## Spend the card's energy from the shared pool and resolve its effects in order
## through BattleState.apply_effects (which folds in strength/weak for damage and
## drives the EffectResolver). Called only after _validate has passed, so the
## energy is known to be available.
func _spend_and_resolve(unit: Combatant, card: CardData, target: Variant) -> void:
	battle.energy -= card.energy_cost
	battle.apply_effects(unit, target, card.effects)
