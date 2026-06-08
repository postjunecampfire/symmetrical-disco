extends "res://addons/gut/test.gd"
## GUT suite for PartyStats.effective_max_hp (review fix #1): the single source of
## truth for a member's max HP — class base + race CON + allocated CON + passive
## max_hp_up relics — so every heal caps at the same, correct ceiling.

const PartyStatsScript := preload("res://src/run/party_stats.gd")
const RunStateScript := preload("res://src/run/run_state.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _run() -> RunState:
	var run := RunStateScript.new()
	run.party = [&"fighter"] as Array[StringName]
	return run


func test_base_is_class_max() -> void:
	assert_eq(PartyStatsScript.effective_max_hp(_db, _run(), &"fighter"), 34, "fighter base max")


func test_race_con_adds_to_max() -> void:
	var run := _run()
	run.party_races = {&"fighter": &"orc"}  # Orc +2 CON
	var per_con: int = _db.get_battle_config().hp_per_con
	assert_eq(
		PartyStatsScript.effective_max_hp(_db, run, &"fighter"), 34 + 2 * per_con,
		"race CON raises effective max"
	)


func test_allocated_con_adds_to_max() -> void:
	var run := _run()
	run.allocated_stats = {&"fighter": {&"con": 3}}
	var per_con: int = _db.get_battle_config().hp_per_con
	assert_eq(
		PartyStatsScript.effective_max_hp(_db, run, &"fighter"), 34 + 3 * per_con,
		"allocated CON raises effective max"
	)


func test_passive_relic_adds_to_max() -> void:
	var run := _run()
	run.relics = [&"vital_idol"] as Array[StringName]  # passive max_hp_up +6
	assert_eq(
		PartyStatsScript.effective_max_hp(_db, run, &"fighter"), 34 + 6,
		"a passive max_hp_up relic raises effective max"
	)


func test_bonuses_stack() -> void:
	var run := _run()
	run.party_races = {&"fighter": &"orc"}
	run.allocated_stats = {&"fighter": {&"con": 1}}
	run.relics = [&"vital_idol"] as Array[StringName]
	var per_con: int = _db.get_battle_config().hp_per_con
	assert_eq(
		PartyStatsScript.effective_max_hp(_db, run, &"fighter"),
		34 + (2 * per_con) + (1 * per_con) + 6,
		"race + allocated + relic bonuses all stack"
	)


func test_unknown_character_is_zero() -> void:
	assert_eq(PartyStatsScript.effective_max_hp(_db, _run(), &"ghost"), 0, "unknown id -> 0")
