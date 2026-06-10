class_name EffectResolver
extends RefCounted
## Dispatches a single Effect (src/data/effect.gd, §2.2) onto a battle context
## (P1·03). Given an already-chosen `target`, the resolver reads `effect.type`
## and translates it into exactly ONE BattleContext call (src/combat/battle_context.gd).
##
## Scope (deliberately narrow):
##   - Targeting/selection is NOT here. The card-play / AI layer resolves the
##     target set (positionless, by TargetSpec.target_type) and hands each
##     concrete target over; the resolver just applies the effect.
##   - Only the §2.3 PROTOTYPE registry is handled: damage, block, heal,
##     apply_status, draw, gain_energy. Positional effects (move, push) were
##     removed with the grid (ADR-0013). Deferred types (summon, teleport, …)
##     are intentionally unknown until their handler ships.
##
## Error reporting follows the ContentDatabase pattern (detection vs. reporting):
##   - resolve()        : COLLECTS an unknown-type problem into the returned
##                        ResolveResult and applies nothing for it; it never
##                        push_error()s, so the dispatch path stays unit-testable.
##   - resolve_and_report(): wraps resolve() and additionally push_error()s any
##                        collected problem, preserving "fail LOUDLY" for real runs.
##
## The resolver holds no state; one instance can resolve any number of effects.

## The §2.3 prototype effect-type registry this resolver can apply. Mirrors
## ContentDatabase.EFFECT_TYPES; any effect.type outside this set is unknown.
const HANDLED_TYPES: Array[StringName] = [
	&"damage",
	&"block",
	&"heal",
	&"apply_status",
	&"draw",
	&"gain_energy",
	# ADR-0028 (DCC adaptation): caster-side taxes/riders, Charm attacks, the
	# Charm cash-in, and token generation. Mirrors ContentDatabase.EFFECT_TYPES.
	&"self_damage",
	&"self_block",
	&"charm_damage",
	&"consume_status_damage",
	&"add_card",
	# ADR-0029 (injected card layer): curse infliction, item cleanses, found gold.
	&"inflict_curse",
	&"cleanse",
	&"gain_gold",
]


## Result of a resolve attempt. `ok` is true only when `error` is empty.
## Detection-only: building one of these never emits an engine error, so tests
## can exercise the unknown-type path without tripping GUT's error tracker.
class ResolveResult extends RefCounted:
	var ok: bool = true
	var error: String = ""

	func _init(err: String = "") -> void:
		error = err
		ok = err.is_empty()


## Apply `effect` from `source` onto the already-resolved `target`, mutating
## `context`. Returns a ResolveResult; on an unknown effect.type it applies
## nothing and reports ok == false with a descriptive error. Never push_error()s
## (see resolve_and_report() for the loud variant).
func resolve(effect: Effect, source: Variant, target: Variant, context: BattleContext) -> ResolveResult:
	if effect == null:
		return ResolveResult.new("EffectResolver: null effect")

	match effect.type:
		&"damage":
			context.deal_damage(target, effect.amount)
		&"block":
			context.add_block(target, effect.amount)
		&"heal":
			context.heal(target, effect.amount)
		&"apply_status":
			context.apply_status(target, effect.status, effect.stacks)
		&"draw":
			# ADR-0026: drawn cards go to the CASTER's own hand.
			var drawer: Combatant = source if source is Combatant else null
			context.draw_cards(effect.amount, drawer)
		&"gain_energy":
			# ADR-0025: energy gained by a card credits the CASTER's own pool.
			# Non-Combatant sources (context fakes, source-less seams) fall back
			# to the context's default pool attribution.
			var caster: Combatant = source if source is Combatant else null
			context.add_energy(effect.amount, caster)
		&"self_damage":
			# ADR-0028: caster-side tax. apply_effects routes the SOURCE in as the
			# target (once per card); raw damage — block absorbs, never amplified.
			context.deal_damage(target if target != null else source, effect.amount)
		&"self_block":
			# ADR-0028: caster-side block rider (amount pre-scaled by apply_effects).
			context.add_block(target if target != null else source, effect.amount)
		&"charm_damage":
			# ADR-0028: Charm attack — damage, then Charm equal to the UNBLOCKED
			# portion. The context owns the block/Charm math.
			context.charm_strike(target, effect.amount)
		&"consume_status_damage":
			# ADR-0028: cash-in (Coup de Grace) — damage equal to the target's
			# stacks of `status`, then remove them all.
			context.consume_status_damage(target, effect.status)
		&"add_card":
			# ADR-0028: token generation — add params.card_id to the CASTER's hand.
			var token_owner: Combatant = source if source is Combatant else null
			context.add_card_to_hand(StringName(String(effect.params.get("card_id", ""))), token_owner)
		&"inflict_curse":
			# ADR-0029: curse params.card_id joins the TARGET's discard pile (and is
			# recorded for run persistence by the context).
			context.inflict_curse(StringName(String(effect.params.get("card_id", ""))), target)
		&"cleanse":
			# ADR-0029: strip every stack of each listed status from the target.
			context.cleanse(target, effect.params.get("statuses", []))
		&"gain_gold":
			# ADR-0029: found gold — banked on the context, credited post-combat.
			context.add_gold(effect.amount)
		_:
			return ResolveResult.new(
				"EffectResolver: unknown effect.type '%s'" % effect.type
			)

	return ResolveResult.new()


## Resolve like resolve(), then fail LOUDLY: push_error() the collected problem
## (if any) so a real battle surfaces a bad/unhandled effect in the console.
## Detection itself stays in resolve(); this only adds the loud reporting on top.
func resolve_and_report(effect: Effect, source: Variant, target: Variant, context: BattleContext) -> ResolveResult:
	var result := resolve(effect, source, target, context)
	if not result.ok:
		push_error("[EffectResolver] " + result.error)
	return result
