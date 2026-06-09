extends "res://addons/gut/test.gd"
## GUT suite for the rest-node resolver (run-structure.md §5 / P2·07, ADR-0012):
## a rest restores HP (data-driven amount) OR upgrades a card in the run deck to
## its `upgrade_of` variant. Numbers come from the loaded BattleConfig/content.

const RestResolverScript := preload("res://src/run/rest_resolver.gd")
const RunStateScript := preload("res://src/run/run_state.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _resolver() -> RestResolver:
	return RestResolverScript.new(_db)


func _run(fighter_hp: int = 20, mage_hp: int = 20) -> RunState:
	var run := RunStateScript.new()
	run.party = [&"fighter", &"mage"] as Array[StringName]
	run.party_hp = {&"fighter": fighter_hp, &"mage": mage_hp}
	run.downed = [] as Array[StringName]
	run.run_deck = [] as Array[StringName]
	return run


# --- heal -------------------------------------------------------------------

func test_heal_restores_living_members_by_config_amount() -> void:
	# Expectations derive from data AND respect each member's max-HP cap, so
	# rest_heal balance changes can't break this structural test (fighter max 34,
	# mage max 24).
	var amount: int = _db.get_battle_config().rest_heal
	var run := _run(10, 12)
	_resolver().heal(run)
	assert_eq(int(run.party_hp[&"fighter"]), mini(10 + amount, 34), "fighter healed by rest_heal (capped)")
	assert_eq(int(run.party_hp[&"mage"]), mini(12 + amount, 24), "mage healed by rest_heal (capped)")
	assert_gt(int(run.party_hp[&"fighter"]), 10, "fighter actually healed")
	assert_gt(int(run.party_hp[&"mage"]), 12, "mage actually healed")


func test_heal_caps_at_base_max_and_skips_downed() -> void:
	var run := _run(33, 0)  # fighter near full, mage downed
	_resolver().heal(run)
	assert_eq(int(run.party_hp[&"fighter"]), 34, "fighter capped at base max (34)")
	assert_eq(int(run.party_hp[&"mage"]), 0, "a downed member is not healed by a rest")


# --- upgrade ----------------------------------------------------------------

func test_upgrade_replaces_base_card_with_its_variant() -> void:
	var run := _run()
	run.run_deck = [&"shield_bash", &"strike"] as Array[StringName]
	var ok: bool = _resolver().upgrade_card(run, &"shield_bash")
	assert_true(ok, "an upgrade variant exists for shield_bash")
	assert_eq(run.run_deck[0], &"shield_bash_plus", "the base card became its upgrade in place")
	assert_eq(run.run_deck[1], &"strike", "other cards are untouched")


func test_upgrade_replaces_only_one_copy() -> void:
	var run := _run()
	run.run_deck = [&"shield_bash", &"shield_bash"] as Array[StringName]
	_resolver().upgrade_card(run, &"shield_bash")
	assert_eq(run.run_deck[0], &"shield_bash_plus", "first copy upgraded")
	assert_eq(run.run_deck[1], &"shield_bash", "the second copy is left as the base")


func test_upgrade_absent_base_is_noop() -> void:
	var run := _run()
	run.run_deck = [&"strike"] as Array[StringName]
	assert_false(_resolver().upgrade_card(run, &"shield_bash"), "base not in deck -> no upgrade")
	assert_eq(run.run_deck, [&"strike"] as Array[StringName], "deck unchanged")


func test_upgrade_without_a_variant_is_noop() -> void:
	# venom_dart has no upgrade variant authored; upgrading it does nothing.
	var run := _run()
	run.run_deck = [&"venom_dart"] as Array[StringName]
	assert_false(_resolver().upgrade_card(run, &"venom_dart"), "no variant -> false")
	assert_eq(run.run_deck[0], &"venom_dart", "deck unchanged when no upgrade exists")


# --- registry lookup --------------------------------------------------------

func test_get_upgrade_for_finds_the_variant() -> void:
	var up: CardData = _db.get_upgrade_for(&"shield_bash")
	assert_not_null(up, "shield_bash has an upgrade variant")
	assert_eq(up.id, &"shield_bash_plus", "the variant is shield_bash_plus")
	assert_null(_db.get_upgrade_for(&"venom_dart"), "a card without a variant returns null")
