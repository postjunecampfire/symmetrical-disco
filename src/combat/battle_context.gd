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
## Conventions:
##   - `target` / `unit` / `source` are opaque to the resolver: they are whatever
##     the battle state uses for units (an id, a node, a unit object). The
##     resolver never inspects them; it only passes them through. P1·04 picks the
##     concrete type.
##   - Tile coords are `Vector2i` (matches GridModel / data-schemas.md §6).
##   - These methods are the WHOLE contract. The resolver calls nothing else on
##     the context.
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


## Move `unit` onto tile `to_tile`. (effect.type == "move")
## The acting unit relocates to the resolved destination tile.
func move_unit(_unit: Variant, _to_tile: Vector2i) -> void:
	push_error("BattleContext.move_unit() not implemented")


## Shove `target` `amount` tiles directly away from `from`. (effect.type == "push")
## `from` is the push origin (the source/acting unit's position or unit); the
## context computes the displaced destination and applies any collision rules.
func push_unit(_target: Variant, _amount: int, _from: Variant) -> void:
	push_error("BattleContext.push_unit() not implemented")


## Draw `n` cards for the active side. (effect.type == "draw")
func draw_cards(_n: int) -> void:
	push_error("BattleContext.draw_cards() not implemented")


## Add `n` energy to the shared pool this turn. (effect.type == "gain_energy")
func add_energy(_n: int) -> void:
	push_error("BattleContext.add_energy() not implemented")
