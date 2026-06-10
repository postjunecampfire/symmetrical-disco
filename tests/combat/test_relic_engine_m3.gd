extends "res://addons/gut/test.gd"
## GUT suite for the M3 relic trigger kinds (Relics → ~35): on_kill /
## on_curse_drawn / hp_threshold / on_status_applied / on_card_played fire from
## BattleState's virtual seams via EncounterBattle, and the run-layer passive
## effects (economy / sight / derivation) are static RelicEngine queries.
## Mirrors tests/combat/test_relic_engine.gd: /data content for the battle,
## in-memory RelicData so each test states its own relic.

const RelicEngineScript := preload("res://src/combat/relic_engine.gd")
const RelicDataScript := preload("res://src/data/relic_data.gd")
const EncounterAssemblerScript := preload("res://src/combat/encounter_assembler.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")

var _db: ContentDatabase


# One db load per script (before_all, not before_each): nothing here mutates the
# database, and the per-test load was the suite's whole runtime.
func before_all() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _relic(trigger: StringName, effect: StringName, amount: int) -> RelicData:
	var r := RelicDataScript.new()
	r.id = &"test_relic_m3"
	r.display_name = "Test Relic M3"
	r.trigger = trigger
	r.effect = effect
	r.amount = amount
	return r


## A real assembled fight (relics optional) so the EncounterBattle overrides run.
func _battle(relics: Array[RelicData] = []) -> EncounterBattle:
	return EncounterAssemblerScript.new().build(
		_db.get_encounter(&"enc_combat_01"), _db,
		[&"fighter", &"mage"] as Array[StringName], 1, {}, {},
		{}, {}, relics
	)


# --- on_kill ------------------------------------------------------------------

func test_on_kill_gain_block_credits_party() -> void:
	var battle := _battle([_relic(&"on_kill", &"gain_block", 3)] as Array[RelicData])
	var enemy: Combatant = battle.living_enemies()[0]
	battle.deal_damage(enemy, enemy.hp + enemy.block)
	assert_false(enemy.is_alive(), "the enemy died")
	for unit in battle.living_players():
		assert_eq(unit.block, 3, "%s gained 3 Block from the kill" % unit.display_name)


func test_on_kill_gain_energy_credits_first_pool() -> void:
	var battle := _battle([_relic(&"on_kill", &"gain_energy", 1)] as Array[RelicData])
	battle.start_player_turn()
	var first: Combatant = battle.living_players()[0]
	var base: int = battle.energy_of(first)
	var enemy: Combatant = battle.living_enemies()[0]
	battle.deal_damage(enemy, enemy.hp + enemy.block)
	assert_eq(battle.energy_of(first), base + 1, "kill energy lands in the first pool")


func test_on_kill_gain_gold_banks_run_gold() -> void:
	var battle := _battle([_relic(&"on_kill", &"gain_gold", 5)] as Array[RelicData])
	var enemy: Combatant = battle.living_enemies()[0]
	battle.deal_damage(enemy, enemy.hp + enemy.block)
	assert_eq(battle.gold_found, 5, "kill gold banked for finish_combat to credit")


func test_on_kill_fires_for_unblockable_dot_deaths() -> void:
	var battle := _battle([_relic(&"on_kill", &"gain_gold", 5)] as Array[RelicData])
	var enemy: Combatant = battle.living_enemies()[0]
	battle.deal_unblockable(enemy, enemy.hp)
	assert_false(enemy.is_alive(), "the DoT killed")
	assert_eq(battle.gold_found, 5, "a poison/bleed death is still a kill")


func test_no_on_kill_without_a_death() -> void:
	var battle := _battle([_relic(&"on_kill", &"gain_gold", 5)] as Array[RelicData])
	var enemy: Combatant = battle.living_enemies()[0]
	battle.deal_damage(enemy, 1)
	assert_true(enemy.is_alive(), "chip damage did not kill")
	assert_eq(battle.gold_found, 0, "no kill, no gold")


# --- on_curse_drawn -----------------------------------------------------------

func test_on_curse_drawn_gain_energy_credits_the_drawer() -> void:
	var battle := _battle([_relic(&"on_curse_drawn", &"gain_energy", 1)] as Array[RelicData])
	var unit: Combatant = battle.living_players()[0]
	var curse: CardData = _db.get_card(&"wound")
	assert_not_null(curse, "the 'wound' curse exists in /data")
	battle.deck_of(unit).draw_pile.append(curse)  # next draw_one pops from the back
	var base: int = battle.energy_of(unit)
	battle.draw_cards(1, unit)
	assert_eq(battle.energy_of(unit), base + 1, "drawing a curse paid 1 energy back")


func test_on_curse_drawn_ignores_ordinary_draws() -> void:
	var battle := _battle([_relic(&"on_curse_drawn", &"gain_energy", 1)] as Array[RelicData])
	var unit: Combatant = battle.living_players()[0]
	battle.deck_of(unit).draw_pile.append(_db.get_card(&"strike"))
	var base: int = battle.energy_of(unit)
	battle.draw_cards(1, unit)
	assert_eq(battle.energy_of(unit), base, "a skill draw triggers nothing")


# --- hp_threshold -------------------------------------------------------------

func test_hp_threshold_strength_fires_once_per_combat() -> void:
	var battle := _battle([_relic(&"hp_threshold", &"add_strength", 2)] as Array[RelicData])
	var unit: Combatant = battle.living_players()[0]
	var dmg: int = unit.hp - unit.max_hp / 2 + 1  # lands strictly below half
	battle.deal_damage(unit, dmg)
	assert_true(unit.hp * 2 < unit.max_hp, "the member is below half HP")
	assert_eq(unit.status_stacks(&"strength"), 2, "first crossing grants Strength")
	battle.deal_damage(unit, 1)
	assert_eq(unit.status_stacks(&"strength"), 2, "the latch holds — no second proc")


func test_hp_threshold_block_credits_that_member_only() -> void:
	var battle := _battle([_relic(&"hp_threshold", &"gain_block", 8)] as Array[RelicData])
	var players := battle.living_players()
	var hurt: Combatant = players[0]
	battle.deal_damage(hurt, hurt.hp - hurt.max_hp / 2 + 1)
	assert_eq(hurt.block, 8, "the dropping member gained the Block")
	assert_eq(players[1].block, 0, "the other member gained nothing")


func test_hp_threshold_silent_above_half() -> void:
	var battle := _battle([_relic(&"hp_threshold", &"add_strength", 2)] as Array[RelicData])
	var unit: Combatant = battle.living_players()[0]
	battle.deal_damage(unit, 1)
	if unit.hp * 2 >= unit.max_hp:
		assert_eq(unit.status_stacks(&"strength"), 0, "no proc while at/above half HP")


# --- on_status_applied --------------------------------------------------------

func test_amplify_burn_adds_extra_stacks_on_enemies() -> void:
	var battle := _battle([_relic(&"on_status_applied", &"amplify_burn", 1)] as Array[RelicData])
	var enemy: Combatant = battle.living_enemies()[0]
	battle.apply_status(enemy, &"burn", 3)
	assert_eq(enemy.status_stacks(&"burn"), 4, "3 applied + 1 amplified")


func test_amplify_does_not_touch_player_side_applications() -> void:
	var battle := _battle([_relic(&"on_status_applied", &"amplify_burn", 1)] as Array[RelicData])
	var unit: Combatant = battle.living_players()[0]
	battle.apply_status(unit, &"burn", 3)
	assert_eq(unit.status_stacks(&"burn"), 3, "an enemy burning the party is not amplified")


func test_amplify_matches_only_its_status() -> void:
	var battle := _battle([_relic(&"on_status_applied", &"amplify_bleed", 2)] as Array[RelicData])
	var enemy: Combatant = battle.living_enemies()[0]
	battle.apply_status(enemy, &"burn", 3)
	assert_eq(enemy.status_stacks(&"burn"), 3, "a bleed amplifier ignores burn")
	battle.apply_status(enemy, &"bleed", 3)
	assert_eq(enemy.status_stacks(&"bleed"), 5, "and amplifies bleed by its amount")


# --- on_card_played (combo) ----------------------------------------------------

func test_combo_damage_kicks_in_from_the_third_play() -> void:
	var battle := _battle([_relic(&"on_card_played", &"combo_damage", 2)] as Array[RelicData])
	var player: Combatant = battle.living_players()[0]
	var enemy: Combatant = battle.living_enemies()[0]
	var hit := Effect.new()
	hit.type = &"damage"
	hit.amount = 5
	battle.cards_played_this_turn = 2
	var hp_before: int = enemy.hp + enemy.block
	battle.apply_effects(player, enemy, [hit], false)  # flat: no stat scaling
	assert_eq(enemy.hp + enemy.block, hp_before - 5, "2nd play: base damage only")
	battle.cards_played_this_turn = 3
	hp_before = enemy.hp + enemy.block
	battle.apply_effects(player, enemy, [hit], false)
	assert_eq(enemy.hp + enemy.block, hp_before - 7, "3rd play: +2 combo damage")


func test_card_play_counts_plays_and_turn_start_resets() -> void:
	var battle := _battle()
	battle.start_player_turn()
	assert_eq(battle.cards_played_this_turn, 0, "turn start resets the counter")
	var player: Combatant = battle.living_players()[0]
	var enemy: Combatant = battle.living_enemies()[0]
	var card: CardData = _db.get_card(&"strike")
	battle.deck_of(player).hand.append(card)
	var play := CardPlay.new(battle)
	assert_true(play.play_card(player, card, enemy).ok, "the strike resolved")
	assert_eq(battle.cards_played_this_turn, 1, "the play was counted")
	battle.start_player_turn()
	assert_eq(battle.cards_played_this_turn, 0, "next turn resets again")


func test_enemy_attacks_never_gain_combo_damage() -> void:
	var battle := _battle([_relic(&"on_card_played", &"combo_damage", 2)] as Array[RelicData])
	var player: Combatant = battle.living_players()[0]
	var enemy: Combatant = battle.living_enemies()[0]
	var hit := Effect.new()
	hit.type = &"damage"
	hit.amount = 5
	battle.cards_played_this_turn = 5
	var hp_before: int = player.hp + player.block
	battle.apply_effects(enemy, player, [hit], false)
	assert_eq(player.hp + player.block, hp_before - 5, "enemy damage stays unmodified")


# --- Run-layer static queries (economy / sight / derivation) -------------------

func test_economy_query_totals() -> void:
	var relics: Array[RelicData] = [
		_relic(&"passive", &"gold_on_win", 8), _relic(&"passive", &"gold_on_win", 15),
		_relic(&"passive", &"gold_on_rest", 12),
		_relic(&"passive", &"gold_pile_bonus", 50),
	]
	assert_eq(RelicEngineScript.gold_on_win_total(relics), 23, "gold_on_win sums")
	assert_eq(RelicEngineScript.gold_on_rest_total(relics), 12, "gold_on_rest sums")
	assert_eq(RelicEngineScript.gold_pile_bonus_percent(relics), 50, "pile bonus sums")
	assert_eq(RelicEngineScript.gold_on_win_total([]), 0, "empty pool = 0")


func test_shop_discount_caps() -> void:
	var relics: Array[RelicData] = [
		_relic(&"passive", &"shop_discount", 40), _relic(&"passive", &"shop_discount", 40),
	]
	assert_eq(
		RelicEngineScript.shop_discount_percent(relics),
		RelicEngineScript.SHOP_DISCOUNT_CAP,
		"stacked discounts cap so prices never bottom out"
	)
	assert_eq(
		RelicEngineScript.curse_removal_discount_percent(
			[_relic(&"passive", &"curse_removal_discount", 95)] as Array[RelicData]
		),
		RelicEngineScript.CURSE_REMOVAL_DISCOUNT_CAP,
		"curse-removal discount caps too"
	)


func test_sight_queries() -> void:
	assert_true(
		RelicEngineScript.reveals_map([_relic(&"passive", &"reveal_map", 0)] as Array[RelicData]),
		"reveal_map query reads the effect"
	)
	assert_false(RelicEngineScript.reveals_map([] as Array[RelicData]), "no relic, no reveal")
	assert_true(
		RelicEngineScript.reveals_boss([_relic(&"passive", &"reveal_boss", 0)] as Array[RelicData]),
		"reveal_boss query reads the effect"
	)
	assert_false(
		RelicEngineScript.reveals_boss([_relic(&"passive", &"reveal_map", 0)] as Array[RelicData]),
		"reveal_map alone does not preview the boss"
	)


func test_derivation_queries() -> void:
	var relics: Array[RelicData] = [
		_relic(&"passive", &"extra_copy_rare", 1),
		_relic(&"passive", &"extra_copy_first", 1),
		_relic(&"passive", &"upgrade_basics", 0),
	]
	assert_eq(RelicEngineScript.extra_rare_copies(relics), 1, "rare-copy bonus summed")
	assert_eq(RelicEngineScript.extra_first_copies(relics), 1, "first-copy bonus summed")
	assert_true(RelicEngineScript.upgrades_basics(relics), "basics-upgrade flag read")
	assert_false(RelicEngineScript.upgrades_basics([] as Array[RelicData]), "absent = false")


func test_combo_and_status_bonus_helpers() -> void:
	var relics: Array[RelicData] = [_relic(&"on_card_played", &"combo_damage", 2)]
	assert_eq(RelicEngineScript.combo_bonus(relics, 2), 0, "below threshold: no bonus")
	assert_eq(RelicEngineScript.combo_bonus(relics, 3), 2, "at threshold: full bonus")
	assert_eq(
		RelicEngineScript.status_bonus(
			[_relic(&"on_status_applied", &"amplify_poison", 1)] as Array[RelicData], &"poison"
		), 1, "amplify_poison maps to the poison status"
	)
	assert_eq(
		RelicEngineScript.status_bonus(
			[_relic(&"on_status_applied", &"amplify_poison", 1)] as Array[RelicData], &"burn"
		), 0, "and ignores other statuses"
	)


# --- Authored content sanity ----------------------------------------------------

func test_relic_pool_reaches_m3_target() -> void:
	assert_gte(_db.relics.size(), 35, "M3 target: ~35 authored relics")


func test_new_trigger_relics_load_from_data() -> void:
	assert_eq(_db.get_relic(&"trophy_belt").trigger, &"on_kill", "on_kill relic authored")
	assert_eq(_db.get_relic(&"graveside_candle").trigger, &"on_curse_drawn", "on_curse_drawn authored")
	assert_eq(_db.get_relic(&"berserkers_torc").trigger, &"hp_threshold", "hp_threshold authored")
	assert_eq(_db.get_relic(&"ember_pendant").trigger, &"on_status_applied", "on_status_applied authored")
	assert_eq(_db.get_relic(&"tempo_baton").trigger, &"on_card_played", "on_card_played authored")
	assert_eq(_db.get_relic(&"haggling_charm").effect, &"shop_discount", "economy relic authored")
	assert_eq(_db.get_relic(&"cartographers_lens").effect, &"reveal_map", "sight relic authored")
	assert_eq(_db.get_relic(&"collectors_folio").effect, &"extra_copy_rare", "derivation relic authored")
