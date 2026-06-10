extends "res://addons/gut/test.gd"
## GUT suite for the relic system (P2·12, run-structure.md §7/§8): RelicEngine
## applies combat_start / passive / turn_start effects, and the assembler +
## EncounterBattle wire those hooks into a real fight. Uses /data content for the
## battle and in-memory RelicData so each test states its own relic.

const RelicEngineScript := preload("res://src/combat/relic_engine.gd")
const RelicDataScript := preload("res://src/data/relic_data.gd")
const EncounterAssemblerScript := preload("res://src/combat/encounter_assembler.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _relic(trigger: StringName, effect: StringName, amount: int) -> RelicData:
	var r := RelicDataScript.new()
	r.id = &"test_relic"
	r.display_name = "Test Relic"
	r.trigger = trigger
	r.effect = effect
	r.amount = amount
	return r


## A real assembled fight (relics optional) to apply engine hooks against.
func _battle(relics: Array[RelicData] = []) -> EncounterBattle:
	return EncounterAssemblerScript.new().build(
		_db.get_encounter(&"enc_combat_01"), _db,
		[&"fighter", &"mage"] as Array[StringName], 1, {}, {},
		{}, {}, relics
	)


# --- RelicEngine: combat_start ----------------------------------------------

func test_gain_block_grants_block_to_party() -> void:
	var battle := _battle()
	RelicEngineScript.new().apply_combat_start(battle, [_relic(&"combat_start", &"gain_block", 6)])
	for unit in battle.living_players():
		assert_eq(unit.block, 6, "%s gained block" % unit.display_name)


func test_add_strength_grants_strength_to_party() -> void:
	var battle := _battle()
	RelicEngineScript.new().apply_combat_start(battle, [_relic(&"combat_start", &"add_strength", 2)])
	for unit in battle.living_players():
		assert_eq(unit.status_stacks(&"strength"), 2, "%s gained strength" % unit.display_name)


# --- RelicEngine: passive ---------------------------------------------------

func test_max_hp_up_raises_max_and_current_hp() -> void:
	var battle := _battle()
	var before: Dictionary = {}
	for unit in battle.living_players():
		before[unit.display_name] = unit.max_hp
	RelicEngineScript.new().apply_passive(battle, [_relic(&"passive", &"max_hp_up", 5)])
	for unit in battle.living_players():
		assert_eq(unit.max_hp, int(before[unit.display_name]) + 5, "max HP raised")
		assert_eq(unit.hp, unit.max_hp, "current HP kept full after a passive max-HP bump")


# --- RelicEngine: turn_start ------------------------------------------------

func test_gain_energy_adds_energy() -> void:
	# ADR-0025 provisional: a party-level energy relic credits the FIRST living
	# player's pool (the origin character).
	var battle := _battle()
	battle.start_player_turn()
	var first: Combatant = battle.living_players()[0]
	var base: int = battle.energy_of(first)
	RelicEngineScript.new().apply_turn_start(battle, [_relic(&"turn_start", &"gain_energy", 2)])
	assert_eq(battle.energy_of(first), base + 2, "turn_start energy relic adds to the first pool")


func test_mismatched_trigger_is_ignored() -> void:
	var battle := _battle()
	# A combat_start relic handed to the turn_start hook must do nothing.
	RelicEngineScript.new().apply_turn_start(battle, [_relic(&"combat_start", &"gain_block", 6)])
	for unit in battle.living_players():
		assert_eq(unit.block, 0, "combat_start relic not applied by the turn_start hook")


# --- Integration: assembler + EncounterBattle wiring ------------------------

func test_assembler_applies_combat_start_relics() -> void:
	var battle := _battle([_relic(&"combat_start", &"gain_block", 4)] as Array[RelicData])
	for unit in battle.living_players():
		assert_eq(unit.block, 4, "assembler applied a combat_start relic at build")


func test_encounter_battle_applies_turn_start_relics_each_turn() -> void:
	var battle := _battle([_relic(&"turn_start", &"gain_energy", 2)] as Array[RelicData])
	var base: int = _db.get_battle_config().energy_per_character
	battle.start_player_turn()
	assert_eq(
		battle.energy_of(battle.living_players()[0]), base + 2,
		"turn_start relic fires on top of the first pool's base refill (ADR-0025)"
	)


func test_passive_relic_raises_max_hp_via_assembler() -> void:
	var battle := _battle([_relic(&"passive", &"max_hp_up", 6)] as Array[RelicData])
	var fighter: Combatant = null
	for unit in battle.living_players():
		var d := unit.source_data as CharacterData
		if d != null and d.id == &"fighter":
			fighter = unit
	assert_not_null(fighter, "fighter spawned")
	assert_eq(fighter.max_hp, _db.get_character(&"fighter").max_hp + 6, "passive max_hp_up raised the fighter's max HP at assembly")


func test_authored_relics_load() -> void:
	assert_not_null(_db.get_relic(&"iron_brand"), "authored relic loads from data/relics")
	assert_eq(_db.get_relic(&"dynamo_core").effect, &"gain_energy", "relic fields parsed")
