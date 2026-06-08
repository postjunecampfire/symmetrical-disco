class_name BattleContext
extends RefCounted
## The interface the EffectResolver (P1·03) needs from battle state.
##
## This is a documented "interface" base: a small, stable set of methods the
## resolver calls to actually mutate combat. P1·04 (battle state) implements it
## for real — by extending this class or by duck-typing the same method names.
## Keeping the surface tiny here is deliberate: the resolver dispatches on
## effect.type and translates each effect into ONE of these calls, so this is the
## seam between "what an effect means" (data, §2.3) and "how combat changes"
## (state). Do not grow it without a matching effect-type/registry change.
##
## Positionless (ADR-0013): there are no move/push primitives — combat has no
## board. `target` / `source` are opaque to the resolver (a Combatant in P1·04);
## the resolver never inspects them, it only passes them through.
##
## The bodies below are unimplemented stubs that push_error() if called. A real
## context (P1·04) overrides every one. The test suite supplies its own stub
## context that records calls instead of extending this — both are valid, since
## the resolver only relies on the method NAMES and SIGNATURES, not this type.

## Deal `amount` damage to `target`. (effect.type == "damage")
func deal_damage(_target: Variant, _amount: int) -> void:
	push_error("BattleContext.deal_damage() not implemented")


## Grant `amount` block to `target`. (effect.type == "block")
func add_block(_target: Variant, _amount: int) -> void:
	push_error("BattleContext.add_block() not implemented")


## Restore `amount` HP to `target`. (effect.type == "heal")
func heal(_target: Variant, _amount: int) -> void:
	push_error("BattleContext.heal() not implemented")


## Add `stacks` of status `status_id` to `target`. (effect.type == "apply_status")
func apply_status(_target: Variant, _status_id: StringName, _stacks: int) -> void:
	push_error("BattleContext.apply_status() not implemented")


## Draw `n` cards for the active side. (effect.type == "draw")
func draw_cards(_n: int) -> void:
	push_error("BattleContext.draw_cards() not implemented")


## Add `n` energy to the shared pool this turn. (effect.type == "gain_energy")
func add_energy(_n: int) -> void:
	push_error("BattleContext.add_energy() not implemented")
