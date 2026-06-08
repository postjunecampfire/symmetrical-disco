extends "res://addons/gut/test.gd"
## GUT suite for src/combat/effect_resolver.gd (task P1·03, positionless ADR-0013).
##
## Each prototype effect type (§2.3) is dispatched through the resolver onto a
## lightweight stub context that simply RECORDS the call (method name + args).
## The assertions prove the resolver invokes the right BattleContext method with
## the right arguments — never more than one call per effect — and that an
## unknown effect.type is reported (detection path) without mutating anything.
##
## Positionless: there are no move/push effects (removed with the grid).

const EffectResolverScript := preload("res://src/combat/effect_resolver.gd")


## Records every BattleContext call the resolver makes. Each entry in `calls` is
## { "method": StringName, "args": Array }.
class RecordingContext extends BattleContext:
	var calls: Array[Dictionary] = []

	func _record(method: StringName, args: Array) -> void:
		calls.append({"method": method, "args": args})

	func deal_damage(target: Variant, amount: int) -> void:
		_record(&"deal_damage", [target, amount])

	func add_block(target: Variant, amount: int) -> void:
		_record(&"add_block", [target, amount])

	func heal(target: Variant, amount: int) -> void:
		_record(&"heal", [target, amount])

	func apply_status(target: Variant, status_id: StringName, stacks: int) -> void:
		_record(&"apply_status", [target, status_id, stacks])

	func draw_cards(n: int) -> void:
		_record(&"draw_cards", [n])

	func add_energy(n: int) -> void:
		_record(&"add_energy", [n])


# --- Helpers ----------------------------------------------------------------

func _resolver() -> EffectResolver:
	return EffectResolverScript.new()


func _effect(type: StringName) -> Effect:
	var e := Effect.new()
	e.type = type
	return e


# --- damage -----------------------------------------------------------------

func test_damage_calls_deal_damage_with_amount() -> void:
	var ctx := RecordingContext.new()
	var e := _effect(&"damage")
	e.amount = 6
	var result := _resolver().resolve(e, &"source", &"goblin", ctx)

	assert_true(result.ok, "known type resolves ok")
	assert_eq(ctx.calls.size(), 1, "exactly one context call")
	assert_eq(ctx.calls[0]["method"], &"deal_damage")
	assert_eq(ctx.calls[0]["args"], [&"goblin", 6])


# --- block ------------------------------------------------------------------

func test_block_calls_add_block_with_amount() -> void:
	var ctx := RecordingContext.new()
	var e := _effect(&"block")
	e.amount = 5
	var result := _resolver().resolve(e, &"source", &"hero", ctx)

	assert_true(result.ok)
	assert_eq(ctx.calls.size(), 1)
	assert_eq(ctx.calls[0]["method"], &"add_block")
	assert_eq(ctx.calls[0]["args"], [&"hero", 5])


# --- heal -------------------------------------------------------------------

func test_heal_calls_heal_with_amount() -> void:
	var ctx := RecordingContext.new()
	var e := _effect(&"heal")
	e.amount = 8
	var result := _resolver().resolve(e, &"source", &"hero", ctx)

	assert_true(result.ok)
	assert_eq(ctx.calls.size(), 1)
	assert_eq(ctx.calls[0]["method"], &"heal")
	assert_eq(ctx.calls[0]["args"], [&"hero", 8])


# --- apply_status -----------------------------------------------------------

func test_apply_status_passes_status_id_and_stacks() -> void:
	var ctx := RecordingContext.new()
	var e := _effect(&"apply_status")
	e.status = &"poison"
	e.stacks = 3
	var result := _resolver().resolve(e, &"source", &"goblin", ctx)

	assert_true(result.ok)
	assert_eq(ctx.calls.size(), 1)
	assert_eq(ctx.calls[0]["method"], &"apply_status")
	assert_eq(ctx.calls[0]["args"], [&"goblin", &"poison", 3])


# --- draw -------------------------------------------------------------------

func test_draw_calls_draw_cards_with_amount() -> void:
	var ctx := RecordingContext.new()
	var e := _effect(&"draw")
	e.amount = 2
	var result := _resolver().resolve(e, &"source", null, ctx)

	assert_true(result.ok)
	assert_eq(ctx.calls.size(), 1)
	assert_eq(ctx.calls[0]["method"], &"draw_cards")
	assert_eq(ctx.calls[0]["args"], [2])


# --- gain_energy ------------------------------------------------------------

func test_gain_energy_calls_add_energy_with_amount() -> void:
	var ctx := RecordingContext.new()
	var e := _effect(&"gain_energy")
	e.amount = 1
	var result := _resolver().resolve(e, &"source", null, ctx)

	assert_true(result.ok)
	assert_eq(ctx.calls.size(), 1)
	assert_eq(ctx.calls[0]["method"], &"add_energy")
	assert_eq(ctx.calls[0]["args"], [1])


# --- removed positional types are now unknown -------------------------------

func test_move_effect_type_is_now_unknown() -> void:
	# `move` was removed with the grid (ADR-0013); it must no longer resolve.
	var ctx := RecordingContext.new()
	var result := _resolver().resolve(_effect(&"move"), &"hero", &"target", ctx)
	assert_false(result.ok, "move is no longer a handled effect type")
	assert_eq(ctx.calls.size(), 0, "removed type applies nothing")


func test_push_effect_type_is_now_unknown() -> void:
	var ctx := RecordingContext.new()
	var result := _resolver().resolve(_effect(&"push"), &"hero", &"target", ctx)
	assert_false(result.ok, "push is no longer a handled effect type")
	assert_eq(ctx.calls.size(), 0, "removed type applies nothing")


# --- unknown type (detection path) ------------------------------------------

func test_unknown_effect_type_reports_and_applies_nothing() -> void:
	var ctx := RecordingContext.new()
	var e := _effect(&"summon")  # a deferred / unhandled type
	var result := _resolver().resolve(e, &"source", &"target", ctx)

	assert_false(result.ok, "unknown type must not resolve ok")
	assert_true(
		result.error.findn("unknown effect.type") != -1,
		"error should name the failure: %s" % result.error
	)
	assert_true(result.error.findn("summon") != -1, "error should name the type")
	assert_eq(ctx.calls.size(), 0, "unknown type applies nothing to the context")


func test_null_effect_reports_and_applies_nothing() -> void:
	var ctx := RecordingContext.new()
	var result := _resolver().resolve(null, &"source", &"target", ctx)

	assert_false(result.ok, "null effect must not resolve ok")
	assert_eq(ctx.calls.size(), 0, "null effect applies nothing")


# --- registry sanity --------------------------------------------------------

func test_handled_types_match_prototype_registry() -> void:
	# The resolver's handled set should match the loader's §2.3 prototype
	# registry exactly, so every loadable effect.type has a handler.
	var handled := EffectResolverScript.HANDLED_TYPES.duplicate()
	var expected := ContentDatabase.EFFECT_TYPES.duplicate()
	handled.sort()
	expected.sort()
	assert_eq(handled, expected, "handled types mirror the loader's registry")
	assert_false(handled.has(&"move"), "move removed from the registry")
	assert_false(handled.has(&"push"), "push removed from the registry")
