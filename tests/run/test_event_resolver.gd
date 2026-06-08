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
	run.run_deck = [] as Array[StringName]
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

func test_heal_restores_living_members() -> void:
	var run := _run(10, 12)
	_resolver().apply(run, _choice(&"heal", 8))
	assert_eq(int(run.party_hp[&"fighter"]), 18, "fighter healed by amount")
	assert_eq(int(run.party_hp[&"mage"]), 20, "mage healed by amount")


func test_heal_caps_at_base_max_hp() -> void:
	var run := _run(33, 23)
	_resolver().apply(run, _choice(&"heal", 50))
	assert_eq(int(run.party_hp[&"fighter"]), 34, "fighter capped at base max (34)")
	assert_eq(int(run.party_hp[&"mage"]), 24, "mage capped at base max (24)")


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

func test_add_card_appends_to_run_deck() -> void:
	var run := _run()
	_resolver().apply(run, _choice(&"add_card", 0, &"field_dressing"))
	assert_true(run.run_deck.has(&"field_dressing"), "the card joins the run deck")


func test_remove_card_removes_one_copy() -> void:
	var run := _run()
	run.run_deck = [&"strike", &"field_dressing", &"field_dressing"] as Array[StringName]
	_resolver().apply(run, _choice(&"remove_card", 0, &"field_dressing"))
	assert_eq(run.run_deck.size(), 2, "exactly one copy removed")
	assert_true(run.run_deck.has(&"field_dressing"), "the second copy remains")
	assert_true(run.run_deck.has(&"strike"), "unrelated cards untouched")


func test_remove_card_absent_is_noop() -> void:
	var run := _run()
	run.run_deck = [&"strike"] as Array[StringName]
	_resolver().apply(run, _choice(&"remove_card", 0, &"field_dressing"))
	assert_eq(run.run_deck.size(), 1, "removing an absent card changes nothing")


func test_add_relic_appends_to_relics() -> void:
	var run := _run()
	_resolver().apply(run, _choice(&"add_relic", 0, &"shrine_blessing"))
	assert_true(run.relics.has(&"shrine_blessing"), "the relic id is recorded")


func test_nothing_is_noop() -> void:
	var run := _run(10, 12)
	_resolver().apply(run, _choice(&"nothing"))
	assert_eq(int(run.party_hp[&"fighter"]), 10, "nothing leaves HP unchanged")
	assert_eq(run.run_deck.size(), 0, "nothing leaves the deck unchanged")


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

	var run := _run(10, 12)
	assert_true(_resolver().apply_choice_index(run, medic, 0), "first choice resolves")
	assert_eq(int(run.party_hp[&"fighter"]), 18, "medic's salve heals the party")
