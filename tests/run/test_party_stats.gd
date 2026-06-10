extends "res://addons/gut/test.gd"
## GUT suite for PartyStats.effective_max_hp (review fix #1): the single source of
## truth for a member's max HP — class overlay + race base CON (ADR-0021 pt1) + allocated CON + passive
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


func _class_base() -> int:
	# ADR-0021 pt1: the class layer is a small overlay; its max_hp (base_hp +
	# class CON * hp_per_con) is read from data so balance edits don't break this.
	return _db.get_character(&"fighter").max_hp


func test_base_is_class_overlay_max() -> void:
	var cfg: BattleConfig = _db.get_battle_config()
	assert_eq(
		PartyStatsScript.effective_max_hp(_db, _run(), &"fighter"),
		cfg.base_hp + _db.get_character(&"fighter").constitution * cfg.hp_per_con,
		"fighter base max = base_hp + class CON * hp_per_con"
	)


func test_race_con_adds_to_max() -> void:
	var run := _run()
	run.party_races = {&"fighter": &"orc"}  # Orc base CON 4 (ADR-0021 pt1)
	var per_con: int = _db.get_battle_config().hp_per_con
	assert_eq(
		PartyStatsScript.effective_max_hp(_db, run, &"fighter"), _class_base() + 4 * per_con,
		"race CON raises effective max"
	)


func test_allocated_con_adds_to_max() -> void:
	var run := _run()
	run.allocated_stats = {&"fighter": {&"con": 3}}
	var per_con: int = _db.get_battle_config().hp_per_con
	assert_eq(
		PartyStatsScript.effective_max_hp(_db, run, &"fighter"), _class_base() + 3 * per_con,
		"allocated CON raises effective max"
	)


func test_passive_relic_adds_to_max() -> void:
	var run := _run()
	run.relics = [&"vital_idol"] as Array[StringName]  # passive max_hp_up +6
	assert_eq(
		PartyStatsScript.effective_max_hp(_db, run, &"fighter"), _class_base() + 6,
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
		_class_base() + (4 * per_con) + (1 * per_con) + 6,
		"race + allocated + relic bonuses all stack"
	)


func test_unknown_character_is_zero() -> void:
	assert_eq(PartyStatsScript.effective_max_hp(_db, _run(), &"ghost"), 0, "unknown id -> 0")
