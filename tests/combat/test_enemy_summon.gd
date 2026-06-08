extends "res://addons/gut/test.gd"
## GUT suite for the mid-fight minion summon (enemy kit redesign / anti-turtle
## lever): every `summon_every` turns a summoner spawns a `summon_id` minion into
## the enemy team INSTEAD of acting, up to `summon_max`. Dragging a fight out keeps
## the board growing.

const EncounterAssemblerScript := preload("res://src/combat/encounter_assembler.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")
const EnemyDataScript := preload("res://src/data/enemy_data.gd")
const CombatantScript := preload("res://src/combat/combatant.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _battle() -> EncounterBattle:
	# Boss fight assembles with enemy_db set, so summoners can resolve minions.
	return EncounterAssemblerScript.new().build(
		_db.get_encounter(&"enc_combat_01"), _db, [&"fighter", &"mage"] as Array[StringName], 1
	)


func _summoner(every: int, cap: int, sid: StringName = &"gremlin") -> EnemyData:
	var d: EnemyData = EnemyDataScript.new()
	d.summon_id = sid
	d.summon_every = every
	d.summon_max = cap
	return d


func _enemy_unit() -> Combatant:
	var c: Combatant = CombatantScript.new()
	c.team = Combatant.Team.ENEMY
	return c


func test_summon_spawns_every_nth_turn_and_consumes_action() -> void:
	var battle := _battle()
	var before: int = battle.living_enemies().size()
	var s := _summoner(2, 3)
	var e := _enemy_unit()

	assert_false(battle._apply_enemy_summon(e, s), "turn 1 is not a summon turn")
	assert_eq(battle.living_enemies().size(), before, "no minion yet")
	assert_true(battle._apply_enemy_summon(e, s), "turn 2 summons (consumes the action)")
	assert_eq(battle.living_enemies().size(), before + 1, "a minion joined the enemy team")
	assert_eq(e.summons_done, 1, "summon counted")


func test_summon_respects_the_cap() -> void:
	var battle := _battle()
	var before: int = battle.living_enemies().size()
	var s := _summoner(1, 2)  # every turn, max 2
	var e := _enemy_unit()
	for _i in 5:
		battle._apply_enemy_summon(e, s)
	assert_eq(e.summons_done, 2, "never exceeds summon_max")
	assert_eq(battle.living_enemies().size(), before + 2, "only the capped number spawned")


func test_summoned_minion_is_the_right_enemy() -> void:
	var battle := _battle()
	var s := _summoner(1, 1, &"gremlin")
	var e := _enemy_unit()
	battle._apply_enemy_summon(e, s)
	var spawned: Combatant = battle.living_enemies()[battle.living_enemies().size() - 1]
	var data := spawned.source_data as EnemyData
	assert_eq(data.id, &"gremlin", "spawned the configured minion type")


func test_unconfigured_enemy_never_summons() -> void:
	var battle := _battle()
	var before: int = battle.living_enemies().size()
	var e := _enemy_unit()
	assert_false(battle._apply_enemy_summon(e, EnemyDataScript.new()), "no summon configured")
	assert_eq(battle.living_enemies().size(), before, "no minion spawned")


func test_captain_summons_loaded_from_data() -> void:
	var captain: EnemyData = _db.get_enemy(&"warband_captain")
	assert_eq(captain.summon_id, &"gremlin", "captain calls gremlin reinforcements")
	assert_gt(captain.summon_every, 0, "on a cadence")
	assert_gt(captain.summon_max, 0, "up to a cap")
