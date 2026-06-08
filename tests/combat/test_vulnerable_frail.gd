extends "res://addons/gut/test.gd"
## GUT suite for the two new enemy debuff-slot statuses (enemy kit redesign):
##   Vulnerable — the target takes +50% damage from ATTACKS (not poison/bare hits).
##   Frail      — the target gains -50% block.
## Both are duration-stacking and decay one stack per turn (like Weak). Built on a
## real assembled battle so the loaded StatusData drives stacking/decay; enemies
## (0 attack stat) are used as clean attackers so the numbers isolate the status.

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


# --- Vulnerable -------------------------------------------------------------

func test_vulnerable_amplifies_attack_damage() -> void:
	var battle := _battle()
	var enemies: Array[Combatant] = battle.living_enemies()
	var atk: Combatant = enemies[0]
	var tgt: Combatant = enemies[1]
	tgt.block = 0

	tgt.hp = 50
	battle.deal_damage_from(atk, tgt, 10)
	assert_eq(tgt.hp, 40, "baseline: 10 damage, no Vulnerable")

	tgt.hp = 50
	battle.apply_status(tgt, &"vulnerable", 2)
	battle.deal_damage_from(atk, tgt, 10)
	assert_eq(tgt.hp, 35, "Vulnerable: 10 → 15 (+50%) damage taken")


func test_vulnerable_does_not_affect_bare_damage_or_poison() -> void:
	# Vulnerable is attack-only: a bare deal_damage (the path poison ticks use) is
	# NOT amplified.
	var battle := _battle()
	var tgt: Combatant = battle.living_enemies()[0]
	tgt.block = 0
	tgt.hp = 50
	battle.apply_status(tgt, &"vulnerable", 2)
	battle.deal_damage(tgt, 6)
	assert_eq(tgt.hp, 44, "bare damage (poison path) ignores Vulnerable")


func test_vulnerable_decays_each_turn() -> void:
	var battle := _battle()
	var unit: Combatant = battle.living_players()[0]
	battle.apply_status(unit, &"vulnerable", 2)
	assert_eq(unit.status_stacks(&"vulnerable"), 2, "applied 2 turns")
	battle.start_player_turn()  # ticks player statuses
	assert_eq(unit.status_stacks(&"vulnerable"), 1, "decays one stack per turn")


# --- Frail ------------------------------------------------------------------

func test_frail_reduces_block_gained() -> void:
	var battle := _battle()
	var unit: Combatant = battle.living_players()[0]

	unit.block = 0
	battle.add_block(unit, 10)
	assert_eq(unit.block, 10, "baseline: full block, no Frail")

	unit.block = 0
	battle.apply_status(unit, &"frail", 2)
	battle.add_block(unit, 10)
	assert_eq(unit.block, 5, "Frail: block gained halved (10 → 5)")


func test_frail_decays_each_turn() -> void:
	var battle := _battle()
	var unit: Combatant = battle.living_players()[0]
	battle.apply_status(unit, &"frail", 2)
	assert_eq(unit.status_stacks(&"frail"), 2, "applied 2 turns")
	battle.start_player_turn()
	assert_eq(unit.status_stacks(&"frail"), 1, "decays one stack per turn")


# --- Loaded as real statuses ------------------------------------------------

func test_new_statuses_load() -> void:
	assert_not_null(_db.get_status(&"vulnerable"), "vulnerable StatusData loads")
	assert_not_null(_db.get_status(&"frail"), "frail StatusData loads")
	assert_eq(_db.get_status(&"vulnerable").stacking, &"duration", "duration stacking")
