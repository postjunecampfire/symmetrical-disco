class_name EffectResolver
extends RefCounted
## Dispatches a single Effect (src/data/effect.gd, §2.2) onto a battle context
## (P1·03). Given an already-chosen `target`, the resolver reads `effect.type`
## and translates it into exactly ONE BattleContext call (src/combat/battle_context.gd).
##
## Scope (deliberately narrow):
##   - Targeting/selection is NOT here. The card-play task chooses `target` and
##     hands it over already resolved; the resolver just applies the effect.
##   - Only the §2.3 PROTOTYPE registry is handled: damage, block, heal,
##     apply_status, move, push, draw, gain_energy. Deferred types (summon,
##     teleport, …) are intentionally unknown until their handler ships.
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
	&"move",
	&"push",
	&"draw",
	&"gain_energy",
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
		&"move":
			# The acting unit (source) relocates onto the resolved destination
			# tile. Targeting picked the tile and handed it over as `target`.
			context.move_unit(source, _as_tile(target))
		&"push":
			# Shove `target` `amount` tiles away from the acting unit (source).
			context.push_unit(target, effect.amount, source)
		&"draw":
			context.draw_cards(effect.amount)
		&"gain_energy":
			context.add_energy(effect.amount)
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


## Normalize a resolved `move` target into a tile coord. A tile target is a
## Vector2i already; anything else is passed straight through so a context that
## models units-as-tiles still works. Kept tiny and isolated so the destination
## convention lives in one place.
func _as_tile(target: Variant) -> Vector2i:
	if target is Vector2i:
		return target
	return Vector2i.ZERO
