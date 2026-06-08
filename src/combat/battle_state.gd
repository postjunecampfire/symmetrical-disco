class_name BattleState
extends BattleContext
## The integration spine of a battle (task P1·04): the live runtime that owns the
## combatants, the shared deck, the shared energy pool, and the turn loop — and
## the concrete implementation of the BattleContext interface the EffectResolver
## (P1·03) calls into.
##
## Positionless (ADR-0013): combat has no grid. A target is a Combatant (or a set
## of Combatants resolved from a TargetSpec via resolve_targets); there is no
## move/push. The resolver's dispatch lands on real mutations: hp/block changes,
## status changes, deck draws, energy gains.
##
## Turn structure (ADR-0010): STRICT PHASES — a player phase, then an enemy phase,
## repeating. `start_player_turn()` refills the shared energy pool to
## `BattleConfig.energy_per_turn`, ticks per-turn statuses on the player units,
## and draws the per-turn hand. `end_player_turn()` discards the hand and runs the
## enemy phase. Win/lose is evaluated via `check_outcome()`.
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

## Effect types that act globally on the acting side rather than on a target
## (so they are applied once per card/intent, not once per resolved target).
const GLOBAL_EFFECTS: Array[StringName] = [&"draw", &"gain_energy"]


# --- Owned state ------------------------------------------------------------

## Global tunables (energy_per_turn, draw_per_turn, …). Injected, never inlined.
var config: BattleConfig

## The shared deck (draw/discard cycle). `draw_cards()` delegates here.
var deck: Deck

## Status definitions keyed by id -> StatusData. Drives stacking/decay metadata;
## absent ids fall back to schema defaults (intensity stacking, decays each turn).
var status_defs: Dictionary = {}

## Win condition for this encounter (data-schemas.md §6). `defeat_all` is fully
## implemented; `survive_turns` is a stubbed hook.
var win_condition: StringName = &"defeat_all"
var win_param: int = 0

## All combatants, in registration order. Player and enemy units share one list;
## filter by team. Dead units stay in the list (hp == 0) so references remain valid.
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

## Seeded RNG for non-deterministic targeting (random_enemy). Only consumed when a
## random_enemy target is resolved, so deterministic content stays reproducible.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## `battle_config` is the injected world; `battle_deck` is the shared deck (a
## default empty one is built if none supplied so the state is always usable).
## `status_definitions` maps status id -> StatusData.
func _init(
	battle_config: BattleConfig = null,
	battle_deck: Deck = null,
	status_definitions: Dictionary = {}
) -> void:
	config = battle_config if battle_config != null else BattleConfig.new()
	deck = battle_deck if battle_deck != null else Deck.new(config)
	status_defs = status_definitions


# --- Combatant registry -----------------------------------------------------

## Register `unit` in the battle. Returns the unit for call chaining.
func add_combatant(unit: Combatant) -> Combatant:
	combatants.append(unit)
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


# --- Positionless targeting -------------------------------------------------

## Resolve a TargetSpec (data-schemas.md §2.1) into the concrete set of
## Combatants it affects, from `actor`'s perspective. `chosen` is the single unit
## the caller picked for single-target kinds (enemy / ally); group kinds ignore it.
## Returns living units only.
func resolve_targets(spec: TargetSpec, actor: Combatant, chosen: Variant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	if spec == null or actor == null:
		return out
	match spec.target_type:
		&"self":
			out.append(actor)
		&"ally":
			if chosen is Combatant and (chosen as Combatant).is_alive():
				out.append(chosen)
		&"all_allies":
			out = living_on_team(actor.team)
		&"enemy":
			if chosen is Combatant and (chosen as Combatant).is_alive():
				out.append(chosen)
		&"all_enemies":
			out = _opponents(actor)
		&"random_enemy":
			var foes: Array[Combatant] = _opponents(actor)
			if not foes.is_empty():
				out.append(foes[_rng.randi_range(0, foes.size() - 1)])
	return out


## The living units on the team opposing `actor`.
func _opponents(actor: Combatant) -> Array[Combatant]:
	var other: int = (
		Combatant.Team.ENEMY if actor.team == Combatant.Team.PLAYER
		else Combatant.Team.PLAYER
	)
	return living_on_team(other)


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


# --- Unit-target resolution -------------------------------------------------

## Resolve an effect's `target` to a concrete living-or-dead Combatant, or null.
## Positionless: the target is always a Combatant (or null); there are no tiles.
func _resolve_unit(target: Variant) -> Combatant:
	if target is Combatant:
		return target
	return null


# ============================================================================
#  BattleContext implementation (the seam the EffectResolver calls)
# ============================================================================

## Deal `amount` damage to `target`: block absorbs first, the remainder reduces
## hp. (Offensive strength/weak modifiers are applied where the attack ORIGINATES
## — see `deal_damage_from()` / `apply_effects()` — because the resolver's
## deal_damage(target, amount) carries no source. A bare deal_damage is treated as
## already-modified raw damage.) Lethal results are clamped at 0 hp.
func deal_damage(target: Variant, amount: int) -> void:
	var unit: Combatant = _resolve_unit(target)
	if unit == null or amount <= 0 or not unit.is_alive():
		return
	var remaining: int = amount
	if unit.block > 0:
		var absorbed: int = min(unit.block, remaining)
		unit.block -= absorbed
		remaining -= absorbed
	if remaining > 0:
		unit.hp = max(0, unit.hp - remaining)


## Grant `amount` block to `target`. Block accumulates; the `block` StatusData
## governs whether it decays at turn start (see `_tick_statuses`). Mirrored into
## the status dict so UI/status queries see a `block` entry too.
func add_block(target: Variant, amount: int) -> void:
	var unit: Combatant = _resolve_unit(target)
	if unit == null or amount <= 0:
		return
	unit.block += amount
	unit.set_status(STATUS_BLOCK, unit.block)


## Restore `amount` HP to `target`, clamped to max_hp. The dead are not healed.
func heal(target: Variant, amount: int) -> void:
	var unit: Combatant = _resolve_unit(target)
	if unit == null or amount <= 0 or not unit.is_alive():
		return
	unit.hp = min(unit.max_hp, unit.hp + amount)


## Add `stacks` of `status_id` to `target`, honouring StatusData.stacking:
## `intensity` adds, `duration`/`flag` refresh to the larger of current/incoming.
## `block` is routed through add_block so the block field stays authoritative.
func apply_status(target: Variant, status_id: StringName, stacks: int) -> void:
	var unit: Combatant = _resolve_unit(target)
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


## Draw `n` cards for the active side via the shared Deck (honours hand cap and
## the reshuffle cooldown cycle).
func draw_cards(n: int) -> void:
	if n <= 0:
		return
	deck.draw(n)


## Add `n` energy to the shared pool this turn (the `gain_energy` effect).
func add_energy(n: int) -> void:
	energy = max(0, energy + n)


# ============================================================================
#  Damage with an attacker (strength / weak)  — used by apply_effects & AI
# ============================================================================

## Compute the strength/weak-modified outgoing damage `attacker` deals for a base
## `amount`. Strength adds its stacks; weak reduces by a fixed fraction. Kept as
## the single place offensive modifiers live so card play and enemy intents route
## through the same math. Never returns below 0.
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
## EffectResolver with THIS BattleState as the context. `target` may be a single
## Combatant or an Array[Combatant] (an AoE target set from resolve_targets).
## Targeted effects apply to each unit in the set; GLOBAL_EFFECTS (draw,
## gain_energy) apply ONCE regardless of set size. For `damage`, the attacker's
## strength/weak is folded in before dispatch (the BattleContext seam is source-less).
func apply_effects(source: Combatant, target: Variant, effects: Array) -> void:
	var targets: Array = target if target is Array else [target]
	for effect in effects:
		if not (effect is Effect):
			continue
		var e: Effect = effect
		if GLOBAL_EFFECTS.has(e.type):
			_resolver.resolve(e, source, null, self)
			continue
		for t in targets:
			if e.type == &"damage":
				var modified := e.duplicate() as Effect
				modified.amount = modified_damage(source, e.amount)
				_resolver.resolve(modified, source, t, self)
			else:
				_resolver.resolve(e, source, t, self)


# ============================================================================
#  Turn loop
# ============================================================================

## Begin a player turn: advance the turn counter, refill the shared energy pool to
## the configured per-turn amount, tick per-turn statuses on the player units,
## and draw the per-turn hand from the shared deck.
func start_player_turn() -> void:
	phase = Phase.PLAYER
	turn_number += 1
	energy = config.energy_per_turn
	_tick_statuses(Combatant.Team.PLAYER)
	deck.draw_for_turn()


## End the player turn: discard the hand back into the cycle, then run the enemy
## phase. Kept as one call so a caller (UI) has a single "end turn" hook.
func end_player_turn() -> void:
	deck.discard_hand()
	_run_enemy_phase()


## Resolve the enemy phase: tick enemy statuses, then let each living, un-stunned
## enemy act through the overridable `_take_enemy_action` hook.
func _run_enemy_phase() -> void:
	phase = Phase.ENEMY
	_tick_statuses(Combatant.Team.ENEMY)
	for enemy in living_enemies():
		if _is_stunned_and_consume(enemy):
			continue
		_take_enemy_action(enemy)
	phase = Phase.PLAYER


## Hook: one enemy's action. The default is a no-op placeholder; EncounterBattle
## overrides it to delegate to the injected EnemyAI.
func _take_enemy_action(_enemy: Combatant) -> void:
	pass


# ============================================================================
#  Status processing (behaviour in code, magnitudes/flags in data)
# ============================================================================

## Tick every per-turn status on the living units of `team`, in a fixed order so
## results are deterministic: POISON deals damage then decrements; BLOCK decays
## per its StatusData; STRENGTH/WEAK decay per their StatusData. STUN is NOT
## decayed here — it is CONSUMED at the moment a unit would act.
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
	# start it resets if its StatusData decays (the prototype default).
	if _status_decays(STATUS_BLOCK):
		unit.block = 0
		unit.set_status(STATUS_BLOCK, 0)

	# Strength / weak: decay one stack per turn iff their StatusData says so.
	if _status_decays(STATUS_STRENGTH):
		unit.add_status_stacks(STATUS_STRENGTH, -1)
	if _status_decays(STATUS_WEAK):
		unit.add_status_stacks(STATUS_WEAK, -1)

	# Stun is intentionally NOT decayed here. It is consumed at the moment the unit
	# would act (`_is_stunned_and_consume`), so a stun applied before a unit's turn
	# causes it to skip exactly one action and is then cleared.


## If `unit` is stunned, consume one stack and report true (the unit skips its
## action). Returns false (unit acts normally) when not stunned.
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
## ONGOING. Players-dead is checked first so a mutual wipe reads as LOSS.
func check_outcome() -> Outcome:
	match win_condition:
		&"survive_turns":
			return _check_survive_turns()
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
## party wipe is still a loss.
func _check_survive_turns() -> Outcome:
	if living_players().is_empty():
		return Outcome.LOSS
	if win_param > 0 and turn_number >= win_param:
		return Outcome.WIN
	return Outcome.ONGOING
