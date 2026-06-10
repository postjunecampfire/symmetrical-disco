extends GutTest
## GUT tests for CardReward — card-reward draft + card pool (P2·06,
## run-structure.md §6).
##
## Everything is built in code (no JSON): CardData are hand-made and collected
## into a plain Dictionary registry (card_id -> CardData), and a RunState carries
## just the `party` the draft filters against. Tests assert the eligible-pool
## rules (party tag or neutral, never innate), N-distinct seeded drafts,
## determinism (same seed -> same offer), pick/skip effects on skill collections (ADR-0026), and the
## small-pool degradation (fewer than N eligible -> as many as exist, no error).

# --- Fixture builders ---

func _make_card(
	id: StringName, tag: StringName, innate: bool, rarity: StringName
) -> CardData:
	var card := CardData.new()
	card.id = id
	card.display_name = String(id)
	card.character_tag = tag
	card.innate = innate
	card.rarity = rarity
	return card


## A registry spanning every eligibility case for a {knight, mage} party:
##   - innate neutrals (strike/defend)  -> excluded (innate)
##   - knight/mage tagged cards         -> eligible
##   - a neutral non-innate card        -> eligible
##   - a card tagged for a non-party id  -> excluded (off-party)
## Eligible set: shield_bash, power_strike, frost_nova, arcane_bolt,
## neutral_potion (5 cards).
func _make_registry() -> Dictionary:
	var cards: Array[CardData] = [
		_make_card(&"strike", &"neutral", true, &"common"),
		_make_card(&"defend", &"neutral", true, &"common"),
		_make_card(&"shield_bash", &"knight", false, &"common"),
		_make_card(&"power_strike", &"knight", false, &"rare"),
		_make_card(&"frost_nova", &"mage", false, &"uncommon"),
		_make_card(&"arcane_bolt", &"mage", false, &"common"),
		_make_card(&"neutral_potion", &"neutral", false, &"common"),
		_make_card(&"heal_wave", &"cleric", false, &"common"),
	]
	var registry: Dictionary = {}
	for c: CardData in cards:
		registry[c.id] = c
	return registry


func _make_run() -> RunState:
	var state := RunState.new()
	state.seed = 4242
	state.party = [&"knight", &"mage"] as Array[StringName]
	return state


## Ids of an offer, in order, for compact comparison.
func _ids(offer: Array[CardData]) -> Array[StringName]:
	var out: Array[StringName] = []
	for c: CardData in offer:
		out.append(c.id)
	return out


# --- Eligibility ---

func test_eligible_pool_excludes_innate_and_off_party() -> void:
	var reward := CardReward.new(_make_registry())
	var pool: Array[CardData] = reward.eligible_pool(_make_run())

	var ids: Array[StringName] = _ids(pool)
	assert_eq(pool.size(), 5, "five cards are eligible for a knight+mage party")
	assert_does_not_have(ids, &"strike", "innate strike is excluded")
	assert_does_not_have(ids, &"defend", "innate defend is excluded")
	assert_does_not_have(ids, &"heal_wave", "off-party (cleric) card is excluded")
	assert_has(ids, &"shield_bash", "knight card is eligible")
	assert_has(ids, &"frost_nova", "mage card is eligible")
	assert_has(ids, &"neutral_potion", "neutral non-innate card is eligible")


func test_every_drafted_option_is_eligible() -> void:
	var reward := CardReward.new(_make_registry())
	var run: RunState = _make_run()
	var offer: Array[CardData] = reward.draft(run, 3, run.seed)

	for card: CardData in offer:
		assert_false(card.innate, "no innate card is ever offered: %s" % card.id)
		var on_party: bool = (
			card.character_tag == CardReward.NEUTRAL_TAG
			or run.party.has(card.character_tag)
		)
		assert_true(on_party, "offered card is party-tagged or neutral: %s" % card.id)


# --- Draft shape ---

func test_draft_returns_n_distinct_options() -> void:
	var reward := CardReward.new(_make_registry())
	var run: RunState = _make_run()
	var offer: Array[CardData] = reward.draft(run, 3, run.seed)

	assert_eq(offer.size(), 3, "draft returns exactly N options")

	var seen: Dictionary = {}
	for card: CardData in offer:
		assert_false(seen.has(card.id), "no duplicate within an offer: %s" % card.id)
		seen[card.id] = true
	assert_eq(seen.size(), 3, "all three options are distinct")


func test_default_choice_count_is_three() -> void:
	var reward := CardReward.new(_make_registry())
	var run: RunState = _make_run()
	var offer: Array[CardData] = reward.draft(run)
	assert_eq(offer.size(), 3, "N defaults to 3")


# --- Determinism ---

func test_same_seed_produces_same_offer() -> void:
	var reward := CardReward.new(_make_registry())
	var run: RunState = _make_run()

	var a: Array[CardData] = reward.draft(run, 3, 12345)
	var b: Array[CardData] = reward.draft(run, 3, 12345)
	assert_eq(_ids(a), _ids(b), "same seed -> identical offer (ids and order)")


func test_rarity_weighted_draft_is_deterministic() -> void:
	var weights: Dictionary = {&"common": 1.0, &"uncommon": 2.0, &"rare": 3.0}
	var reward := CardReward.new(_make_registry(), weights)
	var run: RunState = _make_run()

	var a: Array[CardData] = reward.draft(run, 3, 777)
	var b: Array[CardData] = reward.draft(run, 3, 777)
	assert_eq(_ids(a), _ids(b), "weighted draft is reproducible for a fixed seed")
	assert_eq(a.size(), 3, "weighted draft still returns N distinct options")


# --- Pick / skip ---

func test_pick_appends_exactly_one_id() -> void:
	var reward := CardReward.new(_make_registry())
	var run: RunState = _make_run()
	run.skill_collections = {&"fighter": ["shield_bash"], &"mage": []}
	run.active_loadouts = {&"fighter": ["shield_bash"], &"mage": []}

	var appended: bool = reward.pick(run, &"frost_nova")
	assert_true(appended, "pick reports success")
	# frost_nova is mage-tagged -> it joins the MAGE's collection (ADR-0026).
	var mage_coll: Array = run.skill_collections[&"mage"]
	assert_eq(mage_coll.size(), 1, "exactly one skill was granted")
	assert_eq(StringName(String(mage_coll[0])), &"frost_nova", "the picked skill joins its owner's collection")


func test_skip_leaves_collections_unchanged() -> void:
	var reward := CardReward.new(_make_registry())
	var run: RunState = _make_run()
	run.skill_collections = {&"fighter": ["shield_bash"], &"mage": []}
	run.active_loadouts = {&"fighter": ["shield_bash"], &"mage": []}

	reward.skip(run)
	assert_eq(
		run.skill_collections[&"fighter"],
		["shield_bash"],
		"skip adds nothing to the run deck"
	)


# --- Small-pool degradation ---

func test_pool_smaller_than_n_returns_what_exists() -> void:
	# Only two cards are eligible for a lone-knight party (knight + neutral);
	# the mage/cleric cards drop out.
	var reward := CardReward.new(_make_registry())
	var run: RunState = _make_run()
	run.party = [&"knight"] as Array[StringName]

	var offer: Array[CardData] = reward.draft(run, 5, run.seed)
	assert_eq(offer.size(), 3, "returns all eligible (shield_bash, power_strike, neutral_potion)")

	var seen: Dictionary = {}
	for card: CardData in offer:
		seen[card.id] = true
	assert_eq(seen.size(), 3, "the returned options are still distinct, no error")


func test_empty_pool_returns_empty_offer() -> void:
	var reward := CardReward.new({})
	var run: RunState = _make_run()
	var offer: Array[CardData] = reward.draft(run, 3, run.seed)
	assert_eq(offer.size(), 0, "an empty registry yields an empty offer without error")


# --- min_act crossover gate (ADR-0020 / M3 pool hygiene) ---------------------

func test_min_act_gates_card_out_of_early_pools() -> void:
	var registry: Dictionary = _make_registry()
	var gated: CardData = _make_card(&"big_multiplier", &"knight", false, &"rare")
	gated.min_act = 10
	registry[gated.id] = gated
	var reward := CardReward.new(registry)
	var run: RunState = _make_run()

	run.act = 1
	assert_does_not_have(
		_ids(reward.eligible_pool(run)), &"big_multiplier",
		"a min_act 10 card is not draftable at act 1"
	)
	run.act = 9
	assert_does_not_have(
		_ids(reward.eligible_pool(run)), &"big_multiplier",
		"…nor at act 9 (gate is inclusive of its act)"
	)
	run.act = 10
	assert_has(
		_ids(reward.eligible_pool(run)), &"big_multiplier",
		"the card unlocks exactly at its min_act"
	)
	run.act = 18
	assert_has(
		_ids(reward.eligible_pool(run)), &"big_multiplier",
		"…and stays draftable below it"
	)


func test_min_act_zero_is_ungated() -> void:
	var reward := CardReward.new(_make_registry())
	var run: RunState = _make_run()
	run.act = 1
	# Every fixture card has the default min_act 0 -> the act-1 pool is intact.
	assert_eq(reward.eligible_pool(run).size(), 5, "min_act 0 cards draft from act 1")
