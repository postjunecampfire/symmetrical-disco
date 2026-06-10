extends "res://addons/gut/test.gd"
## ADR-0024 (solo start + Act-2 recruit) and ADR-0021 pt2 (Act-3 class pick):
## member ids are stable handles, classless members fight off their race base
## with highest-stat attacks, the recruit arrives whole (kit + own pools), and
## the class pick applies the overlay + unlocks the class card pool.

const RunControllerScript := preload("res://src/run/run_controller.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _solo() -> RunController:
	var rc := RunControllerScript.new(_db)
	rc.start_run([&"hero_1"] as Array[StringName], 11, {&"hero_1": &"orc"})
	return rc


func test_solo_start_is_classless_with_race_base() -> void:
	var rc := _solo()
	assert_eq(rc.run.party.size(), 1, "Act 1 is solo (ADR-0024)")
	assert_true(rc.is_classless(&"hero_1"), "the origin member has no class")
	var ch: CharacterData = PartyMember.character_for(_db, rc.run, &"hero_1")
	assert_eq(ch.attack_stat, &"highest", "pre-class attacks use the highest stat")
	# Race kit + custom card seed the collection (no class kit yet).
	var coll: Array = rc.run.skill_collections[&"hero_1"]
	assert_true(coll.has(&"orcish_rage"), "race custom card in the collection")
	assert_gt(coll.size(), 1, "the origin kit is present")


func test_classless_member_fights_with_race_stats() -> void:
	var rc := _solo()
	var battle: EncounterBattle = rc.begin_combat(&"enc_t1_rats", &"trash")
	assert_eq(battle.living_players().size(), 1, "solo fight")
	var hero: Combatant = battle.living_players()[0]
	assert_eq(hero.strength, 5, "Orc base STR 5 (no class overlay)")
	assert_eq(hero.attack_power(), 5, "highest-stat rule picks STR for an Orc")
	assert_gte(battle.deck_of(hero).total_in_cycle(), _db.get_battle_config().derived_deck_floor, "own derived deck")


func test_recruit_offer_is_three_distinct_and_deterministic() -> void:
	var rc := _solo()
	var a: Array[StringName] = rc.recruit_offer()
	var b: Array[StringName] = rc.recruit_offer()
	assert_eq(a, b, "same run seed -> same offer (resume-safe)")
	assert_eq(a.size(), mini(3, _db.races.size()), "three candidates (or all races if fewer)")
	for i in range(a.size()):
		for j in range(i + 1, a.size()):
			assert_ne(a[i], a[j], "candidates are distinct")


func test_recruit_joins_whole() -> void:
	var rc := _solo()
	var cid: StringName = rc.recruit(&"elf")
	assert_eq(cid, &"hero_2", "the recruit takes the second stable slot")
	assert_eq(rc.run.party.size(), 2, "party of 2 from Act 2 (ADR-0016 cap)")
	assert_true(rc.is_classless(cid), "the recruit arrives classless, like the origin")
	assert_true((rc.run.skill_collections[cid] as Array).has(&"elven_focus"), "recruit kit includes the race custom card")
	assert_gt(int(rc.run.party_hp[cid]), 0, "recruit arrives at full HP")
	assert_eq(rc.recruit(&"human"), &"", "no third recruit — the party caps at 2")


func test_class_pick_applies_overlay_and_unlocks_pool() -> void:
	var rc := _solo()
	rc.recruit(&"elf")
	# Pre-class: class-tagged cards are NOT draftable (pool gating, pt2).
	var reward := CardReward.new(_db, {})
	for card in reward.eligible_pool(rc.run):
		assert_eq(card.character_tag, &"neutral", "origin-tier drafts are neutral-only")

	assert_true(rc.choose_class(&"hero_1", &"fighter"), "origin picks Fighter")
	assert_true(rc.choose_class(&"hero_2", &"mage"), "recruit picks Mage")
	assert_false(rc.choose_class(&"hero_1", &"rogue"), "a class pick is final")

	var ch: CharacterData = PartyMember.character_for(_db, rc.run, &"hero_1")
	assert_eq(ch.attack_stat, &"str", "the pick locks attack_stat")
	assert_eq(ch.strength, _db.get_character(&"fighter").strength, "class overlay applied")
	assert_true((rc.run.skill_collections[&"hero_1"] as Array).has(&"shield_bash"), "class kit granted as skills")

	# Post-pick: the chosen classes' tagged cards join the draft pool.
	var tags: Dictionary = {}
	for card in reward.eligible_pool(rc.run):
		tags[card.character_tag] = true
	assert_true(tags.has(&"fighter") and tags.has(&"mage"), "class pools unlocked by the pick")
	assert_false(tags.has(&"rogue"), "unpicked class pools stay locked")


func test_mixed_race_pair_is_balanced_per_member() -> void:
	var rc := _solo()
	rc.recruit(&"elf")
	var orc_hp: int = PartyStats.effective_max_hp(_db, rc.run, &"hero_1")
	var elf_hp: int = PartyStats.effective_max_hp(_db, rc.run, &"hero_2")
	assert_gt(orc_hp, elf_hp, "heterogeneous pair: Orc (CON 4) outlasts Elf (CON 2)")
