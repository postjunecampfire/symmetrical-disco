class_name Shop
extends RefCounted
## The merchant + treasure services (ADR-0023): what run currency ("Gold") is
## FOR. A shop node offers 3 skills (drafted from the party-eligible pool, same
## rarity weighting as card rewards), 1 not-yet-owned relic, 1–2 consumable item
## cards, a party heal, and a "remove a curse" service (ADR-0029) — priced from
## BattleConfig and scaled by act depth. A treasure node grants one of relic /
## consumable / gold pile / skill, rolled deterministically per node.
##
## Pure run-layer logic (RunState + ContentDatabase in, mutations out), so the
## whole economy is GUT-testable without UI. The map screen is just buttons.

## One assembled shop inventory. `skill_ids`/`relic_id`/`consumable_ids` empty
## out as they sell.
class ShopOffer extends RefCounted:
	var skill_ids: Array[StringName] = []
	var relic_id: StringName = &""
	## Consumable item cards on the shelf (ADR-0029): 1–2 per stock.
	var consumable_ids: Array[StringName] = []
	## id (skill / relic / consumable) -> price in gold. Heal price under
	## &"__heal"; curse-removal service price under &"__curse_removal".
	var prices: Dictionary = {}


var _db: ContentDatabase


func _init(db: ContentDatabase) -> void:
	_db = db


## Rarity-weighted relic roll (M3 pool hygiene): pick a rarity bucket by the
## BattleConfig relic_weight_* knobs (only buckets that still have un-owned
## relics count), then uniform within the bucket. Replaces the uniform pick on
## elite/treasure rolls — with a rare-heavy relic spread a uniform roll handed
## out rares as often as commons. Deterministic for a given rng state; falls
## back to a uniform pick if every represented rarity weighs 0 (a roll never
## stalls). The shop SHELF stays a uniform pick: it already prices by rarity.
static func weighted_relic_pick(
	db: ContentDatabase, pool: Array[StringName], rng: RandomNumberGenerator
) -> StringName:
	if pool.is_empty():
		return &""
	var cfg: BattleConfig = db.get_battle_config()
	# Fixed rarity order keeps the roll deterministic regardless of Dictionary
	# iteration; pool arrives sorted, so buckets are stable too.
	var order: Array[StringName] = [&"common", &"uncommon", &"rare"]
	var weights: Dictionary = {
		&"common": cfg.relic_weight_common,
		&"uncommon": cfg.relic_weight_uncommon,
		&"rare": cfg.relic_weight_rare,
	}
	var buckets: Dictionary = {}  # rarity -> Array[StringName]
	for rid: StringName in pool:
		var relic: RelicData = db.get_relic(rid)
		var rarity: StringName = relic.rarity if relic != null else &"common"
		if not buckets.has(rarity):
			var empty: Array[StringName] = []
			buckets[rarity] = empty
		(buckets[rarity] as Array[StringName]).append(rid)
	var total: int = 0
	for rarity: StringName in order:
		if buckets.has(rarity):
			total += int(weights[rarity])
	if total <= 0:
		return pool[rng.randi_range(0, pool.size() - 1)]
	var roll: int = rng.randi_range(0, total - 1)
	var acc: int = 0
	for rarity: StringName in order:
		if not buckets.has(rarity):
			continue
		acc += int(weights[rarity])
		if roll < acc:
			var bucket: Array[StringName] = buckets[rarity]
			return bucket[rng.randi_range(0, bucket.size() - 1)]
	return pool[rng.randi_range(0, pool.size() - 1)]


## The act-scaled price for one skill card (by rarity) in `act`.
func skill_price(card: CardData, act: int) -> int:
	var cfg: BattleConfig = _db.get_battle_config()
	var base: int = cfg.shop_price_common
	if card != null and card.rarity == &"uncommon":
		base = cfg.shop_price_uncommon
	elif card != null and card.rarity == &"rare":
		base = cfg.shop_price_rare
	return _scaled(base, act)


## Assemble the inventory for a shop node: 3 eligible skills (seeded by run seed
## + node id, so a resume re-offers the same stock), one not-yet-owned relic
## (seeded pick — with a ~35-relic pool the old "first alphabetically" stock
## was degenerate), and the heal service price. M3 economy relics then discount
## the whole shelf (shop_discount, capped) and the curse-removal service
## additionally (curse_removal_discount).
func build_offer(run: RunState, node_id: StringName) -> ShopOffer:
	var offer := ShopOffer.new()
	var reward := CardReward.new(_db, CardReward.weights_for_act(run.act))
	var stock: Array[CardData] = reward.draft(run, 3, run.seed ^ hash(node_id))
	for card in stock:
		offer.skill_ids.append(card.id)
		offer.prices[card.id] = skill_price(card, run.act)
	var relic_pool: Array[StringName] = _available_relics(run)
	if not relic_pool.is_empty():
		var relic_rng := RandomNumberGenerator.new()
		relic_rng.seed = run.seed ^ hash(node_id) ^ 0x4E11C
		var rid: StringName = relic_pool[relic_rng.randi_range(0, relic_pool.size() - 1)]
		offer.relic_id = rid
		offer.prices[rid] = _scaled(_db.get_battle_config().shop_price_relic, run.act)
	# Consumables (ADR-0029): up to 2 distinct items, seeded like the skill stock.
	var pool: Array[StringName] = _consumable_pool()
	var rng := RandomNumberGenerator.new()
	rng.seed = run.seed ^ hash(node_id) ^ 0x5EED
	while not pool.is_empty() and offer.consumable_ids.size() < 2:
		var iid: StringName = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		offer.consumable_ids.append(iid)
		offer.prices[iid] = _scaled(_db.get_battle_config().shop_price_consumable, run.act)
	offer.prices[&"__heal"] = _scaled(_db.get_battle_config().shop_price_heal, run.act)
	# "Remove a curse" service (ADR-0029): StS-style removal returns ONLY for
	# curses — loadout deactivation stays the free knob for skills.
	offer.prices[&"__curse_removal"] = _scaled(
		_db.get_battle_config().shop_price_curse_removal, run.act
	)
	# M3 economy relics: shop_discount lowers EVERY price on the shelf (summed
	# across relics, capped in RelicEngine); curse_removal_discount stacks on the
	# removal service afterwards. Floors at 1 gold — nothing is ever free.
	var relics: Array[RelicData] = _run_relics(run)
	var discount: int = RelicEngine.shop_discount_percent(relics)
	if discount > 0:
		for key: Variant in offer.prices.keys():
			offer.prices[key] = maxi(1, int(offer.prices[key]) * (100 - discount) / 100)
	var curse_discount: int = RelicEngine.curse_removal_discount_percent(relics)
	if curse_discount > 0:
		offer.prices[&"__curse_removal"] = maxi(
			1, int(offer.prices[&"__curse_removal"]) * (100 - curse_discount) / 100
		)
	return offer


## Buy a skill: deducts gold and grants it into the owner's collection (tagged
## cards -> their owner, neutral -> first member; same rule as card rewards).
## Returns false (no mutation) if gold is short or the id isn't in the offer.
func buy_skill(run: RunState, offer: ShopOffer, card_id: StringName) -> bool:
	if not offer.skill_ids.has(card_id):
		return false
	var price: int = int(offer.prices.get(card_id, 0))
	if run.currency < price:
		return false
	var reward := CardReward.new(_db, {})
	if not reward.pick(run, card_id):
		return false
	run.currency -= price
	offer.skill_ids.erase(card_id)
	return true


## Buy a consumable item card (ADR-0029): deducts gold, appends it to the party
## inventory (RunState.consumables — it rides the next derived deck on top of
## the floor). Returns false if gold is short or the id isn't on the shelf.
func buy_consumable(run: RunState, offer: ShopOffer, item_id: StringName) -> bool:
	if not offer.consumable_ids.has(item_id):
		return false
	var price: int = int(offer.prices.get(item_id, 0))
	if run.currency < price:
		return false
	run.consumables.append(item_id)
	run.currency -= price
	offer.consumable_ids.erase(item_id)
	return true


## Buy a curse removal (ADR-0029): deducts the service price and removes ONE
## copy of `curse_id` from `member`'s curse list — the removal restores one
## auto-fill basic in their derived deck. Returns false (no mutation) if gold is
## short or the member doesn't carry that curse. Repeatable while curses and
## gold last (each purchase removes one curse).
func buy_curse_removal(
	run: RunState, offer: ShopOffer, member: StringName, curse_id: StringName
) -> bool:
	var price: int = int(offer.prices.get(&"__curse_removal", 0))
	if run.currency < price:
		return false
	var curses: Array[StringName] = run.curses_of(member)
	var idx: int = curses.find(curse_id)
	if idx == -1:
		return false
	curses.remove_at(idx)
	run.currency -= price
	return true


## Buy the offered relic. Returns false if gold is short / already sold.
func buy_relic(run: RunState, offer: ShopOffer) -> bool:
	if offer.relic_id == &"":
		return false
	var price: int = int(offer.prices.get(offer.relic_id, 0))
	if run.currency < price:
		return false
	run.relics.append(offer.relic_id)
	run.currency -= price
	offer.relic_id = &""
	return true


## Buy the heal service: every living member heals by rest_heal (capped at their
## effective max, like a rest). Returns false if gold is short.
func buy_heal(run: RunState, offer: ShopOffer) -> bool:
	var price: int = int(offer.prices.get(&"__heal", 0))
	if run.currency < price:
		return false
	var amount: int = _db.get_battle_config().rest_heal
	for cid in run.party:
		var hp: int = int(run.party_hp.get(cid, 0))
		if hp <= 0:
			continue  # downed members are not healed (matches rest semantics)
		var cap: int = PartyStats.effective_max_hp(_db, run, cid)
		run.party_hp[cid] = maxi(hp, mini(hp + amount, cap))
	run.currency -= price
	return true


# --- Treasure (ADR-0023) ------------------------------------------------------

## What a treasure node contains: {"kind": &"relic"|&"consumable"|&"gold"|
## &"skill", "id": ..., "amount": int}. Deterministic per node. Relic is
## preferred while un-owned relics remain; a consumable item can roll next
## (ADR-0029); otherwise gold and skills alternate.
func treasure_roll(run: RunState, node_id: StringName) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = run.seed ^ hash(node_id)
	var cfg: BattleConfig = _db.get_battle_config()
	var relics: Array[StringName] = _available_relics(run)
	var roll: float = rng.randf()
	if not relics.is_empty() and roll < 0.4:
		# M3 pool hygiene: treasure relics roll rarity-weighted, not uniform.
		return {"kind": &"relic", "id": weighted_relic_pick(_db, relics, rng), "amount": 0}
	var items: Array[StringName] = _consumable_pool()
	if not items.is_empty() and roll < 0.55:
		return {"kind": &"consumable", "id": items[rng.randi_range(0, items.size() - 1)], "amount": 0}
	if roll < 0.8 or run.party.is_empty():
		return {"kind": &"gold", "id": &"", "amount": _gold_pile(run, rng, cfg)}
	var reward := CardReward.new(_db, {})
	var stock: Array[CardData] = reward.draft(run, 1, run.seed ^ hash(node_id))
	if stock.is_empty():
		return {"kind": &"gold", "id": &"", "amount": _gold_pile(run, rng, cfg)}
	return {"kind": &"skill", "id": stock[0].id, "amount": 0}


## One treasure gold pile: the configured range, then the M3 gold_pile_bonus
## relic percentage on top ("+X% gold piles").
func _gold_pile(run: RunState, rng: RandomNumberGenerator, cfg: BattleConfig) -> int:
	var amount: int = rng.randi_range(cfg.treasure_gold_min, cfg.treasure_gold_max)
	var bonus: int = RelicEngine.gold_pile_bonus_percent(_run_relics(run))
	return amount + amount * bonus / 100


## Apply a treasure_roll result to the run. Returns a short human description.
func take_treasure(run: RunState, loot: Dictionary) -> String:
	match loot.get("kind"):
		&"relic":
			var rid: StringName = loot.get("id", &"")
			run.relics.append(rid)
			var relic: RelicData = _db.get_relic(rid)
			return "Relic: %s" % (relic.display_name if relic != null else String(rid))
		&"skill":
			var cid: StringName = loot.get("id", &"")
			CardReward.new(_db, {}).pick(run, cid)
			var card: CardData = _db.get_card(cid)
			return "Skill: %s" % (card.display_name if card != null else String(cid))
		&"consumable":
			var iid: StringName = loot.get("id", &"")
			run.consumables.append(iid)
			var item: CardData = _db.get_card(iid)
			return "Item: %s" % (item.display_name if item != null else String(iid))
		_:
			var amount: int = int(loot.get("amount", 0))
			run.currency += amount
			return "%d Gold" % amount


# --- Internals -----------------------------------------------------------------

func _scaled(base: int, act: int) -> int:
	var cfg: BattleConfig = _db.get_battle_config()
	return maxi(1, int(round(base * (1.0 + cfg.shop_act_scale * float(maxi(1, act) - 1)))))


## Every consumable item card id (card_kind == "consumable"), sorted for
## determinism (ADR-0029). Items are not gated by class/party — they're gear.
func _consumable_pool() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in _db.cards.keys():
		var card: CardData = _db.cards[key]
		if card != null and card.card_kind == &"consumable":
			out.append(card.id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## Relic ids the run does not own yet, sorted for determinism. BOSS-rarity
## relics never reach a shop shelf or treasure chest — they arrive only via the
## act-boss Sponsor Box (ADR-0028), mirroring RunController.available_relics.
func _available_relics(run: RunState) -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in _db.relics.keys():
		var rid := StringName(String(key))
		if run.relics.has(rid):
			continue
		var relic: RelicData = _db.get_relic(rid)
		if relic != null and relic.rarity == &"boss":
			continue
		out.append(rid)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## The run's owned relics resolved to RelicData (unknown ids skipped) — the list
## the M3 economy queries (discounts / gold pile bonus) read.
func _run_relics(run: RunState) -> Array[RelicData]:
	var out: Array[RelicData] = []
	for rid in run.relics:
		var relic: RelicData = _db.get_relic(rid)
		if relic != null:
			out.append(relic)
	return out
