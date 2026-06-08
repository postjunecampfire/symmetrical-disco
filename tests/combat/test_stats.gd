extends "res://addons/gut/test.gd"
## GUT suite for the stat system (P3·02, ADR-0014): STR/INT scale attack damage
## via a per-character attack_stat, DEX scales block, CON -> max HP. Enemies carry
## no stats, so their intent damage stays flat.

const BattleStateScript := preload("res://src/combat/battle_state.gd")
const CombatantScript := preload("res://src/combat/combatant.gd")


func _state() -> BattleState:
	var cfg := BattleConfig.new()
	return BattleStateScript.new(cfg, Deck.new(cfg), {})


func _player(state: BattleState, attack_stat: StringName, str_v: int, dex_v: int,
		int_v: int, hp: int = 40) -> Combatant:
	var c := CombatantScript.new()
	c.team = Combatant.Team.PLAYER
	c.display_name = "Hero"
	c.max_hp = hp
	c.hp = hp
	c.strength = str_v
	c.dexterity = dex_v
	c.intelligence = int_v
	c.attack_stat = attack_stat
	return state.add_combatant(c)


func _enemy(state: BattleState, hp: int = 30) -> Combatant:
	var c := CombatantScript.new()
	c.team = Combatant.Team.ENEMY
	c.display_name = "Foe"
	c.max_hp = hp
	c.hp = hp
	return state.add_combatant(c)


func _dmg(amount: int) -> Effect:
	var e := Effect.new()
	e.type = &"damage"
	e.amount = amount
	return e


func _blk(amount: int) -> Effect:
	var e := Effect.new()
	e.type = &"block"
	e.amount = amount
	return e


# --- attack stat scales damage ----------------------------------------------

func test_str_attack_stat_adds_to_damage() -> void:
	var s := _state()
	var hero := _player(s, &"str", 6, 0, 0)
	var foe := _enemy(s, 30)
	s.apply_effects(hero, foe, [_dmg(4)])  # 4 base + STR 6 = 10
	assert_eq(foe.hp, 20, "physical damage scales with STR")


func test_int_attack_stat_adds_to_damage() -> void:
	var s := _state()
	var mage := _player(s, &"int", 0, 0, 6)
	var foe := _enemy(s, 30)
	s.apply_effects(mage, foe, [_dmg(4)])  # 4 base + INT 6 = 10
	assert_eq(foe.hp, 20, "magic damage scales with INT")


func test_dex_attack_stat_adds_to_damage() -> void:
	# Rogue-style: attacks scale with DEX.
	var s := _state()
	var rogue := _player(s, &"dex", 0, 5, 0)
	var foe := _enemy(s, 30)
	s.apply_effects(rogue, foe, [_dmg(4)])  # 4 base + DEX 5 = 9
	assert_eq(foe.hp, 21, "physical/finesse damage scales with DEX")


func test_attack_power_picks_the_right_stat() -> void:
	var s := _state()
	var martial := _player(s, &"str", 6, 0, 9)
	assert_eq(martial.attack_power(), 6, "str attacker ignores INT")
	var caster := _player(s, &"int", 9, 0, 6)
	assert_eq(caster.attack_power(), 6, "int attacker ignores STR")
	var rogue := _player(s, &"dex", 9, 7, 9)
	assert_eq(rogue.attack_power(), 7, "dex attacker uses DEX")


func test_strength_status_stacks_with_attack_stat() -> void:
	var s := _state()
	var hero := _player(s, &"str", 5, 0, 0)
	var foe := _enemy(s, 30)
	s.apply_status(hero, &"strength", 2)
	s.apply_effects(hero, foe, [_dmg(4)])  # 4 + STR 5 + Strength 2 = 11
	assert_eq(foe.hp, 19, "the attack stat and Strength status both add")


# --- DEX scales block -------------------------------------------------------

func test_dex_scales_block() -> void:
	var s := _state()
	var hero := _player(s, &"str", 0, 4, 0)
	s.apply_effects(hero, hero, [_blk(5)])  # 5 base + DEX 4 = 9
	assert_eq(hero.block, 9, "block scales with the source's DEX")


# --- enemies have no stat bonus ---------------------------------------------

func test_enemy_damage_is_flat() -> void:
	var s := _state()
	var foe := _enemy(s, 30)
	assert_eq(foe.attack_power(), 0, "enemies contribute no attack-stat bonus")
	var hero := _player(s, &"str", 0, 0, 0, 40)
	s.apply_effects(foe, hero, [_dmg(6)])  # flat 6 (no stats on the enemy)
	assert_eq(hero.hp, 34, "enemy intent damage stays as authored")
