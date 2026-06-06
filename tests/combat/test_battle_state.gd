extends "res://addons/gut/test.gd"
## GUT suite for src/combat/battle_state.gd + src/combat/combatant.gd (task P1·04).
##
## Builds a small battle IN CODE (no JSON/.tres needed): a tiny grid, 1–2 player
## combatants vs 2–3 enemies, a BattleConfig, and StatusData for the five
## prototype statuses. Asserts the integration spine: energy refills at turn
## start; the five statuses tick correctly (poison damages, block absorbs then
## decays, stun skips, strength/weak modify damage); deal_damage routes through
## block then hp; and a scripted sequence drives the battle to a WIN and,
## separately, to a LOSS via check_outcome().

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


## StatusData map for the five prototype statuses with their intended flags:
## block decays each turn (does not carry over), poison/stun/weak count down,
## strength persists. Magnitudes/flags live here in data, behaviour in code.
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


func _character(hp: int, move_range: int = 3) -> CharacterData:
	var d := CharacterData.new()
	d.id = &"hero"
	d.display_name = "Hero"
	d.max_hp = hp
	d.move_range = move_range
	return d


func _enemy_data(hp: int, move_range: int = 2) -> EnemyData:
	var d := EnemyData.new()
	d.id = &"grunt"
	d.display_name = "Grunt"
	d.max_hp = hp
	d.move_range = move_range
	return d


## A fresh BattleState on an 8x8 grid with the five StatusData defs wired in.
func _state(energy: int = 3, draw: int = 0) -> BattleState:
	var cfg := _config(energy, draw)
	var grid := GridModel.new(Vector2i(8, 8))
	var deck := Deck.new(cfg)
	return BattleStateScript.new(cfg, grid, deck, _status_defs())


func _add_player(state: BattleState, hp: int, pos: Vector2i) -> Combatant:
	var unit := CombatantScript.from_character(_character(hp), pos)
	return state.add_combatant(unit)


func _add_enemy(state: BattleState, hp: int, pos: Vector2i) -> Combatant:
	var unit := CombatantScript.from_enemy(_enemy_data(hp), pos)
	return state.add_combatant(unit)


# --- Combatant model --------------------------------------------------------

func test_combatant_from_character_copies_data() -> void:
	var unit := CombatantScript.from_character(_character(30, 4), Vector2i(1, 2))
	assert_eq(unit.max_hp, 30)
	assert_eq(unit.hp, 30, "spawns at full hp")
	assert_eq(unit.move_range, 4)
	assert_eq(unit.grid_position, Vector2i(1, 2))
	assert_true(unit.is_player())
	assert_true(unit.is_alive())


# --- deal_damage: block then hp ---------------------------------------------

func test_deal_damage_routes_through_block_then_hp() -> void:
	var state := _state()
	var enemy := _add_enemy(state, 20, Vector2i(4, 4))
	state.add_block(enemy, 5)

	state.deal_damage(enemy, 8)  # 5 absorbed by block, 3 to hp

	assert_eq(enemy.block, 0, "block fully consumed")
	assert_eq(enemy.hp, 17, "remaining 3 damage hit hp")


func test_deal_damage_block_can_fully_absorb() -> void:
	var state := _state()
	var enemy := _add_enemy(state, 20, Vector2i(4, 4))
	state.add_block(enemy, 10)

	state.deal_damage(enemy, 6)

	assert_eq(enemy.block, 4, "block partially consumed")
	assert_eq(enemy.hp, 20, "no damage reached hp")


func test_deal_damage_clamps_at_zero_and_frees_tile() -> void:
	var state := _state()
	var enemy := _add_enemy(state, 5, Vector2i(4, 4))

	state.deal_damage(enemy, 99)

	assert_eq(enemy.hp, 0, "hp clamps at 0")
	assert_false(enemy.is_alive())
	assert_false(state.grid.is_occupied(Vector2i(4, 4)), "dead unit frees its tile")


# --- strength / weak modify outgoing damage ---------------------------------

func test_strength_adds_to_outgoing_damage() -> void:
	var state := _state()
	var attacker := _add_player(state, 30, Vector2i(0, 0))
	var target := _add_enemy(state, 30, Vector2i(1, 0))
	state.apply_status(attacker, &"strength", 3)

	state.deal_damage_from(attacker, target, 6)  # 6 + 3 strength = 9

	assert_eq(target.hp, 21)


func test_weak_reduces_outgoing_damage() -> void:
	var state := _state()
	var attacker := _add_player(state, 30, Vector2i(0, 0))
	var target := _add_enemy(state, 30, Vector2i(1, 0))
	state.apply_status(attacker, &"weak", 1)

	state.deal_damage_from(attacker, target, 8)  # floor(8 * 0.75) = 6

	assert_eq(target.hp, 24)


func test_apply_effects_folds_strength_into_damage() -> void:
	# Criterion 6: apply a damage effect list through the resolver + state, and
	# confirm the attacker's strength was folded in (proves resolver<->state wire).
	var state := _state()
	var attacker := _add_player(state, 30, Vector2i(0, 0))
	var target := _add_enemy(state, 30, Vector2i(1, 0))
	state.apply_status(attacker, &"strength", 2)

	var dmg := Effect.new()
	dmg.type = &"damage"
	dmg.amount = 5
	state.apply_effects(attacker, target, [dmg])  # (5 + 2) = 7

	assert_eq(target.hp, 23)


# --- energy refill ----------------------------------------------------------

func test_energy_refills_at_player_turn_start() -> void:
	var state := _state(3)
	_add_player(state, 30, Vector2i(0, 0))
	_add_enemy(state, 30, Vector2i(7, 7))

	state.energy = 0
	state.start_player_turn()
	assert_eq(state.energy, 3, "energy refills to energy_per_turn")
	assert_eq(state.turn_number, 1, "turn counter advances")

	state.energy = 1  # spend some
	state.start_player_turn()
	assert_eq(state.energy, 3, "refills again next turn, not accumulates")


func test_add_energy_tops_up_pool() -> void:
	var state := _state(3)
	state.energy = 2
	state.add_energy(2)
	assert_eq(state.energy, 4, "gain_energy adds on top of the pool")


# --- draw at turn start ------------------------------------------------------

func test_player_turn_start_draws_per_turn() -> void:
	var cfg := _config(3, 2)
	var grid := GridModel.new(Vector2i(8, 8))
	var deck := Deck.new(cfg)
	# Seed the draw pile with 5 plain cards.
	for _i in range(5):
		deck.draw_pile.append(_card())
	var state := BattleStateScript.new(cfg, grid, deck, _status_defs())
	_add_player(state, 30, Vector2i(0, 0))

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
	var player := _add_player(state, 30, Vector2i(0, 0))
	_add_enemy(state, 30, Vector2i(7, 7))
	state.apply_status(player, &"poison", 3)

	state.start_player_turn()  # ticks player statuses

	assert_eq(player.hp, 27, "poison dealt its 3 stacks as damage")
	assert_eq(player.status_stacks(&"poison"), 2, "poison decremented by one")


# --- block decays at owner's turn start -------------------------------------

func test_block_absorbs_during_turn_then_resets_next_turn() -> void:
	var state := _state()
	var player := _add_player(state, 30, Vector2i(0, 0))
	_add_enemy(state, 30, Vector2i(7, 7))

	state.add_block(player, 6)
	assert_eq(player.block, 6)
	state.deal_damage(player, 4)  # absorbed
	assert_eq(player.block, 2, "block absorbed incoming damage")
	assert_eq(player.hp, 30)

	state.start_player_turn()  # block decays (does not carry over)
	assert_eq(player.block, 0, "leftover block resets at the owner's next turn")


# --- stun skips the action --------------------------------------------------

func test_stun_makes_enemy_skip_its_action() -> void:
	# Use a BattleState subclass that records which enemies actually acted, so we
	# can prove a stunned enemy is skipped while an un-stunned one acts.
	var state := _RecordingBattleState.new(_config(), GridModel.new(Vector2i(8, 8)), Deck.new(_config()), _status_defs())
	_add_player(state, 30, Vector2i(0, 0))
	var stunned := _add_enemy(state, 30, Vector2i(7, 7))
	var active := _add_enemy(state, 30, Vector2i(6, 6))
	state.apply_status(stunned, &"stun", 1)

	state.start_player_turn()
	state.end_player_turn()  # runs the enemy phase

	assert_false(state.acted.has(stunned), "stunned enemy skipped its action")
	assert_true(state.acted.has(active), "un-stunned enemy still acted")
	assert_eq(stunned.status_stacks(&"stun"), 0, "stun was consumed")


## BattleState that records each enemy that reaches its action.
class _RecordingBattleState extends BattleState:
	var acted: Array = []

	func _take_enemy_action(enemy: Combatant) -> void:
		acted.append(enemy)


# --- push -------------------------------------------------------------------

func test_push_shoves_target_away_and_updates_grid() -> void:
	var state := _state()
	var pusher := _add_player(state, 30, Vector2i(2, 2))
	var victim := _add_enemy(state, 30, Vector2i(3, 2))

	state.push_unit(victim, 2, pusher)  # pushed in +x from (3,2) to (5,2)

	assert_eq(victim.grid_position, Vector2i(5, 2))
	assert_true(state.grid.is_occupied(Vector2i(5, 2)))
	assert_false(state.grid.is_occupied(Vector2i(3, 2)), "old tile freed")


func test_push_stops_at_grid_edge() -> void:
	var state := _state()
	var pusher := _add_player(state, 30, Vector2i(5, 0))
	var victim := _add_enemy(state, 30, Vector2i(6, 0))

	state.push_unit(victim, 5, pusher)  # would go past x=7 edge

	assert_eq(victim.grid_position, Vector2i(7, 0), "stops at the last in-bounds tile")


# --- move -------------------------------------------------------------------

func test_move_unit_relocates_on_grid() -> void:
	var state := _state()
	var unit := _add_player(state, 30, Vector2i(1, 1))

	state.move_unit(unit, Vector2i(3, 4))

	assert_eq(unit.grid_position, Vector2i(3, 4))
	assert_true(state.grid.is_occupied(Vector2i(3, 4)))
	assert_false(state.grid.is_occupied(Vector2i(1, 1)), "old tile freed")


# --- heal -------------------------------------------------------------------

func test_heal_clamps_to_max_hp() -> void:
	var state := _state()
	var unit := _add_player(state, 30, Vector2i(0, 0))
	state.deal_damage(unit, 10)
	assert_eq(unit.hp, 20)

	state.heal(unit, 100)
	assert_eq(unit.hp, 30, "heal clamps to max_hp")


# --- win / lose -------------------------------------------------------------

func test_check_outcome_ongoing_with_both_sides_alive() -> void:
	var state := _state()
	_add_player(state, 30, Vector2i(0, 0))
	_add_enemy(state, 30, Vector2i(7, 7))
	assert_eq(state.check_outcome(), BattleState.Outcome.ONGOING)


func test_scripted_sequence_drives_battle_to_win() -> void:
	# 1 player vs 2 enemies. Player kills both enemies via apply_effects (the
	# resolver+state path), and check_outcome reports WIN once all enemies die.
	var state := _state()
	var hero := _add_player(state, 30, Vector2i(0, 0))
	var e1 := _add_enemy(state, 10, Vector2i(7, 7))
	var e2 := _add_enemy(state, 10, Vector2i(6, 6))

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
	# 1 player vs 1 enemy; the enemy strikes the player down. check_outcome => LOSS.
	var state := _state()
	var hero := _add_player(state, 8, Vector2i(0, 0))
	var foe := _add_enemy(state, 30, Vector2i(1, 0))

	var crush := Effect.new()
	crush.type = &"damage"
	crush.amount = 8

	state.apply_effects(foe, hero, [crush])
	assert_false(hero.is_alive())
	assert_eq(state.check_outcome(), BattleState.Outcome.LOSS, "all players dead => LOSS")


func test_mutual_wipe_reads_as_loss() -> void:
	var state := _state()
	var hero := _add_player(state, 5, Vector2i(0, 0))
	var foe := _add_enemy(state, 5, Vector2i(1, 0))
	state.deal_damage(hero, 5)
	state.deal_damage(foe, 5)
	assert_eq(state.check_outcome(), BattleState.Outcome.LOSS, "player wipe wins ties as loss")
