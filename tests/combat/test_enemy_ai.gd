extends "res://addons/gut/test.gd"
## GUT suite for src/combat/enemy_ai.gd (task P1·08, positionless ADR-0013):
## enemy intent selection, telegraphing, and execution on the enemy phase.
##
## Builds everything IN CODE (no JSON/.tres): a BattleState with the five
## prototype StatusData defs, player/enemy combatants, and EnemyData carrying
## hand-built IntentData. Asserts:
##   - weighted selection is deterministic under a fixed seed and respects weights;
##   - the `sequence` pattern cycles intents in order;
##   - get_telegraph() reflects the upcoming intent (and its lowest-HP target);
##   - take_turn() damages the LOWEST-HP player for a single-target intent;
##   - an all_enemies intent hits every player;
##   - a self/buff intent acts on the enemy itself;
##   - graceful no-target / no-intent / dead-enemy handling.

const EnemyAIScript := preload("res://src/combat/enemy_ai.gd")
const BattleStateScript := preload("res://src/combat/battle_state.gd")
const CombatantScript := preload("res://src/combat/combatant.gd")


# --- Fixtures ---------------------------------------------------------------

func _config(energy: int = 3, draw: int = 0) -> BattleConfig:
	var c := BattleConfig.new()
	c.energy_per_turn = energy
	c.draw_per_turn = draw
	c.max_hand = 10
	c.reshuffle_discard = true
	return c


func _status(id: StringName, stacking: StringName, decays: bool) -> StatusData:
	var s := StatusData.new()
	s.id = id
	s.display_name = String(id)
	s.stacking = stacking
	s.decays_each_turn = decays
	return s


func _status_defs() -> Dictionary:
	var defs := {}
	defs[&"poison"] = _status(&"poison", &"intensity", true)
	defs[&"block"] = _status(&"block", &"intensity", true)
	defs[&"stun"] = _status(&"stun", &"duration", true)
	defs[&"strength"] = _status(&"strength", &"intensity", false)
	defs[&"weak"] = _status(&"weak", &"duration", true)
	return defs


func _state(energy: int = 3) -> BattleState:
	var cfg := _config(energy, 0)
	var deck := Deck.new(cfg)
	return BattleStateScript.new(cfg, deck, _status_defs())


func _character(hp: int) -> CharacterData:
	var d := CharacterData.new()
	d.id = &"hero"
	d.display_name = "Hero"
	d.max_hp = hp
	return d


func _add_player(state: BattleState, hp: int) -> Combatant:
	return state.add_combatant(CombatantScript.from_character(_character(hp)))


func _add_enemy(state: BattleState, data: EnemyData) -> Combatant:
	return state.add_combatant(CombatantScript.from_enemy(data))


func _damage_effect(amount: int) -> Effect:
	var e := Effect.new()
	e.type = &"damage"
	e.amount = amount
	return e


func _block_effect(amount: int) -> Effect:
	var e := Effect.new()
	e.type = &"block"
	e.amount = amount
	return e


## An IntentData with the given id, telegraph, weight, effects, and target kind.
func _intent(id: StringName, telegraph: StringName, weight: int,
		effects: Array[Effect], target_type: StringName = &"enemy") -> IntentData:
	var i := IntentData.new()
	i.id = id
	i.telegraph = telegraph
	i.weight = weight
	var spec := TargetSpec.new()
	spec.target_type = target_type
	i.target = spec
	i.effects = effects
	return i


func _enemy_data(pattern: StringName, intents: Array[IntentData]) -> EnemyData:
	var d := EnemyData.new()
	d.id = &"grunt"
	d.display_name = "Grunt"
	d.max_hp = 30
	d.intent_pattern = pattern
	d.intents = intents
	return d


# ============================================================================
#  1. Weighted selection — deterministic + respects weights
# ============================================================================

func test_weighted_selection_is_deterministic_under_fixed_seed() -> void:
	var state := _state()
	var enemy := _add_enemy(state, _enemy_data(&"random_weighted", []))
	_add_player(state, 30)

	var atk_a := _intent(&"a", &"attack", 1, [_damage_effect(3)] as Array[Effect])
	var atk_b := _intent(&"b", &"attack", 1, [_damage_effect(3)] as Array[Effect])
	var atk_c := _intent(&"c", &"attack", 1, [_damage_effect(3)] as Array[Effect])
	var data := _enemy_data(&"random_weighted", [atk_a, atk_b, atk_c] as Array[IntentData])

	var ai1 := EnemyAIScript.new(1234)
	var ai2 := EnemyAIScript.new(1234)
	var seq1: Array = []
	var seq2: Array = []
	for _i in range(20):
		seq1.append(ai1.select_intent(enemy, data, state).id)
		seq2.append(ai2.select_intent(enemy, data, state).id)
	assert_eq(seq1, seq2, "same seed reproduces the same weighted-pick sequence")


func test_weighted_selection_never_picks_zero_weight_and_favors_dominant() -> void:
	var state := _state()
	var enemy := _add_enemy(state, _enemy_data(&"random_weighted", []))
	_add_player(state, 30)

	var never := _intent(&"never", &"attack", 0, [_damage_effect(3)] as Array[Effect])
	var dominant := _intent(&"dominant", &"attack", 9, [_damage_effect(3)] as Array[Effect])
	var minor := _intent(&"minor", &"attack", 1, [_damage_effect(3)] as Array[Effect])
	var data := _enemy_data(&"random_weighted", [never, dominant, minor] as Array[IntentData])

	var ai := EnemyAIScript.new(99)
	var counts := {&"never": 0, &"dominant": 0, &"minor": 0}
	for _i in range(1000):
		counts[ai.select_intent(enemy, data, state).id] += 1

	assert_eq(counts[&"never"], 0, "a 0-weight intent is never chosen")
	assert_gt(counts[&"dominant"], counts[&"minor"], "the dominant weight is chosen most")
	assert_gt(counts[&"dominant"], 800, "weight 9/10 dominates over 1000 draws")


# ============================================================================
#  2. Sequence pattern — cycles in order
# ============================================================================

func test_sequence_pattern_cycles_in_order() -> void:
	var state := _state()
	var enemy := _add_enemy(state, _enemy_data(&"sequence", []))
	_add_player(state, 30)

	var one := _intent(&"one", &"attack", 1, [_damage_effect(3)] as Array[Effect])
	var two := _intent(&"two", &"block", 1, [_block_effect(3)] as Array[Effect], &"self")
	var three := _intent(&"three", &"attack", 1, [_damage_effect(3)] as Array[Effect])
	var data := _enemy_data(&"sequence", [one, two, three] as Array[IntentData])

	var ai := EnemyAIScript.new(0)
	var order: Array = []
	for _i in range(7):
		order.append(ai.select_intent(enemy, data, state).id)

	assert_eq(
		order,
		[&"one", &"two", &"three", &"one", &"two", &"three", &"one"],
		"sequence cycles intents in order and wraps"
	)


# ============================================================================
#  3. Telegraph — reflects the upcoming intent before it resolves
# ============================================================================

func test_telegraph_reflects_upcoming_intent_before_resolve() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	var atk := _intent(&"slash", &"attack", 1, [_damage_effect(5)] as Array[Effect])
	var data := _enemy_data(&"sequence", [atk] as Array[IntentData])
	var enemy := _add_enemy(state, data)

	var ai := EnemyAIScript.new(0)
	assert_null(ai.get_telegraph(enemy), "no telegraph before selection")

	ai.select_intent(enemy, data, state)
	var tel := ai.get_telegraph(enemy)
	assert_not_null(tel, "telegraph exists after selection")
	assert_eq(tel.intent.id, &"slash", "telegraph names the upcoming intent")
	assert_eq(tel.intent.telegraph, &"attack", "telegraph exposes the icon")
	assert_eq(tel.target, player, "telegraph resolved the lowest-HP player as target")
	assert_eq(player.hp, 30, "telegraph does NOT resolve effects yet")
	assert_eq(ai.get_telegraphed_intent(enemy).id, &"slash")


# ============================================================================
#  4. Execution — damages lowest-HP player / AoE / self-buff
# ============================================================================

func test_take_turn_damages_lowest_hp_player() -> void:
	var state := _state()
	var healthy := _add_player(state, 30)
	var hurt := _add_player(state, 10)
	var atk := _intent(&"slash", &"attack", 1, [_damage_effect(6)] as Array[Effect])
	var data := _enemy_data(&"sequence", [atk] as Array[IntentData])
	var enemy := _add_enemy(state, data)

	var ai := EnemyAIScript.new(0)
	ai.take_turn(state, enemy, data)

	assert_eq(hurt.hp, 4, "single-target intent hits the lowest-HP player (10 - 6)")
	assert_eq(healthy.hp, 30, "the healthier player is untouched")


func test_take_turn_aoe_intent_hits_every_player() -> void:
	var state := _state()
	var p1 := _add_player(state, 30)
	var p2 := _add_player(state, 20)
	var nova := _intent(&"quake", &"attack", 1, [_damage_effect(5)] as Array[Effect], &"all_enemies")
	var data := _enemy_data(&"sequence", [nova] as Array[IntentData])
	var enemy := _add_enemy(state, data)

	var ai := EnemyAIScript.new(0)
	ai.take_turn(state, enemy, data)

	assert_eq(p1.hp, 25, "AoE hit the first player")
	assert_eq(p2.hp, 15, "AoE hit the second player")


func test_take_turn_self_buff_intent_gains_block() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	var guard := _intent(&"guard", &"block", 1, [_block_effect(7)] as Array[Effect], &"self")
	var data := _enemy_data(&"sequence", [guard] as Array[IntentData])
	var enemy := _add_enemy(state, data)

	var ai := EnemyAIScript.new(0)
	ai.take_turn(state, enemy, data)

	assert_eq(enemy.block, 7, "block intent applied to the enemy itself")
	assert_eq(player.hp, 30, "self/buff intent does not hit the player")


# ============================================================================
#  5. Graceful handling — no target, no intents, lazy selection
# ============================================================================

func test_take_turn_no_living_player_is_graceful_noop() -> void:
	var state := _state()
	var atk := _intent(&"slash", &"attack", 1, [_damage_effect(6)] as Array[Effect])
	var data := _enemy_data(&"sequence", [atk] as Array[IntentData])
	var enemy := _add_enemy(state, data)

	var ai := EnemyAIScript.new(0)
	var result := ai.take_turn(state, enemy, data)

	assert_null(result, "no living player -> no action performed")


func test_take_turn_no_intents_is_graceful_noop() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	var data := _enemy_data(&"random_weighted", [] as Array[IntentData])
	var enemy := _add_enemy(state, data)

	var ai := EnemyAIScript.new(0)
	var result := ai.take_turn(state, enemy, data)

	assert_null(result, "no intents -> no action")
	assert_eq(player.hp, 30, "no damage dealt")


func test_take_turn_dead_enemy_is_graceful_noop() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	var atk := _intent(&"slash", &"attack", 1, [_damage_effect(6)] as Array[Effect])
	var data := _enemy_data(&"sequence", [atk] as Array[IntentData])
	var enemy := _add_enemy(state, data)
	enemy.hp = 0

	var ai := EnemyAIScript.new(0)
	var result := ai.take_turn(state, enemy, data)

	assert_null(result, "a dead enemy takes no turn")
	assert_eq(player.hp, 30, "dead enemy deals no damage")


func test_take_turn_lazily_selects_when_no_telegraph_pending() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	var atk := _intent(&"slash", &"attack", 1, [_damage_effect(5)] as Array[Effect])
	var data := _enemy_data(&"sequence", [atk] as Array[IntentData])
	var enemy := _add_enemy(state, data)

	var ai := EnemyAIScript.new(0)
	assert_null(ai.get_telegraph(enemy), "no telegraph pre-selected")
	var result := ai.take_turn(state, enemy, data)

	assert_not_null(result, "lazily selected and performed an intent")
	assert_eq(result.id, &"slash")
	assert_eq(player.hp, 25, "lazily selected intent's damage applied")


func test_telegraph_cleared_after_performing() -> void:
	var state := _state()
	_add_player(state, 30)
	var atk := _intent(&"slash", &"attack", 1, [_damage_effect(5)] as Array[Effect])
	var data := _enemy_data(&"sequence", [atk] as Array[IntentData])
	var enemy := _add_enemy(state, data)

	var ai := EnemyAIScript.new(0)
	ai.select_intent(enemy, data, state)
	assert_not_null(ai.get_telegraph(enemy), "telegraph set after selection")
	ai.take_turn(state, enemy, data)
	assert_null(ai.get_telegraph(enemy), "telegraph cleared after the intent is performed")
