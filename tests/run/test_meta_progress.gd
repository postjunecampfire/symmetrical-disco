extends "res://addons/gut/test.gd"
## GUT suite for cross-run meta (P3·08): MetaState persistence + MetaProgress
## cash-out gating, banking a chosen boon, and applying banked boons to a fresh run.

const MetaStateScript := preload("res://src/run/meta_state.gd")
const MetaProgressScript := preload("res://src/run/meta_progress.gd")
const RunStateScript := preload("res://src/run/run_state.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _threshold() -> int:
	return _db.get_battle_config().meta_cash_out_acts


# --- Persistence ------------------------------------------------------------

func test_meta_round_trips() -> void:
	const PATH := "user://test_meta.json"
	var m: MetaState = MetaStateScript.new()
	m.acts_cleared = 14
	m.boons = [&"boon_vigor", &"boon_heirloom_relic"] as Array[StringName]
	assert_true(m.save_to(PATH), "saved meta")
	var loaded: MetaState = MetaStateScript.load_from(PATH)
	assert_eq(loaded.acts_cleared, 14, "acts_cleared round-trips")
	assert_eq(loaded.boons.size(), 2, "boons round-trip")
	assert_true(loaded.boons.has(&"boon_vigor"), "boon id preserved")
	DirAccess.remove_absolute(PATH)


func test_missing_meta_loads_fresh() -> void:
	var loaded: MetaState = MetaStateScript.load_from("user://does_not_exist_meta.json")
	assert_not_null(loaded, "missing meta -> a fresh MetaState, never null")
	assert_eq(loaded.acts_cleared, 0, "fresh meta starts empty")


# --- Cash-out gating --------------------------------------------------------

func test_cash_out_unlocks_at_threshold_and_accrues() -> void:
	var m: MetaState = MetaStateScript.new()
	var mp: MetaProgress = MetaProgressScript.new(_db, m)
	var t: int = _threshold()
	m.acts_cleared = t - 1
	assert_false(mp.cash_out_available(), "no cash-out before the threshold")
	m.acts_cleared = t
	assert_true(mp.cash_out_available(), "first boon unlocks at the threshold")
	assert_true(mp.cash_out(&"boon_vigor"), "banked the chosen boon")
	assert_false(mp.cash_out_available(), "2nd boon needs 2x the threshold")
	m.acts_cleared = t * 2
	assert_true(mp.cash_out_available(), "2nd cash-out unlocks at 2x")


func test_cash_out_rejects_when_unavailable_or_unknown() -> void:
	var m: MetaState = MetaStateScript.new()
	var mp: MetaProgress = MetaProgressScript.new(_db, m)
	assert_false(mp.cash_out(&"boon_vigor"), "no cash-out available yet")
	m.acts_cleared = _threshold()
	assert_false(mp.cash_out(&"no_such_boon"), "unknown boon rejected")
	assert_eq(m.boons.size(), 0, "nothing banked on rejection")


# --- Applying boons to a fresh run ------------------------------------------

func _fresh_run() -> RunState:
	var run := RunStateScript.new()
	run.party = [&"fighter", &"mage"] as Array[StringName]
	return run


func test_apply_relic_and_card_boons() -> void:
	var m: MetaState = MetaStateScript.new()
	m.boons = [&"boon_heirloom_relic", &"boon_field_kit"] as Array[StringName]
	var run := _fresh_run()
	MetaProgressScript.new(_db, m).apply_boons(run)
	assert_true(run.relics.has(&"iron_brand"), "relic boon grants a starting relic")
	assert_true(run.run_deck.has(&"field_dressing"), "card boon adds a starting card")


func test_apply_stat_boon_to_every_member() -> void:
	var m: MetaState = MetaStateScript.new()
	m.boons = [&"boon_vigor"] as Array[StringName]  # +2 CON
	var run := _fresh_run()
	MetaProgressScript.new(_db, m).apply_boons(run)
	assert_eq(int(run.allocated_stats[&"fighter"][&"con"]), 2, "stat boon adds CON to each member")
	assert_eq(int(run.allocated_stats[&"mage"][&"con"]), 2, "…including the mage")
