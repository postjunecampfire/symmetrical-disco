extends "res://addons/gut/test.gd"
## GUT suite for src/combat/battle_state.gd + src/combat/combatant.gd (task P1·04,
## positionless ADR-0013).
##
## Builds a small battle IN CODE (no JSON/.tres needed): 1–2 player combatants vs
## 2–3 enemies, a BattleConfig, and StatusData for the five prototype statuses.
## Asserts the integration spine: energy refills at turn start; the five statuses
## tick correctly (poison damages, block absorbs then decays, stun skips,
## strength/weak modify damage); deal_damage routes through block then hp;
## resolve_targets/apply_effects drive single- and group-target effects; and a
## scripted sequence drives the battle to a WIN and a LOSS via check_outcome().

const BattleStateScript := preload("res://src/combat/battle_state.gd")
const CombatantScript := preload("res://src/combat/combatant.gd")


# --- Fixtures ---------------------------------------------------------------

func _config(energy: int = 3, draw: int = 5) -> BattleConfig:
	var c := BattleConfig.new()
	c.energy_per_turn = energy
	c.draw_per_turn = draw
	c.max_hand = 10
	c.reshuffle_discard = true
	return c


## StatusData map for the five prototype statuses with their intended flags.
func _status_defs() -> Dictionary:
	var defs := {}
	defs[&"poison"] = _status(&"poison", &"intensity", true)
	defs[&"block"] = _status(&"block", &"intensity", true)
	defs[&"stun"] = _status(&"stun", &"duration", true)
	defs[&"strength"] = _status(&"strength", &"intensity", false)
	defs[&"weak"] = _status(&"weak", &"duration", true)
	return defs


func _status(id: StringName, stacking: StringName, decays: bool) -> StatusData:
	var s := StatusData.new()
	s.id = id
	s.display_name = String(id)
	s.stacking = stacking
	s.decays_each_turn = decays
	return s


func _character(hp: int) -> CharacterData:
	var d := CharacterData.new()
	d.id = &"hero"
	d.display_name = "Hero"
	d.max_hp = hp
	return d


func _enemy_data(hp: int) -> EnemyData:
	var d := EnemyData.new()
	d.id = &"grunt"
	d.display_name = "Grunt"
	d.max_hp = hp
	return d


## A fresh positionless BattleState with the five StatusData defs wired in.
func _state(energy: int = 3, draw: int = 0) -> BattleState:
	var cfg := _config(energy, draw)
	var deck := Deck.new(cfg)
	return BattleStateScript.new(cfg, deck, _status_defs())


func _add_player(state: BattleState, hp: int) -> Combatant:
	return state.add_combatant(CombatantScript.from_character(_character(hp)))


func _add_enemy(state: BattleState, hp: int) -> Combatant:
	return state.add_combatant(CombatantScript.from_enemy(_enemy_data(hp)))


# --- Combatant model --------------------------------------------------------

func test_combatant_from_character_copies_data() -> void:
	var unit := CombatantScript.from_character(_character(30))
	assert_eq(unit.max_hp, 30)
	assert_eq(unit.hp, 30, "spawns at full hp")
	assert_true(unit.is_player())
	assert_true(unit.is_alive())


# --- deal_damage: block then hp ---------------------------------------------

func test_deal_damage_routes_through_block_then_hp() -> void:
	var state := _state()
	var enemy := _add_enemy(state, 20)
	state.add_block(enemy, 5)

	state.deal_damage(enemy, 8)  # 5 absorbed by block, 3 to hp

	assert_eq(enemy.block, 0, "block fully consumed")
	assert_eq(enemy.hp, 17, "remaining 3 damage hit hp")


func test_deal_damage_block_can_fully_absorb() -> void:
	var state := _state()
	var enemy := _add_enemy(state, 20)
	state.add_block(enemy, 10)

	state.deal_damage(enemy, 6)

	assert_eq(enemy.block, 4, "block partially consumed")
	assert_eq(enemy.hp, 20, "no damage reached hp")


func test_deal_damage_clamps_at_zero() -> void:
	var state := _state()
	var enemy := _add_enemy(state, 5)

	state.deal_damage(enemy, 99)

	assert_eq(enemy.hp, 0, "hp clamps at 0")
	assert_false(enemy.is_alive())


# --- strength / weak modify outgoing damage ---------------------------------

func test_strength_adds_to_outgoing_damage() -> void:
	var state := _state()
	var attacker := _add_player(state, 30)
	var target := _add_enemy(state, 30)
	state.apply_status(attacker, &"strength", 3)

	state.deal_damage_from(attacker, target, 6)  # 6 + 3 strength = 9

	assert_eq(target.hp, 21)


func test_weak_reduces_outgoing_damage() -> void:
	var state := _state()
	var attacker := _add_player(state, 30)
	var target := _add_enemy(state, 30)
	state.apply_status(attacker, &"weak", 1)

	state.deal_damage_from(attacker, target, 8)  # floor(8 * 0.75) = 6

	assert_eq(target.hp, 24)


func test_apply_effects_folds_strength_into_damage() -> void:
	# Criterion 6: apply a damage effect list through the resolver + state, and
	# confirm the attacker's strength was folded in (proves resolver<->state wire).
	var state := _state()
	var attacker := _add_player(state, 30)
	var target := _add_enemy(state, 30)
	state.apply_status(attacker, &"strength", 2)

	var dmg := Effect.new()
	dmg.type = &"damage"
	dmg.amount = 5
	state.apply_effects(attacker, target, [dmg])  # (5 + 2) = 7

	assert_eq(target.hp, 23)


# --- positionless targeting -------------------------------------------------

func test_resolve_targets_self_and_all_enemies() -> void:
	var state := _state()
	var hero := _add_player(state, 30)
	var e1 := _add_enemy(state, 20)
	var e2 := _add_enemy(state, 20)

	var self_spec := TargetSpec.new()
	self_spec.target_type = &"self"
	assert_eq(state.resolve_targets(self_spec, hero, null), [hero], "self resolves to the actor")

	var aoe := TargetSpec.new()
	aoe.target_type = &"all_enemies"
	var foes := state.resolve_targets(aoe, hero, null)
	assert_eq(foes.size(), 2, "all_enemies resolves to every living enemy")
	assert_true(foes.has(e1) and foes.has(e2))


func test_apply_effects_aoe_hits_every_enemy() -> void:
	# A damage effect against an all_enemies target set hits each enemy once.
	var state := _state()
	var hero := _add_player(state, 30)
	var e1 := _add_enemy(state, 20)
	var e2 := _add_enemy(state, 20)

	var aoe := TargetSpec.new()
	aoe.target_type = &"all_enemies"
	var targets := state.resolve_targets(aoe, hero, null)

	var dmg := Effect.new()
	dmg.type = &"damage"
	dmg.amount = 4
	state.apply_effects(hero, targets, [dmg])

	assert_eq(e1.hp, 16, "first enemy took the AoE")
	assert_eq(e2.hp, 16, "second enemy took the AoE")


func test_apply_effects_draw_applies_once_for_aoe() -> void:
	# A global effect (draw) on an AoE card must fire ONCE, not once per target.
	var cfg := _config(3, 0)
	var deck := Deck.new(cfg)
	for _i in range(5):
		deck.draw_pile.append(_card())
	var state := BattleStateScript.new(cfg, deck, _status_defs())
	var hero := _add_player(state, 30)
	_add_enemy(state, 20)
	_add_enemy(state, 20)

	var aoe := TargetSpec.new()
	aoe.target_type = &"all_enemies"
	var targets := state.resolve_targets(aoe, hero, null)

	var draw := Effect.new()
	draw.type = &"draw"
	draw.amount = 1
	state.apply_effects(hero, targets, [draw])

	assert_eq(deck.hand.size(), 1, "draw fired once despite a 2-enemy target set")


# --- energy refill ----------------------------------------------------------

func test_energy_refills_per_character_at_player_turn_start() -> void:
	# ADR-0025: each living player refills their OWN pool to energy_per_character.
	var state := _state(3)
	var p1 := _add_player(state, 30)
	var p2 := _add_player(state, 30)
	_add_enemy(state, 30)

	state.start_player_turn()
	var base: int = state.config.energy_per_character
	assert_eq(state.energy_of(p1), base, "player 1 pool refills to energy_per_character")
	assert_eq(state.energy_of(p2), base, "player 2 pool refills independently")
	assert_eq(state.turn_number, 1, "turn counter advances")

	state.spend_energy(p1, base)
	state.start_player_turn()
	assert_eq(state.energy_of(p1), base, "refills again next turn, not accumulates")


func test_spend_energy_is_per_pool() -> void:
	# ADR-0025: one character's spending never drains the other's pool.
	var state := _state(3)
	var p1 := _add_player(state, 30)
	var p2 := _add_player(state, 30)
	state.start_player_turn()
	var base: int = state.config.energy_per_character
	assert_true(state.spend_energy(p1, 1), "affordable spend succeeds")
	assert_eq(state.energy_of(p1), base - 1, "spender's pool debited")
	assert_eq(state.energy_of(p2), base, "the OTHER pool is untouched")
	assert_false(state.spend_energy(p1, base), "overdraft refused")
	assert_eq(state.energy_of(p1), base - 1, "refused spend debits nothing")


func test_add_energy_tops_up_a_pool() -> void:
	var state := _state(3)
	var p1 := _add_player(state, 30)
	state.start_player_turn()
	var base: int = state.config.energy_per_character
	state.add_energy(2, p1)
	assert_eq(state.energy_of(p1), base + 2, "gain_energy adds on top of the pool")
	state.add_energy(1)  # source-less: credits the first living player
	assert_eq(state.energy_of(p1), base + 3, "source-less gain credits the first living player")


# --- draw at turn start ------------------------------------------------------

func test_player_turn_start_draws_per_turn() -> void:
	var cfg := _config(3, 2)
	var deck := Deck.new(cfg)
	for _i in range(5):
		deck.draw_pile.append(_card())
	var state := BattleStateScript.new(cfg, deck, _status_defs())
	_add_player(state, 30)

	state.start_player_turn()
	assert_eq(deck.hand.size(), 2, "drew draw_per_turn cards at turn start")


func _card() -> CardData:
	var c := CardData.new()
	c.id = &"plain"
	c.display_name = "Plain"
	return c


# --- poison ticks -----------------------------------------------------------

func test_poison_damages_then_decrements_at_turn_start() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	_add_enemy(state, 30)
	state.apply_status(player, &"poison", 3)

	state.start_player_turn()

	assert_eq(player.hp, 27, "poison dealt its 3 stacks as damage")
	assert_eq(player.status_stacks(&"poison"), 2, "poison decremented by one")


func test_poison_ignores_block_anti_turtle() -> void:
	# Poison is the turtle tax: block does NOT absorb it (unlike attacks).
	var state := _state()
	var player := _add_player(state, 30)
	_add_enemy(state, 30)
	state.add_block(player, 10)
	state.apply_status(player, &"poison", 4)

	state.start_player_turn()  # poison ticks (ignoring block), then block resets

	assert_eq(player.hp, 26, "poison hit hp directly for its 4 stacks, bypassing block")


# --- block decays at owner's turn start -------------------------------------

func test_block_absorbs_during_turn_then_resets_next_turn() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	_add_enemy(state, 30)

	state.add_block(player, 6)
	assert_eq(player.block, 6)
	state.deal_damage(player, 4)
	assert_eq(player.block, 2, "block absorbed incoming damage")
	assert_eq(player.hp, 30)

	state.start_player_turn()
	assert_eq(player.block, 0, "leftover block resets at the owner's next turn")


# --- stun skips the action --------------------------------------------------

func test_stun_makes_enemy_skip_its_action() -> void:
	var state := _RecordingBattleState.new(_config(), Deck.new(_config()), _status_defs())
	_add_player(state, 30)
	var stunned := _add_enemy(state, 30)
	var active := _add_enemy(state, 30)
	state.apply_status(stunned, &"stun", 1)

	state.start_player_turn()
	state.end_player_turn()

	assert_false(state.acted.has(stunned), "stunned enemy skipped its action")
	assert_true(state.acted.has(active), "un-stunned enemy still acted")
	assert_eq(stunned.status_stacks(&"stun"), 0, "stun was consumed")


## BattleState that records each enemy that reaches its action.
class _RecordingBattleState extends BattleState:
	var acted: Array = []

	func _take_enemy_action(enemy: Combatant) -> void:
		acted.append(enemy)


# --- heal -------------------------------------------------------------------

func test_heal_clamps_to_max_hp() -> void:
	var state := _state()
	var unit := _add_player(state, 30)
	state.deal_damage(unit, 10)
	assert_eq(unit.hp, 20)

	state.heal(unit, 100)
	assert_eq(unit.hp, 30, "heal clamps to max_hp")


# --- win / lose -------------------------------------------------------------

func test_check_outcome_ongoing_with_both_sides_alive() -> void:
	var state := _state()
	_add_player(state, 30)
	_add_enemy(state, 30)
	assert_eq(state.check_outcome(), BattleState.Outcome.ONGOING)


func test_scripted_sequence_drives_battle_to_win() -> void:
	var state := _state()
	var hero := _add_player(state, 30)
	var e1 := _add_enemy(state, 10)
	var e2 := _add_enemy(state, 10)

	var smite := Effect.new()
	smite.type = &"damage"
	smite.amount = 10

	state.apply_effects(hero, e1, [smite])
	assert_eq(state.check_outcome(), BattleState.Outcome.ONGOING, "one enemy still up")

	state.apply_effects(hero, e2, [smite])
	assert_false(e1.is_alive())
	assert_false(e2.is_alive())
	assert_eq(state.check_outcome(), BattleState.Outcome.WIN, "all enemies dead => WIN")


func test_scripted_sequence_drives_battle_to_loss() -> void:
	var state := _state()
	var hero := _add_player(state, 8)
	var foe := _add_enemy(state, 30)

	var crush := Effect.new()
	crush.type = &"damage"
	crush.amount = 8

	state.apply_effects(foe, hero, [crush])
	assert_false(hero.is_alive())
	assert_eq(state.check_outcome(), BattleState.Outcome.LOSS, "all players dead => LOSS")


func test_mutual_wipe_reads_as_loss() -> void:
	var state := _state()
	var hero := _add_player(state, 5)
	var foe := _add_enemy(state, 5)
	state.deal_damage(hero, 5)
	state.deal_damage(foe, 5)
	assert_eq(state.check_outcome(), BattleState.Outcome.LOSS, "player wipe wins ties as loss")
