extends "res://addons/gut/test.gd"
## GUT suite for the event-node resolver (run-structure.md §6 / P2·08, ADR-0012):
## an event choice's typed outcomes (heal / damage_party / add_card / remove_card
## / add_relic / nothing) are applied to the RunState. HP caps come from the
## loaded content; everything else mutates the run in place.

const EventResolverScript := preload("res://src/run/event_resolver.gd")
const RunStateScript := preload("res://src/run/run_state.gd")
const EventChoiceScript := preload("res://src/data/event_choice.gd")
const EventOutcomeScript := preload("res://src/data/event_outcome.gd")
const EventDataScript := preload("res://src/data/event_data.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _resolver() -> EventResolver:
	return EventResolverScript.new(_db)


## A RunState with the two-member party at given HP.
func _run(fighter_hp: int = 20, mage_hp: int = 20) -> RunState:
	var run := RunStateScript.new()
	run.party = [&"fighter", &"mage"] as Array[StringName]
	run.party_hp = {&"fighter": fighter_hp, &"mage": mage_hp}
	run.downed = [] as Array[StringName]
	run.skill_collections = {&"fighter": [], &"mage": []}
	run.active_loadouts = {&"fighter": [], &"mage": []}
	run.relics = [] as Array[StringName]
	return run


## A single outcome wrapped in a choice.
func _choice(kind: StringName, amount: int = 0, id: StringName = &"") -> EventChoice:
	var o := EventOutcomeScript.new()
	o.kind = kind
	o.amount = amount
	o.id = id
	var c := EventChoiceScript.new()
	c.outcomes = [o] as Array[EventOutcome]
	return c


# --- heal -------------------------------------------------------------------

func _fmax() -> int:
	return _db.get_character(&"fighter").max_hp


func _mmax() -> int:
	return _db.get_character(&"mage").max_hp


func test_heal_restores_living_members() -> void:
	# Start BELOW the (now small, ADR-0021 pt1) class maxes so the heal is visible.
	var run := _run(2, 1)
	_resolver().apply(run, _choice(&"heal", 2))
	assert_eq(int(run.party_hp[&"fighter"]), mini(2 + 2, _fmax()), "fighter healed by amount (capped)")
	assert_eq(int(run.party_hp[&"mage"]), mini(1 + 2, _mmax()), "mage healed by amount (capped)")


func test_heal_caps_at_base_max_hp() -> void:
	var run := _run(_fmax() - 1, _mmax() - 1)
	_resolver().apply(run, _choice(&"heal", 50))
	assert_eq(int(run.party_hp[&"fighter"]), _fmax(), "fighter capped at base max")
	assert_eq(int(run.party_hp[&"mage"]), _mmax(), "mage capped at base max")


func test_heal_skips_downed_member() -> void:
	var run := _run(10, 0)  # mage downed
	_resolver().apply(run, _choice(&"heal", 8))
	assert_eq(int(run.party_hp[&"mage"]), 0, "a downed member is not healed by an event heal")


# --- damage_party -----------------------------------------------------------

func test_damage_party_subtracts_hp() -> void:
	var run := _run(10, 12)
	_resolver().apply(run, _choice(&"damage_party", 4))
	assert_eq(int(run.party_hp[&"fighter"]), 6, "fighter took damage")
	assert_eq(int(run.party_hp[&"mage"]), 8, "mage took damage")


func test_damage_party_floors_at_zero_and_marks_downed() -> void:
	var run := _run(3, 12)
	_resolver().apply(run, _choice(&"damage_party", 5))
	assert_eq(int(run.party_hp[&"fighter"]), 0, "fighter floored at 0")
	assert_true(run.downed.has(&"fighter"), "a member reduced to 0 is downed")
	assert_false(run.downed.has(&"mage"), "a survivor is not downed")


# --- card / relic deltas ----------------------------------------------------

func test_add_card_grants_skill_to_first_member() -> void:
	var run := _run()
	_resolver().apply(run, _choice(&"add_card", 0, &"field_dressing"))
	assert_true((run.skill_collections[&"fighter"] as Array).has("field_dressing") or (run.skill_collections[&"fighter"] as Array).has(&"field_dressing"), "the skill joins the first member's collection (ADR-0026)")


func test_remove_card_removes_one_copy() -> void:
	var run := _run()
	run.skill_collections[&"fighter"] = ["quick_stab", "field_dressing", "field_dressing"]
	_resolver().apply(run, _choice(&"remove_card", 0, &"field_dressing"))
	var coll: Array = run.skill_collections[&"fighter"]
	assert_eq(coll.size(), 2, "exactly one copy removed")
	assert_true(coll.has("field_dressing"), "the second copy remains")
	assert_true(coll.has("quick_stab"), "unrelated skills untouched")


func test_remove_card_absent_is_noop() -> void:
	var run := _run()
	run.skill_collections[&"fighter"] = ["quick_stab"]
	_resolver().apply(run, _choice(&"remove_card", 0, &"field_dressing"))
	assert_eq((run.skill_collections[&"fighter"] as Array).size(), 1, "removing an absent skill changes nothing")


func test_add_relic_appends_to_relics() -> void:
	var run := _run()
	_resolver().apply(run, _choice(&"add_relic", 0, &"shrine_blessing"))
	assert_true(run.relics.has(&"shrine_blessing"), "the relic id is recorded")


func test_nothing_is_noop() -> void:
	var run := _run(10, 12)
	_resolver().apply(run, _choice(&"nothing"))
	assert_eq(int(run.party_hp[&"fighter"]), 10, "nothing leaves HP unchanged")
	assert_eq((run.skill_collections[&"fighter"] as Array).size(), 0, "nothing leaves the collections unchanged")


# --- multiple outcomes + choice index --------------------------------------

func test_apply_runs_all_outcomes_in_order() -> void:
	var dmg := _choice(&"damage_party", 5)
	# Append a second outcome (a relic) to the same choice.
	var relic := EventOutcomeScript.new()
	relic.kind = &"add_relic"
	relic.id = &"shrine_blessing"
	dmg.outcomes.append(relic)

	var run := _run(10, 12)
	_resolver().apply(run, dmg)
	assert_eq(int(run.party_hp[&"fighter"]), 5, "first outcome (damage) applied")
	assert_true(run.relics.has(&"shrine_blessing"), "second outcome (relic) applied")


func test_apply_choice_index_rejects_out_of_range() -> void:
	var ev := EventDataScript.new()
	ev.choices = [_choice(&"heal", 5)] as Array[EventChoice]
	var run := _run(10, 12)
	assert_false(_resolver().apply_choice_index(run, ev, 5), "out-of-range index rejected")
	assert_false(_resolver().apply_choice_index(run, null, 0), "null event rejected")
	assert_eq(int(run.party_hp[&"fighter"]), 10, "no outcome applied on rejection")


# --- authored content loads + resolves --------------------------------------

func test_authored_events_load_and_resolve() -> void:
	var medic: EventData = _db.get_event(&"evt_wandering_medic")
	assert_not_null(medic, "authored event loads from data/events")
	assert_eq(medic.choices.size(), 3, "medic event has three choices")

	var run := _run(2, 1)
	assert_true(_resolver().apply_choice_index(run, medic, 0), "first choice resolves")
	assert_eq(int(run.party_hp[&"fighter"]), mini(2 + 5, _fmax()), "medic's salve heals the party (capped)")


# --- M3: gold economy ---------------------------------------------------------

func test_gain_gold_adds_currency() -> void:
	var run := _run()
	run.currency = 10
	_resolver().apply(run, _choice(&"gain_gold", 25))
	assert_eq(run.currency, 35, "gain_gold adds to the run's currency")


func test_lose_gold_floors_at_zero() -> void:
	var run := _run()
	run.currency = 15
	_resolver().apply(run, _choice(&"lose_gold", 40))
	assert_eq(run.currency, 0, "lose_gold never goes negative")


# --- M3: choice conditions (race / class / min_gold / has_curse / has_relic) ---

func _gated(cond: Dictionary) -> EventChoice:
	var c := _choice(&"gain_gold", 10)
	c.condition = cond
	return c


func test_race_condition_matches_any_member() -> void:
	var run := _run()
	run.party_races = {&"fighter": &"human", &"mage": &"elf"}
	assert_true(EventResolverScript.is_choice_available(run, _gated({"race": "elf"})),
		"a party with an elf sees the elf branch")
	assert_false(EventResolverScript.is_choice_available(run, _gated({"race": "orc"})),
		"no orc in the party hides the orc branch")


func test_class_condition_and_preclass_state() -> void:
	var run := _run()
	run.member_classes = {&"fighter": &"fighter", &"mage": &""}  # mage pre-Act-3
	assert_true(EventResolverScript.is_choice_available(run, _gated({"class": "fighter"})),
		"a classed member satisfies its class branch")
	assert_false(EventResolverScript.is_choice_available(run, _gated({"class": "mage"})),
		"a pre-class member ('' per ADR-0021 pt2) never matches a class branch")


func test_min_gold_condition_boundary() -> void:
	var run := _run()
	run.currency = 20
	assert_true(EventResolverScript.is_choice_available(run, _gated({"min_gold": 20})),
		"exactly enough gold qualifies")
	assert_false(EventResolverScript.is_choice_available(run, _gated({"min_gold": 21})),
		"one short and the branch is hidden")


func test_has_curse_condition_both_polarities() -> void:
	var run := _run()
	assert_false(EventResolverScript.is_choice_available(run, _gated({"has_curse": true})),
		"an uncursed party can't take the cleansing branch")
	run.curses_of(&"fighter").append(&"burden")
	assert_true(EventResolverScript.is_choice_available(run, _gated({"has_curse": true})),
		"a cursed party can")
	assert_false(EventResolverScript.is_choice_available(run, _gated({"has_curse": false})),
		"has_curse:false hides when someone is cursed")


func test_has_relic_condition() -> void:
	var run := _run()
	assert_false(EventResolverScript.is_choice_available(run, _gated({"has_relic": "merchants_ledger"})),
		"missing relic hides the branch")
	run.relics.append(&"merchants_ledger")
	assert_true(EventResolverScript.is_choice_available(run, _gated({"has_relic": "merchants_ledger"})),
		"owning the relic reveals it")


func test_conditions_are_anded() -> void:
	var run := _run()
	run.currency = 100
	assert_false(EventResolverScript.is_choice_available(run, _gated({"min_gold": 40, "has_curse": true})),
		"all keys must hold: rich but uncursed fails the hexbreaker gate")
	run.curses_of(&"fighter").append(&"doubt")
	assert_true(EventResolverScript.is_choice_available(run, _gated({"min_gold": 40, "has_curse": true})),
		"rich AND cursed passes")


func test_apply_choice_index_rejects_gated_choice() -> void:
	var ev := EventDataScript.new()
	ev.id = &"evt_test_gate"
	ev.choices = [_gated({"min_gold": 50})] as Array[EventChoice]
	var run := _run()
	run.currency = 10
	assert_false(_resolver().apply_choice_index(run, ev, 0), "an unmet condition rejects the pick")
	assert_eq(run.currency, 10, "nothing applied on rejection")


# --- M3: weighted gamble tables -----------------------------------------------

func _gamble(groups: Array, weights: Array) -> EventChoice:
	var c := EventChoiceScript.new()
	c.label = "gamble"
	for i in groups.size():
		var o := EventOutcomeScript.new()
		o.kind = &"gain_gold"
		o.amount = int(groups[i])
		c.random_groups.append([o])
		c.random_weights.append(int(weights[i]))
	return c


func test_gamble_applies_exactly_one_group() -> void:
	var run := _run()
	run.seed = 12345
	_resolver().apply(run, _gamble([10, 999], [1, 1]), &"evt_salt")
	assert_true(run.currency == 10 or run.currency == 999,
		"exactly one weighted group applies, not both (got %d)" % run.currency)


func test_gamble_is_deterministic_for_same_seed_and_salt() -> void:
	var a := _run()
	a.seed = 777
	var b := _run()
	b.seed = 777
	_resolver().apply(a, _gamble([10, 999], [1, 1]), &"evt_salt")
	_resolver().apply(b, _gamble([10, 999], [1, 1]), &"evt_salt")
	assert_eq(a.currency, b.currency, "same run seed + event salt -> same roll (no save-scumming)")


func test_gamble_single_group_always_fires() -> void:
	var run := _run()
	run.seed = 42
	_resolver().apply(run, _gamble([30], [1]), &"evt_sure_thing")
	assert_eq(run.currency, 30, "a one-entry table is a certainty")


# --- M3: authored catalogue resolves end to end --------------------------------

func test_event_catalogue_has_28_events() -> void:
	assert_gte(_db.events.size(), 28, "M3 target: >= 28 authored events (got %d)" % _db.events.size())


func test_every_authored_event_keeps_a_safe_unconditional_exit() -> void:
	for id: Variant in _db.events.keys():
		var ev: EventData = _db.events[id]
		var open_count := 0
		for choice in ev.choices:
			if choice.condition.is_empty():
				open_count += 1
		assert_gt(open_count, 0, "event '%s' must offer at least one ungated choice" % id)


func test_gravekeeper_greed_pays_gold_and_curses() -> void:
	var ev: EventData = _db.get_event(&"evt_gravekeepers_bargain")
	var run := _run()
	assert_true(_resolver().apply_choice_index(run, ev, 0), "greedy crypt choice resolves")
	assert_eq(run.currency, 60, "grave-gold gained")
	assert_true(run.curses_of(&"fighter").has(&"burden"), "ADR-0029 hook: the greedy pick is cursed")


func test_hexbreaker_cleansing_costs_gold_and_removes_curse() -> void:
	var ev: EventData = _db.get_event(&"evt_hexbreakers_hut")
	var run := _run()
	run.currency = 50
	run.curses_of(&"fighter").append(&"doubt")
	assert_true(_resolver().apply_choice_index(run, ev, 0), "rite available when rich AND cursed")
	assert_eq(run.currency, 10, "40 gold paid")
	assert_true(run.curses_of(&"fighter").is_empty(), "the curse is lifted")


func test_curse_eater_trades_curse_for_gold() -> void:
	var ev: EventData = _db.get_event(&"evt_curse_eater")
	var run := _run()
	run.curses_of(&"fighter").append(&"hex_mark")
	assert_true(_resolver().apply_choice_index(run, ev, 0), "feed choice available while cursed")
	assert_true(run.curses_of(&"fighter").is_empty(), "the curse is eaten")
	assert_eq(run.currency, 50, "the eater pays out")

	var fresh := _run()
	assert_false(_resolver().apply_choice_index(fresh, ev, 0), "uncursed party can't take the trade")


func test_blood_altar_hp_for_relic() -> void:
	var ev: EventData = _db.get_event(&"evt_blood_altar")
	var run := _run(10, 12)
	assert_true(_resolver().apply_choice_index(run, ev, 0), "blood price resolves")
	assert_eq(int(run.party_hp[&"fighter"]), 5, "everyone bleeds for 5")
	assert_true(run.relics.has(&"iron_brand"), "the relic is granted")


func test_smugglers_drop_consumables_with_debt() -> void:
	var ev: EventData = _db.get_event(&"evt_smugglers_drop")
	var run := _run()
	assert_true(_resolver().apply_choice_index(run, ev, 0), "cache choice resolves")
	assert_true(run.consumables.has(&"fire_bomb") and run.consumables.has(&"throwing_knife"),
		"both consumables granted")
	assert_true(run.curses_of(&"fighter").has(&"debt"), "the smugglers' debt comes with it")


func test_orcish_war_shrine_race_branch() -> void:
	var ev: EventData = _db.get_event(&"evt_orcish_war_shrine")
	var run := _run()
	run.party_races = {&"fighter": &"orc", &"mage": &"elf"}
	assert_true(_resolver().apply_choice_index(run, ev, 0), "orc warcry available to an orc party")
	assert_true((run.skill_collections[&"fighter"] as Array).has(&"orcish_rage"),
		"the race basic is granted")

	var humans := _run()
	humans.party_races = {&"fighter": &"human", &"mage": &"human"}
	assert_false(_resolver().apply_choice_index(humans, ev, 0), "no orc, no warcry")


func test_gamblers_den_wager_is_deterministic_within_a_run() -> void:
	var ev: EventData = _db.get_event(&"evt_gamblers_den")
	var a := _run()
	a.seed = 999
	a.currency = 20
	var b := _run()
	b.seed = 999
	b.currency = 20
	assert_true(_resolver().apply_choice_index(a, ev, 0), "wager resolves")
	assert_true(_resolver().apply_choice_index(b, ev, 0), "wager resolves again")
	assert_eq(a.currency, b.currency, "same seed -> same fate at the dice table")
	assert_true(a.currency == 70 or a.currency == 0, "outcome is one of the authored stakes (got %d)" % a.currency)
