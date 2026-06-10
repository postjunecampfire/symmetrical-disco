class_name EnemyAI
extends RefCounted
## Enemy intent selection, telegraphing, and execution (task P1·08).
##
## A STANDALONE controller that drives enemies on the enemy phase WITHOUT
## modifying BattleState. It operates entirely through BattleState's public API
## (living_players(), resolve_targets(), apply_effects()) and the data Resources
## (EnemyData / IntentData / TargetSpec, data-schemas.md §5).
##
## Positionless (ADR-0013): there is no movement or pathfinding — combat has no
## board. Targeting is by kind: offensive intents hit the chosen player; the
## chosen player is the one with the LOWEST current HP (earliest in order on a
## tie, deterministic). Self/buff intents act on the enemy itself. An intent's
## TargetSpec is resolved through BattleState.resolve_targets so AoE intents
## (all_enemies) hit every player.
##
## Responsibilities:
##   1. SELECTION — pick the next IntentData per `intent_pattern`: `random_weighted`
##      (by weight, via a SEEDED RNG) or `sequence` (cycle in order). Remembered
##      per enemy so it can be telegraphed then resolved.
##   2. TELEGRAPH — expose the chosen intent (icon + primary target) before it
##      resolves so UI can show "what this enemy will do next turn".
##   3. EXECUTION — on the enemy phase, resolve the telegraphed intent's effects
##      against its target set via BattleState.apply_effects().
##
## Determinism: a single seeded RNG, advanced only on weighted picks, so a fixed
## seed reproduces an entire enemy phase.

## TargetSpec kinds that aim at the OPPOSING side. Offensiveness is decided by the
## intent's TargetSpec — not its telegraph icon — so a `debuff` intent authored with
## target_type "enemy" lands on a PLAYER (the icon is presentation, the spec is
## semantics). Before the M3 tier pass the icon decided, which made every debuff
## intent (hexer's Frail, the Warden's hex) target the CASTER — a self-jinx bug.
const OFFENSIVE_TARGET_TYPES: Array[StringName] = [&"enemy", &"all_enemies", &"random_enemy"]


## A single enemy's pending decision: the intent it will perform and the primary
## target it picked when the intent was selected.
class Telegraph extends RefCounted:
	## The IntentData this enemy will perform next.
	var intent: IntentData = null
	## The resolved primary target (lowest-HP player for offensive intents, the
	## enemy itself for self/buff intents). May be null when no target exists.
	var target: Combatant = null

	func _init(chosen_intent: IntentData = null, chosen_target: Combatant = null) -> void:
		intent = chosen_intent
		target = chosen_target


## Seeded RNG backing `random_weighted` selection. Re-seeding makes an entire
## enemy phase reproducible. Only weighted picks consume randomness.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Per-enemy telegraph memory: Combatant -> Telegraph. Keyed by instance so two
## enemies sharing one EnemyData keep independent selections.
var _telegraphs: Dictionary = {}

## Per-enemy cursor for the `sequence` pattern: Combatant -> int next index.
var _sequence_index: Dictionary = {}


## `rng_seed` seeds the internal RNG so weighted selection is deterministic from
## construction.
func _init(rng_seed: int = 0) -> void:
	_rng.seed = rng_seed


## Re-seed the internal RNG.
func set_seed(rng_seed: int) -> void:
	_rng.seed = rng_seed


# ============================================================================
#  1. Intent selection
# ============================================================================

## Choose the next intent for `enemy` per its `intent_pattern`, REMEMBER it (with
## a freshly resolved primary target) so it can be telegraphed, and return it.
## Returns null when the enemy has no intents.
func select_intent(enemy: Combatant, enemy_data: EnemyData, battle_state: BattleState) -> IntentData:
	if enemy_data == null or enemy_data.intents.is_empty():
		_telegraphs[enemy] = Telegraph.new(null, null)
		return null

	var intent: IntentData
	match enemy_data.intent_pattern:
		&"random_weighted":
			intent = _select_weighted(enemy_data.intents)
		_:
			# `sequence` and any unknown pattern both cycle in order.
			intent = _select_sequence(enemy, enemy_data.intents)

	var target := _choose_target(enemy, intent, battle_state)
	_telegraphs[enemy] = Telegraph.new(intent, target)
	return intent


## Weighted pick over `intents` by IntentData.weight using the seeded RNG. Weights
## <= 0 are never chosen. If every weight is <= 0, falls back to a uniform pick.
## Advances the RNG by exactly one draw.
func _select_weighted(intents: Array[IntentData]) -> IntentData:
	var total: int = 0
	for intent in intents:
		total += max(0, intent.weight)

	if total <= 0:
		var idx: int = _rng.randi_range(0, intents.size() - 1)
		return intents[idx]

	var roll: int = _rng.randi_range(0, total - 1)
	var cumulative: int = 0
	for intent in intents:
		cumulative += max(0, intent.weight)
		if roll < cumulative:
			return intent
	return intents[intents.size() - 1]


## Sequence pick: return the intent at this enemy's cursor, then advance (wrapping).
func _select_sequence(enemy: Combatant, intents: Array[IntentData]) -> IntentData:
	var index: int = int(_sequence_index.get(enemy, 0))
	if index < 0 or index >= intents.size():
		index = 0
	_sequence_index[enemy] = (index + 1) % intents.size()
	return intents[index]


# ============================================================================
#  2. Telegraph
# ============================================================================

## The remembered Telegraph for `enemy` (intent + primary target), or null if no
## intent has been selected yet.
func get_telegraph(enemy: Combatant) -> Telegraph:
	return _telegraphs.get(enemy, null)


## Convenience: the upcoming IntentData for `enemy`, or null if none selected.
func get_telegraphed_intent(enemy: Combatant) -> IntentData:
	var tel: Telegraph = _telegraphs.get(enemy, null)
	return tel.intent if tel != null else null


## True if `enemy`'s telegraphed intent is offensive (targets a player) rather
## than a self/buff intent. Read off the intent's TargetSpec: enemy-facing kinds
## are offensive; self/ally/all_allies (and a missing spec) act on the caster.
func _is_offensive(intent: IntentData) -> bool:
	if intent == null or intent.target == null:
		return false
	return OFFENSIVE_TARGET_TYPES.has(intent.target.target_type)


# ============================================================================
#  3. Execution on the enemy phase
# ============================================================================

## Resolve `enemy`'s turn against `battle_state`:
##   (a) use the telegraphed intent (selecting one lazily if none is pending);
##   (b) resolve the intent's TargetSpec into a target set (via
##       battle_state.resolve_targets, using the chosen primary target);
##   (c) apply the intent's effects with battle_state.apply_effects().
##
## Graceful no-ops: a dead enemy, an enemy with no intents, or an offensive intent
## with no living player all return without mutating the battle. After it acts the
## enemy's telegraph is CLEARED so the next phase re-selects. Returns the
## IntentData performed, or null when the enemy did nothing.
func take_turn(battle_state: BattleState, enemy: Combatant, enemy_data: EnemyData) -> IntentData:
	if battle_state == null or enemy == null or not enemy.is_alive():
		return null

	var tel: Telegraph = _telegraphs.get(enemy, null)
	if tel == null or tel.intent == null:
		select_intent(enemy, enemy_data, battle_state)
		tel = _telegraphs.get(enemy, null)

	if tel == null or tel.intent == null:
		return null  # enemy has no intents — nothing to do.

	var intent: IntentData = tel.intent
	# Re-resolve the primary target against the live battle in case it died.
	var primary: Combatant = _choose_target(enemy, intent, battle_state)
	if primary == null:
		primary = tel.target

	if _is_offensive(intent) and (primary == null or not primary.is_alive()):
		# No valid victim: clear the telegraph and skip.
		_telegraphs.erase(enemy)
		return null

	var targets: Array[Combatant] = battle_state.resolve_targets(intent.target, enemy, primary)
	if not targets.is_empty():
		battle_state.apply_effects(enemy, targets, intent.effects)

	_telegraphs.erase(enemy)
	return intent


# ============================================================================
#  Targeting (positionless)
# ============================================================================

## Pick the primary target for `intent`: the enemy ITSELF for self/buff intents,
## the lowest-HP living player for offensive intents. Returns null when an
## offensive intent has no living players to hit.
func _choose_target(enemy: Combatant, intent: IntentData, battle_state: BattleState) -> Combatant:
	if intent == null:
		return null
	if not _is_offensive(intent):
		return enemy
	return _lowest_hp_player(battle_state)


## The living player with the lowest current HP, or null if none live. Ties go to
## the earliest in living_players() order so selection is deterministic.
func _lowest_hp_player(battle_state: BattleState) -> Combatant:
	var best: Combatant = null
	for player in battle_state.living_players():
		if best == null or player.hp < best.hp:
			best = player
	return best
