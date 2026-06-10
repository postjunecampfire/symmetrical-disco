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
## Enemy debuff-slot statuses (P2·12 follow-up / enemy kit redesign): Vulnerable
## raises damage the target TAKES from attacks; Frail reduces block the target
## GAINS. Both `duration`-stacking and decay one stack per turn (like Weak).
const STATUS_VULNERABLE: StringName = &"vulnerable"
const STATUS_FRAIL: StringName = &"frail"
## Multipliers for the two new debuffs (behaviour in code, the FLAG in data, like Weak).
const VULNERABLE_MULT: float = 1.5  # +50% damage taken
const FRAIL_MULT: float = 0.5       # -50% block gained
## Charm (ADR-0028): a non-decaying stacking debuff. Every CHARM_PROC_THRESHOLD
## stacks crossed applies CHARM_PROC_STACKS of Vulnerable AND Weak; at stacks >=
## the target's max_hp the target is executed (lethal, bypasses block). Behaviour
## in code, the flag (non-decay, intensity) in data — the Weak/Vulnerable pattern.
const STATUS_CHARM: StringName = &"charm"
const CHARM_PROC_THRESHOLD: int = 10
const CHARM_PROC_STACKS: int = 2
## M3 statuses (mage DoT ≠ rogue poison):
##   Burn  — ticks like poison (stacks as damage at the owner's phase start, then
##           -1 stack) but block CAN absorb it; the blockability is its identity
##           vs poison's anti-turtle pierce.
##   Bleed — procs when the unit ACTS (a player card play / an enemy intent):
##           stacks as damage that IGNORES block (exertion opens the wound; block
##           is armor, not stitches), then -1 stack per proc. No per-turn decay.
##   Mark  — a marked target takes +stacks FLAT damage on each attack hit, added
##           AFTER multipliers (Vulnerable), then loses ONE stack per hit — the
##           many-small-hits payoff vs Vulnerable's percentage.
const STATUS_BURN: StringName = &"burn"
const STATUS_BLEED: StringName = &"bleed"
const STATUS_MARK: StringName = &"mark"

## Effect types that act globally on the acting side rather than on a target
## (so they are applied once per card/intent, not once per resolved target).
const GLOBAL_EFFECTS: Array[StringName] = [&"draw", &"gain_energy", &"add_card", &"gain_gold"]
## Effect types that apply ONCE to the CASTER regardless of the card's target
## set (ADR-0028): the bomb self-damage tax and caster-side block riders.
const SOURCE_EFFECTS: Array[StringName] = [&"self_damage", &"self_block"]


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

## Per-member decks (ADR-0026): each player unit fights with its OWN Deck,
## derived from its skill loadout at assembly. Keyed by Combatant. The legacy
## `deck` below remains ONLY as the fixture/single-deck fallback for unit tests;
## the run path always populates `decks`.
var decks: Dictionary = {}

## Per-character energy pools (ADR-0025 — supersedes the SHARED pool of
## ADR-0017; the relic/boon increase model carries forward). Keyed by Combatant.
## Each living player refills to config.energy_per_character at player-phase
## start and spends only on their OWN plays — one character's spending never
## starves the other, and the recast/spam brake (ADR-0017) now binds per pool.
var _energy: Dictionary = {}

## Current phase and a turn counter (incremented each player turn start). The
## counter feeds the survive_turns hook.
var phase: Phase = Phase.PLAYER
var turn_number: int = 0

## Reusable resolver for applying effect lists (criterion 6). Holds no state.
var _resolver: EffectResolver = EffectResolver.new()

## Seeded RNG for non-deterministic targeting (random_enemy). Only consumed when a
## random_enemy target is resolved, so deterministic content stays reproducible.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Card registry (id -> CardData) for token generation (`add_card`, ADR-0028).
## Injected at assembly; an empty lookup makes add_card a safe no-op.
var card_lookup: Dictionary = {}

## The map-node band this fight came from ("trash" | "elite" | "boss" | "").
## Set by RunController.begin_combat; read by the Fame triggers (ADR-0028).
var band: StringName = &""

## Charm executions this battle (ADR-0028) — feeds the Fame "execute" trigger
## and telemetry.
var charm_executes: int = 0

## Curses inflicted on player members this battle (ADR-0029): entries of
## {"member": StringName, "card": StringName}. RunController.finish_combat
## persists them into RunState.member_curses — the battle layer stays
## run-agnostic, like charm_executes.
var inflicted_curses: Array[Dictionary] = []

## Consumable card ids PLAYED this battle (ADR-0029). finish_combat removes one
## inventory copy per entry; unplayed consumables persist to future combats.
var consumed_items: Array[StringName] = []

## Run gold found mid-combat (ADR-0029, `gain_gold` — lucky_coin). Credited to
## RunState.currency by finish_combat.
var gold_found: int = 0


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


## Deal `amount` damage that IGNORES block, straight to hp — for poison and other
## block-piercing effects. This is what lets a damage-over-time strategy tax a
## turtle that would otherwise soak everything with block. Clamped at 0; the dead
## are not hit.
func deal_unblockable(target: Variant, amount: int) -> void:
	var unit: Combatant = _resolve_unit(target)
	if unit == null or amount <= 0 or not unit.is_alive():
		return
	unit.hp = max(0, unit.hp - amount)


## Grant `amount` block to `target`. Block accumulates; the `block` StatusData
## governs whether it decays at turn start (see `_tick_statuses`). Mirrored into
## the status dict so UI/status queries see a `block` entry too.
func add_block(target: Variant, amount: int) -> void:
	var unit: Combatant = _resolve_unit(target)
	if unit == null or amount <= 0:
		return
	# Frail: the block-limiting debuff reduces block GAINED (floored), at the single
	# point all block is granted, so it applies to every source symmetrically.
	if unit.has_status(STATUS_FRAIL):
		amount = int(floor(float(amount) * FRAIL_MULT))
	if amount <= 0:
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
	if status_id == STATUS_CHARM and stacks > 0:
		# Charm has threshold/execute behaviour (ADR-0028) — one routing point so
		# every source (cards, charm_strike, intents) shares the same math.
		_apply_charm(unit, stacks)
		return
	match _status_stacking(status_id):
		&"intensity":
			unit.add_status_stacks(status_id, stacks)
		_:
			# duration / flag: refresh rather than sum.
			unit.set_status(status_id, max(unit.status_stacks(status_id), stacks))


## The deck `unit` plays from (ADR-0026). Falls back to the legacy shared deck
## when no per-member deck was registered (fixture battles).
func deck_of(unit: Combatant) -> Deck:
	return decks.get(unit, deck)


## Draw `n` cards (the `draw` effect) into the CASTER's own hand (ADR-0026).
## A null unit (source-less seams/relics) draws for the first living player.
func draw_cards(n: int, unit: Combatant = null) -> void:
	if n <= 0:
		return
	var who: Combatant = unit
	if who == null:
		var players := living_players()
		who = players[0] if not players.is_empty() else null
	if who == null:
		deck.draw(n)
		return
	_apply_on_draw(who, deck_of(who).draw(n))


## Energy of `unit`'s own pool (ADR-0025). Unknown/null unit -> 0.
func energy_of(unit: Combatant) -> int:
	if unit == null:
		return 0
	return int(_energy.get(unit, 0))


## Spend `n` from `unit`'s own pool. Returns false (and spends nothing) if the
## pool is short — callers validate first, this is the enforcement.
func spend_energy(unit: Combatant, n: int) -> bool:
	if unit == null or n < 0 or energy_of(unit) < n:
		return false
	_energy[unit] = energy_of(unit) - n
	return true


## Add `n` energy to a pool (the `gain_energy` effect / energy relics, ADR-0025).
## `unit` selects the pool; a null unit (source-less callers) credits the FIRST
## living player — the provisional attribution for party-level relics until
## relics get holders. Pools never go below 0.
func add_energy(n: int, unit: Combatant = null) -> void:
	var who: Combatant = unit
	if who == null:
		var players := living_players()
		if players.is_empty():
			return
		who = players[0]
	_energy[who] = max(0, energy_of(who) + n)


## Total energy across living players (diagnostics / sim policies; per-pool
## checks are the real gate, ADR-0025).
func total_energy() -> int:
	var sum: int = 0
	for unit in living_players():
		sum += energy_of(unit)
	return sum


# ============================================================================
#  Charm & cash-in (ADR-0028)
# ============================================================================

## Add `stacks` Charm to `unit`, then resolve Charm's two behaviours:
##   * THRESHOLD PROC: each CHARM_PROC_THRESHOLD boundary crossed applies
##     CHARM_PROC_STACKS of Vulnerable and Weak (duration statuses — they
##     refresh rather than sum, like every other application of those debuffs).
##   * EXECUTE: at Charm >= max_hp the unit is defeated outright (hp -> 0,
##     bypassing block). Max HP — not current — so damage-Charm alone cannot
##     converge into a free execute (the mod's 2026-05-29 lesson).
func _apply_charm(unit: Combatant, stacks: int) -> void:
	if unit == null or stacks <= 0 or not unit.is_alive():
		return
	var before: int = unit.status_stacks(STATUS_CHARM)
	unit.add_status_stacks(STATUS_CHARM, stacks)
	var after: int = unit.status_stacks(STATUS_CHARM)
	var procs: int = after / CHARM_PROC_THRESHOLD - before / CHARM_PROC_THRESHOLD
	for _i in range(procs):
		apply_status(unit, STATUS_VULNERABLE, CHARM_PROC_STACKS)
		apply_status(unit, STATUS_WEAK, CHARM_PROC_STACKS)
	if after >= unit.max_hp:
		unit.hp = 0
		charm_executes += 1


## charm_damage (ADR-0028): block absorbs first (soaking BOTH the damage and the
## Charm — the mod's rule), then the unblocked remainder reduces hp AND applies
## that many Charm stacks. Offensive modifiers were already folded in by
## apply_effects, exactly like `damage`.
func charm_strike(target: Variant, amount: int) -> void:
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
		if unit.is_alive():
			_apply_charm(unit, remaining)


## consume_status_damage (ADR-0028, Coup de Grace): deal damage equal to the
## target's stacks of `status_id` (block absorbs, no stat scaling — the stacks
## ARE the payoff), then remove every stack.
func consume_status_damage(target: Variant, status_id: StringName) -> void:
	var unit: Combatant = _resolve_unit(target)
	if unit == null or status_id == &"" or not unit.is_alive():
		return
	var stacks: int = unit.status_stacks(status_id)
	if stacks <= 0:
		return
	deal_damage(unit, stacks)
	unit.set_status(status_id, 0)


## add_card (ADR-0028): put the registry card `card_id` into `unit`'s hand
## (token generation — Magic Missile et al.). Overflow past max_hand goes to the
## discard pile so the token is never lost. Unknown ids / empty lookups no-op.
func add_card_to_hand(card_id: StringName, unit: Combatant = null) -> void:
	var card: CardData = card_lookup.get(card_id, null)
	if card == null:
		return
	var who: Combatant = unit
	if who == null:
		var players := living_players()
		who = players[0] if not players.is_empty() else null
	if who == null:
		return
	var d: Deck = deck_of(who)
	if d.hand.size() < config.max_hand:
		d.hand.append(card)
	else:
		d.discard_pile.append(card)


## inflict_curse (ADR-0029): shuffle the registry curse `card_id` into the target
## PLAYER's discard pile (it joins the cycle this fight, StS-style) and record it
## so the run layer can persist it onto the member. Enemy targets / unknown ids
## no-op — curses are a player-side affliction.
func inflict_curse(card_id: StringName, target: Variant) -> void:
	var card: CardData = card_lookup.get(card_id, null)
	var unit: Combatant = _resolve_unit(target)
	if card == null or unit == null or not unit.is_player():
		return
	deck_of(unit).discard_pile.append(card)
	var data := unit.source_data as CharacterData
	var member: StringName = data.id if data != null else &""
	inflicted_curses.append({"member": member, "card": card_id})


## cleanse (ADR-0029): remove ALL stacks of each status named in `statuses` from
## the target (the antidote item). Cleansing `block` also clears the block field.
func cleanse(target: Variant, statuses: Variant) -> void:
	var unit: Combatant = _resolve_unit(target)
	if unit == null or not (statuses is Array):
		return
	for s_v: Variant in (statuses as Array):
		var sid := StringName(String(s_v))
		if sid == &"":
			continue
		if sid == STATUS_BLOCK:
			unit.block = 0
		unit.set_status(sid, 0)


## gain_gold (ADR-0029): bank found run gold; finish_combat credits it.
func add_gold(amount: int) -> void:
	gold_found += maxi(0, amount)


# ============================================================================
#  Damage with an attacker (strength / weak)  — used by apply_effects & AI
# ============================================================================

## Compute the stat/strength/weak-modified outgoing damage `attacker` deals for a
## base `amount`. The attacker's attack stat (STR or INT per `attack_stat`,
## ADR-0014) and Strength stacks add; Weak reduces by a fixed fraction. Kept as
## the single place offensive modifiers live so card play and enemy intents route
## through the same math. Enemies have no attack stat (attack_power == 0), so their
## intent damage stays as authored. Never returns below 0.
## `use_attack_stat` is false for neutral (flat) cards (ADR-0016) so they never
## scale with the actor's sheet; the Strength status still applies either way.
## `stat_mult` (ADR-0020): the stat contribution is floor(attack_power * stat_mult);
## 1.0 reproduces the original flat add exactly.
func modified_damage(
	attacker: Combatant, amount: int, use_attack_stat: bool = true, stat_mult: float = 1.0
) -> int:
	if attacker == null:
		return max(0, amount)
	var bonus: int = int(floor(float(attacker.attack_power()) * stat_mult)) if use_attack_stat else 0
	var out: int = amount + bonus + attacker.status_stacks(STATUS_STRENGTH)
	if attacker.has_status(STATUS_WEAK):
		# Weak: -25% outgoing (floored). Behaviour in code, the FLAG in data.
		out = int(floor(float(out) * 0.75))
	return max(0, out)


## Compute the DEX-modified block `source` grants for a base `amount` (ADR-0014:
## DEX -> block). Enemies have dexterity 0; `use_dex` is false for neutral (flat)
## cards (ADR-0016). `stat_mult` (ADR-0020): the DEX contribution is
## floor(DEX * stat_mult); 1.0 reproduces the original flat add exactly.
func modified_block(
	source: Variant, amount: int, use_dex: bool = true, stat_mult: float = 1.0
) -> int:
	var dex: int = (source as Combatant).dexterity if (use_dex and source is Combatant) else 0
	return max(0, amount + int(floor(float(dex) * stat_mult)))


## Deal damage FROM `attacker` to `target`, applying strength/weak first, then the
## target's Vulnerable (an ATTACK-only amplifier — bare deal_damage / poison stays
## unaffected), then the defensive block/hp routing of deal_damage. This is the
## source-aware entry the bare deal_damage cannot express; AI and apply_effects use
## it for `damage`.
func deal_damage_from(attacker: Combatant, target: Combatant, amount: int) -> void:
	var dmg: int = modified_damage(attacker, amount)
	if target != null and target.has_status(STATUS_VULNERABLE):
		dmg = int(floor(float(dmg) * VULNERABLE_MULT))
	dmg = _mark_amplified(target, dmg)
	deal_damage(target, dmg)


## Mark (M3): a marked target takes +stacks FLAT damage on an attack hit, added
## AFTER multipliers (Vulnerable), then loses ONE stack — many small hits cash
## the bonus more often than one big hit (the rogue payoff; Vulnerable is the
## big-hit percentage). Attack-only, like Vulnerable: bare deal_damage (poison/
## burn ticks) never routes through here. Zero-damage non-hits don't consume.
func _mark_amplified(target: Variant, dmg: int) -> int:
	var unit: Combatant = _resolve_unit(target)
	if unit == null or dmg <= 0 or not unit.has_status(STATUS_MARK):
		return dmg
	var bonus: int = unit.status_stacks(STATUS_MARK)
	unit.add_status_stacks(STATUS_MARK, -1)
	return dmg + bonus


# ============================================================================
#  Effect application primitive (criterion 6)
# ============================================================================

## Apply a card/intent `effects` list from `source` onto `target` by driving the
## EffectResolver with THIS BattleState as the context. `target` may be a single
## Combatant or an Array[Combatant] (an AoE target set from resolve_targets).
## Targeted effects apply to each unit in the set; GLOBAL_EFFECTS (draw,
## gain_energy) apply ONCE regardless of set size. For `damage`, the attacker's
## strength/weak is folded in before dispatch (the BattleContext seam is source-less).
## `scale_with_stats` folds the source's attack stat (damage) and DEX (block) in;
## pass false for neutral flat cards (ADR-0016). The Strength status still applies.
func apply_effects(source: Combatant, target: Variant, effects: Array, scale_with_stats: bool = true) -> void:
	var targets: Array = target if target is Array else [target]
	# Ascension (ADR-0022): the member's flat stat_mult step rides on every card.
	var mult_step: float = source.ascension_mult if source != null else 0.0
	for effect in effects:
		if not (effect is Effect):
			continue
		var e: Effect = effect
		if GLOBAL_EFFECTS.has(e.type):
			_resolver.resolve(e, source, null, self)
			continue
		if SOURCE_EFFECTS.has(e.type):
			# ADR-0028: caster-side effects fire ONCE, on the SOURCE, regardless of
			# the card's target set (a 3-enemy bomb taxes its thrower once). The
			# self_damage tax stays RAW (block absorbs; never stat-amplified — the
			# mod's THORNS rule); self_block scales with DEX like any block grant.
			var se := e.duplicate() as Effect
			if e.type == &"self_block":
				se.amount = modified_block(source, e.amount, scale_with_stats, e.stat_mult + mult_step)
			_resolver.resolve(se, source, source, self)
			continue
		for t in targets:
			if e.type == &"damage" or e.type == &"charm_damage":
				var modified := e.duplicate() as Effect
				modified.amount = modified_damage(source, e.amount, scale_with_stats, e.stat_mult + mult_step)
				# Vulnerable amplifies ATTACK damage at the point of impact (parity
				# with deal_damage_from(); previously only that unused source-aware
				# path applied it, so card/intent attacks ignored Vulnerable).
				if t is Combatant and (t as Combatant).has_status(STATUS_VULNERABLE):
					modified.amount = int(floor(float(modified.amount) * VULNERABLE_MULT))
				# Mark (M3): flat bonus after the multiplier, one stack consumed per hit.
				modified.amount = _mark_amplified(t, modified.amount)
				_resolver.resolve(modified, source, t, self)
			elif e.type == &"block":
				var mb := e.duplicate() as Effect
				mb.amount = modified_block(source, e.amount, scale_with_stats, e.stat_mult + mult_step)
				_resolver.resolve(mb, source, t, self)
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
	# ADR-0025: each living player's OWN pool refills; the economy scales with
	# party size (solo Act 1 = one pool) instead of being a flat shared 3.
	_energy.clear()
	for unit in living_players():
		_energy[unit] = config.energy_per_character
	_tick_statuses(Combatant.Team.PLAYER)
	# ADR-0026: every living player draws their own per-turn hand from their own
	# deck (the legacy shared deck draws only when no member decks exist).
	if decks.is_empty():
		deck.draw_for_turn()
	else:
		for unit in living_players():
			_apply_on_draw(unit, deck_of(unit).draw_for_turn())


## When-drawn downsides (ADR-0029): a drawn card with `on_draw_damage` bites the
## DRAWING unit (blockable, like any plain hit — block has usually just reset at
## the owner's turn start, so it lands on HP). Applied wherever a unit draws into
## its own hand (turn draw + the `draw` effect); the legacy shared-deck fixture
## path has no owner and skips it.
func _apply_on_draw(unit: Combatant, drawn: Array[CardData]) -> void:
	if unit == null:
		return
	for card in drawn:
		if card != null and card.on_draw_damage > 0:
			deal_damage(unit, card.on_draw_damage)


## End the player turn: discard the hand back into the cycle, then run the enemy
## phase. Kept as one call so a caller (UI) has a single "end turn" hook.
func end_player_turn() -> void:
	if decks.is_empty():
		deck.discard_hand()
	else:
		for unit in living_players():
			deck_of(unit).discard_hand()
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
		# Bleed (M3): acting opens the wound — a stunned (skipped) enemy doesn't proc.
		on_unit_acted(enemy)
	phase = Phase.PLAYER


## Bleed proc (M3): call when `unit` ACTS — a player playing a card (CardPlay) or
## an enemy executing its intent (_run_enemy_phase). A bleeding unit takes its
## Bleed stacks as damage that IGNORES block (exertion, not incoming attack —
## armor can't stitch a wound), then loses ONE stack. Unlike poison/burn, Bleed
## does NOT tick or decay per turn: a unit that holds still bleeds nothing.
func on_unit_acted(unit: Combatant) -> void:
	if unit == null or not unit.is_alive():
		return
	var bleed: int = unit.status_stacks(STATUS_BLEED)
	if bleed <= 0:
		return
	deal_unblockable(unit, bleed)
	unit.add_status_stacks(STATUS_BLEED, -1)


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
	# Poison: deal its stacks as damage that IGNORES block (anti-turtle: block can't
	# soak a DoT), then drop one stack. Magnitude == stack count; the -1 is the decay.
	var poison: int = unit.status_stacks(STATUS_POISON)
	if poison > 0:
		deal_unblockable(unit, poison)
		if _status_decays(STATUS_POISON):
			unit.add_status_stacks(STATUS_POISON, -1)
		if not unit.is_alive():
			return

	# Burn (M3): the mage DoT — same timing and magnitude as poison (stacks as
	# damage, then -1), but routed through deal_damage so BLOCK ABSORBS it. Ticks
	# BEFORE the block reset below, so leftover block from last turn soaks the
	# flame — the blockability that differentiates burn from poison.
	var burn: int = unit.status_stacks(STATUS_BURN)
	if burn > 0:
		deal_damage(unit, burn)
		if _status_decays(STATUS_BURN):
			unit.add_status_stacks(STATUS_BURN, -1)
		if not unit.is_alive():
			return

	# Block: consumed by incoming damage during the turn; at the owner's turn
	# start it resets if its StatusData decays (the prototype default).
	if _status_decays(STATUS_BLOCK):
		unit.block = 0
		unit.set_status(STATUS_BLOCK, 0)

	# Strength / weak / vulnerable / frail: decay one stack per turn iff their
	# StatusData says so (duration-style debuffs that last 1-2 turns).
	if _status_decays(STATUS_STRENGTH):
		unit.add_status_stacks(STATUS_STRENGTH, -1)
	if _status_decays(STATUS_WEAK):
		unit.add_status_stacks(STATUS_WEAK, -1)
	if _status_decays(STATUS_VULNERABLE):
		unit.add_status_stacks(STATUS_VULNERABLE, -1)
	if _status_decays(STATUS_FRAIL):
		unit.add_status_stacks(STATUS_FRAIL, -1)

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
