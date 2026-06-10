extends "res://addons/gut/test.gd"
## GUT suite for the M3 per-tier enemy mechanics (ADR-0019 deferred tier
## modifiers — act-progression.md §4b):
##   pierce_damage — intent damage that IGNORES block (anti-turtle, T3).
##   revive_allies — raise the caster's dead allies ONCE per battle (T6).
##   Thorns        — an attacker that hits the holder takes its stacks back
##                   (blockable; DoT/source-less damage never stings; T5).
##   Enrage        — a debuff landing on the holder feeds it Strength (T5).
##   AI targeting  — offensiveness comes from the intent's TargetSpec, not its
##                   telegraph icon: a `debuff` intent with target "enemy" lands
##                   on a PLAYER (regression: it used to self-target the caster).
##   EnemyScaler   — pierce/heal/revive amounts scale like damage/block;
##                   status stacks stay unscaled.

const BattleStateScript := preload("res://src/combat/battle_state.gd")
const CombatantScript := preload("res://src/combat/combatant.gd")
const EnemyAIScript := preload("res://src/combat/enemy_ai.gd")
const EnemyScalerScript := preload("res://src/run/enemy_scaler.gd")


# --- In-code fixtures (mirrors test_burn_bleed_mark.gd) -----------------------

func _config() -> BattleConfig:
	var c := BattleConfig.new()
	c.energy_per_character = 3
	c.draw_per_turn = 0
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


## StatusData map matching data/status/*.json flags for the statuses under test.
func _status_defs() -> Dictionary:
	var defs := {}
	defs[&"poison"] = _status(&"poison", &"intensity", true)
	defs[&"block"] = _status(&"block", &"intensity", true)
	defs[&"weak"] = _status(&"weak", &"duration", true)
	defs[&"strength"] = _status(&"strength", &"intensity", false)
	defs[&"thorns"] = _status(&"thorns", &"intensity", false)
	defs[&"enrage"] = _status(&"enrage", &"intensity", false)
	return defs


func _state() -> BattleState:
	var cfg := _config()
	return BattleStateScript.new(cfg, Deck.new(cfg), _status_defs())


func _character(hp: int) -> CharacterData:
	var d := CharacterData.new()
	d.id = &"hero"
	d.display_name = "Hero"
	d.max_hp = hp
	return d


func _add_player(state: BattleState, hp: int) -> Combatant:
	return state.add_combatant(CombatantScript.from_character(_character(hp)))


func _add_enemy(state: BattleState, hp: int, name: String = "Grunt") -> Combatant:
	var c := CombatantScript.new()
	c.team = Combatant.Team.ENEMY
	c.display_name = name
	c.max_hp = hp
	c.hp = hp
	return state.add_combatant(c)


func _spec(target_type: StringName) -> TargetSpec:
	var s := TargetSpec.new()
	s.target_type = target_type
	return s


func _effect(type: StringName, amount: int = 0) -> Effect:
	var e := Effect.new()
	e.type = type
	e.amount = amount
	return e


func _status_effect(id: StringName, stacks: int) -> Effect:
	var e := Effect.new()
	e.type = &"apply_status"
	e.status = id
	e.stacks = stacks
	return e


func _intent(id: StringName, telegraph: StringName, target_type: StringName, effects: Array[Effect]) -> IntentData:
	var i := IntentData.new()
	i.id = id
	i.telegraph = telegraph
	i.target = _spec(target_type)
	i.effects = effects
	i.weight = 1
	return i


# ============================================================================
#  pierce_damage — block-ignoring intent damage
# ============================================================================

func test_pierce_damage_ignores_block() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	var enemy := _add_enemy(state, 20)
	state.add_block(player, 10)
	state.apply_effects(enemy, player, [_effect(&"pierce_damage", 7)])
	assert_eq(player.hp, 23, "pierce goes straight to HP (30 - 7)")
	assert_eq(player.block, 10, "block is untouched by pierce")


func test_plain_damage_still_blocked_for_contrast() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	var enemy := _add_enemy(state, 20)
	state.add_block(player, 10)
	state.apply_effects(enemy, player, [_effect(&"damage", 7)])
	assert_eq(player.hp, 30, "plain damage soaked by block")
	assert_eq(player.block, 3, "block absorbed the hit")


# ============================================================================
#  revive_allies — once-per-source resurrection (the Legion King)
# ============================================================================

func test_revive_allies_raises_dead_allies_once() -> void:
	var state := _state()
	var _player := _add_player(state, 30)
	var king := _add_enemy(state, 100, "King")
	var minion := _add_enemy(state, 25, "Minion")
	state.deal_damage(minion, 25)
	assert_false(minion.is_alive(), "minion is down")
	state.apply_effects(king, king, [_effect(&"revive_allies", 12)])
	assert_true(minion.is_alive(), "revive raised the dead minion")
	assert_eq(minion.hp, 12, "raised to the authored amount")
	# Latch: a second cast does nothing.
	state.deal_damage(minion, 25)
	state.apply_effects(king, king, [_effect(&"revive_allies", 12)])
	assert_false(minion.is_alive(), "second revive is a no-op (once per battle)")


func test_revive_clamps_to_max_hp_and_skips_other_team() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	var king := _add_enemy(state, 100, "King")
	var minion := _add_enemy(state, 8, "Minion")
	state.deal_damage(minion, 8)
	state.deal_damage(player, 30)
	state.apply_effects(king, king, [_effect(&"revive_allies", 50)])
	assert_eq(minion.hp, 8, "revive clamps to max_hp")
	assert_false(player.is_alive(), "the OTHER team's dead are not raised")


# ============================================================================
#  Thorns — retaliation on attack hits (the Duelist / bramble fiend)
# ============================================================================

func test_thorns_stings_the_attacker_on_an_attack_hit() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	var fiend := _add_enemy(state, 40, "Fiend")
	state.apply_status(fiend, &"thorns", 4)
	state.apply_effects(player, fiend, [_effect(&"damage", 6)])
	assert_eq(fiend.hp, 34, "attack landed (40 - 6)")
	assert_eq(player.hp, 26, "attacker took thorns stacks back (30 - 4)")


func test_thorns_is_blockable_on_the_attacker() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	var fiend := _add_enemy(state, 40, "Fiend")
	state.apply_status(fiend, &"thorns", 4)
	state.add_block(player, 10)
	state.apply_effects(player, fiend, [_effect(&"damage", 6)])
	assert_eq(player.hp, 30, "attacker's block soaked the sting")
	assert_eq(player.block, 6, "sting consumed block (10 - 4)")


func test_thorns_does_not_sting_on_sourceless_damage() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	var fiend := _add_enemy(state, 40, "Fiend")
	state.apply_status(fiend, &"thorns", 4)
	state.deal_damage(fiend, 6)        # bare damage — a DoT tick, no attacker
	state.deal_unblockable(fiend, 3)   # poison-style
	assert_eq(player.hp, 30, "no attacker, no sting")


func test_two_thorn_bearers_do_not_recurse() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	var fiend := _add_enemy(state, 40, "Fiend")
	state.apply_status(player, &"thorns", 5)
	state.apply_status(fiend, &"thorns", 4)
	state.apply_effects(player, fiend, [_effect(&"damage", 6)])
	assert_eq(player.hp, 26, "attacker stung once (30 - 4)")
	assert_eq(fiend.hp, 34, "defender took only the attack (no sting-back-loop)")


# ============================================================================
#  Enrage — Strength per debuff landed on the holder (the Pit Champion)
# ============================================================================

func test_enrage_grants_strength_when_a_debuff_lands() -> void:
	var state := _state()
	var _player := _add_player(state, 30)
	var champ := _add_enemy(state, 60, "Champ")
	state.apply_status(champ, &"enrage", 2)
	assert_eq(champ.status_stacks(&"strength"), 0, "applying Enrage itself grants nothing")
	state.apply_status(champ, &"weak", 1)
	assert_eq(champ.status_stacks(&"strength"), 2, "a landed debuff feeds Strength = enrage stacks")
	state.apply_status(champ, &"poison", 3)
	assert_eq(champ.status_stacks(&"strength"), 4, "each debuff application feeds again")


func test_enrage_ignores_buffs_and_block() -> void:
	var state := _state()
	var champ := _add_enemy(state, 60, "Champ")
	state.apply_status(champ, &"enrage", 2)
	state.apply_status(champ, &"strength", 1)
	state.apply_status(champ, &"block", 5)
	assert_eq(champ.status_stacks(&"strength"), 1, "buffs/block never trigger Enrage")


# ============================================================================
#  AI targeting — debuff intents land on PLAYERS (regression for the
#  telegraph-icon self-jinx bug), self/ally intents stay on the enemy side.
# ============================================================================

func _enemy_with_intents(state: BattleState, intents: Array[IntentData]) -> Combatant:
	var data := EnemyData.new()
	data.id = &"test_enemy"
	data.display_name = "Test Enemy"
	data.max_hp = 40
	data.intents = intents
	data.intent_pattern = &"sequence"
	var unit := CombatantScript.from_enemy(data)
	return state.add_combatant(unit)


func test_debuff_intent_targets_a_player_not_the_caster() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	var intents: Array[IntentData] = [
		_intent(&"jinx", &"debuff", &"enemy", [_status_effect(&"weak", 2)]),
	]
	var enemy := _enemy_with_intents(state, intents)
	var ai: EnemyAI = EnemyAIScript.new(7)
	ai.take_turn(state, enemy, enemy.source_data as EnemyData)
	assert_eq(player.status_stacks(&"weak"), 2, "debuff lands on the player")
	assert_eq(enemy.status_stacks(&"weak"), 0, "the caster does not jinx itself")


func test_all_enemies_debuff_hits_every_player() -> void:
	var state := _state()
	var p1 := _add_player(state, 30)
	var p2 := _add_player(state, 25)
	var intents: Array[IntentData] = [
		_intent(&"miasma", &"debuff", &"all_enemies", [_status_effect(&"poison", 2)]),
	]
	var enemy := _enemy_with_intents(state, intents)
	var ai: EnemyAI = EnemyAIScript.new(7)
	ai.take_turn(state, enemy, enemy.source_data as EnemyData)
	assert_eq(p1.status_stacks(&"poison"), 2, "AoE debuff hits player 1")
	assert_eq(p2.status_stacks(&"poison"), 2, "AoE debuff hits player 2")


func test_ally_buff_intent_lands_on_the_enemy_team() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	var intents: Array[IntentData] = [
		_intent(&"rally", &"buff", &"all_allies", [_status_effect(&"strength", 2)]),
	]
	var banner := _enemy_with_intents(state, intents)
	var other := _add_enemy(state, 20, "Other")
	var ai: EnemyAI = EnemyAIScript.new(7)
	ai.take_turn(state, banner, banner.source_data as EnemyData)
	assert_eq(banner.status_stacks(&"strength"), 2, "buff reaches the caster")
	assert_eq(other.status_stacks(&"strength"), 2, "buff reaches its allies")
	assert_eq(player.status_stacks(&"strength"), 0, "players are not buffed")


func test_ally_heal_and_ally_block_intents_support_the_enemy_team() -> void:
	var state := _state()
	var _player := _add_player(state, 30)
	var heal_effects: Array[Effect] = [_effect(&"heal", 7)]
	var block_effects: Array[Effect] = [_effect(&"block", 6)]
	var intents: Array[IntentData] = [
		_intent(&"mend", &"buff", &"all_allies", heal_effects),
		_intent(&"phalanx", &"block", &"all_allies", block_effects),
	]
	var priest := _enemy_with_intents(state, intents)
	var hurt := _add_enemy(state, 30, "Hurt")
	hurt.hp = 10
	var ai: EnemyAI = EnemyAIScript.new(7)
	ai.take_turn(state, priest, priest.source_data as EnemyData)  # mend
	assert_eq(hurt.hp, 17, "ally heal restored the wounded minion (10 + 7)")
	ai.take_turn(state, priest, priest.source_data as EnemyData)  # phalanx
	assert_eq(hurt.block, 6, "ally block shields the minion")
	assert_eq(priest.block, 6, "and the caster itself")


# ============================================================================
#  EnemyScaler — new magnitude kinds scale; stacks stay control
# ============================================================================

func _scaler_config() -> BattleConfig:
	var c := BattleConfig.new()
	c.enemy_scale_baseline_level = 8
	c.enemy_scale_exponent = 1.0
	return c


func test_scaler_scales_pierce_heal_and_revive_amounts() -> void:
	var data := EnemyData.new()
	data.id = &"scaled"
	data.display_name = "Scaled"
	data.max_hp = 100
	var effects: Array[Effect] = [
		_effect(&"pierce_damage", 10),
		_effect(&"heal", 10),
		_effect(&"revive_allies", 10),
		_status_effect(&"poison", 3),
	]
	var intents: Array[IntentData] = [_intent(&"kit", &"attack", &"enemy", effects)]
	data.intents = intents
	var scaler: EnemyScaler = EnemyScalerScript.new(_scaler_config())
	var scaled := scaler.apply_to(data, 16)  # 2x the baseline of 8
	var out := scaled.intents[0].effects
	assert_eq(out[0].amount, 20, "pierce_damage scales like damage")
	assert_eq(out[1].amount, 20, "heal scales (an unscaled heal would vanish at depth)")
	assert_eq(out[2].amount, 20, "revive_allies HP scales")
	assert_eq(out[3].stacks, 3, "status STACKS stay control — unscaled")
