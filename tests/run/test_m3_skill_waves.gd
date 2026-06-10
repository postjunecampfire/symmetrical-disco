extends GutTest
## M3 content pass: skill waves 1-3 (fighter/rogue/mage), race-flavored
## basics + neutral commons, and tree-signature unlock_cards.
##
## Conventions under test:
##   - New wave cards are ordinary draftable skills (valid rarity, cost 0-3,
##     correct character_tag, no `return` on owned damage cards per ADR-0017 —
##     the loader's reference validation enforces the ban, so a clean load is
##     part of the contract).
##   - `"signature": true` cards are EXCLUDED from the draft/shop pools
##     (CardReward.eligible_pool — same mechanism as _plus upgrade variants).
##   - Every progression node carries `unlock_cards` (1-2 signature skills,
##     id convention `sig_<node_id>`); RunController.apply_progression grants
##     them into the member's collection at the pick (ADR-0026 seam).

const RunControllerScript := preload("res://src/run/run_controller.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")

const WAVE_FIGHTER: Array[StringName] = [
	&"crushing_blow", &"rending_slash", &"iron_guard", &"bodyguard",
	&"reckless_swing", &"blood_price", &"shield_slam", &"intimidating_roar",
	&"press_the_attack", &"carve", &"hemorrhage", &"bulwark_charge",
	&"blood_frenzy", &"guardians_oath", &"battering_ram", &"war_banner",
	&"open_wounds", &"mortal_strike", &"crimson_harvest", &"berserkers_gambit",
]
const WAVE_ROGUE: Array[StringName] = [
	&"flicker_strike", &"twin_daggers", &"hunters_mark", &"hamstring",
	&"evasive_roll", &"poison_tip", &"low_blow", &"slip_away", &"opportunist",
	&"surgical_strike", &"flurry_of_blades", &"toxin_smear", &"shadow_feint",
	&"marked_prey", &"trick_blade", &"nimble_escape", &"pickpockets_luck",
	&"death_from_shadow", &"perforate", &"virulent_dose",
]
const WAVE_MAGE: Array[StringName] = [
	&"ember_bolt", &"kindle", &"frost_lance", &"mind_spike", &"arcane_ward",
	&"enfeeble", &"chill_touch", &"scorch", &"spark_volley", &"immolate",
	&"piercing_ray", &"stupefy", &"flash_freeze", &"arcane_intellect",
	&"searing_brand", &"overcharge", &"combust", &"disintegrate", &"pyre",
	&"temporal_lock",
]
const WAVE_NEUTRAL: Array[StringName] = [
	&"savage_chop", &"battle_roar", &"fleet_footwork", &"keen_eyes",
	&"steady_advance", &"quick_thinking", &"rock_throw", &"bandage",
	&"brace_up", &"focused_blow",
]
const VALID_RARITIES: Array[StringName] = [&"common", &"uncommon", &"rare"]
const LINES: Array[StringName] = [&"fighter", &"rogue", &"mage", &"brawler", &"charmer"]

var _db: ContentDatabase
var _result: ContentDatabase.LoadResult


func before_all() -> void:
	_db = ContentDatabaseScript.new()
	_result = _db.load_from_dir("res://data")


func test_full_data_loads_clean() -> void:
	# Covers the loader-side schema contract for every new card: character_tag
	# resolves, statuses (burn/bleed/mark/...) resolve, unlock_cards resolve,
	# and the ADR-0017 `return`-on-owned-damage ban holds.
	assert_true(_result.ok, "data loads with no errors: %s" % str(_result.errors))


func _assert_wave(ids: Array[StringName], tag: StringName) -> void:
	for id in ids:
		var card: CardData = _db.get_card(id)
		assert_not_null(card, "wave card '%s' exists" % id)
		if card == null:
			continue
		assert_eq(card.character_tag, tag, "'%s' tagged %s" % [id, tag])
		assert_has(VALID_RARITIES, card.rarity, "'%s' has a valid rarity" % id)
		assert_between(card.energy_cost, 0, 3, "'%s' costs 0-3" % id)
		assert_ne(card.description, "", "'%s' has a description" % id)
		assert_false(card.signature, "wave card '%s' is draftable (not signature)" % id)
		assert_false(card.innate, "wave card '%s' is not innate" % id)
		assert_false(card.keywords.has(&"return"), "'%s' has no return keyword" % id)


func test_wave_1_fighter_cards_valid() -> void:
	_assert_wave(WAVE_FIGHTER, &"fighter")


func test_wave_2_rogue_cards_valid() -> void:
	_assert_wave(WAVE_ROGUE, &"rogue")


func test_wave_3_mage_cards_valid_and_no_new_aoe() -> void:
	_assert_wave(WAVE_MAGE, &"mage")
	# Standing rule: wave 3 authors NO new AoE damage at all.
	for id in WAVE_MAGE:
		var card: CardData = _db.get_card(id)
		if card == null or card.target == null:
			continue
		assert_ne(card.target.target_type, &"all_enemies", "'%s' is not AoE" % id)


func test_wave_4_neutral_race_basics_valid() -> void:
	_assert_wave(WAVE_NEUTRAL, &"neutral")


func test_every_progression_node_grants_signature_unlocks() -> void:
	for line in LINES:
		var tree: Dictionary = _db.progression_trees.get(line, {})
		assert_eq(tree.size(), 14, "line '%s' loaded" % line)
		for nid: Variant in tree:
			var node: Dictionary = tree[nid]
			var unlocks_v: Variant = node.get("unlock_cards", [])
			assert_true(unlocks_v is Array, "node '%s' has unlock_cards" % nid)
			var unlocks: Array = unlocks_v
			assert_between(unlocks.size(), 1, 2, "node '%s' grants 1-2 signatures" % nid)
			for u: Variant in unlocks:
				var card: CardData = _db.get_card(StringName(String(u)))
				assert_not_null(card, "unlock '%s' of node '%s' resolves" % [u, nid])
				if card == null:
					continue
				assert_true(card.signature, "unlock '%s' is signature-flagged" % u)
				assert_eq(card.character_tag, line, "unlock '%s' is tagged for its line" % u)
				assert_has(
					[&"uncommon", &"rare"] as Array[StringName], card.rarity,
					"signature '%s' is uncommon/rare (1-2 deck copies)" % u
				)


func test_signature_cards_excluded_from_draft_pool() -> void:
	var run := RunState.new()
	run.seed = 99
	run.party = [&"hero_1"] as Array[StringName]
	run.member_classes = {&"hero_1": &"fighter"}
	var reward := CardReward.new(_db)
	var pool: Array[CardData] = reward.eligible_pool(run)
	assert_gt(pool.size(), 0, "fighter pool is non-empty")
	var ids: Array[StringName] = []
	for card in pool:
		assert_false(card.signature, "'%s' in draft pool must not be signature" % card.id)
		ids.append(card.id)
	assert_has(ids, &"carve", "new fighter wave card is draftable")
	assert_has(ids, &"savage_chop", "neutral race basic is draftable")
	assert_does_not_have(ids, &"sig_brigand", "tree signature is NOT draftable")


func test_unlock_cards_granted_on_node_pick() -> void:
	var rc: RunController = RunControllerScript.new(_db)
	rc.start_run([&"hero_1"] as Array[StringName], 5, {&"hero_1": &"orc"})
	rc.choose_class(&"hero_1", &"fighter")
	rc.run.act = 6
	var options: Array[Dictionary] = rc.progression_options(&"hero_1")
	assert_eq(options.size(), 2, "archetype 1-of-2 offered")
	var picked := StringName(String(options[0].get("id")))
	assert_true(rc.apply_progression(&"hero_1", picked), "pick applies")
	var sig := StringName("sig_" + String(picked))
	assert_has(rc.collection_of(&"hero_1"), sig, "signature joins the collection")
	# Act 9: the specialization pick grants its signature too.
	rc.run.act = 9
	var spec: Array[Dictionary] = rc.progression_options(&"hero_1")
	var spec_pick := StringName(String(spec[0].get("id")))
	rc.apply_progression(&"hero_1", spec_pick)
	assert_has(
		rc.collection_of(&"hero_1"), StringName("sig_" + String(spec_pick)),
		"spec signature joins the collection"
	)
