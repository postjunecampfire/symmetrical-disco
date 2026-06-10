extends "res://addons/gut/test.gd"
## M3 relic run-layer effects: derivation modifiers through derive_deck
## (extra_copy_rare / extra_copy_first / upgrade_basics), the shop economy
## (shop_discount / curse_removal_discount / gold_pile_bonus), gold_on_win /
## gold_on_rest through RunController, and the boss-rarity pool gate.

const ContentDatabaseScript := preload("res://src/data/content_database.gd")
const RunControllerScript := preload("res://src/run/run_controller.gd")
const RunStateScript := preload("res://src/run/run_state.gd")

var _db: ContentDatabase


# One db load per script (before_all, not before_each): nothing here mutates the
# database, and the per-test load was the suite's whole runtime.
func before_all() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _run(gold: int = 500) -> RunState:
	var run := RunStateScript.new()
	run.seed = 99
	run.act = 1
	run.party = [&"fighter", &"mage"] as Array[StringName]
	run.party_hp = {&"fighter": 10, &"mage": 8}
	run.skill_collections = {&"fighter": [], &"mage": []}
	run.active_loadouts = {&"fighter": [], &"mage": []}
	run.currency = gold
	return run


func _count(deck: Array[StringName], id: StringName) -> int:
	var n: int = 0
	for entry in deck:
		if entry == id:
			n += 1
	return n


## The first loaded RARE skill card (derivation fixtures shouldn't hardcode ids).
func _a_rare_skill() -> StringName:
	var ids: Array[StringName] = []
	for key: Variant in _db.cards.keys():
		ids.append(StringName(String(key)))
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id in ids:
		var card: CardData = _db.cards[id]
		if card.rarity == &"rare" and card.card_kind == &"skill" and card.upgrade_of == &"":
			return id
	return &""


# --- Derivation modifiers (through derive_deck) --------------------------------

func test_extra_copy_rare_adds_a_rare_copy() -> void:
	var rare: StringName = _a_rare_skill()
	assert_ne(rare, &"", "a rare skill exists in /data")
	var cfg: BattleConfig = _db.get_battle_config()
	var base: Array[StringName] = SkillLoadout.derive_deck([rare] as Array[StringName], _db)
	var boosted: Array[StringName] = SkillLoadout.derive_deck(
		[rare] as Array[StringName], _db, [], [], 0, 1, 0, false
	)
	assert_eq(_count(base, rare), cfg.copies_rare, "baseline rare copies")
	assert_eq(_count(boosted, rare), cfg.copies_rare + 1, "extra_copy_rare adds one")
	var common_deck: Array[StringName] = SkillLoadout.derive_deck(
		[&"quick_stab"] as Array[StringName], _db, [], [], 0, 1, 0, false
	)
	assert_eq(
		_count(common_deck, &"quick_stab"),
		cfg.copies_common,
		"a common skill is untouched by the rare bonus"
	)


func test_extra_copy_first_boosts_only_the_first_active_skill() -> void:
	var cfg: BattleConfig = _db.get_battle_config()
	var deck: Array[StringName] = SkillLoadout.derive_deck(
		[&"quick_stab", &"arcane_bolt"] as Array[StringName], _db, [], [], 0, 0, 1, false
	)
	assert_eq(_count(deck, &"quick_stab"), cfg.copies_common + 1, "first skill +1 copy")
	assert_eq(_count(deck, &"arcane_bolt"), cfg.copies_common, "second skill unchanged")


func test_upgrade_basics_fills_with_plus_variants() -> void:
	var deck: Array[StringName] = SkillLoadout.derive_deck(
		[] as Array[StringName], _db, [], [], 0, 0, 0, true
	)
	assert_gt(_count(deck, &"strike_plus"), 0, "auto-fill uses Strike+")
	assert_gt(_count(deck, &"defend_plus"), 0, "auto-fill uses Defend+")
	assert_eq(_count(deck, &"strike"), 0, "no base Strikes remain")
	assert_eq(_count(deck, &"defend"), 0, "no base Defends remain")
	assert_eq(deck.size(), _db.get_battle_config().derived_deck_floor, "floor unchanged")


func test_upgraded_basics_never_appear_in_drafts() -> void:
	var run := _run()
	var pool: Array[CardData] = CardReward.new(_db, {}).eligible_pool(run)
	for card in pool:
		assert_ne(card.id, &"strike_plus", "Strike+ is upgrade-only, not draftable")
		assert_ne(card.id, &"defend_plus", "Defend+ is upgrade-only, not draftable")


func test_run_controller_derives_with_relic_modifiers() -> void:
	var controller := RunControllerScript.new(_db)
	controller.start_run([&"fighter"] as Array[StringName], 7)
	controller.run.relics.append(&"drill_sergeants_whistle")
	var battle: EncounterBattle = controller.begin_combat(&"enc_combat_01")
	assert_not_null(battle, "fight assembled")
	var unit: Combatant = battle.living_players()[0]
	var deck: Deck = battle.deck_of(unit)
	var found_plus: bool = false
	for pile: Variant in [deck.draw_pile, deck.hand, deck.discard_pile]:
		for card: CardData in pile:
			if card.id == &"strike_plus" or card.id == &"defend_plus":
				found_plus = true
	assert_true(found_plus, "the whistle's upgraded basics reached the assembled deck")


# --- Shop economy ---------------------------------------------------------------

func test_shop_discount_lowers_every_price() -> void:
	var shop := Shop.new(_db)
	var plain: Shop.ShopOffer = shop.build_offer(_run(), &"n_3_1")
	var run := _run()
	run.relics.append(&"haggling_charm")  # 20% off
	var cut: Shop.ShopOffer = shop.build_offer(run, &"n_3_1")
	assert_eq(plain.skill_ids, cut.skill_ids, "same stock either way")
	var compared: int = 0
	for key: Variant in plain.prices.keys():
		# The relic slot's id can differ (the owned relic left the pool) — every
		# shared key (skills, consumables, heal, curse removal) must be 20% off.
		if not cut.prices.has(key):
			continue
		var expected: int = maxi(1, int(plain.prices[key]) * 80 / 100)
		assert_eq(int(cut.prices[key]), expected, "20%% off '%s'" % [key])
		compared += 1
	assert_gte(compared, 5, "skills + consumables + heal + curse removal compared")


func test_curse_removal_discount_stacks_on_shop_discount() -> void:
	var shop := Shop.new(_db)
	var run := _run()
	run.relics.append(&"haggling_charm")      # 20% everything
	run.relics.append(&"hexbreaker_seal")     # then 50% off removal
	var offer: Shop.ShopOffer = shop.build_offer(run, &"n_3_1")
	var base: int = int(shop.build_offer(_run(), &"n_3_1").prices[&"__curse_removal"])
	var expected: int = maxi(1, maxi(1, base * 80 / 100) * 50 / 100)
	assert_eq(int(offer.prices[&"__curse_removal"]), expected, "both discounts applied in order")


func test_gold_pile_bonus_grows_treasure_gold() -> void:
	var shop := Shop.new(_db)
	var cfg: BattleConfig = _db.get_battle_config()
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 41
	var plain: int = shop._gold_pile(_run(), rng_a, cfg)
	var run := _run()
	run.relics.append(&"golden_pickaxe")  # +50%
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 41
	var boosted: int = shop._gold_pile(run, rng_b, cfg)
	assert_eq(boosted, plain + plain * 50 / 100, "the pile grew by the relic percentage")


# --- RunController economy + pool gating -----------------------------------------

func test_gold_on_win_pays_after_a_won_combat() -> void:
	var controller := RunControllerScript.new(_db)
	controller.start_run([&"fighter", &"mage"] as Array[StringName], 7)
	controller.run.relics.append(&"lucky_horseshoe")  # +8 gold per win
	var battle: EncounterBattle = controller.begin_combat(&"enc_combat_01")
	for enemy in battle.living_enemies():
		battle.deal_unblockable(enemy, 9999)
	var before: int = controller.run.currency
	var outcome: int = controller.finish_combat(&"enc_combat_01", battle, 1)
	assert_eq(outcome, BattleState.Outcome.WIN, "the fight was won")
	assert_eq(controller.run.currency, before + 8, "gold_on_win paid out")


func test_gold_on_rest_pays_at_a_rest() -> void:
	var controller := RunControllerScript.new(_db)
	controller.start_run([&"fighter"] as Array[StringName], 7)
	controller.run.relics.append(&"innkeepers_tab")  # +12 gold per rest
	var before: int = controller.run.currency
	assert_true(controller.resolve_rest(&"heal"), "the rest resolved")
	assert_eq(controller.run.currency, before + 12, "gold_on_rest paid out")


func test_boss_rarity_relics_only_from_the_sponsor_box() -> void:
	var controller := RunControllerScript.new(_db)
	controller.start_run([&"fighter"] as Array[StringName], 7)
	var pool: Array[StringName] = controller.available_relics()
	assert_false(pool.is_empty(), "the elite/shop/treasure pool is populated")
	for rid in pool:
		assert_ne(
			_db.get_relic(rid).rarity, &"boss",
			"'%s' must not reach elite/shop/treasure rolls" % rid
		)
	assert_true(pool.has(&"lucky_horseshoe"), "non-boss relics remain available")
	# The shop pool applies the same gate.
	var shop := Shop.new(_db)
	var offer: Shop.ShopOffer = shop.build_offer(_run(), &"n_3_1")
	assert_ne(offer.relic_id, &"", "the shop still stocks a relic")
	assert_ne(_db.get_relic(offer.relic_id).rarity, &"boss", "and it is never boss-rarity")
