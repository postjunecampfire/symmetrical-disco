extends "res://addons/gut/test.gd"
## GUT suite for src/combat/enemy_ai.gd (task P1·08): enemy intent selection,
## telegraphing, and execution on the enemy phase.
##
## Builds everything IN CODE (no JSON/.tres): a small grid, a BattleState with the
## five prototype StatusData defs, player/enemy combatants, and EnemyData carrying
## hand-built IntentData. Asserts the four acceptance criteria:
##   - weighted selection is deterministic under a fixed seed and respects weights
##     (a 0-weight intent is never chosen; a dominant weight is chosen most);
##   - the `sequence` pattern cycles intents in order;
##   - get_telegraph() reflects the upcoming intent before it resolves;
##   - take_turn() moves the enemy CLOSER to the player (grid-position delta) and
##     applies the intent's effects (player hp drops);
##   - graceful no-target / no-intent handling.

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
	var grid := GridModel.new(Vector2i(10, 10))
	var deck := Deck.new(cfg)
	return BattleStateScript.new(cfg, grid, deck, _status_defs())


func _character(hp: int, move_range: int = 3) -> CharacterData:
	var d := CharacterData.new()
	d.id = &"hero"
	d.display_name = "Hero"
	d.max_hp = hp
	d.move_range = move_range
	return d


func _add_player(state: BattleState, hp: int, pos: Vector2i) -> Combatant:
	return state.add_combatant(CombatantScript.from_character(_character(hp), pos))


func _add_enemy(state: BattleState, data: EnemyData, pos: Vector2i) -> Combatant:
	return state.add_combatant(CombatantScript.from_enemy(data, pos))


## A damage effect of `amount`.
func _damage_effect(amount: int) -> Effect:
	var e := Effect.new()
	e.type = &"damage"
	e.amount = amount
	return e


## A block effect of `amount` (self-buff).
func _block_effect(amount: int) -> Effect:
	var e := Effect.new()
	e.type = &"block"
	e.amount = amount
	return e


## An IntentData with the given id, telegraph icon, weight, and effects.
func _intent(id: StringName, telegraph: StringName, weight: int, effects: Array[Effect]) -> IntentData:
	var i := IntentData.new()
	i.id = id
	i.telegraph = telegraph
	i.weight = weight
	i.target = TargetSpec.new()
	i.effects = effects
	return i


## EnemyData with the given pattern and intents.
func _enemy_data(pattern: StringName, intents: Array[IntentData], move_range: int = 2) -> EnemyData:
	var d := EnemyData.new()
	d.id = &"grunt"
	d.display_name = "Grunt"
	d.max_hp = 30
	d.move_range = move_range
	d.intent_pattern = pattern
	d.intents = intents
	return d


# ============================================================================
#  1. Weighted selection — deterministic + respects weights
# ============================================================================

func test_weighted_selection_is_deterministic_under_fixed_seed() -> void:
	var state := _state()
	var enemy := _add_enemy(state, _enemy_data(&"random_weighted", []), Vector2i(5, 5))
	_add_player(state, 30, Vector2i(0, 0))

	var atk_a := _intent(&"a", &"attack", 1, [_damage_effect(3)] as Array[Effect])
	var atk_b := _intent(&"b", &"attack", 1, [_damage_effect(3)] as Array[Effect])
	var atk_c := _intent(&"c", &"attack", 1, [_damage_effect(3)] as Array[Effect])
	var data := _enemy_data(&"random_weighted", [atk_a, atk_b, atk_c] as Array[IntentData])

	# Same seed -> identical sequence of picks across two fresh controllers.
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
	var enemy := _add_enemy(state, _enemy_data(&"random_weighted", []), Vector2i(5, 5))
	_add_player(state, 30, Vector2i(0, 0))

	# never: weight 0 (must never be chosen). dominant: weight 9. minor: weight 1.
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
	var enemy := _add_enemy(state, _enemy_data(&"sequence", []), Vector2i(5, 5))
	_add_player(state, 30, Vector2i(0, 0))

	var one := _intent(&"one", &"attack", 1, [_damage_effect(3)] as Array[Effect])
	var two := _intent(&"two", &"block", 1, [_block_effect(3)] as Array[Effect])
	var three := _intent(&"three", &"attack", 1, [_damage_effect(3)] as Array[Effect])
	var data := _enemy_data(&"sequence", [one, two, three] as Array[IntentData])

	var ai := EnemyAIScript.new(0)
	var order: Array = []
	for _i in range(7):  # 3 + 3 + 1 to prove the wrap.
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
	var player := _add_player(state, 30, Vector2i(0, 0))
	var atk := _intent(&"slash", &"attack", 1, [_damage_effect(5)] as Array[Effect])
	var data := _enemy_data(&"sequence", [atk] as Array[IntentData])
	var enemy := _add_enemy(state, data, Vector2i(2, 0))

	var ai := EnemyAIScript.new(0)
	assert_null(ai.get_telegraph(enemy), "no telegraph before selection")

	ai.select_intent(enemy, data, state)
	var tel := ai.get_telegraph(enemy)
	assert_not_null(tel, "telegraph exists after selection")
	assert_eq(tel.intent.id, &"slash", "telegraph names the upcoming intent")
	assert_eq(tel.intent.telegraph, &"attack", "telegraph exposes the icon")
	assert_eq(tel.target, player, "telegraph resolved the nearest player as target")
	assert_eq(player.hp, 30, "telegraph does NOT resolve effects yet")
	assert_eq(ai.get_telegraphed_intent(enemy).id, &"slash")


# ============================================================================
#  4. Execution — moves closer + applies effects
# ============================================================================

func test_take_turn_moves_enemy_closer_and_damages_player() -> void:
	var state := _state()
	var player := _add_player(state, 30, Vector2i(0, 0))
	var atk := _intent(&"slash", &"attack", 1, [_damage_effect(6)] as Array[Effect])
	var data := _enemy_data(&"sequence", [atk] as Array[IntentData], 2)
	# Enemy 5 tiles east of the player; move_range 2 closes the gap by 2.
	var enemy := _add_enemy(state, data, Vector2i(5, 0))
	var start_dist: int = absi(enemy.grid_position.x - player.grid_position.x) \
		+ absi(enemy.grid_position.y - player.grid_position.y)

	var ai := EnemyAIScript.new(0)
	ai.take_turn(state, enemy, data)

	var end_dist: int = absi(enemy.grid_position.x - player.grid_position.x) \
		+ absi(enemy.grid_position.y - player.grid_position.y)
	assert_lt(end_dist, start_dist, "enemy moved closer to the player")
	assert_eq(end_dist, start_dist - 2, "enemy moved exactly move_range (2) tiles closer")
	assert_eq(enemy.grid_position, Vector2i(3, 0), "enemy ends two tiles west")
	# Out of melee range this turn, but the apply primitive still resolves the
	# intent's effects (range-gating of effects is P1·07/P1·09, not the AI's job).
	assert_eq(player.hp, 24, "intent's damage effect was applied (30 - 6)")
	assert_false(state.grid.is_occupied(Vector2i(5, 0)), "old tile freed")
	assert_eq(state.grid.get_occupant(Vector2i(3, 0)), enemy, "grid registry updated")


func test_take_turn_stops_adjacent_not_on_player_tile() -> void:
	var state := _state()
	var player := _add_player(state, 30, Vector2i(0, 0))
	var atk := _intent(&"slash", &"attack", 1, [_damage_effect(4)] as Array[Effect])
	# Big move_range so it could overshoot; it must stop adjacent, not on the player.
	var data := _enemy_data(&"sequence", [atk] as Array[IntentData], 9)
	var enemy := _add_enemy(state, data, Vector2i(4, 0))

	var ai := EnemyAIScript.new(0)
	ai.take_turn(state, enemy, data)

	assert_eq(enemy.grid_position, Vector2i(1, 0), "stops adjacent to the player")
	assert_ne(enemy.grid_position, player.grid_position, "never occupies the player's tile")
	assert_eq(player.hp, 26, "damage applied (30 - 4)")


func test_take_turn_self_buff_intent_stays_put_and_gains_block() -> void:
	var state := _state()
	_add_player(state, 30, Vector2i(0, 0))
	var guard := _intent(&"guard", &"block", 1, [_block_effect(7)] as Array[Effect])
	var data := _enemy_data(&"sequence", [guard] as Array[IntentData], 3)
	var enemy := _add_enemy(state, data, Vector2i(5, 5))

	var ai := EnemyAIScript.new(0)
	ai.take_turn(state, enemy, data)

	assert_eq(enemy.grid_position, Vector2i(5, 5), "self/buff intent does not chase the player")
	assert_eq(enemy.block, 7, "block intent applied to the enemy itself")


# ============================================================================
#  5. Graceful handling — no target, no intents, lazy selection
# ============================================================================

func test_take_turn_no_living_player_is_graceful_noop() -> void:
	var state := _state()
	# No players at all: an offensive intent has nothing to hit.
	var atk := _intent(&"slash", &"attack", 1, [_damage_effect(6)] as Array[Effect])
	var data := _enemy_data(&"sequence", [atk] as Array[IntentData], 2)
	var enemy := _add_enemy(state, data, Vector2i(5, 0))

	var ai := EnemyAIScript.new(0)
	var result := ai.take_turn(state, enemy, data)

	assert_null(result, "no living player -> no action performed")
	assert_eq(enemy.grid_position, Vector2i(5, 0), "enemy did not move with no target")


func test_take_turn_no_intents_is_graceful_noop() -> void:
	var state := _state()
	var player := _add_player(state, 30, Vector2i(0, 0))
	var data := _enemy_data(&"random_weighted", [] as Array[IntentData], 2)
	var enemy := _add_enemy(state, data, Vector2i(3, 0))

	var ai := EnemyAIScript.new(0)
	var result := ai.take_turn(state, enemy, data)

	assert_null(result, "no intents -> no action")
	assert_eq(player.hp, 30, "no damage dealt")
	assert_eq(enemy.grid_position, Vector2i(3, 0), "no movement")


func test_take_turn_dead_enemy_is_graceful_noop() -> void:
	var state := _state()
	var player := _add_player(state, 30, Vector2i(0, 0))
	var atk := _intent(&"slash", &"attack", 1, [_damage_effect(6)] as Array[Effect])
	var data := _enemy_data(&"sequence", [atk] as Array[IntentData], 2)
	var enemy := _add_enemy(state, data, Vector2i(3, 0))
	enemy.hp = 0  # dead before acting.

	var ai := EnemyAIScript.new(0)
	var result := ai.take_turn(state, enemy, data)

	assert_null(result, "a dead enemy takes no turn")
	assert_eq(player.hp, 30, "dead enemy deals no damage")


func test_take_turn_lazily_selects_when_no_telegraph_pending() -> void:
	# take_turn should pick an intent itself if the phase loop didn't pre-telegraph.
	var state := _state()
	var player := _add_player(state, 30, Vector2i(0, 0))
	var atk := _intent(&"slash", &"attack", 1, [_damage_effect(5)] as Array[Effect])
	var data := _enemy_data(&"sequence", [atk] as Array[IntentData], 1)
	var enemy := _add_enemy(state, data, Vector2i(2, 0))

	var ai := EnemyAIScript.new(0)
	assert_null(ai.get_telegraph(enemy), "no telegraph pre-selected")
	var result := ai.take_turn(state, enemy, data)

	assert_not_null(result, "lazily selected and performed an intent")
	assert_eq(result.id, &"slash")
	assert_eq(player.hp, 25, "lazily selected intent's damage applied")


func test_telegraph_cleared_after_performing() -> void:
	var state := _state()
	_add_player(state, 30, Vector2i(0, 0))
	var atk := _intent(&"slash", &"attack", 1, [_damage_effect(5)] as Array[Effect])
	var data := _enemy_data(&"sequence", [atk] as Array[IntentData], 1)
	var enemy := _add_enemy(state, data, Vector2i(2, 0))

	var ai := EnemyAIScript.new(0)
	ai.select_intent(enemy, data, state)
	assert_not_null(ai.get_telegraph(enemy), "telegraph set after selection")
	ai.take_turn(state, enemy, data)
	assert_null(ai.get_telegraph(enemy), "telegraph cleared after the intent is performed")
