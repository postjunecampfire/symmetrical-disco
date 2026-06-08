extends "res://addons/gut/test.gd"
## GUT suite for the run spine (P2·04 + P2·05): RunController carries HP across
## encounters (ADR-0011) — survivors keep their HP and heal a little after a win,
## downed units revive at low HP next fight, and a TPK ends the run.

const RunControllerScript := preload("res://src/run/run_controller.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")
const EncounterAssemblerScript := preload("res://src/combat/encounter_assembler.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _controller() -> RunController:
	return RunControllerScript.new(_db)


# --- Start: full HP ---------------------------------------------------------

func test_start_run_sets_full_hp() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	assert_eq(rc.run.party_hp[&"fighter"], 34, "vanguard starts at full (CON 17 * 2)")
	assert_eq(rc.run.party_hp[&"mage"], 24, "mage starts at full (CON 12 * 2)")
	assert_true(rc.run.downed.is_empty(), "no one downed at run start")
	assert_gt(rc.run.run_deck.size(), 0, "run deck seeded from starting decks")


# --- Carry / revive ---------------------------------------------------------

func test_downed_unit_revives_at_revive_hp_next_fight() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	rc.run.party_hp[&"fighter"] = 20  # damaged survivor
	rc.run.party_hp[&"mage"] = 0        # downed
	rc.run.downed = [&"mage"] as Array[StringName]

	var carried: Dictionary = rc._carried_for_next_fight()
	assert_eq(carried[&"fighter"], 20, "survivor carries its actual HP")
	assert_eq(
		carried[&"mage"], _db.get_battle_config().revive_hp,
		"a downed unit revives at the configured revive HP"
	)


# --- Write-back: heal survivors, mark downed --------------------------------

func test_win_heals_survivors_and_marks_downed() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	var battle := EncounterAssemblerScript.new().build(
		_db.get_encounter(&"skirmish_01"), _db, [&"fighter", &"mage"] as Array[StringName], 1
	)
	# vanguard survives wounded; mage is downed (0 HP).
	for unit in battle.living_players():
		var data := unit.source_data as CharacterData
		unit.hp = 0 if data.id == &"mage" else 10

	rc._write_back_hp(battle, BattleState.Outcome.WIN)

	var heal: int = _db.get_battle_config().post_combat_heal
	assert_eq(rc.run.party_hp[&"fighter"], 10 + heal, "survivor healed post-combat")
	assert_eq(rc.run.party_hp[&"mage"], 0, "a downed unit is NOT healed")
	assert_true(rc.run.downed.has(&"mage"), "0-HP unit recorded as downed")
	assert_false(rc.run.downed.has(&"fighter"), "survivor not downed")


func test_heal_caps_at_max_hp() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	var battle := EncounterAssemblerScript.new().build(
		_db.get_encounter(&"skirmish_01"), _db, [&"fighter", &"mage"] as Array[StringName], 1
	)
	for unit in battle.living_players():
		unit.hp = unit.max_hp - 1  # one below full
	rc._write_back_hp(battle, BattleState.Outcome.WIN)
	assert_eq(rc.run.party_hp[&"fighter"], 34, "heal clamps to max HP")
	assert_eq(rc.run.party_hp[&"mage"], 24)


# --- TPK ends the run -------------------------------------------------------

func test_tpk_ends_the_run() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	var noop := func(_b: Variant, _cp: Variant) -> void: pass
	var summary: Dictionary = rc.run_act([&"enc_boss_01"], noop)
	assert_false(summary["won"], "doing nothing vs the boss loses")
	assert_eq(summary["death_node"], "enc_boss_01", "death node recorded")
	assert_eq(summary["cleared"], 0, "no nodes cleared on a first-fight wipe")


# --- Attrition is real: HP drops across fights ------------------------------

func test_hp_attrition_across_two_fights() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 7)
	var greedy := func(b: Variant, cp: Variant) -> void: _greedy_turn(b, cp)
	rc.resolve_combat(&"enc_combat_01", greedy)
	rc.resolve_combat(&"enc_combat_01", greedy)
	var total: int = int(rc.run.party_hp[&"fighter"]) + int(rc.run.party_hp[&"mage"])
	assert_lt(total, 34 + 24, "the party is below full HP after two fights (attrition)")
	# HP stays in valid range.
	assert_between(int(rc.run.party_hp[&"fighter"]), 0, 34, "vanguard HP in range")
	assert_between(int(rc.run.party_hp[&"mage"]), 0, 24, "mage HP in range")


# --- Class + race creation (ADR-0015) ---------------------------------------

func test_race_selection_applies_in_run() -> void:
	var rc := _controller()
	# Fighter as an Orc (+2 STR, +2 CON), Mage as an Elf (+2 DEX, +2 INT).
	var races := {&"fighter": &"orc", &"mage": &"elf"}
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1, races)

	# Orc +2 CON -> +4 max HP (hp_per_con 2): fighter 34 -> 38. Elf has no CON.
	assert_eq(rc.run.party_hp[&"fighter"], 38, "race CON bonus raises starting HP")
	assert_eq(rc.run.party_hp[&"mage"], 24, "elf (no CON) leaves mage HP unchanged")
	assert_true(rc.run.run_deck.has(&"orcish_rage"), "orc custom card joins the run deck")
	assert_true(rc.run.run_deck.has(&"elven_focus"), "elf custom card joins the run deck")

	# A spawned fighter combatant carries the Orc stat mods.
	var battle := EncounterAssemblerScript.new().build(
		_db.get_encounter(&"skirmish_01"), _db, [&"fighter"] as Array[StringName], 1, {}, races
	)
	var fighter := battle.living_players()[0]
	assert_eq(fighter.strength, 6 + 2, "Orc +2 STR applied on top of the Fighter class")
	assert_eq(fighter.max_hp, 34 + 4, "Orc +2 CON -> +4 max HP applied")


# --- run_deck -> combat deck injection (P2·06) ------------------------------

func test_run_deck_cards_appear_in_combat() -> void:
	# An Orc Fighter's custom card (orcish_rage) lives in run_deck but in NO
	# starting deck. With run_deck driving combat (P2·06) it must show up in the
	# fight's shared deck. Capture the live battle through the policy.
	var rc := _controller()
	rc.start_run([&"fighter"] as Array[StringName], 5, {&"fighter": &"orc"})
	assert_true(rc.run.run_deck.has(&"orcish_rage"), "precondition: custom card is in the run deck")

	var captured: Array = []
	var capture := func(b: Variant, _cp: Variant) -> void: captured.append(b)
	rc.resolve_combat(&"enc_combat_01", capture)

	assert_false(captured.is_empty(), "policy saw the battle")
	var battle: Variant = captured[0]
	assert_true(
		_deck_has_card(battle.deck, &"orcish_rage"),
		"the run-deck custom card appears in the assembled combat deck"
	)


func test_assembler_falls_back_to_starting_decks_when_run_deck_empty() -> void:
	# With an empty run_deck the assembler must reproduce the original behaviour:
	# the deck is the party's starting decks, so a custom-only card is absent.
	var battle := EncounterAssemblerScript.new().build(
		_db.get_encounter(&"enc_combat_01"), _db,
		[&"fighter"] as Array[StringName], 5, {}, {}, [] as Array[StringName]
	)
	assert_false(
		_deck_has_card(battle.deck, &"orcish_rage"),
		"no race/reward cards leak in when run_deck is empty (starting decks only)"
	)
	assert_gt(_deck_card_count(battle.deck), 0, "the starting-deck fallback still builds a deck")


## True if any zone of `deck` holds a card with `card_id` (a card lives in exactly
## one zone, so the union across zones is the whole deck).
func _deck_has_card(deck: Variant, card_id: StringName) -> bool:
	for zone in [deck.draw_pile, deck.hand, deck.discard_pile, deck.exhaust_pile]:
		for card in zone:
			if card.id == card_id:
				return true
	return false


## Total cards across all zones of `deck`.
func _deck_card_count(deck: Variant) -> int:
	return deck.draw_pile.size() + deck.hand.size() + deck.discard_pile.size() + deck.exhaust_pile.size()


# --- Leveling (P3·05 / ADR-0015) --------------------------------------------

func test_start_run_initialises_leveling_state() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	assert_eq(int(rc.run.party_level[&"fighter"]), 1, "fighter starts at level 1")
	assert_eq(int(rc.run.party_xp[&"fighter"]), 0, "fighter starts at 0 XP")
	assert_eq(rc.unspent_points(&"fighter"), 0, "no unspent points at run start")


func test_winning_a_combat_awards_xp() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 7)
	var greedy := func(b: Variant, cp: Variant) -> void: _greedy_turn(b, cp)
	var outcome: int = rc.resolve_combat(&"enc_combat_01", greedy)
	assert_eq(outcome, BattleState.Outcome.WIN, "precondition: greedy wins enc_combat_01")
	var xp_per_combat: int = _db.get_battle_config().xp_per_combat
	assert_eq(int(rc.run.party_xp[&"fighter"]), xp_per_combat, "a win awards the per-combat XP")
	assert_eq(int(rc.run.party_xp[&"mage"]), xp_per_combat, "each surviving member earns XP")


func test_allocated_stats_apply_in_fight() -> void:
	# Player-allocated STR rides on top of the class base in the assembled fight.
	var alloc := {&"fighter": {&"str": 3, &"dex": 0, &"con": 0, &"int": 0}}
	var battle := EncounterAssemblerScript.new().build(
		_db.get_encounter(&"enc_combat_01"), _db,
		[&"fighter"] as Array[StringName], 1, {}, {}, [] as Array[StringName], alloc
	)
	var fighter := battle.living_players()[0]
	assert_eq(fighter.strength, 6 + 3, "allocated STR adds on top of the Fighter class base (6)")


func test_allocated_con_raises_max_hp_in_fight() -> void:
	var alloc := {&"fighter": {&"str": 0, &"dex": 0, &"con": 2, &"int": 0}}
	var battle := EncounterAssemblerScript.new().build(
		_db.get_encounter(&"enc_combat_01"), _db,
		[&"fighter"] as Array[StringName], 1, {}, {}, [] as Array[StringName], alloc
	)
	var fighter := battle.living_players()[0]
	var per_con: int = _db.get_battle_config().hp_per_con
	assert_eq(fighter.max_hp, 34 + 2 * per_con, "allocated CON raises derived max HP")


func test_allocate_stat_point_through_controller() -> void:
	var rc := _controller()
	rc.start_run([&"fighter"] as Array[StringName], 1)
	rc.run.unspent_points[&"fighter"] = 1  # simulate a level-up's pool
	assert_true(rc.allocate_stat_point(&"fighter", &"str"), "spends the available point")
	assert_eq(rc.unspent_points(&"fighter"), 0, "pool drained")
	assert_eq(int(rc.run.allocated_stats[&"fighter"][&"str"]), 1, "STR allocation recorded")
	assert_false(rc.allocate_stat_point(&"fighter", &"str"), "cannot spend with none left")


# --- Event nodes (P2·08) ----------------------------------------------------

func test_resolve_event_applies_choice_to_run() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	rc.run.party_hp[&"fighter"] = 10
	rc.run.party_hp[&"mage"] = 12
	# evt_wandering_medic choice 0 heals the party by 8.
	assert_true(rc.resolve_event(&"evt_wandering_medic", 0), "valid event + choice resolves")
	assert_eq(int(rc.run.party_hp[&"fighter"]), 18, "the chosen heal outcome applied")


func test_resolve_event_rejects_unknown_event_or_choice() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	assert_false(rc.resolve_event(&"no_such_event", 0), "unknown event id rejected")
	assert_false(rc.resolve_event(&"evt_wandering_medic", 99), "out-of-range choice rejected")


# --- Run-level telemetry (P2·11) --------------------------------------------

## A TelemetryLogger spy that records calls instead of writing to disk.
class _SpyLogger extends TelemetryLogger:
	var events: Array[StringName] = []
	var ended: bool = false

	func log_event(type: StringName, _data: Dictionary) -> void:
		events.append(type)

	func end_run(_summary: Dictionary) -> void:
		ended = true


func test_run_emits_run_level_telemetry() -> void:
	var spy := _SpyLogger.new()
	var rc := RunControllerScript.new(_db, spy)
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 3)
	var greedy := func(b: Variant, cp: Variant) -> void: _greedy_turn(b, cp)
	rc.run_act([&"enc_combat_01"], greedy)

	assert_true(spy.events.has(&"combat_result"), "logs a combat_result per fight")
	assert_true(spy.ended, "ends the run through telemetry")


# --- A simple greedy auto-play policy (max damage, no defense) ---------------

func _greedy_turn(battle: Variant, cp: Variant) -> void:
	var guard: int = 0
	while battle.energy > 0 and guard < 40:
		guard += 1
		var enemies: Array[Combatant] = battle.living_enemies()
		if enemies.is_empty():
			return
		var target: Combatant = _lowest_hp(enemies)
		var acted: bool = false
		for card in battle.deck.hand.duplicate():
			if card.energy_cost > battle.energy:
				continue
			if not _card_is_offensive(card):
				continue
			var actor: Combatant = _card_actor(battle, card)
			if actor == null:
				continue
			if cp.play_card(actor, card, _resolve_tgt(card, actor, target)).ok:
				acted = true
				break
		if acted:
			continue
		var strike: CardData = _db.get_card(&"strike")
		for actor in battle.living_players():
			if strike == null or strike.energy_cost > battle.energy:
				break
			if cp.play_innate(actor, strike, target).ok:
				acted = true
				break
		if not acted:
			return


func _card_actor(battle: Variant, card: CardData) -> Combatant:
	if card.character_tag == &"neutral":
		var ps: Array[Combatant] = battle.living_players()
		return ps[0] if not ps.is_empty() else null
	for p in battle.living_players():
		var d := p.source_data as CharacterData
		if d != null and d.id == card.character_tag:
			return p
	return null


func _card_is_offensive(card: CardData) -> bool:
	for e in card.effects:
		if e is Effect and e.type == &"damage":
			return true
	return false


func _resolve_tgt(card: CardData, actor: Combatant, target: Combatant) -> Variant:
	match card.target.target_type:
		&"self":
			return actor
		&"enemy":
			return target
		_:
			return null


func _lowest_hp(units: Array[Combatant]) -> Combatant:
	var best: Combatant = null
	for u in units:
		if best == null or u.hp < best.hp:
			best = u
	return best
