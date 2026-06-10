extends "res://addons/gut/test.gd"
## Shop + treasure economy (ADR-0023): offers are deterministic per node, prices
## scale by rarity and act, purchases deduct gold and grant skills/relics/heals,
## and short gold never mutates anything.

const ContentDatabaseScript := preload("res://src/data/content_database.gd")
const RunStateScript := preload("res://src/run/run_state.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _run(gold: int = 500) -> RunState:
	var run := RunStateScript.new()
	run.seed = 99
	run.act = 1
	run.party = [&"fighter", &"mage"] as Array[StringName]
	run.party_hp = {&"fighter": 3, &"mage": 2}
	run.skill_collections = {&"fighter": [], &"mage": []}
	run.active_loadouts = {&"fighter": [], &"mage": []}
	run.currency = gold
	return run


func test_offer_is_deterministic_and_priced() -> void:
	var shop := Shop.new(_db)
	var a: Shop.ShopOffer = shop.build_offer(_run(), &"n_3_1")
	var b: Shop.ShopOffer = shop.build_offer(_run(), &"n_3_1")
	assert_eq(a.skill_ids, b.skill_ids, "same run seed + node id -> same stock")
	assert_eq(a.skill_ids.size(), 3, "three skills on the shelf")
	assert_ne(a.relic_id, &"", "a relic is offered while un-owned relics remain")
	for cid in a.skill_ids:
		assert_gt(int(a.prices.get(cid, 0)), 0, "every skill is priced")
	assert_gt(int(a.prices.get(&"__heal", 0)), 0, "the heal service is priced")


func test_prices_scale_with_act_depth() -> void:
	var shop := Shop.new(_db)
	var card: CardData = _db.get_card(&"quick_stab")  # common
	var p1: int = shop.skill_price(card, 1)
	var p10: int = shop.skill_price(card, 10)
	assert_eq(p1, _db.get_battle_config().shop_price_common, "act 1 = base price")
	assert_gt(p10, p1, "deeper merchants charge more")


func test_buy_skill_deducts_and_grants() -> void:
	var shop := Shop.new(_db)
	var run := _run(500)
	var offer: Shop.ShopOffer = shop.build_offer(run, &"n_2_0")
	var cid: StringName = offer.skill_ids[0]
	var price: int = int(offer.prices.get(cid, 0))
	assert_true(shop.buy_skill(run, offer, cid), "purchase succeeds with enough gold")
	assert_eq(run.currency, 500 - price, "gold deducted")
	var owned: bool = false
	for member in run.party:
		if (run.skill_collections[member] as Array).has(cid):
			owned = true
	assert_true(owned, "the skill joined a member's collection")
	assert_false(offer.skill_ids.has(cid), "the shelf slot sold out")
	assert_false(shop.buy_skill(run, offer, cid), "sold-out slot cannot be re-bought")


func test_buy_refused_when_gold_short() -> void:
	var shop := Shop.new(_db)
	var run := _run(1)
	var offer: Shop.ShopOffer = shop.build_offer(run, &"n_2_0")
	assert_false(shop.buy_skill(run, offer, offer.skill_ids[0]), "skill refused")
	assert_false(shop.buy_relic(run, offer), "relic refused")
	assert_false(shop.buy_heal(run, offer), "heal refused")
	assert_eq(run.currency, 1, "no gold was taken")
	assert_eq((run.skill_collections[&"fighter"] as Array).size(), 0, "nothing granted")
	assert_true(run.relics.is_empty(), "no relic granted")


func test_buy_relic_and_heal() -> void:
	var shop := Shop.new(_db)
	var run := _run(500)
	var offer: Shop.ShopOffer = shop.build_offer(run, &"n_2_0")
	var rid: StringName = offer.relic_id
	assert_true(shop.buy_relic(run, offer), "relic purchase succeeds")
	assert_true(run.relics.has(rid), "relic owned")
	assert_eq(offer.relic_id, &"", "relic shelf sold out")

	var before_f: int = int(run.party_hp[&"fighter"])
	assert_true(shop.buy_heal(run, offer), "heal purchase succeeds")
	assert_gt(int(run.party_hp[&"fighter"]), before_f, "the party was healed")
	var cap: int = PartyStats.effective_max_hp(_db, run, &"fighter")
	assert_lte(int(run.party_hp[&"fighter"]), cap, "heal caps at effective max")


func test_treasure_roll_is_deterministic_and_takeable() -> void:
	var shop := Shop.new(_db)
	var run := _run(0)
	var a: Dictionary = shop.treasure_roll(run, &"n_5_2")
	var b: Dictionary = shop.treasure_roll(run, &"n_5_2")
	assert_eq(a, b, "same node -> same loot")
	var desc: String = shop.take_treasure(run, a)
	assert_ne(desc, "", "taking treasure reports what was gained")
	match a.get("kind"):
		&"gold":
			assert_eq(run.currency, int(a.get("amount", 0)), "gold pile banked")
		&"relic":
			assert_true(run.relics.has(a.get("id")), "relic granted")
		&"skill":
			var owned: bool = false
			for member in run.party:
				if (run.skill_collections[member] as Array).has(a.get("id")):
					owned = true
			assert_true(owned, "skill granted")


# --- Rarity-weighted relic rolls (M3 pool hygiene) ---------------------------

func _rarity_of(rid: StringName) -> StringName:
	var relic: RelicData = _db.get_relic(rid)
	return relic.rarity if relic != null else &""


func test_weighted_relic_pick_is_deterministic_and_in_pool() -> void:
	var run := _run(0)
	var shop := Shop.new(_db)
	var pool: Array[StringName] = shop._available_relics(run)
	assert_gt(pool.size(), 0, "un-owned relics exist")
	var a := RandomNumberGenerator.new()
	a.seed = 12345
	var b := RandomNumberGenerator.new()
	b.seed = 12345
	var pick_a: StringName = Shop.weighted_relic_pick(_db, pool, a)
	var pick_b: StringName = Shop.weighted_relic_pick(_db, pool, b)
	assert_eq(pick_a, pick_b, "same rng state -> same pick")
	assert_has(pool, pick_a, "the pick comes from the pool")
	assert_ne(_rarity_of(pick_a), &"boss", "boss relics never roll (Sponsor Box only)")


func test_weighted_relic_pick_distribution_favors_commons() -> void:
	# Sanity, not statistics: with weights 50/35/15 a rarity BUCKET is chosen
	# first, so commons must out-roll rares over many seeds even though the
	# authored relic spread is rare-heavy (7c/15u/10r) — the uniform pick this
	# replaced rolled rares more often than commons.
	var run := _run(0)
	var shop := Shop.new(_db)
	var pool: Array[StringName] = shop._available_relics(run)
	var counts: Dictionary = {&"common": 0, &"uncommon": 0, &"rare": 0}
	var rng := RandomNumberGenerator.new()
	for i: int in 600:
		rng.seed = 1000 + i
		var rid: StringName = Shop.weighted_relic_pick(_db, pool, rng)
		var rarity: StringName = _rarity_of(rid)
		counts[rarity] = int(counts.get(rarity, 0)) + 1
	assert_gt(int(counts[&"common"]), int(counts[&"rare"]),
		"commons out-roll rares: %s" % str(counts))
	assert_gt(int(counts[&"common"]), 0, "commons roll at all")
	assert_gt(int(counts[&"rare"]), 0, "rares still roll (weight 15, not 0)")


func test_weighted_relic_pick_empty_pool_returns_nothing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var empty: Array[StringName] = []
	assert_eq(Shop.weighted_relic_pick(_db, empty, rng), &"", "empty pool -> &\"\"")


func test_run_controller_roll_relic_is_weighted_and_unowned() -> void:
	var rc := RunController.new(_db)
	rc.start_run([&"fighter"] as Array[StringName], 7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var rid: StringName = rc.roll_relic(rng)
	assert_ne(rid, &"", "a relic rolls while the pool is non-empty")
	assert_false(rc.run.relics.has(rid), "the roll never offers an owned relic")
	assert_ne(_rarity_of(rid), &"boss", "boss rarity stays Sponsor-Box-only")
