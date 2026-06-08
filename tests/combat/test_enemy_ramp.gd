extends "res://addons/gut/test.gd"
## GUT suite for the enemy damage ramp (enemy kit redesign): a SCHEDULED buff turn
## (every Nth turn the enemy gains Strength instead of acting) and a PASSIVE ramp
## (free Strength every turn, boss mode). Strength is the permanent +damage status,
## so it compounds over a long fight — punishing slow play without nerfing burst.

const EncounterAssemblerScript := preload("res://src/combat/encounter_assembler.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")
const EnemyDataScript := preload("res://src/data/enemy_data.gd")
const CombatantScript := preload("res://src/combat/combatant.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


## A real EncounterBattle so _apply_enemy_ramp can be exercised on it.
func _battle() -> EncounterBattle:
	return EncounterAssemblerScript.new().build(
		_db.get_encounter(&"enc_combat_01"), _db, [&"fighter", &"mage"] as Array[StringName], 1
	)


func _enemy() -> Combatant:
	var c: Combatant = CombatantScript.new()
	c.team = Combatant.Team.ENEMY
	return c


# --- Scheduled buff turn ----------------------------------------------------

func test_scheduled_ramp_fires_every_nth_turn_and_consumes_the_action() -> void:
	var battle := _battle()
	var data: EnemyData = EnemyDataScript.new()
	data.ramp_amount = 2
	data.ramp_every = 4
	var e := _enemy()

	# Turns 1-3: no ramp, normal action (returns false).
	for i in 3:
		assert_false(battle._apply_enemy_ramp(e, data), "turn %d is a normal turn" % (i + 1))
		assert_eq(e.status_stacks(&"strength"), 0, "no Strength before the 4th turn")
	# Turn 4: buff turn — grants Strength AND consumes the action (returns true).
	assert_true(battle._apply_enemy_ramp(e, data), "the 4th turn is a buff turn")
	assert_eq(e.status_stacks(&"strength"), 2, "buff turn grants ramp_amount Strength")
	# Turns 5-7 normal, turn 8 buffs again → 4 Strength.
	for _i in 3:
		battle._apply_enemy_ramp(e, data)
	assert_true(battle._apply_enemy_ramp(e, data), "buffs again on the 8th turn")
	assert_eq(e.status_stacks(&"strength"), 4, "ramp compounds over a long fight")


# --- Passive ramp (boss) ----------------------------------------------------

func test_passive_ramp_is_free_every_turn() -> void:
	var battle := _battle()
	var data: EnemyData = EnemyDataScript.new()
	data.ramp_amount = 1
	data.ramp_passive = true
	var e := _enemy()

	# Passive ramp never consumes the action (returns false) but adds Strength each call.
	assert_false(battle._apply_enemy_ramp(e, data), "passive ramp does not consume the action")
	assert_eq(e.status_stacks(&"strength"), 1, "passive grants Strength turn 1")
	battle._apply_enemy_ramp(e, data)
	battle._apply_enemy_ramp(e, data)
	assert_eq(e.status_stacks(&"strength"), 3, "passive ramp accrues every turn for free")


func test_upcoming_special_telegraphs_the_buff_turn() -> void:
	# The UI peek must flag the buff turn BEFORE it happens so the telegraph is honest.
	var battle := _battle()
	var data: EnemyData = EnemyDataScript.new()
	data.ramp_amount = 2
	data.ramp_every = 3
	var e := _enemy()
	e.source_data = data
	# Turns 1,2 are normal; the 3rd will be the empower turn.
	assert_eq(battle.upcoming_special(e), &"", "turn 1 telegraphs a normal action")
	e.turns_taken = 2
	assert_eq(battle.upcoming_special(e), &"empower", "next (3rd) turn telegraphs Empower")


func test_upcoming_special_telegraphs_summon() -> void:
	var battle := _battle()
	var e := _enemy()
	e.source_data = _db.get_enemy(&"warband_captain")  # summons gremlins every 3
	e.turns_taken = 2
	assert_eq(battle.upcoming_special(e), &"summon", "captain telegraphs Reinforce on its summon turn")


func test_no_ramp_when_unconfigured() -> void:
	var battle := _battle()
	var data: EnemyData = EnemyDataScript.new()  # ramp_amount 0
	var e := _enemy()
	assert_false(battle._apply_enemy_ramp(e, data), "no ramp configured → never a buff turn")
	assert_eq(e.status_stacks(&"strength"), 0, "no Strength gained")


# --- Loaded from data -------------------------------------------------------

func test_enemy_ramp_fields_load() -> void:
	# Assert the cadence/shape, not exact magnitudes, so balance tuning of the
	# amounts doesn't break the suite.
	var footman: EnemyData = _db.get_enemy(&"footman")
	assert_eq(footman.ramp_every, 4, "Medium enemy ramps on a 4-turn cadence")
	assert_gt(footman.ramp_amount, 0, "Medium has a ramp amount")
	assert_false(footman.ramp_passive, "Medium ramp is a scheduled buff turn, not passive")

	var warden: EnemyData = _db.get_enemy(&"iron_warden")
	assert_true(warden.ramp_passive, "boss ramps passively (free)")
	assert_gt(warden.ramp_amount, 0, "boss has a passive ramp amount")
