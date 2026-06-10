extends "res://addons/gut/test.gd"
## GUT suite for the ADR-0028 (DCC adaptation) combat mechanics:
##   self_damage  — caster-side bomb tax: once per card, block absorbs, never stat-amplified.
##   self_block   — caster-side block rider (Gut Check): once per card, DEX-scaled.
##   Charm        — non-decaying stacking debuff: Vuln+Weak proc every 10 stacks
##                  crossed; execute (hp -> 0, bypasses block) at stacks >= max_hp.
##   charm_damage — attack that applies Charm equal to UNBLOCKED damage dealt.
##   consume_status_damage — Coup de Grace: damage = target's Charm, then remove it.
##   add_card     — token generation into the caster's hand (Magic Missile).
## Also covers the Vulnerable fold into apply_effects (card/intent attacks now
## amplify on Vulnerable targets, parity with deal_damage_from).

const EncounterAssemblerScript := preload("res://src/combat/encounter_assembler.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _battle() -> EncounterBattle:
	# enc_combat_01 = grunt ×2 → two flat enemies (attack_power 0).
	return EncounterAssemblerScript.new().build(
		_db.get_encounter(&"enc_combat_01"), _db, [&"fighter", &"mage"] as Array[StringName], 1
	)


func _effect(type: StringName, amount: int = 0, status: StringName = &"", stacks: int = 0) -> Effect:
	var e := Effect.new()
	e.type = type
	e.amount = amount
	e.status = status
	e.stacks = stacks
	e.stat_mult = 1.0
	return e


# --- self_damage (the bomb tax) ----------------------------------------------

func test_self_damage_fires_once_for_an_aoe_and_block_absorbs() -> void:
	var battle := _battle()
	var caster: Combatant = battle.living_players()[0]
	var foes: Array[Combatant] = battle.living_enemies()
	assert_gt(foes.size(), 1, "multiple enemies so 'once per card' is observable")
	caster.hp = 30
	caster.block = 2
	# A bomb: AOE damage + a 3-point caster tax (Cobbled Bomb's shape).
	var effects: Array = [_effect(&"damage", 4), _effect(&"self_damage", 3)]
	battle.apply_effects(caster, foes, effects, false)
	# Tax fired ONCE (not per enemy): 3 incoming, 2 blocked, 1 to hp.
	assert_eq(caster.block, 0, "the tax is absorbed by block first")
	assert_eq(caster.hp, 29, "3 tax - 2 block = 1 hp, applied once for the whole AOE")


func test_self_damage_is_never_stat_amplified() -> void:
	var battle := _battle()
	var caster: Combatant = battle.living_players()[0]
	caster.block = 0
	caster.hp = 30
	battle.apply_status(caster, &"strength", 5)  # would add to any normal attack
	battle.apply_effects(caster, battle.living_enemies(), [_effect(&"self_damage", 3)], true)
	assert_eq(caster.hp, 27, "the tax stays 3 — Strength/attack stat never amplify it")


# --- self_block (Gut Check) ---------------------------------------------------

func test_self_block_lands_on_caster_with_dex_scaling() -> void:
	var battle := _battle()
	var caster: Combatant = battle.living_players()[0]
	var foe: Combatant = battle.living_enemies()[0]
	caster.block = 0
	caster.dexterity = 2
	foe.hp = 50
	# Gut Check's shape: damage the enemy, block the caster — one card.
	battle.apply_effects(caster, [foe], [_effect(&"damage", 4), _effect(&"self_block", 4)], true)
	assert_lt(foe.hp, 50, "the enemy took the hit")
	assert_eq(caster.block, 6, "the caster gained 4 + DEX 2 block (enemy untouched by block)")


# --- Charm: thresholds + execute ----------------------------------------------

func test_charm_proc_fires_on_each_threshold_crossing() -> void:
	var battle := _battle()
	var foe: Combatant = battle.living_enemies()[0]
	battle.apply_status(foe, &"charm", 9)
	assert_eq(foe.status_stacks(&"vulnerable"), 0, "9 Charm: below the 10 threshold")
	battle.apply_status(foe, &"charm", 1)
	assert_eq(foe.status_stacks(&"vulnerable"), 2, "crossing 10 procs 2 Vulnerable")
	assert_eq(foe.status_stacks(&"weak"), 2, "…and 2 Weak")
	battle.apply_status(foe, &"charm", 9)
	assert_eq(foe.status_stacks(&"charm"), 19, "Charm accumulates (intensity, no decay)")
	battle.apply_status(foe, &"charm", 1)
	assert_eq(foe.status_stacks(&"weak"), 2, "crossing 20 refreshes the duration debuffs")


func test_charm_does_not_decay_on_turn_tick() -> void:
	var battle := _battle()
	var foe: Combatant = battle.living_enemies()[0]
	battle.apply_status(foe, &"charm", 5)
	battle.start_player_turn()
	battle.end_player_turn()  # enemy phase ticks enemy statuses
	assert_eq(foe.status_stacks(&"charm"), 5, "Charm never decays (the run-long debuff)")


func test_charm_executes_at_max_hp_bypassing_block() -> void:
	var battle := _battle()
	var foe: Combatant = battle.living_enemies()[0]
	foe.block = 99
	var need: int = foe.max_hp
	battle.apply_status(foe, &"charm", need)
	assert_false(foe.is_alive(), "Charm >= max_hp executes through block")
	assert_eq(battle.charm_executes, 1, "the execute is counted (Fame trigger)")


# --- charm_damage (Charm = unblocked damage) -----------------------------------

func test_charm_damage_charms_only_the_unblocked_portion() -> void:
	var battle := _battle()
	var caster: Combatant = battle.living_players()[0]
	var foe: Combatant = battle.living_enemies()[0]
	foe.hp = 50
	foe.block = 3
	battle.apply_effects(caster, [foe], [_effect(&"charm_damage", 8)], false)
	# 8 incoming: 3 blocked, 5 to hp → 5 Charm. (No stat scaling: fighter str only
	# folds when scale_with_stats — passed false to isolate the rule.)
	assert_eq(foe.hp, 45, "5 unblocked damage landed")
	assert_eq(foe.status_stacks(&"charm"), 5, "Charm equals the UNBLOCKED damage only")


func test_charm_damage_fully_blocked_applies_no_charm() -> void:
	var battle := _battle()
	var caster: Combatant = battle.living_players()[0]
	var foe: Combatant = battle.living_enemies()[0]
	foe.hp = 50
	foe.block = 20
	battle.apply_effects(caster, [foe], [_effect(&"charm_damage", 8)], false)
	assert_eq(foe.hp, 50, "fully absorbed")
	assert_eq(foe.status_stacks(&"charm"), 0, "block soaks the Charm too (the mod's rule)")


# --- consume_status_damage (Coup de Grace) -------------------------------------

func test_consume_status_damage_cashes_in_charm() -> void:
	var battle := _battle()
	var caster: Combatant = battle.living_players()[0]
	var foe: Combatant = battle.living_enemies()[0]
	foe.hp = 50
	foe.block = 0
	battle.apply_status(foe, &"charm", 8)
	battle.apply_effects(caster, [foe], [_effect(&"consume_status_damage", 0, &"charm")], false)
	assert_eq(foe.hp, 42, "damage equals the Charm stacks (8)")
	assert_eq(foe.status_stacks(&"charm"), 0, "…and the Charm is consumed")


# --- add_card (token generation) ------------------------------------------------

func test_add_card_puts_the_token_in_the_casters_hand() -> void:
	var battle := _battle()
	var caster: Combatant = battle.living_players()[0]
	var hand_before: int = battle.deck_of(caster).hand.size()
	var e := _effect(&"add_card")
	e.params = {"card_id": "magic_missile"}
	battle.apply_effects(caster, battle.living_enemies(), [e], true)
	var hand: Array[CardData] = battle.deck_of(caster).hand
	assert_eq(hand.size(), hand_before + 1, "token added ONCE (global, not per target)")
	assert_eq(String(hand[hand.size() - 1].id), "magic_missile", "…and it is the named card")


func test_add_card_overflows_to_discard_when_hand_is_full() -> void:
	var battle := _battle()
	var caster: Combatant = battle.living_players()[0]
	var deck: Deck = battle.deck_of(caster)
	var filler: CardData = _db.get_card(&"magic_missile")
	while deck.hand.size() < battle.config.max_hand:
		deck.hand.append(filler)
	var discard_before: int = deck.discard_pile.size()
	battle.add_card_to_hand(&"magic_missile", caster)
	assert_eq(deck.hand.size(), battle.config.max_hand, "hand respects max_hand")
	assert_eq(deck.discard_pile.size(), discard_before + 1, "the token overflows to discard, never lost")


# --- Vulnerable fold into apply_effects ------------------------------------------

func test_card_damage_now_amplifies_on_vulnerable_targets() -> void:
	var battle := _battle()
	var enemies: Array[Combatant] = battle.living_enemies()
	var atk: Combatant = enemies[0]   # enemy attacker: 0 attack stat isolates the math
	var tgt: Combatant = enemies[1]
	tgt.block = 0
	tgt.hp = 50
	battle.apply_effects(atk, [tgt], [_effect(&"damage", 10)], true)
	assert_eq(tgt.hp, 40, "baseline 10")
	tgt.hp = 50
	battle.apply_status(tgt, &"vulnerable", 2)
	battle.apply_effects(atk, [tgt], [_effect(&"damage", 10)], true)
	assert_eq(tgt.hp, 35, "Vulnerable: 10 → 15 through the card/intent path too")


# --- The new effect types are registered end to end ------------------------------

func test_new_effect_types_validate_and_dcc_cards_load() -> void:
	var result = _db.load_from_dir("res://data")
	assert_true(result.ok, "real /data (incl. ADR-0028 cards) loads cleanly")
	for cid in [&"gut_check", &"cobbled_bomb", &"play_to_the_crowd", &"coup_de_grace", &"spell_weave"]:
		assert_not_null(_db.get_card(cid), "card '%s' loads" % cid)
	assert_not_null(_db.get_status(&"charm"), "charm StatusData loads")
	assert_false(_db.get_status(&"charm").decays_each_turn, "charm never decays")
