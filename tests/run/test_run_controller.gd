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
	rc.start_run([&"vanguard", &"mage"] as Array[StringName], 1)
	assert_eq(rc.run.party_hp[&"vanguard"], 34, "vanguard starts at full (CON 17 * 2)")
	assert_eq(rc.run.party_hp[&"mage"], 24, "mage starts at full (CON 12 * 2)")
	assert_true(rc.run.downed.is_empty(), "no one downed at run start")
	assert_gt(rc.run.run_deck.size(), 0, "run deck seeded from starting decks")


# --- Carry / revive ---------------------------------------------------------

func test_downed_unit_revives_at_revive_hp_next_fight() -> void:
	var rc := _controller()
	rc.start_run([&"vanguard", &"mage"] as Array[StringName], 1)
	rc.run.party_hp[&"vanguard"] = 20  # damaged survivor
	rc.run.party_hp[&"mage"] = 0        # downed
	rc.run.downed = [&"mage"] as Array[StringName]

	var carried: Dictionary = rc._carried_for_next_fight()
	assert_eq(carried[&"vanguard"], 20, "survivor carries its actual HP")
	assert_eq(
		carried[&"mage"], _db.get_battle_config().revive_hp,
		"a downed unit revives at the configured revive HP"
	)


# --- Write-back: heal survivors, mark downed --------------------------------

func test_win_heals_survivors_and_marks_downed() -> void:
	var rc := _controller()
	rc.start_run([&"vanguard", &"mage"] as Array[StringName], 1)
	var battle := EncounterAssemblerScript.new().build(
		_db.get_encounter(&"skirmish_01"), _db, [&"vanguard", &"mage"] as Array[StringName], 1
	)
	# vanguard survives wounded; mage is downed (0 HP).
	for unit in battle.living_players():
		var data := unit.source_data as CharacterData
		unit.hp = 0 if data.id == &"mage" else 10

	rc._write_back_hp(battle, BattleState.Outcome.WIN)

	var heal: int = _db.get_battle_config().post_combat_heal
	assert_eq(rc.run.party_hp[&"vanguard"], 10 + heal, "survivor healed post-combat")
	assert_eq(rc.run.party_hp[&"mage"], 0, "a downed unit is NOT healed")
	assert_true(rc.run.downed.has(&"mage"), "0-HP unit recorded as downed")
	assert_false(rc.run.downed.has(&"vanguard"), "survivor not downed")


func test_heal_caps_at_max_hp() -> void:
	var rc := _controller()
	rc.start_run([&"vanguard", &"mage"] as Array[StringName], 1)
	var battle := EncounterAssemblerScript.new().build(
		_db.get_encounter(&"skirmish_01"), _db, [&"vanguard", &"mage"] as Array[StringName], 1
	)
	for unit in battle.living_players():
		unit.hp = unit.max_hp - 1  # one below full
	rc._write_back_hp(battle, BattleState.Outcome.WIN)
	assert_eq(rc.run.party_hp[&"vanguard"], 34, "heal clamps to max HP")
	assert_eq(rc.run.party_hp[&"mage"], 24)


# --- TPK ends the run -------------------------------------------------------

func test_tpk_ends_the_run() -> void:
	var rc := _controller()
	rc.start_run([&"vanguard", &"mage"] as Array[StringName], 1)
	var noop := func(_b: Variant, _cp: Variant) -> void: pass
	var summary: Dictionary = rc.run_act([&"enc_boss_01"], noop)
	assert_false(summary["won"], "doing nothing vs the boss loses")
	assert_eq(summary["death_node"], "enc_boss_01", "death node recorded")
	assert_eq(summary["cleared"], 0, "no nodes cleared on a first-fight wipe")


# --- Attrition is real: HP drops across fights ------------------------------

func test_hp_attrition_across_two_fights() -> void:
	var rc := _controller()
	rc.start_run([&"vanguard", &"mage"] as Array[StringName], 7)
	var greedy := func(b: Variant, cp: Variant) -> void: _greedy_turn(b, cp)
	rc.resolve_combat(&"enc_combat_01", greedy)
	rc.resolve_combat(&"enc_combat_01", greedy)
	var total: int = int(rc.run.party_hp[&"vanguard"]) + int(rc.run.party_hp[&"mage"])
	assert_lt(total, 34 + 24, "the party is below full HP after two fights (attrition)")
	# HP stays in valid range.
	assert_between(int(rc.run.party_hp[&"vanguard"]), 0, 34, "vanguard HP in range")
	assert_between(int(rc.run.party_hp[&"mage"]), 0, 24, "mage HP in range")


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
	rc.start_run([&"vanguard", &"mage"] as Array[StringName], 3)
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
