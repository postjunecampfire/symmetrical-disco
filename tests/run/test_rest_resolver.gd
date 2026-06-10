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
	run.skill_collections = {&"fighter": [], &"mage": []}
	run.active_loadouts = {&"fighter": [], &"mage": []}
	return run


# --- heal -------------------------------------------------------------------

func test_heal_restores_living_members_by_config_amount() -> void:
	# Expectations derive from data AND respect each member's max-HP cap (ADR-0021
	# pt1: class-only maxes are small — fighter 6, mage 4 at current data), so
	# balance edits can't break this structural test.
	var amount: int = _db.get_battle_config().rest_heal
	var fmax: int = PartyStats.effective_max_hp(_db, _run(), &"fighter")
	var mmax: int = PartyStats.effective_max_hp(_db, _run(), &"mage")
	var run := _run(2, 1)
	_resolver().heal(run)
	assert_eq(int(run.party_hp[&"fighter"]), mini(2 + amount, fmax), "fighter healed by rest_heal (capped)")
	assert_eq(int(run.party_hp[&"mage"]), mini(1 + amount, mmax), "mage healed by rest_heal (capped)")
	assert_gt(int(run.party_hp[&"fighter"]), 2, "fighter actually healed")
	assert_gt(int(run.party_hp[&"mage"]), 1, "mage actually healed")


func test_heal_caps_at_base_max_and_skips_downed() -> void:
	var fmax: int = PartyStats.effective_max_hp(_db, _run(), &"fighter")
	var run := _run(fmax - 1, 0)  # fighter near full, mage downed
	_resolver().heal(run)
	assert_eq(int(run.party_hp[&"fighter"]), fmax, "fighter capped at base max")
	assert_eq(int(run.party_hp[&"mage"]), 0, "a downed member is not healed by a rest")


# --- upgrade ----------------------------------------------------------------

func test_upgrade_replaces_base_card_with_its_variant() -> void:
	var run := _run()
	run.skill_collections[&"fighter"] = ["shield_bash", "quick_stab"]
	run.active_loadouts[&"fighter"] = ["shield_bash"]
	var ok: bool = _resolver().upgrade_card(run, &"shield_bash")
	assert_true(ok, "an upgrade variant exists for shield_bash")
	var coll: Array = run.skill_collections[&"fighter"]
	assert_eq(StringName(String(coll[0])), &"shield_bash_plus", "the skill became its upgrade in place (ADR-0026)")
	assert_eq(StringName(String(coll[1])), &"quick_stab", "other skills are untouched")
	var loadout: Array = run.active_loadouts[&"fighter"]
	assert_eq(StringName(String(loadout[0])), &"shield_bash_plus", "the active loadout follows the upgrade")


func test_upgrade_replaces_only_one_copy() -> void:
	var run := _run()
	run.skill_collections[&"fighter"] = ["shield_bash", "shield_bash"]
	_resolver().upgrade_card(run, &"shield_bash")
	var coll: Array = run.skill_collections[&"fighter"]
	assert_eq(StringName(String(coll[0])), &"shield_bash_plus", "first skill entry upgraded")
	assert_eq(StringName(String(coll[1])), &"shield_bash", "the second collection entry stays base (one upgrade per rest)")


func test_upgrade_absent_base_is_noop() -> void:
	var run := _run()
	run.skill_collections[&"fighter"] = ["quick_stab"]
	assert_false(_resolver().upgrade_card(run, &"shield_bash"), "skill not owned -> no upgrade")
	assert_eq(run.skill_collections[&"fighter"], ["quick_stab"], "collection unchanged")


func test_upgrade_without_a_variant_is_noop() -> void:
	# A card with no authored upgrade variant cannot be rest-upgraded. (The
	# auto-fill basics USED to be the example here; M3 gave them Strike+/Defend+
	# for the upgrade_basics relic — they still never enter collections, so
	# rest-upgrade can't reach them in real play.)
	var run := _run()
	run.skill_collections[&"fighter"] = ["bandage"]
	assert_false(_resolver().upgrade_card(run, &"bandage"), "no variant -> false")
	assert_eq(run.skill_collections[&"fighter"], ["bandage"], "collection unchanged when no upgrade exists")


# --- registry lookup --------------------------------------------------------

func test_get_upgrade_for_finds_the_variant() -> void:
	var up: CardData = _db.get_upgrade_for(&"shield_bash")
	assert_not_null(up, "shield_bash has an upgrade variant")
	assert_eq(up.id, &"shield_bash_plus", "the variant is shield_bash_plus")
	# M3: the basics gained Strike+/Defend+ for the upgrade_basics relic, so a
	# variant-less example must be a card that genuinely has none.
	assert_null(_db.get_upgrade_for(&"bandage"), "a card without a variant returns null")
	assert_eq(_db.get_upgrade_for(&"strike").id, &"strike_plus", "the basics now upgrade (M3 whistle relic)")
