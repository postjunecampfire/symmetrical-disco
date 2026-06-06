class_name BattleState
extends BattleContext
## The integration spine of a battle (task P1·04): the live runtime that owns the
## combatants, the grid, the shared deck, the shared energy pool, and the turn
## loop — and the concrete implementation of the BattleContext interface the
## EffectResolver (P1·03) calls into.
##
## It extends BattleContext and OVERRIDES every method (deal_damage, add_block,
## heal, apply_status, move_unit, push_unit, draw_cards, add_energy) so the
## resolver's effect dispatch lands on real mutations: hp/block changes, status
## changes, grid moves/pushes, deck draws, energy gains. `target` / `unit` /
## `source` are concrete `Combatant` instances here (the resolver treats them as
## opaque, §battle_context conventions).
##
## Turn structure (resolves data-schemas.md §12's open question for the
## prototype): STRICT PHASES — a player phase, then an enemy phase, repeating.
## `start_player_turn()` refills the shared energy pool to
## `BattleConfig.energy_per_turn`, ticks per-turn statuses on the player units,
## and draws the per-turn hand. `end_player_turn()` discards the hand and runs
## the enemy phase. Win/lose is evaluated after each lethal change and exposed via
## `check_outcome()`.
##
## All balance numbers come from the injected BattleConfig and the StatusData
## resources (ADR-0003): magnitudes/flags in data, behaviour in code.

## Outcome of a battle, returned by `check_outcome()`.
enum Outcome { ONGOING, WIN, LOSS }

## Which side is currently acting. Strict two-phase model.
enum Phase { PLAYER, ENEMY }

## The five prototype status ids (data-schemas.md §2.4). Named so the behaviour
## switch reads as semantics, not loose strings.
const STATUS_POISON: StringName = &"poison"
const STATUS_BLOCK: StringName = &"block"
const STATUS_STUN: StringName = &"stun"
const STATUS_STRENGTH: StringName = &"strength"
const STATUS_WEAK: StringName = &"weak"


# --- Owned state ------------------------------------------------------------

## Global tunables (energy_per_turn, draw_per_turn, …). Injected, never inlined.
var config: BattleConfig

## The tactical grid (occupant tracking, bounds, passability).
var grid: GridModel

## The shared deck (draw/discard cycle). `draw_cards()` delegates here.
var deck: Deck

## Status definitions keyed by id -> StatusData. Drives stacking/decay metadata;
## absent ids fall back to schema defaults (intensity stacking, decays each turn).
var status_defs: Dictionary = {}

## Win condition for this encounter (data-schemas.md §6). `defeat_all` is fully
## implemented; `survive_turns` / `reach_tile` are stubbed hooks.
var win_condition: StringName = &"defeat_all"
var win_param: int = 0

## All combatants, in spawn order. Player and enemy units share one list; filter
## by team. Dead units stay in the list (hp == 0) so references remain valid.
var combatants: Array[Combatant] = []

## The shared per-turn energy pool. Refilled to config.energy_per_turn at the
## start of each player turn; spent by playing cards (P1·07) and topped up by the
## `gain_energy` effect via add_energy().
var energy: int = 0

## Current phase and a turn counter (incremented each player turn start). The
## counter feeds the survive_turns hook.
var phase: Phase = Phase.PLAYER
var turn_number: int = 0

## Reusable resolver for applying effect lists (criterion 6). Holds no state.
var _resolver: EffectResolver = EffectResolver.new()


## `battle_config` and `grid_model` are the injected world; `battle_deck` is the
## shared deck (a default empty one is built if none supplied so the state is
## always usable). `status_definitions` maps status id -> StatusData.
func _init(
	battle_config: BattleConfig = null,
	grid_model: GridModel = null,
	battle_deck: Deck = null,
	status_definitions: Dictionary = {}
) -> void:
	config = battle_config if battle_config != null else BattleConfig.new()
	grid = grid_model if grid_model != null else GridModel.new()
	deck = battle_deck if battle_deck != null else Deck.new(config)
	status_defs = status_definitions


# --- Combatant registry -----------------------------------------------------

## Register `unit` in the battle and place it on the grid at its grid_position.
## Returns the unit for call chaining.
func add_combatant(unit: Combatant) -> Combatant:
	combatants.append(unit)
	grid.set_occupant(unit.grid_position, unit)
	return unit


## All living combatants on a side.
func living_on_team(team: int) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c in combatants:
		if c.team == team and c.is_alive():
			out.append(c)
	return out


func living_players() -> Array[Combatant]:
	return living_on_team(Combatant.Team.PLAYER)


func living_enemies() -> Array[Combatant]:
	return living_on_team(Combatant.Team.ENEMY)


# --- StatusData lookup ------------------------------------------------------

## The StatusData for `status_id`, or null if undefined. Callers fall back to
## schema defaults when null so a missing definition never crashes a tick.
func _status_def(status_id: StringName) -> StatusData:
	return status_defs.get(status_id, null)


## Whether `status_id` decays each turn. Defaults to the schema default (true)
## when the status is undefined.
func _status_decays(status_id: StringName) -> bool:
	var def := _status_def(status_id)
	return def.decays_each_turn if def != null else true


## The stacking mode of `status_id` (schema default `intensity` when undefined).
func _status_stacking(status_id: StringName) -> StringName:
	var def := _status_def(status_id)
	return def.stacking if def != null else &"intensity"


# ============================================================================
#  BattleContext implementation (the seam the EffectResolver calls)
# ============================================================================

## Deal `amount` damage to `target`, modified by the SOURCE-independent defensive
## path: block absorbs first, the remainder reduces hp. (Offensive strength/weak
## modifiers are applied where the attack ORIGINATES — see
## `deal_damage_from()` / `apply_effects()` — because the resolver's
## deal_damage(target, amount) carries no source. A bare deal_damage is treated
## as already-modified raw damage.) Lethal results are clamped at 0 hp and
## trigger the grid/occupant cleanup.
func deal_damage(target: Variant, amount: int) -> void:
	var unit := target as Combatant
	if unit == null or amount <= 0 or not unit.is_alive():
		return
	var remaining: int = amount
	if unit.block > 0:
		var absorbed: int = min(unit.block, remaining)
		unit.block -= absorbed
		remaining -= absorbed
	if remaining > 0:
		unit.hp = max(0, unit.hp - remaining)
		if not unit.is_alive():
			_on_unit_died(unit)


## Grant `amount` block to `target`. Block accumulates; the `block` StatusData
## governs whether it decays at turn start (see `_tick_statuses`). Mirrored into
## the status dict so UI/status queries see a `block` entry too.
func add_block(target: Variant, amount: int) -> void:
	var unit := target as Combatant
	if unit == null or amount <= 0:
		return
	unit.block += amount
	unit.set_status(STATUS_BLOCK, unit.block)


## Restore `amount` HP to `target`, clamped to max_hp. The dead are not healed.
func heal(target: Variant, amount: int) -> void:
	var unit := target as Combatant
	if unit == null or amount <= 0 or not unit.is_alive():
		return
	unit.hp = min(unit.max_hp, unit.hp + amount)


## Add `stacks` of `status_id` to `target`, honouring StatusData.stacking:
## `intensity` adds, `duration`/`flag` refresh to the larger of current/incoming.
## `block` is routed through add_block so the block field stays authoritative.
func apply_status(target: Variant, status_id: StringName, stacks: int) -> void:
	var unit := target as Combatant
	if unit == null or stacks == 0:
		return
	if status_id == STATUS_BLOCK:
		add_block(unit, stacks)
		return
	match _status_stacking(status_id):
		&"intensity":
			unit.add_status_stacks(status_id, stacks)
		_:
			# duration / flag: refresh rather than sum.
			unit.set_status(status_id, max(unit.status_stacks(status_id), stacks))


## Relocate `unit` onto tile `to_tile`, keeping the grid occupant registry in
## sync. No-op if the destination is out of bounds or impassable terrain.
func move_unit(unit: Variant, to_tile: Vector2i) -> void:
	var c := unit as Combatant
	if c == null:
		return
	if not grid.in_bounds(to_tile) or grid.is_blocked(to_tile):
		return
	grid.clear_occupant(c.grid_position)
	c.grid_position = to_tile
	grid.set_occupant(to_tile, c)


## Shove `target` `amount` tiles directly away from `from` (the acting unit).
## Direction is the dominant axis of (target - from); the unit slides tile by tile
## and stops before leaving bounds, hitting blocked terrain, or entering an
## occupied tile. Whatever distance it cleared is committed to the grid.
func push_unit(target: Variant, amount: int, from: Variant) -> void:
	var unit := target as Combatant
	if unit == null or amount <= 0:
		return
	var origin: Vector2i = unit.grid_position
	if from is Combatant:
		origin = (from as Combatant).grid_position
	elif from is Vector2i:
		origin = from
	var delta: Vector2i = unit.grid_position - origin
	var step := _push_step(delta)
	if step == Vector2i.ZERO:
		return
	var pos: Vector2i = unit.grid_position
	for _i in range(amount):
		var next: Vector2i = pos + step
		if not grid.in_bounds(next) or grid.is_blocked(next) or grid.is_occupied(next):
			break
		pos = next
	if pos != unit.grid_position:
		move_unit(unit, pos)


## Draw `n` cards for the active side via the shared Deck (honours hand cap and
## the reshuffle cooldown cycle).
func draw_cards(n: int) -> void:
	if n <= 0:
		return
	deck.draw(n)


## Add `n` energy to the shared pool this turn (the `gain_energy` effect).
func add_energy(n: int) -> void:
	energy = max(0, energy + n)


# --- Push direction helper --------------------------------------------------

## Reduce a displacement to a unit step along the dominant orthogonal axis. Ties
## (pure diagonal / zero) resolve toward the x axis when non-zero, matching the
## grid's 4-connected movement (no diagonals).
func _push_step(delta: Vector2i) -> Vector2i:
	if delta == Vector2i.ZERO:
		return Vector2i.ZERO
	if abs(delta.x) >= abs(delta.y):
		return Vector2i(sign(delta.x), 0)
	return Vector2i(0, sign(delta.y))


# ============================================================================
#  Damage with an attacker (strength / weak)  — used by apply_effects & AI
# ============================================================================

## Compute the strength/weak-modified outgoing damage `attacker` deals for a base
## `amount`. Strength adds its stacks; weak reduces by a configurable-but-here
## fixed fraction. Kept as the single place offensive modifiers live so card play
## and enemy intents route through the same math. Never returns below 0.
func modified_damage(attacker: Combatant, amount: int) -> int:
	if attacker == null:
		return max(0, amount)
	var out: int = amount + attacker.status_stacks(STATUS_STRENGTH)
	if attacker.has_status(STATUS_WEAK):
		# Weak: -25% outgoing (floored). Behaviour in code, the FLAG in data.
		out = int(floor(float(out) * 0.75))
	return max(0, out)


## Deal damage FROM `attacker` to `target`, applying strength/weak first, then the
## defensive block/hp routing of deal_damage. This is the source-aware entry the
## bare deal_damage cannot express; AI and apply_effects use it for `damage`.
func deal_damage_from(attacker: Combatant, target: Combatant, amount: int) -> void:
	deal_damage(target, modified_damage(attacker, amount))


# ============================================================================
#  Effect application primitive (criterion 6)
# ============================================================================

## Apply a card/intent `effects` list from `source` onto `target` by driving the
## EffectResolver with THIS BattleState as the context — wiring resolver + state
## together. For `damage` effects we pre-apply the attacker's strength/weak (the
## resolver's deal_damage carries no source) and hand the resolver the already
## modified amount; all other effect types pass straight through. Targeting,
## energy-spend, and UI belong to P1·07 — this is only the apply primitive.
func apply_effects(source: Combatant, target: Variant, effects: Array) -> void:
	for effect in effects:
		if effect is Effect and effect.type == &"damage":
			# Fold the attacker's offensive modifiers in before dispatch, since the
			# BattleContext.deal_damage seam is source-less.
			var modified := effect.duplicate() as Effect
			modified.amount = modified_damage(source, effect.amount)
			_resolver.resolve(modified, source, target, self)
		else:
			_resolver.resolve(effect, source, target, self)


# ============================================================================
#  Turn loop
# ============================================================================

## Begin a player turn: advance the turn counter, refill the shared energy pool to
## the configured per-turn amount, tick per-turn statuses on the player units,
## and draw the per-turn hand from the shared deck. Hooks for UI/AI can subclass
## or wrap; the order here is the prototype contract.
func start_player_turn() -> void:
	phase = Phase.PLAYER
	turn_number += 1
	energy = config.energy_per_turn
	_tick_statuses(Combatant.Team.PLAYER)
	deck.draw_for_turn()


## End the player turn: discard the hand back into the cycle, then run the enemy
## phase. Kept as one call so a caller (P1·07 UI) has a single "end turn" hook.
func end_player_turn() -> void:
	deck.discard_hand()
	_run_enemy_phase()


## Resolve the enemy phase: tick enemy statuses, then let each living, un-stunned
## enemy act. Acting logic (intent selection / targeting) is a later task; here we
## provide the phase skeleton with the stun-skip and status tick wired so the turn
## loop and status processing are testable end to end.
func _run_enemy_phase() -> void:
	phase = Phase.ENEMY
	_tick_statuses(Combatant.Team.ENEMY)
	for enemy in living_enemies():
		if _is_stunned_and_consume(enemy):
			continue
		_take_enemy_action(enemy)
	phase = Phase.PLAYER


## Hook: one enemy's action. The default is a no-op placeholder; AI/intent
## resolution lands in a later task. Override or extend to drive intents through
## apply_effects(). Kept here so the phase loop is complete and overridable.
func _take_enemy_action(_enemy: Combatant) -> void:
	pass


# ============================================================================
#  Status processing (behaviour in code, magnitudes/flags in data)
# ============================================================================

## Tick every per-turn status on the living units of `team`, in a fixed order so
## results are deterministic: POISON deals damage then decrements; BLOCK decays
## per its StatusData; STRENGTH/WEAK decay per their StatusData
## (decays_each_turn). STUN is NOT decayed here — it is CONSUMED at the moment a
## unit would act (`_is_stunned_and_consume`), so a freshly applied stun still
## skips the very next action and is then cleared.
func _tick_statuses(team: int) -> void:
	for unit in living_on_team(team):
		_tick_unit_statuses(unit)


## Apply the start-of-turn status effects to a single unit.
func _tick_unit_statuses(unit: Combatant) -> void:
	# Poison: deal its stacks as damage (block can still absorb), then drop one
	# stack. Magnitude == stack count; the -1 decay is the schema's per-turn tick.
	var poison: int = unit.status_stacks(STATUS_POISON)
	if poison > 0:
		deal_damage(unit, poison)
		if _status_decays(STATUS_POISON):
			unit.add_status_stacks(STATUS_POISON, -1)
		if not unit.is_alive():
			return

	# Block: consumed by incoming damage during the turn; at the owner's turn
	# start it resets if its StatusData decays (the prototype default — block does
	# NOT carry over). If a status author sets decays_each_turn = false, block is
	# allowed to persist.
	if _status_decays(STATUS_BLOCK):
		unit.block = 0
		unit.set_status(STATUS_BLOCK, 0)

	# Strength / weak: decay one stack per turn iff their StatusData says so.
	# Strength is typically persistent (decays_each_turn = false); weak typically
	# counts down. Either way the flag lives in data.
	if _status_decays(STATUS_STRENGTH):
		unit.add_status_stacks(STATUS_STRENGTH, -1)
	if _status_decays(STATUS_WEAK):
		unit.add_status_stacks(STATUS_WEAK, -1)

	# Stun is intentionally NOT decayed here. It is consumed at the moment the unit
	# would act (`_is_stunned_and_consume`), so a stun applied to a unit before its
	# turn correctly causes it to skip exactly one action and is then cleared. The
	# `decays_each_turn` flag on stun's StatusData still governs whether a stun that
	# is never acted upon (e.g. on a unit that dies first) would otherwise persist;
	# consumption-at-action keeps the skip semantics precise for the live case.


## If `unit` is stunned, consume one stack and report true (the unit skips its
## action). Returns false (unit acts normally) when not stunned. Centralising
## stun consumption here means "stun causes the unit to skip its action" is
## enforced at exactly the point an action would happen.
func _is_stunned_and_consume(unit: Combatant) -> bool:
	if unit.has_status(STATUS_STUN):
		unit.add_status_stacks(STATUS_STUN, -1)
		return true
	return false


# ============================================================================
#  Win / lose evaluation
# ============================================================================

## Evaluate the battle outcome. `defeat_all` (the prototype default) is fully
## implemented: all enemies dead => WIN; all players dead => LOSS; otherwise
## ONGOING. Players-dead is checked first so a mutual wipe reads as LOSS. Other
## win_conditions are routed to their stub hooks.
func check_outcome() -> Outcome:
	match win_condition:
		&"survive_turns":
			return _check_survive_turns()
		&"reach_tile":
			return _check_reach_tile()
		_:
			return _check_defeat_all()


## defeat_all: loss if no players remain; win if no enemies remain.
func _check_defeat_all() -> Outcome:
	if living_players().is_empty():
		return Outcome.LOSS
	if living_enemies().is_empty():
		return Outcome.WIN
	return Outcome.ONGOING


## survive_turns hook (stub): win once `turn_number` reaches `win_param`, but a
## party wipe is still a loss. Full survive logic (and when the count advances) is
## a later task; this keeps the outcome enum honest in the meantime.
func _check_survive_turns() -> Outcome:
	if living_players().is_empty():
		return Outcome.LOSS
	if win_param > 0 and turn_number >= win_param:
		return Outcome.WIN
	return Outcome.ONGOING


## reach_tile hook (stub): a party wipe is a loss; the reach-condition itself is
## deferred (needs the packed-tile convention from §6) and is left ONGOING.
func _check_reach_tile() -> Outcome:
	if living_players().is_empty():
		return Outcome.LOSS
	return Outcome.ONGOING


# --- Death bookkeeping ------------------------------------------------------

## Clean up when `unit` drops to 0 hp: free its grid tile so the space is no
## longer blocked. The unit stays in `combatants` (filtered out by the living_*
## queries) so any held references stay valid.
func _on_unit_died(unit: Combatant) -> void:
	if grid.get_occupant(unit.grid_position) == unit:
		grid.clear_occupant(unit.grid_position)
