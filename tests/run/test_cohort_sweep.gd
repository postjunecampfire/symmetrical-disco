extends "res://addons/gut/test.gd"
## M3 exit-gate harness pin (tools/cohort_lib.gd + tools/cohort_sweep.gd):
## cohort construction must grant the race kit, the act-3 class pick, the act-6
## archetype node (stats + signature), the seeded K-drafts and the pre-levels
## through the REAL RunController seams — and run_cell must smoke
## deterministically. Pins the API so the sweep harness can't rot.

const CohortLibScript := preload("res://tools/cohort_lib.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _lib(k: float = 1.3) -> RefCounted:
	return CohortLibScript.new(_db, k)


func test_act6_cohort_is_classed_with_archetype_and_signature() -> void:
	var rc: RunController = _lib().build_controller(&"human", &"fighter", &"brigand", 6, 0, "greedy")
	for cid in rc.run.party:
		assert_eq(PartyMember.class_of(rc.run, cid), &"fighter", "class pick applied to %s" % cid)
		var walk: Array = rc.run.member_progression.get(cid, [])
		assert_eq(walk, ["brigand"], "act-6 archetype walked (depth 1) for %s" % cid)
		assert_has(rc.collection_of(cid), &"sig_brigand", "archetype signature granted to %s" % cid)
		assert_between(rc.loadout_of(cid).size(), 1, _db.get_battle_config().skill_slots, "curated loadout within slots")
		assert_eq(int(rc.run.party_hp[cid]), PartyStats.effective_max_hp(_db, rc.run, cid), "enters the act at effective max HP")


func test_draft_emulation_grants_k_per_act_and_respects_min_act() -> void:
	# K dial: with drafts_per_act 0 the party is kit-only; with 1.3 the party
	# carries roundi(1.3 * acts_cleared) extra skills, granted via CardReward.
	var kit_only: RunController = _lib(0.0).build_controller(&"human", &"fighter", &"brigand", 6, 0, "greedy")
	var drafted: RunController = _lib(1.3).build_controller(&"human", &"fighter", &"brigand", 6, 0, "greedy")
	var expected: int = roundi(1.3 * 5)  # acts 1..5 cleared entering act 6
	assert_eq(drafted.total_skills() - kit_only.total_skills(), expected, "K = acts_cleared x 1.3 drafts granted")
	for cid in drafted.run.party:
		for skill_id in drafted.collection_of(cid):
			var card: CardData = _db.get_card(skill_id)
			assert_not_null(card, "every granted skill resolves")
			assert_true(card.min_act <= 6, "%s drafted within its min_act gate" % skill_id)


func test_prelevel_allocates_policy_stats_on_top_of_node_bonus() -> void:
	# Entering act 6: 15 level points (3 x 5 acts) + brigand's stat_bonus (2 STR
	# + 1 CON) all land in allocated_stats via the normal seams.
	var rc: RunController = _lib(0.0).build_controller(&"human", &"fighter", &"brigand", 6, 0, "greedy")
	var alloc: Dictionary = rc.run.allocated_stats.get(&"hero_1", {})
	var total: int = 0
	for stat: Variant in alloc:
		total += int(alloc[stat])
	assert_eq(total, 15 + 3, "level points + archetype stat_bonus")
	assert_gt(int(alloc.get(&"str", 0)), int(alloc.get(&"con", 0)), "greedy pre-levels the attack stat")


func test_build_is_deterministic_per_seed() -> void:
	var a: RunController = _lib().build_controller(&"elf", &"mage", &"sorcerer", 9, 4, "defensive")
	var b: RunController = _lib().build_controller(&"elf", &"mage", &"sorcerer", 9, 4, "defensive")
	for cid in a.run.party:
		assert_eq(a.collection_of(cid), b.collection_of(cid), "same seed -> same collection for %s" % cid)
		assert_eq(a.loadout_of(cid), b.loadout_of(cid), "same seed -> same loadout for %s" % cid)
	assert_eq(a.run.member_progression, b.run.member_progression, "same seed -> same tree walk")


func test_invalid_cohort_is_refused_loudly() -> void:
	# A typo'd line must not run a silently-classless party (it would poison the
	# spread read). validate_cohort gates build_controller AND run_cell.
	var lib: RefCounted = _lib()
	assert_true(lib.validate_cohort(&"cat", &"charmer", &"evoker"), "valid triple accepted")
	assert_false(lib.validate_cohort(&"gnome", &"fighter", &"brigand"), "unknown race refused")
	assert_false(lib.validate_cohort(&"human", &"fighterr", &"brigand"), "unknown line refused")
	assert_false(lib.validate_cohort(&"human", &"fighter", &"warrior"), "act-9 spec is not an archetype")
	assert_null(lib.build_controller(&"human", &"fighterr", &"brigand", 6, 0, "greedy"))
	assert_eq(lib.run_cell(&"human", &"fighter", &"wrong_arch", 1, 1, "greedy"), {}, "invalid cell is empty")


func test_run_cell_smokes_at_act_1_with_two_seeds() -> void:
	var lib: RefCounted = _lib()
	assert_eq(lib.act_ladder(1).size(), 6, "ladder is 4 combats + elite + boss")
	var cell: Dictionary = lib.run_cell(&"human", &"fighter", &"brigand", 1, 2, "defensive")
	assert_eq(cell["seeds"], 2, "records N")
	assert_eq(cell["act"], 1)
	assert_eq(cell["policy"], "defensive")
	assert_between(int(cell["wins"]), 0, 2, "wins within seed count")
	assert_between(float(cell["win_rate"]), 0.0, 1.0)
	assert_between(float(cell["avg_cleared"]), 0.0, 6.0)
	var again: Dictionary = lib.run_cell(&"human", &"fighter", &"brigand", 1, 2, "defensive")
	assert_eq(cell, again, "cells are deterministic per seed set")
