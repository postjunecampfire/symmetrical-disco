extends "res://addons/gut/test.gd"
## SkillLoadout (ADR-0026): the deterministic projection of an active skill
## loadout into a derived deck — copies by rarity (3/2/1), alternating
## Strike/Defend auto-fill to the 20-card floor — plus the collection ops
## (acquire with slot cap, upgrade-in-place, remove-one-copy).

const ContentDatabaseScript := preload("res://src/data/content_database.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _cfg() -> BattleConfig:
	return _db.get_battle_config()


func test_copies_follow_rarity() -> void:
	# shield_bash is common (3), mana_surge uncommon (2), berserker_rampage rare (1).
	var loadout: Array[StringName] = [&"shield_bash", &"mana_surge", &"berserker_rampage"]
	var deck := SkillLoadout.derive_deck(loadout, _db)
	assert_eq(deck.count(&"shield_bash"), _cfg().copies_common, "common -> 3 copies")
	assert_eq(deck.count(&"mana_surge"), _cfg().copies_uncommon, "uncommon -> 2 copies")
	assert_eq(deck.count(&"berserker_rampage"), _cfg().copies_rare, "rare -> 1 copy (the ADR-0020 guardrail)")


func test_autofill_pads_to_the_floor_alternating_basics() -> void:
	var deck := SkillLoadout.derive_deck([&"berserker_rampage"] as Array[StringName], _db)
	assert_eq(deck.size(), _cfg().derived_deck_floor, "short loadouts pad to the floor")
	assert_eq(deck.count(&"strike") + deck.count(&"defend") + 1, deck.size(), "padding is all basics")
	# Alternating 1:1 (tunable): counts differ by at most one.
	assert_lte(absi(deck.count(&"strike") - deck.count(&"defend")), 1, "Strike:Defend fill is ~1:1")


func test_full_common_loadout_needs_no_fill() -> void:
	var loadout: Array[StringName] = []
	for _i in range(7):
		loadout.append(&"shield_bash")  # 7 commons × 3 = 21 ≥ floor
	var deck := SkillLoadout.derive_deck(loadout, _db)
	assert_eq(deck.size(), 21, "no padding above the floor")
	assert_eq(deck.count(&"defend"), 0, "no auto-fill when the floor is met")


func test_unknown_skill_ids_are_skipped() -> void:
	var deck := SkillLoadout.derive_deck([&"no_such_skill"] as Array[StringName], _db)
	assert_eq(deck.size(), _cfg().derived_deck_floor, "unknown ids contribute nothing; floor still holds")


func test_acquire_respects_slot_cap() -> void:
	var collection: Array[StringName] = []
	var loadout: Array[StringName] = []
	for i in range(_cfg().skill_slots + 3):
		SkillLoadout.acquire(collection, loadout, &"quick_stab", _cfg())
	assert_eq(collection.size(), _cfg().skill_slots + 3, "every acquisition joins the collection")
	assert_eq(loadout.size(), _cfg().skill_slots, "the loadout caps at skill_slots")


func test_replace_skill_upgrades_collection_and_loadout() -> void:
	var collection: Array[StringName] = [&"shield_bash", &"quick_stab"]
	var loadout: Array[StringName] = [&"shield_bash"]
	var n := SkillLoadout.replace_skill(collection, loadout, &"shield_bash", &"shield_bash_plus")
	assert_eq(n, 1, "one collection entry swapped")
	assert_true(collection.has(&"shield_bash_plus") and loadout.has(&"shield_bash_plus"), "both views upgraded")


func test_remove_skill_takes_one_copy() -> void:
	var collection: Array[StringName] = [&"quick_stab", &"quick_stab"]
	var loadout: Array[StringName] = [&"quick_stab"]
	assert_true(SkillLoadout.remove_skill(collection, loadout, &"quick_stab"), "a copy was removed")
	assert_eq(collection.size(), 1, "only one collection copy removed")
	assert_false(SkillLoadout.remove_skill(collection, loadout, &"no_such"), "absent skill -> false")
