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
	# ADR-0021 pt1: class max is a small overlay (base_hp + class CON * hp_per_con).
	assert_eq(rc.run.party_hp[&"fighter"], _db.get_character(&"fighter").max_hp, "fighter starts at full")
	assert_eq(rc.run.party_hp[&"mage"], _db.get_character(&"mage").max_hp, "mage starts at full")
	assert_true(rc.run.downed.is_empty(), "no one downed at run start")
	assert_gt((rc.run.skill_collections[&"fighter"] as Array).size(), 0, "skill collection seeded from the class kit (ADR-0026)")


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
	# fighter survives wounded; mage is downed (0 HP).
	for unit in battle.living_players():
		var data := unit.source_data as CharacterData
		unit.hp = 0 if data.id == &"mage" else 3

	rc._write_back_hp(battle, BattleState.Outcome.WIN)

	var heal: int = _db.get_battle_config().post_combat_heal
	var fmax: int = _db.get_character(&"fighter").max_hp
	assert_eq(rc.run.party_hp[&"fighter"], mini(3 + heal, fmax), "survivor healed post-combat (capped)")
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
	assert_eq(rc.run.party_hp[&"fighter"], _db.get_character(&"fighter").max_hp, "heal clamps to max HP")
	assert_eq(rc.run.party_hp[&"mage"], _db.get_character(&"mage").max_hp)


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
	# Use a fight that reliably damages the party even after the post-combat heal
	# (trivial fights end at full HP); enc_combat_04 = brute + ogre (Hard).
	rc.resolve_combat(&"enc_combat_04", greedy)
	rc.resolve_combat(&"enc_combat_04", greedy)
	var fmax: int = _db.get_character(&"fighter").max_hp
	var mmax: int = _db.get_character(&"mage").max_hp
	var total: int = int(rc.run.party_hp[&"fighter"]) + int(rc.run.party_hp[&"mage"])
	assert_lt(total, fmax + mmax, "the party is below full HP after two fights (attrition)")
	# HP stays in valid range.
	assert_between(int(rc.run.party_hp[&"fighter"]), 0, fmax, "fighter HP in range")
	assert_between(int(rc.run.party_hp[&"mage"]), 0, mmax, "mage HP in range")


# --- Class + race creation (ADR-0015) ---------------------------------------

func test_race_selection_applies_in_run() -> void:
	var rc := _controller()
	# ADR-0021 pt1: races are the BASE templates (Orc 5/3/4/2, Elf 2/5/2/5);
	# classes are small overlays on top.
	var races := {&"fighter": &"orc", &"mage": &"elf"}
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1, races)

	var per_con: int = _db.get_battle_config().hp_per_con
	var fmax: int = _db.get_character(&"fighter").max_hp + 4 * per_con  # Orc base CON 4
	var mmax: int = _db.get_character(&"mage").max_hp + 2 * per_con  # Elf base CON 2
	assert_eq(rc.run.party_hp[&"fighter"], fmax, "race base CON raises starting HP")
	assert_eq(rc.run.party_hp[&"mage"], mmax, "elf base CON raises mage HP")
	assert_true((rc.run.skill_collections[&"fighter"] as Array).has(&"orcish_rage"), "orc custom card joins the fighter's collection")
	assert_true((rc.run.skill_collections[&"mage"] as Array).has(&"elven_focus"), "elf custom card joins the mage's collection")

	# A spawned fighter combatant carries the Orc stat mods.
	var battle := EncounterAssemblerScript.new().build(
		_db.get_encounter(&"skirmish_01"), _db, [&"fighter"] as Array[StringName], 1, {}, races
	)
	var fighter := battle.living_players()[0]
	var cls: CharacterData = _db.get_character(&"fighter")
	assert_eq(fighter.strength, cls.strength + 5, "Orc base STR 5 + Fighter overlay")
	assert_eq(fighter.max_hp, cls.max_hp + 4 * _db.get_battle_config().hp_per_con, "Orc base CON 4 -> +8 max HP")


# --- derived member decks (ADR-0026) -----------------------------------------

func test_member_skills_appear_in_their_own_combat_deck() -> void:
	# An Orc Fighter's custom card (orcish_rage) lives in the fighter's skill
	# collection; the derived member deck (ADR-0026) must contain it, plus the
	# auto-fill Strike/Defend basics up to the floor.
	var rc := _controller()
	rc.start_run([&"fighter"] as Array[StringName], 5, {&"fighter": &"orc"})
	assert_true((rc.run.skill_collections[&"fighter"] as Array).has(&"orcish_rage"), "precondition: custom card is a skill")

	var captured: Array = []
	var capture := func(b: Variant, _cp: Variant) -> void: captured.append(b)
	rc.resolve_combat(&"enc_combat_01", capture)

	assert_false(captured.is_empty(), "policy saw the battle")
	var battle: Variant = captured[0]
	var fighter: Combatant = battle.living_players()[0] if not battle.living_players().is_empty() else null
	if fighter == null:
		pass_test("party wiped before capture; deck composition covered by assembler tests")
		return
	var deck: Deck = battle.deck_of(fighter)
	assert_true(_deck_has_card(deck, &"orcish_rage"), "the skill appears in the member's derived deck")
	assert_true(_deck_has_card(deck, &"strike"), "auto-fill basics pad the deck to the floor (ADR-0026)")
	assert_gte(_deck_card_count(deck), _db.get_battle_config().derived_deck_floor, "derived deck meets the 20-card floor")


func test_assembler_derives_from_class_kit_when_no_member_decks_given() -> void:
	# Legacy/standalone callers (no member_decks): each member's deck derives on
	# the spot from the class starting kit + auto-fill (ADR-0026 fallback).
	var battle := EncounterAssemblerScript.new().build(
		_db.get_encounter(&"enc_combat_01"), _db,
		[&"fighter"] as Array[StringName], 5, {}, {}, {}
	)
	var fighter: Combatant = battle.living_players()[0]
	var deck: Deck = battle.deck_of(fighter)
	assert_false(_deck_has_card(deck, &"orcish_rage"), "no race/reward skills leak into the kit fallback")
	assert_gte(_deck_card_count(deck), _db.get_battle_config().derived_deck_floor, "fallback deck meets the floor")


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
	# ADR-0021 pt1: a raceless party is no longer a playable config — give the
	# members their race base templates so the staged fight is winnable.
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 7, {&"fighter": &"orc", &"mage": &"elf"})
	# The authored enemy blocks are Act-3-strength (scaler baseline 8) while the
	# ADR-0021 pt1 party starts fragile — emulate a leveled party so the staged
	# unscaled fight is winnable and the XP bookkeeping (the thing under test)
	# can be observed on a WIN.
	rc.run.allocated_stats = {
		&"fighter": {&"str": 8, &"con": 8}, &"mage": {&"int": 8, &"con": 8}
	}
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
		[&"fighter"] as Array[StringName], 1, {}, {}, {}, alloc
	)
	var fighter := battle.living_players()[0]
	assert_eq(fighter.strength, _db.get_character(&"fighter").strength + 3, "allocated STR adds on top of the class overlay")


func test_allocated_con_raises_max_hp_in_fight() -> void:
	var alloc := {&"fighter": {&"str": 0, &"dex": 0, &"con": 2, &"int": 0}}
	var battle := EncounterAssemblerScript.new().build(
		_db.get_encounter(&"enc_combat_01"), _db,
		[&"fighter"] as Array[StringName], 1, {}, {}, {}, alloc
	)
	var fighter := battle.living_players()[0]
	var per_con: int = _db.get_battle_config().hp_per_con
	assert_eq(fighter.max_hp, _db.get_character(&"fighter").max_hp + 2 * per_con, "allocated CON raises derived max HP")


func test_allocate_stat_point_through_controller() -> void:
	var rc := _controller()
	rc.start_run([&"fighter"] as Array[StringName], 1)
	rc.run.unspent_points[&"fighter"] = 1  # simulate a level-up's pool
	assert_true(rc.allocate_stat_point(&"fighter", &"str"), "spends the available point")
	assert_eq(rc.unspent_points(&"fighter"), 0, "pool drained")
	assert_eq(int(rc.run.allocated_stats[&"fighter"][&"str"]), 1, "STR allocation recorded")
	assert_false(rc.allocate_stat_point(&"fighter", &"str"), "cannot spend with none left")


# --- Effective max-HP heal cap (review fix #1) -------------------------------

func test_post_combat_heal_fills_to_effective_max_not_base() -> void:
	# An Orc fighter's effective max includes the race base CON (ADR-0021 pt1). A
	# post-combat heal must fill into that headroom, not clamp to the class overlay.
	var rc := _controller()
	rc.start_run([&"fighter"] as Array[StringName], 1, {&"fighter": &"orc"})
	var battle := EncounterAssemblerScript.new().build(
		_db.get_encounter(&"enc_combat_01"), _db,
		[&"fighter"] as Array[StringName], 1, {}, {&"fighter": &"orc"}
	)
	var eff_max: int = PartyStats.effective_max_hp(_db, rc.run, &"fighter")
	var cls_max: int = _db.get_character(&"fighter").max_hp
	assert_gt(eff_max, cls_max, "precondition: race CON adds headroom above the class overlay")
	var fighter := battle.living_players()[0]
	fighter.hp = eff_max - 2  # wounded, but above the class-overlay max
	rc._write_back_hp(battle, BattleState.Outcome.WIN)
	var heal: int = _db.get_battle_config().post_combat_heal
	assert_eq(
		int(rc.run.party_hp[&"fighter"]), mini(eff_max, eff_max - 2 + heal),
		"heal caps at the race-boosted effective max, not the class overlay"
	)


# --- Class promotion (P3·06) ------------------------------------------------

func test_promotion_eligible_only_at_threshold() -> void:
	var rc := _controller()
	rc.start_run([&"fighter"] as Array[StringName], 1)
	assert_eq(rc.eligible_promotions(&"fighter").size(), 0, "not eligible at level 1")
	rc.run.party_level[&"fighter"] = _db.get_battle_config().promotion_level  # hit the threshold
	var offered := rc.eligible_promotions(&"fighter")
	assert_eq(offered.size(), 2, "two branches offered at the promotion level")
	var ids: Array[StringName] = []
	for p in offered:
		ids.append(p.id)
	assert_true(ids.has(&"berserker") and ids.has(&"guardian"), "fighter's branches")


func test_apply_promotion_folds_stats_and_card() -> void:
	var rc := _controller()
	rc.start_run([&"fighter"] as Array[StringName], 1)
	rc.run.party_level[&"fighter"] = _db.get_battle_config().promotion_level
	var deck_before: int = (rc.run.skill_collections[&"fighter"] as Array).size()
	assert_true(rc.apply_promotion(&"fighter", &"berserker"), "applies an eligible branch")
	assert_eq(int(rc.run.allocated_stats[&"fighter"][&"str"]), 3, "Berserker folds +3 STR into allocations")
	assert_eq((rc.run.skill_collections[&"fighter"] as Array).size(), deck_before + 1, "signature skill added to the collection")
	assert_true((rc.run.skill_collections[&"fighter"] as Array).has(&"berserker_rampage"), "the right signature skill")
	assert_true(rc.run.party_promotions[&"fighter"].has(&"berserker"), "promotion recorded")


func test_promotion_accrual_needs_higher_level_and_offers_other_branch() -> void:
	var rc := _controller()
	rc.start_run([&"fighter"] as Array[StringName], 1)
	var lvl: int = _db.get_battle_config().promotion_level
	rc.run.party_level[&"fighter"] = lvl
	rc.apply_promotion(&"fighter", &"berserker")
	assert_eq(rc.eligible_promotions(&"fighter").size(), 0, "no 2nd promotion until 2x the level")
	rc.run.party_level[&"fighter"] = lvl * 2
	var offered := rc.eligible_promotions(&"fighter")
	assert_eq(offered.size(), 1, "the remaining branch is offered for the 2nd promotion")
	assert_eq(offered[0].id, &"guardian", "berserker already taken -> guardian remains")


func test_apply_promotion_rejects_wrong_class_or_ineligible() -> void:
	var rc := _controller()
	rc.start_run([&"fighter"] as Array[StringName], 1)
	rc.run.party_level[&"fighter"] = _db.get_battle_config().promotion_level
	assert_false(rc.apply_promotion(&"fighter", &"assassin"), "rogue branch rejected for a fighter")
	rc.run.party_level[&"fighter"] = 1
	assert_false(rc.apply_promotion(&"fighter", &"berserker"), "rejected below the threshold")


# --- Relics (P2·12) ---------------------------------------------------------

func test_grant_relic_adds_and_dedupes() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	assert_true(rc.grant_relic(&"iron_brand", "elite"), "a real relic is granted")
	assert_true(rc.run.relics.has(&"iron_brand"), "relic recorded on the run")
	assert_false(rc.grant_relic(&"iron_brand"), "granting the same relic twice is a no-op")
	assert_false(rc.grant_relic(&"no_such_relic"), "an unknown relic id is rejected")


func test_granted_relic_applies_in_the_next_fight() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	rc.grant_relic(&"iron_brand")  # +6 block at combat_start
	var battle := rc.begin_combat(&"enc_combat_01")
	assert_not_null(battle, "combat assembled")
	for unit in battle.living_players():
		assert_eq(unit.block, 6, "the owned relic's combat_start block applied in the fight")


func test_available_relics_excludes_owned() -> void:
	var rc := _controller()
	rc.start_run([&"fighter"] as Array[StringName], 1)
	var before: int = rc.available_relics().size()
	assert_gt(before, 0, "some relics are available")
	rc.grant_relic(&"iron_brand")
	assert_false(rc.available_relics().has(&"iron_brand"), "an owned relic drops out of the pool")
	assert_eq(rc.available_relics().size(), before - 1, "pool shrinks by one")


# --- Rest nodes (P2·07) -----------------------------------------------------

func test_resolve_rest_heal_restores_party() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	rc.run.party_hp[&"fighter"] = 2
	var amount: int = _db.get_battle_config().rest_heal
	var fmax: int = _db.get_character(&"fighter").max_hp
	assert_true(rc.resolve_rest(&"heal"), "heal choice applies")
	assert_eq(int(rc.run.party_hp[&"fighter"]), mini(2 + amount, fmax), "rest heals by config amount (capped)")


func test_resolve_rest_upgrade_swaps_skill() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	rc.run.skill_collections[&"fighter"] = ["shield_bash", "quick_stab"]
	assert_true(rc.resolve_rest(&"upgrade", &"shield_bash"), "upgrade applies when base + variant exist")
	assert_true((rc.run.skill_collections[&"fighter"] as Array).has("shield_bash_plus") or (rc.run.skill_collections[&"fighter"] as Array).has(&"shield_bash_plus"), "the upgraded skill replaced the base (ADR-0026)")
	assert_false((rc.run.skill_collections[&"fighter"] as Array).has("shield_bash"), "the base skill was replaced")


func test_resolve_rest_rejects_unknown_kind() -> void:
	var rc := _controller()
	rc.start_run([&"fighter"] as Array[StringName], 1)
	assert_false(rc.resolve_rest(&"meditate"), "an unknown rest kind is rejected")


# --- Event nodes (P2·08) ----------------------------------------------------

func test_resolve_event_applies_choice_to_run() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	rc.run.party_hp[&"fighter"] = 2
	rc.run.party_hp[&"mage"] = 1
	# evt_wandering_medic choice 0 heals the party by 8 (capped at the small
	# ADR-0021 pt1 class max).
	assert_true(rc.resolve_event(&"evt_wandering_medic", 0), "valid event + choice resolves")
	assert_eq(
		int(rc.run.party_hp[&"fighter"]),
		mini(2 + 8, _db.get_character(&"fighter").max_hp),
		"the chosen heal outcome applied"
	)


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
	# ADR-0026: each member plays offense from their OWN derived deck's hand
	# (Strike is an ordinary deck card now — no innate fallback).
	var guard: int = 0
	while battle.total_energy() > 0 and guard < 40:
		guard += 1
		var enemies: Array[Combatant] = battle.living_enemies()
		if enemies.is_empty():
			return
		var target: Combatant = _lowest_hp(enemies)
		var acted: bool = false
		for actor in battle.living_players():
			for card in battle.deck_of(actor).hand.duplicate():
				if not _card_is_offensive(card):
					continue
				if card.energy_cost > battle.energy_of(actor):
					continue  # ADR-0025: the actor's OWN pool must afford it
				if cp.play_card(actor, card, _resolve_tgt(card, actor, target)).ok:
					acted = true
					break
			if acted:
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


# --- 18-act act-advance flow (ADR-0019) ---------------------------------------

func test_start_run_begins_at_act_one() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	assert_eq(rc.run.act, 1, "a fresh run starts in act 1")


func test_advance_act_moves_on_and_regenerates_the_map() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	rc.run.party_hp[&"fighter"] = 17  # mid-run damage that must carry across acts
	rc.run.position = &"n_boss"
	rc.run.cleared = [&"n_0_0", &"n_boss"] as Array[StringName]
	assert_true(rc.advance_act(), "act 2 exists in the authored curve")
	assert_eq(rc.run.act, 2, "the run moved to act 2")
	assert_not_null(rc.run.map, "a new map was generated for act 2")
	assert_eq(rc.run.position, &"", "position resets for the new act")
	assert_true(rc.run.cleared.is_empty(), "cleared nodes reset for the new act")
	assert_eq(rc.run.party_hp[&"fighter"], 17, "HP carries across the act boundary")


func test_advance_act_is_deterministic_per_run_seed() -> void:
	var a := _controller()
	a.start_run([&"fighter", &"mage"] as Array[StringName], 99)
	a.advance_act()
	var b := _controller()
	b.start_run([&"fighter", &"mage"] as Array[StringName], 99)
	b.advance_act()
	assert_eq(a.run.map.to_dict(), b.run.map.to_dict(), "same run seed -> same act-2 map")


func test_advance_act_returns_false_past_the_last_act() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	rc.run.act = 18
	assert_false(rc.advance_act(), "there is no act 19 — the run is won")
	assert_eq(rc.run.act, 18, "a failed advance leaves the act unchanged")


# --- Enemy band scaling at assembly (ADR-0019) --------------------------------

func test_begin_combat_band_scales_enemy_stats() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	var plain: EncounterBattle = rc.begin_combat(&"enc_combat_01")
	var banded: EncounterBattle = rc.begin_combat(&"enc_combat_01", &"trash")
	var act1: ActConfig = _db.get_act(1)
	assert_not_null(act1, "act 1 config loads")
	var scaler := EnemyScaler.new(_db.get_battle_config())
	var level: int = EnemyScaler.band_level(act1, &"trash")
	var plain_enemies: Array[Combatant] = plain.living_enemies()
	var banded_enemies: Array[Combatant] = banded.living_enemies()
	assert_eq(banded_enemies.size(), plain_enemies.size(), "same spawn count either way")
	var saw_reduction: bool = false
	for i in range(plain_enemies.size()):
		var expected: int = scaler.scaled(plain_enemies[i].max_hp, level, 1)
		assert_eq(banded_enemies[i].max_hp, expected, "enemy %d HP scaled to the act-1 trash band" % i)
		if banded_enemies[i].max_hp < plain_enemies[i].max_hp:
			saw_reduction = true
	assert_true(saw_reduction, "act-1 trash band (below baseline) actually reduces stats")


func test_begin_combat_without_band_is_unscaled() -> void:
	var rc := _controller()
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 1)
	var plain: EncounterBattle = rc.begin_combat(&"enc_combat_01")
	var plain_enemies: Array[Combatant] = plain.living_enemies()
	assert_gt(plain_enemies.size(), 0, "encounter spawns enemies")
	for e in plain_enemies:
		var data := e.source_data as EnemyData
		assert_not_null(data, "enemy has source data")
		assert_eq(e.max_hp, data.max_hp, "no band -> authored stat block unscaled")
