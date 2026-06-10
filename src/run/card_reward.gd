class_name CardReward
extends RefCounted
## Card-reward draft + card pool for the run layer (run-structure.md §6).
##
## After a combat, the player is offered a pick-1-of-N draft drawn from the
## character-tagged card pool: every non-innate card whose `character_tag`
## matches a party character id, plus cards tagged `neutral`. Innate cards
## (strike/defend) and within-offer duplicates are excluded.
##
## The draft is seeded (deterministic: same seed -> same offer) and optionally
## rarity-weighted. The chosen card id joins a member's SKILL COLLECTION via
## pick(); skip() takes nothing.
##
## Usage:
##   var reward := CardReward.new(db)            # db = ContentDatabase OR a
##                                               #   Dictionary card_id -> CardData
##   var offer: Array[CardData] = reward.draft(run_state, 3, run_state.seed)
##   reward.pick(run_state, offer[0].id)         # or reward.skip(run_state)
##
## The registry argument is normalized once in _init(): a ContentDatabase
## contributes its `cards` registry; a plain Dictionary is used directly.

## Reserved character_tag meaning "any unit can play" (data-schemas.md §3).
const NEUTRAL_TAG: StringName = &"neutral"

## Default number of options offered (run-structure.md §6, v1 default).
const DEFAULT_CHOICES: int = 3

## card_id (StringName) -> CardData. Normalized in _init().
var _cards: Dictionary = {}

## rarity (StringName) -> weight (number). Empty == uniform odds. When non-empty,
## a rarity absent from this map weighs 0; if that would make every available
## card weigh 0, selection falls back to uniform so a draft never stalls.
var _rarity_weights: Dictionary = {}


## ADR-0020 reward pools: rarity weights shift A -> B -> C with depth. Tier 1
## drafts are all-common (the classless origin pool); rares only weigh in from
## tier 2 and climb toward the deep game.
static func weights_for_act(act: int) -> Dictionary:
	var tier: int = clampi((maxi(1, act) - 1) / 3 + 1, 1, 6)
	match tier:
		1: return {&"common": 8, &"uncommon": 2, &"rare": 0}
		2: return {&"common": 6, &"uncommon": 3, &"rare": 1}
		3: return {&"common": 5, &"uncommon": 4, &"rare": 1}
		4: return {&"common": 4, &"uncommon": 4, &"rare": 2}
		5: return {&"common": 3, &"uncommon": 4, &"rare": 3}
		_: return {&"common": 2, &"uncommon": 4, &"rare": 4}


## card_registry is either a ContentDatabase or a Dictionary (card_id -> CardData).
func _init(card_registry: Variant, rarity_weights: Dictionary = {}) -> void:
	_cards = _normalize_registry(card_registry)
	_rarity_weights = rarity_weights.duplicate()


# --- Public API ---

## All cards eligible for this party's draft: non-innate cards whose
## character_tag is `neutral` or matches a party character id. Returned sorted by
## id so the pool ordering is deterministic regardless of registry iteration
## order (the seed then drives selection on top of a stable base order).
func eligible_pool(run_state: RunState) -> Array[CardData]:
	# Draft-pool gating (ADR-0021 pt2): a tagged card is draftable only if some
	# member HAS that class. Pre-class members contribute nothing — the origin
	# tier drafts from the neutral pool only; the Act-3 pick opens class pools.
	var party: Dictionary = {}
	for cid: StringName in run_state.party:
		party[cid] = true  # legacy class-keyed member ids
		var cls: StringName = StringName(String(run_state.member_classes.get(cid, "")))
		if cls != &"":
			party[cls] = true

	var pool: Array[CardData] = []
	for key: Variant in _cards.keys():
		var value: Variant = _cards[key]
		if not (value is CardData):
			continue
		var card: CardData = value
		if card.upgrade_of != &"":
			continue  # upgrade variants are reached via rest upgrades, not drafts
		if card.signature:
			continue  # tree signatures arrive via progression unlock_cards only
		if card.innate:
			continue
		if card.card_kind != &"skill":
			continue  # ADR-0029: curses/consumables NEVER enter reward pools
		if card.character_tag == NEUTRAL_TAG or party.has(card.character_tag):
			pool.append(card)

	pool.sort_custom(_compare_card_id)
	return pool


## Produce a draft of up to `n` distinct eligible CardData options for `run_state`,
## using `rng_seed` for deterministic, rarity-weighted selection. If the eligible
## pool is smaller than `n`, returns as many distinct cards as exist (never errors).
func draft(run_state: RunState, n: int = DEFAULT_CHOICES, rng_seed: int = 0) -> Array[CardData]:
	var pool: Array[CardData] = eligible_pool(run_state)

	var count: int = n
	if count > pool.size():
		count = pool.size()
	if count < 0:
		count = 0

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var available: Array[CardData] = []
	available.assign(pool)

	var offer: Array[CardData] = []
	for _i: int in count:
		var idx: int = _weighted_index(available, rng)
		offer.append(available[idx])
		available.remove_at(idx)
	return offer


## Grant the chosen skill: tagged cards join their OWNER's collection, neutral
## cards join the first member's (ADR-0026). Returns true if granted;
## false for an empty id (a no-op). Mirrors §6: the picked id joins the run deck.
func pick(run_state: RunState, card_id: StringName) -> bool:
	if card_id == &"":
		return false
	var owner: StringName = run_state.party[0] if not run_state.party.is_empty() else &""
	var card: CardData = _cards.get(card_id, null)
	if card != null and card.character_tag != &"neutral":
		for member in run_state.party:
			var cls: StringName = StringName(String(run_state.member_classes.get(member, "")))
			if member == card.character_tag or cls == card.character_tag:
				owner = member
				break
	if owner == &"":
		return false
	var coll_v: Variant = run_state.skill_collections.get(owner)
	var load_v: Variant = run_state.active_loadouts.get(owner)
	if not (coll_v is Array):
		return false
	(coll_v as Array).append(card_id)
	if load_v is Array and (load_v as Array).size() < 10:
		(load_v as Array).append(card_id)
	return true


## Take nothing from the offer; run_state is left unchanged (§6 allows skipping).
func skip(_run_state: RunState) -> void:
	pass


# --- Internals ---

func _normalize_registry(card_registry: Variant) -> Dictionary:
	if card_registry is ContentDatabase:
		var db: ContentDatabase = card_registry
		return db.cards
	if card_registry is Dictionary:
		var dict: Dictionary = card_registry
		return dict
	return {}


## Weighted pick without replacement: pick one index from `available` by rarity
## weight using `rng`. Falls back to a uniform pick if total weight is zero.
func _weighted_index(available: Array[CardData], rng: RandomNumberGenerator) -> int:
	var total: float = 0.0
	for card: CardData in available:
		total += _weight_for(card)

	if total <= 0.0:
		return rng.randi_range(0, available.size() - 1)

	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for i: int in available.size():
		acc += _weight_for(available[i])
		if roll < acc:
			return i
	return available.size() - 1


## Draft weight for a card. Empty weights -> uniform (1.0). Otherwise the card's
## rarity weight, defaulting to 0.0 for an unlisted rarity.
func _weight_for(card: CardData) -> float:
	if _rarity_weights.is_empty():
		return 1.0
	var w: Variant = _rarity_weights.get(card.rarity, 0.0)
	return float(w)


## Stable, deterministic ordering by card id.
func _compare_card_id(a: CardData, b: CardData) -> bool:
	return String(a.id) < String(b.id)
