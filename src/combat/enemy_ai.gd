class_name EnemyAI
extends RefCounted
## Enemy intent selection, telegraphing, and execution (task P1·08).
##
## A STANDALONE controller that drives enemies on the enemy phase WITHOUT
## modifying BattleState. It operates entirely through BattleState's public API
## (living_players(), apply_effects(), move_unit(), grid) and the data Resources
## (EnemyData / IntentData / TargetSpec, data-schemas.md §5). Final wiring — having
## the battle loop call this on the enemy phase (e.g. via BattleState's
## `_take_enemy_action` hook or by injecting an EnemyAI) — lands at integration in
## P1·09; this module is pure mechanics + tests.
##
## Responsibilities (the three the task names):
##   1. SELECTION — pick the next IntentData from an enemy's `intents` per its
##      `intent_pattern`: `random_weighted` (by IntentData.weight, via a SEEDED
##      RandomNumberGenerator so a fixed seed is deterministic) or `sequence`
##      (cycle the list in order). The choice is REMEMBERED per enemy so it can be
##      telegraphed and then resolved.
##   2. TELEGRAPH — expose the chosen intent (icon + target) BEFORE it resolves so
##      UI can show "what this enemy will do next turn".
##   3. EXECUTION — on the enemy phase, take the telegraphed intent (selecting one
##      lazily if none is pending), move the enemy toward a sensible target up to
##      its move_range using the Pathfinder, then resolve the intent's effects via
##      BattleState.apply_effects().
##
## Per-enemy memory (chosen intent + chosen target) is keyed by the Combatant
## instance so multiple enemies sharing one EnemyData each keep their own
## telegraph. Determinism: a single seeded RNG, advanced only on weighted picks,
## so a fixed seed reproduces an entire enemy phase.

## Telegraph icons that mean "stand still / act on self" — block/buff/debuff
## intents don't chase a player. Offensive icons (attack/move) home in on the
## nearest living player. Behaviour keyed by the schema's telegraph vocabulary
## (data-schemas.md §5 IntentData.telegraph); no balance numbers live here.
const SELF_TELEGRAPHS: Array[StringName] = [&"block", &"buff", &"debuff"]


## A single enemy's pending decision: the intent it will perform and the target
## it picked when the intent was selected. Bundled so telegraph and execution
## read the same resolved choice.
class Telegraph extends RefCounted:
	## The IntentData this enemy will perform next.
	var intent: IntentData = null
	## The resolved target Combatant (nearest living player for offensive intents,
	## the enemy itself for self/buff intents). May be null when no target exists.
	var target: Combatant = null

	func _init(chosen_intent: IntentData = null, chosen_target: Combatant = null) -> void:
		intent = chosen_intent
		target = chosen_target


## Seeded RNG backing `random_weighted` selection. Re-seeding (set `seed`) makes
## an entire enemy phase reproducible — the core determinism guarantee the tests
## assert. Only weighted picks consume randomness; `sequence` never touches it.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Per-enemy telegraph memory: Combatant -> Telegraph. Keyed by instance so two
## enemies sharing one EnemyData keep independent selections.
var _telegraphs: Dictionary = {}

## Per-enemy cursor for the `sequence` pattern: Combatant -> int next index.
var _sequence_index: Dictionary = {}


## `rng_seed` seeds the internal RNG so weighted selection is deterministic from
## construction. Tests pass a fixed seed; production may pass a run seed.
func _init(rng_seed: int = 0) -> void:
	_rng.seed = rng_seed


## Re-seed the internal RNG. Resets the weighted-selection stream so a caller can
## reproduce a phase on demand without rebuilding the controller.
func set_seed(rng_seed: int) -> void:
	_rng.seed = rng_seed


# ============================================================================
#  1. Intent selection
# ============================================================================

## Choose the next intent for `enemy` from `enemy_data.intents` per
## `enemy_data.intent_pattern`, REMEMBER it (with a freshly resolved target) so it
## can be telegraphed, and return it. Returns null when the enemy has no intents.
##
## `random_weighted` draws by IntentData.weight using the seeded RNG (a 0-weight
## intent can never be drawn; a dominant weight is drawn most). `sequence` cycles
## the list in order, one step per call, wrapping at the end. Any other pattern
## falls back to `sequence` so an unknown pattern never crashes a phase.
##
## NOTE: the target is resolved at selection time against the CURRENT battle so
## the telegraph can name it. `battle_state` is needed only to pick that target;
## selection itself does not mutate the battle.
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
## <= 0 are treated as 0 (never chosen). If every weight is <= 0, falls back to a
## uniform pick over the list so a misconfigured enemy still acts. Advances the RNG
## by exactly one draw, keeping the stream deterministic under a fixed seed.
func _select_weighted(intents: Array[IntentData]) -> IntentData:
	var total: int = 0
	for intent in intents:
		total += max(0, intent.weight)

	if total <= 0:
		# Degenerate: all weights non-positive. Uniform fallback (still seeded).
		var idx: int = _rng.randi_range(0, intents.size() - 1)
		return intents[idx]

	# Draw a point in [0, total) and walk the cumulative weights to find its slot.
	var roll: int = _rng.randi_range(0, total - 1)
	var cumulative: int = 0
	for intent in intents:
		cumulative += max(0, intent.weight)
		if roll < cumulative:
			return intent
	# Unreachable given total > 0, but return the last as a safe fallback.
	return intents[intents.size() - 1]


## Sequence pick: return the intent at this enemy's cursor, then advance (wrapping).
## The cursor is per-enemy so each grunt walks its own cycle independently.
func _select_sequence(enemy: Combatant, intents: Array[IntentData]) -> IntentData:
	var index: int = int(_sequence_index.get(enemy, 0))
	if index < 0 or index >= intents.size():
		index = 0
	_sequence_index[enemy] = (index + 1) % intents.size()
	return intents[index]


# ============================================================================
#  2. Telegraph
# ============================================================================

## The remembered Telegraph for `enemy` (intent + resolved target), or null if no
## intent has been selected yet. UI reads this to show the upcoming action's icon
## (telegraph.intent.telegraph) and its target before the enemy phase resolves.
func get_telegraph(enemy: Combatant) -> Telegraph:
	return _telegraphs.get(enemy, null)


## Convenience: the upcoming IntentData for `enemy`, or null if none selected.
func get_telegraphed_intent(enemy: Combatant) -> IntentData:
	var tel: Telegraph = _telegraphs.get(enemy, null)
	return tel.intent if tel != null else null


## True if `enemy`'s telegraphed intent is offensive (chases a player) rather than
## a self/buff intent (stays put). Drives movement in take_turn().
func _is_offensive(intent: IntentData) -> bool:
	return intent != null and not SELF_TELEGRAPHS.has(intent.telegraph)


# ============================================================================
#  3. Execution on the enemy phase
# ============================================================================

## Resolve `enemy`'s turn against `battle_state`:
##   (a) use the telegraphed intent (selecting one lazily if none is pending);
##   (b) move the enemy toward its target up to `move_range` via the Pathfinder
##       for offensive intents (stay put for self/buff intents);
##   (c) resolve the intent's effects with
##       battle_state.apply_effects(enemy, target, intent.effects).
##
## Graceful no-ops: a dead enemy, an enemy with no intents, or an offensive intent
## with no living player target all return without mutating the battle (an offensive
## intent only moves toward + strikes a real target). After it acts the enemy's
## telegraph is CLEARED so the next phase re-selects (matching Slay-the-Spire's
## "telegraph next, then perform" cadence). Returns the IntentData performed, or
## null when the enemy did nothing.
##
## Stun handling lives in BattleState (`_is_stunned_and_consume`, which skips the
## action before this is ever called), so a stunned enemy simply never reaches
## take_turn during the phase; calling take_turn directly on one still resolves its
## intent — the skip is the phase loop's job, by design (P1·09 wiring).
func take_turn(battle_state: BattleState, enemy: Combatant, enemy_data: EnemyData) -> IntentData:
	if battle_state == null or enemy == null or not enemy.is_alive():
		return null

	# Use the pending telegraph; lazily select if the phase loop didn't pre-pick.
	var tel: Telegraph = _telegraphs.get(enemy, null)
	if tel == null or tel.intent == null:
		select_intent(enemy, enemy_data, battle_state)
		tel = _telegraphs.get(enemy, null)

	if tel == null or tel.intent == null:
		return null  # enemy has no intents — nothing to do.

	var intent: IntentData = tel.intent
	# Re-resolve the target against the live battle in case it died/moved between
	# telegraph and execution; falls back to the telegraphed one.
	var target: Combatant = _choose_target(enemy, intent, battle_state)
	if target == null:
		target = tel.target

	if _is_offensive(intent):
		if target == null or not target.is_alive():
			# No valid victim: clear the telegraph and skip. (a) gracefully handled.
			_telegraphs.erase(enemy)
			return null
		_move_toward(battle_state, enemy, target, intent)
	# Self/buff intents stay put; their target is the enemy itself (see _choose_target).

	if target != null:
		battle_state.apply_effects(enemy, target, intent.effects)

	# Performed: clear so the next phase telegraphs and selects afresh.
	_telegraphs.erase(enemy)
	return intent


# ============================================================================
#  Targeting
# ============================================================================

## Pick the target for `intent`: the enemy ITSELF for self/buff intents (block,
## buff, debuff icons — they affect the caster), the NEAREST living player for
## offensive intents (attack/move icons). Manhattan distance ties break toward the
## earliest player in spawn order for determinism. Returns null when an offensive
## intent has no living players to hit.
func _choose_target(enemy: Combatant, intent: IntentData, battle_state: BattleState) -> Combatant:
	if intent == null:
		return null
	if not _is_offensive(intent):
		return enemy
	return _nearest_living_player(enemy, battle_state)


## The living player closest (Manhattan) to `enemy`, or null if none live. Ties go
## to the earliest in living_players() order so selection is deterministic.
func _nearest_living_player(enemy: Combatant, battle_state: BattleState) -> Combatant:
	var best: Combatant = null
	var best_dist: int = 0
	for player in battle_state.living_players():
		var dist: int = _manhattan(enemy.grid_position, player.grid_position)
		if best == null or dist < best_dist:
			best = player
			best_dist = dist
	return best


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


# ============================================================================
#  Movement
# ============================================================================

## Move `enemy` toward `target` up to `enemy.move_range` tiles, stopping on the
## tile ADJACENT to (or as close as the path allows toward) the target. Uses the
## Pathfinder over the battle's grid, treating other units as obstacles
## (block_occupied) so the enemy never walks through a body or onto the target's
## own tile. Commits the move through battle_state.move_unit() so the grid occupant
## registry stays in sync. A no-op if already adjacent, if no path exists, or if
## move_range is 0.
##
## `intent` is accepted so a future melee-vs-ranged distinction (stop within the
## intent's TargetSpec.range rather than strictly adjacent) can slot in here; the
## prototype closes to adjacency, which satisfies single-range melee intents.
func _move_toward(battle_state: BattleState, enemy: Combatant, target: Combatant, intent: IntentData) -> void:
	if enemy.move_range <= 0:
		return
	var grid: GridModel = battle_state.grid
	var pathfinder := Pathfinder.new(grid)

	# Path enemy -> target, ignoring occupants only on the two endpoints (the
	# target's tile is where we'd path TO; we trim to just short of it below).
	var path: Array[Vector2i] = pathfinder.find_path(
		enemy.grid_position, target.grid_position, true
	)
	if path.size() <= 1:
		return  # no path, or already on the target tile (shouldn't happen).

	# Walk the path up to move_range steps, but never step ONTO the target's tile
	# (the last path element). The reachable tile is the furthest such step.
	var max_steps: int = min(enemy.move_range, path.size() - 1)
	var destination: Vector2i = enemy.grid_position
	for step_index in range(1, max_steps + 1):
		var tile: Vector2i = path[step_index]
		if tile == target.grid_position:
			break  # don't occupy the target's tile.
		destination = tile

	if destination != enemy.grid_position:
		battle_state.move_unit(enemy, destination)
