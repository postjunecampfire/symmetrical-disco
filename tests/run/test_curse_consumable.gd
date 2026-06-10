extends "res://addons/gut/test.gd"
## Injected non-skill card layer (ADR-0029): per-member curses count toward the
## derived-deck floor (displacing Strike/Defend auto-fill; swelling above it),
## party consumables inject ON TOP and are consumed when played, relic
## `floor_reduction` lowers the floor (min derived_deck_floor_min), curses never
## enter reward pools, the shop sells items + curse removal, events can
## add/remove curses and grant items, enemies inflict curses that persist, and
## the whole layer round-trips through saves.

const ContentDatabaseScript := preload("res://src/data/content_database.gd")
const RunControllerScript := preload("res://src/run/run_controller.gd")
const RunStateScript := preload("res://src/run/run_state.gd")
const CardPlayScript := preload("res://src/cards/card_play.gd")
const BattleStateScript := preload("res://src/combat/battle_state.gd")
const CombatantScript := preload("res://src/combat/combatant.gd")
const DeckScript := preload("res://src/cards/deck.gd")
const EventResolverScript := preload("res://src/run/event_resolver.gd")
const EventChoiceScript := preload("res://src/data/event_choice.gd")
const EventOutcomeScript := preload("res://src/data/event_outcome.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _cfg() -> BattleConfig:
	return _db.get_battle_config()


func _controller() -> RunController:
	var rc: RunController = RunControllerScript.new(_db)
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 7)
	return rc


func _run_for_pools(gold: int = 500) -> RunState:
	var run := RunStateScript.new()
	run.seed = 42
	run.act = 1
	run.party = [&"fighter", &"mage"] as Array[StringName]
	run.party_hp = {&"fighter": 10, &"mage": 8}
	run.skill_collections = {&"fighter": [], &"mage": []}
	run.active_loadouts = {&"fighter": [], &"mage": []}
	run.currency = gold
	return run


func _choice(kind: StringName, amount: int = 0, id: StringName = &"") -> EventChoice:
	var o := EventOutcomeScript.new()
	o.kind = kind
	o.amount = amount
	o.id = id
	var c := EventChoiceScript.new()
	c.outcomes = [o] as Array[EventOutcome]
	return c


# --- Data loads clean (new schema fields + validations vs real content) ------

func test_content_loads_clean_with_injected_layer() -> void:
	var result := _db.load_from_dir("res://data")
	assert_true(result.ok, "real /data loads with no errors: %s" % [result.errors])
	assert_eq(_db.get_card(&"wound").card_kind, &"curse", "curse kind parsed")
	assert_eq(_db.get_card(&"healing_draught").card_kind, &"consumable", "consumable kind parsed")
	assert_eq(_db.get_card(&"strike").card_kind, &"skill", "absent card_kind defaults to skill")
	assert_eq(_db.get_card(&"hex_mark").on_draw_damage, 2, "on_draw_damage parsed")
	assert_true(_db.get_card(&"wound").keywords.has(&"unplayable"), "curses are unplayable")


# --- derive_deck: displacement / swell / on-top / floor reduction ------------

func test_curses_displace_autofill_below_the_floor() -> void:
	var curses: Array[StringName] = [&"wound", &"doubt"]
	var deck := SkillLoadout.derive_deck([&"berserker_rampage"] as Array[StringName], _db, curses)
	assert_eq(deck.size(), _cfg().derived_deck_floor, "curses COUNT toward the floor — deck stays at it")
	assert_eq(deck.count(&"wound"), 1, "curse rides the deck")
	assert_eq(deck.count(&"doubt"), 1, "second curse rides the deck")
	var basics: int = deck.count(&"strike") + deck.count(&"defend")
	assert_eq(basics, _cfg().derived_deck_floor - 1 - 2, "each curse DISPLACED one fill basic")
	assert_lte(absi(deck.count(&"strike") - deck.count(&"defend")), 1, "alternation preserved for the remainder")


func test_curses_swell_the_deck_at_or_above_the_floor() -> void:
	var loadout: Array[StringName] = []
	for _i in range(7):
		loadout.append(&"shield_bash")  # 7 commons x 3 = 21 >= floor
	var deck := SkillLoadout.derive_deck(loadout, _db, [&"wound"] as Array[StringName])
	assert_eq(deck.size(), 22, "above the floor a curse adds on top (swell)")
	assert_eq(deck.count(&"defend"), 0, "no auto-fill appears above the floor")


func test_removing_a_curse_restores_a_basic() -> void:
	var with_curse := SkillLoadout.derive_deck([] as Array[StringName], _db, [&"wound"] as Array[StringName])
	var without := SkillLoadout.derive_deck([] as Array[StringName], _db)
	assert_eq(with_curse.size(), without.size(), "same floor either way")
	assert_eq(
		without.count(&"strike") + without.count(&"defend"),
		with_curse.count(&"strike") + with_curse.count(&"defend") + 1,
		"removal hands back one auto-fill basic — the value of the shop service"
	)


func test_consumables_inject_on_top_never_toward_the_floor() -> void:
	var items: Array[StringName] = [&"healing_draught", &"fire_bomb"]
	var deck := SkillLoadout.derive_deck([] as Array[StringName], _db, [] as Array[StringName], items)
	assert_eq(deck.size(), _cfg().derived_deck_floor + 2, "items ride ON TOP of the floor")
	var basics: int = deck.count(&"strike") + deck.count(&"defend")
	assert_eq(basics, _cfg().derived_deck_floor, "items displace NO fill basics")


func test_floor_reduction_lowers_the_floor_with_a_hard_min() -> void:
	var reduced := SkillLoadout.derive_deck([] as Array[StringName], _db, [] as Array[StringName], [] as Array[StringName], 4)
	assert_eq(reduced.size(), _cfg().derived_deck_floor - 4, "floor_reduction 4 -> 16-card fill")
	var floored := SkillLoadout.derive_deck([] as Array[StringName], _db, [] as Array[StringName], [] as Array[StringName], 100)
	assert_eq(floored.size(), _cfg().derived_deck_floor_min, "reduction clamps at derived_deck_floor_min")


func test_travel_light_relic_feeds_floor_reduction() -> void:
	var relic: RelicData = _db.get_relic(&"travel_light")
	assert_not_null(relic, "the proof relic exists")
	assert_eq(relic.effect, &"floor_reduction", "rare relic carries the new effect")
	assert_eq(RelicEngine.floor_reduction_total([relic]), 4, "engine sums the reduction")
	assert_eq(RelicEngine.floor_reduction_total([_db.get_relic(&"vital_idol"), relic]), 4, "other relics contribute 0")


# --- Reward pools: curses/consumables NEVER drafted ---------------------------

func test_injected_kinds_never_enter_reward_pools() -> void:
	var pool: Array[CardData] = CardReward.new(_db).eligible_pool(_run_for_pools())
	assert_gt(pool.size(), 0, "the pool is non-empty")
	for card in pool:
		assert_eq(card.card_kind, &"skill", "'%s' (kind %s) must not be draftable" % [card.id, card.card_kind])


# --- Unplayable curses + when-drawn damage ------------------------------------

func test_unplayable_curse_is_rejected_by_card_play() -> void:
	var rc := _controller()
	rc.run.curses_of(&"fighter").append(&"wound")
	var battle: EncounterBattle = rc.begin_combat(&"enc_combat_01")
	var unit: Combatant = battle.living_players()[0]
	var deck: Deck = battle.deck_of(unit)
	var wound: CardData = null
	for c in deck.draw_pile:
		if c.id == &"wound":
			wound = c
	assert_not_null(wound, "the inflicted curse rides the derived deck")
	deck.draw_pile.erase(wound)
	deck.hand.append(wound)
	var result: CardPlay.PlayResult = CardPlayScript.new(battle).play_card(unit, wound, unit)
	assert_false(result.ok, "a curse is a dead draw")
	assert_string_contains(result.reason, "unplayable", "rejection names the rule")
	assert_true(deck.hand.has(wound), "the dead card stays in hand")


func test_on_draw_damage_bites_the_drawing_unit() -> void:
	var battle: BattleState = BattleStateScript.new(_cfg(), DeckScript.new(_cfg()), _db.statuses)
	var unit: Combatant = CombatantScript.from_character(_db.get_character(&"fighter"))
	battle.add_combatant(unit)
	var deck: Deck = DeckScript.new(_cfg())
	deck.assemble_from_card_ids([&"hex_mark"] as Array[StringName], _db.cards)
	battle.decks[unit] = deck
	var hp0: int = unit.hp
	battle.start_player_turn()
	assert_eq(unit.hp, hp0 - 2, "drawing Hex Mark costs 2 HP")


# --- Enemy inflict_curse: in-combat + run persistence -------------------------

func test_enemy_inflicts_curse_into_discard_and_run() -> void:
	var rc := _controller()
	var battle: EncounterBattle = rc.begin_combat(&"enc_combat_01")
	var unit: Combatant = battle.living_players()[0]
	var enemy: Combatant = battle.living_enemies()[0]
	var eff := Effect.new()
	eff.type = &"inflict_curse"
	eff.params = {"card_id": "hex_mark"}
	battle.apply_effects(enemy, unit, [eff])
	var deck: Deck = battle.deck_of(unit)
	assert_eq(deck.discard_pile.size(), 1, "the curse joins THIS fight's cycle (discard)")
	assert_eq(deck.discard_pile[0].id, &"hex_mark", "the named curse card")
	assert_eq(battle.inflicted_curses.size(), 1, "infliction recorded for the run layer")
	rc.finish_combat(&"enc_combat_01", battle, 1)
	assert_true(rc.run.curses_of(&"fighter").has(&"hex_mark"), "finish_combat persists the curse onto the member")
	# And the NEXT fight derives it into the member's deck.
	var battle2: EncounterBattle = rc.begin_combat(&"enc_combat_01")
	var found: bool = false
	for c in battle2.deck_of(battle2.living_players()[0]).draw_pile:
		if c.id == &"hex_mark":
			found = true
	assert_true(found, "the curse rides every later derived deck until removed")


func test_inflict_curse_ignores_enemy_targets() -> void:
	var rc := _controller()
	var battle: EncounterBattle = rc.begin_combat(&"enc_combat_01")
	var enemy: Combatant = battle.living_enemies()[0]
	battle.inflict_curse(&"wound", enemy)
	assert_eq(battle.inflicted_curses.size(), 0, "curses are a player-side affliction")


# --- Consumables: exhaust + consume-from-inventory ----------------------------

func test_played_consumable_exhausts_and_leaves_the_inventory() -> void:
	var rc := _controller()
	rc.run.consumables.append(&"healing_draught")
	rc.run.consumables.append(&"healing_draught")
	var battle: EncounterBattle = rc.begin_combat(&"enc_combat_01")
	var unit: Combatant = battle.living_players()[0]
	var deck: Deck = battle.deck_of(unit)
	var draughts: Array[CardData] = []
	for c in deck.draw_pile:
		if c.id == &"healing_draught":
			draughts.append(c)
	assert_eq(draughts.size(), 2, "both inventory copies injected (first member's deck, on top)")
	deck.draw_pile.erase(draughts[0])
	deck.hand.append(draughts[0])
	unit.hp = maxi(1, unit.hp - 5)  # leave room so the heal is visible
	var result: CardPlay.PlayResult = CardPlayScript.new(battle).play_card(unit, draughts[0], unit)
	assert_true(result.ok, "a consumable is a normal playable card: %s" % result.reason)
	assert_true(deck.exhaust_pile.has(draughts[0]), "exhaust keyword routes it out of the cycle")
	assert_eq(battle.consumed_items, [&"healing_draught"] as Array[StringName], "play recorded for consumption")
	rc.finish_combat(&"enc_combat_01", battle, 1)
	assert_eq(rc.run.consumables.size(), 1, "ONE copy consumed; the unplayed copy persists")


func test_second_member_deck_carries_curses_not_items() -> void:
	var rc := _controller()
	rc.run.consumables.append(&"fire_bomb")
	rc.run.curses_of(&"mage").append(&"doubt")
	var battle: EncounterBattle = rc.begin_combat(&"enc_combat_01")
	var mage: Combatant = battle.living_players()[1]
	var has_doubt: bool = false
	var has_bomb: bool = false
	for c in battle.deck_of(mage).draw_pile:
		if c.id == &"doubt":
			has_doubt = true
		if c.id == &"fire_bomb":
			has_bomb = true
	assert_true(has_doubt, "the mage's own curse rides the mage's deck")
	assert_false(has_bomb, "party items inject into the FIRST member's deck only")


func test_gain_gold_banks_through_finish_combat() -> void:
	var rc := _controller()
	var before: int = rc.run.currency
	var battle: EncounterBattle = rc.begin_combat(&"enc_combat_01")
	battle.add_gold(25)
	rc.finish_combat(&"enc_combat_01", battle, 1)
	assert_eq(rc.run.currency, before + 25, "lucky-coin gold is credited post-fight")


func test_cleanse_strips_listed_statuses() -> void:
	var battle: BattleState = BattleStateScript.new(_cfg(), DeckScript.new(_cfg()), _db.statuses)
	var unit: Combatant = CombatantScript.from_character(_db.get_character(&"fighter"))
	battle.add_combatant(unit)
	unit.add_status_stacks(&"poison", 3)
	unit.add_status_stacks(&"burn", 2)
	unit.add_status_stacks(&"strength", 2)
	battle.cleanse(unit, ["poison", "burn", "bleed"])
	assert_eq(unit.status_stacks(&"poison"), 0, "poison cleansed")
	assert_eq(unit.status_stacks(&"burn"), 0, "burn cleansed")
	assert_eq(unit.status_stacks(&"strength"), 2, "unlisted statuses untouched")


# --- Shop: consumable stock + curse removal service ---------------------------

func test_shop_stocks_consumables_and_sells_them() -> void:
	var shop := Shop.new(_db)
	var run := _run_for_pools(500)
	var offer: Shop.ShopOffer = shop.build_offer(run, &"n_2_0")
	assert_eq(offer.consumable_ids.size(), 2, "two items on the shelf")
	var again: Shop.ShopOffer = shop.build_offer(_run_for_pools(500), &"n_2_0")
	assert_eq(offer.consumable_ids, again.consumable_ids, "stock is deterministic per node")
	var iid: StringName = offer.consumable_ids[0]
	var price: int = int(offer.prices.get(iid, 0))
	assert_gt(price, 0, "items are priced")
	assert_true(shop.buy_consumable(run, offer, iid), "purchase succeeds")
	assert_eq(run.currency, 500 - price, "gold deducted")
	assert_true(run.consumables.has(iid), "item joined the party inventory")
	assert_false(shop.buy_consumable(run, offer, iid), "sold-out slot refuses")


func test_shop_curse_removal_is_priced_and_targeted() -> void:
	var shop := Shop.new(_db)
	var run := _run_for_pools(500)
	run.curses_of(&"fighter").append(&"wound")
	run.curses_of(&"fighter").append(&"wound")
	var offer: Shop.ShopOffer = shop.build_offer(run, &"n_2_0")
	var price: int = int(offer.prices.get(&"__curse_removal", 0))
	assert_eq(price, _cfg().shop_price_curse_removal, "act-1 price = base knob")
	assert_true(shop.buy_curse_removal(run, offer, &"fighter", &"wound"), "removal succeeds")
	assert_eq(run.curses_of(&"fighter").size(), 1, "exactly ONE copy removed")
	assert_eq(run.currency, 500 - price, "service price deducted")
	assert_false(shop.buy_curse_removal(run, offer, &"mage", &"wound"), "wrong member refused (targeted removal)")
	assert_false(shop.buy_curse_removal(run, offer, &"fighter", &"doubt"), "absent curse refused")
	var broke := _run_for_pools(1)
	broke.curses_of(&"fighter").append(&"wound")
	assert_false(shop.buy_curse_removal(broke, shop.build_offer(broke, &"n_2_0"), &"fighter", &"wound"), "short gold refused")
	assert_eq(broke.curses_of(&"fighter").size(), 1, "no mutation on refusal")


func test_treasure_can_roll_a_consumable() -> void:
	var shop := Shop.new(_db)
	var found: bool = false
	for i in range(300):
		var run := _run_for_pools(0)
		run.relics = [] as Array[StringName]
		var loot: Dictionary = shop.treasure_roll(run, StringName("tnode_%d" % i))
		if loot.get("kind") == &"consumable":
			found = true
			var desc: String = shop.take_treasure(run, loot)
			assert_true(run.consumables.has(loot.get("id")), "taking it stocks the inventory")
			assert_string_contains(desc, "Item", "report names the item")
			break
	assert_true(found, "the consumable branch is reachable")


# --- Event ops -----------------------------------------------------------------

func test_event_add_curse_hits_the_first_member() -> void:
	var run := _run_for_pools()
	EventResolverScript.new(_db).apply(run, _choice(&"add_curse", 0, &"burden"))
	assert_true(run.curses_of(&"fighter").has(&"burden"), "the first member carries the event curse")
	assert_eq(run.curses_of(&"mage").size(), 0, "the second member is untouched")


func test_event_remove_curse_by_id_and_first_found() -> void:
	var run := _run_for_pools()
	run.curses_of(&"mage").append(&"doubt")
	run.curses_of(&"mage").append(&"wound")
	EventResolverScript.new(_db).apply(run, _choice(&"remove_curse", 0, &"wound"))
	assert_eq(run.curses_of(&"mage"), [&"doubt"] as Array[StringName], "named curse removed wherever it sits")
	EventResolverScript.new(_db).apply(run, _choice(&"remove_curse"))
	assert_eq(run.curses_of(&"mage").size(), 0, "empty id removes the first curse found")
	EventResolverScript.new(_db).apply(run, _choice(&"remove_curse"))
	assert_eq(run.curses_of(&"mage").size(), 0, "no curse anywhere -> no-op")


func test_event_add_consumable_stocks_the_inventory() -> void:
	var run := _run_for_pools()
	EventResolverScript.new(_db).apply(run, _choice(&"add_consumable", 0, &"healing_draught"))
	assert_eq(run.consumables, [&"healing_draught"] as Array[StringName], "item granted to the party")


func test_authored_curse_events_load_and_resolve() -> void:
	var shrine: EventData = _db.get_event(&"evt_cursed_shrine")
	assert_not_null(shrine, "the shrine still loads")
	var run := _run_for_pools()
	EventResolverScript.new(_db).apply_choice_index(run, shrine, 0)
	assert_true(run.curses_of(&"fighter").has(&"burden"), "the shrine now grants its curse properly")
	assert_true(run.relics.has(&"shrine_blessing"), "and its relic")
	var cache: EventData = _db.get_event(&"evt_peddlers_cache")
	assert_not_null(cache, "the peddler's cache loads")
	var run2 := _run_for_pools()
	EventResolverScript.new(_db).apply_choice_index(run2, cache, 0)
	assert_eq(run2.consumables.size(), 2, "the cache grants two items")


# --- Save round-trip -----------------------------------------------------------

func test_curses_and_consumables_survive_a_save_round_trip() -> void:
	var run := _run_for_pools()
	run.curses_of(&"fighter").append(&"wound")
	run.curses_of(&"mage").append(&"hex_mark")
	run.consumables.append(&"healing_draught")
	run.consumables.append(&"healing_draught")
	var restored: RunState = RunStateScript.from_dict(run.to_dict())
	assert_eq(restored.curses_of(&"fighter"), [&"wound"] as Array[StringName], "fighter's curse round-trips")
	assert_eq(restored.curses_of(&"mage"), [&"hex_mark"] as Array[StringName], "mage's curse round-trips")
	assert_eq(restored.consumables, [&"healing_draught", &"healing_draught"] as Array[StringName], "inventory (with duplicates) round-trips")
	var legacy: RunState = RunStateScript.from_dict({"seed": 1, "party": ["fighter"]})
	assert_eq(legacy.consumables.size(), 0, "old saves without the keys still load")
	assert_eq(legacy.curses_of(&"fighter").size(), 0, "missing curse map defaults empty")
