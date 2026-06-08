class_name Deck
extends RefCounted
## The SHARED deck for a battle (ADR-0004): one draw pile, one hand, one discard
## pile, plus an exhaust zone, for the whole party. The draw/discard/reshuffle
## cycle IS the cooldown model (ADR-0006): drawing a card = that skill coming off
## cooldown; reshuffling discard back into the draw pile is the baseline cooldown
## length; `exhaust` removes a card from the cycle (one-shot / very long
## cooldown); `return` sends a played card straight back to hand (short cooldown).
##
## Innate Strike/Defend live on the unit's action bar, NOT in the deck (ADR-0005),
## so deck assembly explicitly EXCLUDES any card flagged `innate`.
##
## All balance numbers (draw_per_turn, max_hand, reshuffle on/off) come from a
## BattleConfig resource — never hardcoded here (data-schemas.md §7, ADR-0003).
##
## Shuffles use a SEEDED RandomNumberGenerator so battle replays / tests are
## deterministic. Inject a seed via the constructor or `set_seed()`.

## Keyword StringNames recognised by the cycle. Kept as named constants so the
## strings live in exactly one place and read as cooldown semantics, not magic.
const KEYWORD_EXHAUST: StringName = &"exhaust"
const KEYWORD_RETURN: StringName = &"return"

## The global battle tunables (draw_per_turn, max_hand, reshuffle_discard).
## Injected, never hardcoded. A default is constructed if none is supplied so the
## deck is always usable, but real battles pass the loaded /data resource.
var config: BattleConfig

## The shared piles. Each holds CardData instances (the same instance can only be
## in one pile at a time). `hand`/`discard`/`draw_pile`/`exhaust` are the four
## zones a card can occupy.
var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []
var exhaust_pile: Array[CardData] = []

## Seeded RNG for deterministic shuffles. Tests (and replays) set a known seed so
## the same seed always yields the same draw order.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## `battle_config` is the source of all per-turn economy numbers. `rng_seed`
## seeds the shuffle RNG for determinism.
func _init(battle_config: BattleConfig = null, rng_seed: int = 0) -> void:
	config = battle_config if battle_config != null else BattleConfig.new()
	_rng.seed = rng_seed


# --- Determinism ------------------------------------------------------------

## Set the shuffle seed. Same seed + same starting multiset => same draw order.
func set_seed(rng_seed: int) -> void:
	_rng.seed = rng_seed


# --- Deck assembly (ADR-0004 / ADR-0005) ------------------------------------

## Build the shared draw pile from the union of the party's `starting_deck` card
## ids, resolving each id through `card_lookup` to a CardData. Innate actions are
## EXCLUDED (ADR-0005): any card flagged `innate`, and any id that resolves to an
## innate card, is skipped — innate Strike/Defend live on the action bar, not the
## deck. Unknown ids (not in the lookup) are skipped too; validation that ids
## resolve is the loader's job (ContentDatabase), not the deck's.
##
## `card_lookup` maps StringName id -> CardData. After assembly the cards sit in
## `draw_pile` UNSHUFFLED (assembly order); call `shuffle_draw_pile()` or
## `start_battle()` to randomise. All other piles are cleared.
func assemble(party: Array[CharacterData], card_lookup: Dictionary) -> void:
	var card_ids: Array[StringName] = []
	for character in party:
		if character == null:
			continue
		for card_id in character.starting_deck:
			card_ids.append(card_id)
	assemble_from_card_ids(card_ids, card_lookup)


## Build the shared draw pile from an EXPLICIT list of card ids (the run deck:
## starting-deck cards plus race custom cards and drafted rewards — P2·06 /
## ADR-0015). This is the seam that lets a run's accumulated deck — not just each
## class's starting deck — drive a fight, so race/reward cards actually appear.
##
## Same rules as `assemble`: innate actions are EXCLUDED (ADR-0005) and unknown
## ids are skipped (id validity is the loader's job). Duplicate ids produce
## duplicate cards (each resolves to the same shared CardData instance, matching
## how starting decks with repeats already behave). Resulting `draw_pile` is
## UNSHUFFLED; all other piles are cleared.
func assemble_from_card_ids(card_ids: Array[StringName], card_lookup: Dictionary) -> void:
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	exhaust_pile.clear()

	for card_id in card_ids:
		if not card_lookup.has(card_id):
			continue
		var card: CardData = card_lookup[card_id]
		if card == null or card.innate:
			continue  # Innate actions never enter the deck (ADR-0005).
		draw_pile.append(card)


## Convenience entry point for the start of a battle: shuffle the assembled draw
## pile with the current seed. Hand/discard/exhaust are left as assembled.
func start_battle() -> void:
	shuffle_draw_pile()


# --- Shuffling --------------------------------------------------------------

## Deterministically shuffle the draw pile in place using the seeded RNG
## (Fisher–Yates). Same seed + same multiset => same resulting order.
func shuffle_draw_pile() -> void:
	_shuffle(draw_pile)


## Fisher–Yates shuffle of `pile` in place using the seeded RNG.
func _shuffle(pile: Array[CardData]) -> void:
	for i in range(pile.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: CardData = pile[i]
		pile[i] = pile[j]
		pile[j] = tmp


# --- Reshuffle (the cooldown cycle, ADR-0006) -------------------------------

## Move the entire discard pile back into the draw pile and shuffle it. This is
## the baseline cooldown cycle: skills sitting in discard become drawable again.
## Exhausted cards are NOT touched — they have left the cycle. No-op (returns
## false) if `config.reshuffle_discard` is off or the discard pile is empty.
func reshuffle_discard_into_draw() -> bool:
	if not config.reshuffle_discard:
		return false
	if discard_pile.is_empty():
		return false
	draw_pile.append_array(discard_pile)
	discard_pile.clear()
	shuffle_draw_pile()
	return true


# --- Drawing ----------------------------------------------------------------

## Draw a single card from the top of the draw pile into the hand. If the draw
## pile is empty, first try to reshuffle the discard back in (ADR-0006). Honours
## the hand cap: if the hand is already at `config.max_hand`, nothing is drawn.
## Returns the drawn CardData, or null if no card could be drawn (empty cycle or
## full hand).
func draw_one() -> CardData:
	if hand.size() >= config.max_hand:
		return null
	if draw_pile.is_empty():
		# Draw pile empty: the cooldown cycle refreshes by reshuffling discard.
		if not reshuffle_discard_into_draw():
			return null  # Nothing left anywhere in the cycle.
	if draw_pile.is_empty():
		return null
	var card: CardData = draw_pile.pop_back()
	hand.append(card)
	return card


## Draw up to `count` cards, respecting the hand cap and the empty-pile reshuffle
## rule. Stops early if the hand fills up or the whole cycle is exhausted.
## Returns the cards actually drawn, in draw order.
func draw(count: int) -> Array[CardData]:
	var drawn: Array[CardData] = []
	for _i in range(count):
		var card: CardData = draw_one()
		if card == null:
			break
		drawn.append(card)
	return drawn


## Draw the per-turn allotment (`config.draw_per_turn`), capped by `max_hand`.
## The standard turn-start draw. Returns the cards actually drawn.
func draw_for_turn() -> Array[CardData]:
	return draw(config.draw_per_turn)


# --- Playing / discarding ---------------------------------------------------

## Remove `card` from the hand and route it by its keywords (ADR-0006):
##   * `exhaust` -> exhaust pile (leaves the cycle entirely; very long cooldown),
##   * `return`  -> stays in hand (short cooldown), respecting the hand cap,
##   * otherwise -> discard pile (rejoins the cycle on the next reshuffle).
## `exhaust` takes precedence over `return` if a card somehow carries both.
## Returns true if the card was in hand and routed; false if it wasn't in hand.
func play_from_hand(card: CardData) -> bool:
	var idx: int = hand.find(card)
	if idx == -1:
		return false
	hand.remove_at(idx)
	if card.keywords.has(KEYWORD_EXHAUST):
		exhaust_pile.append(card)
	elif card.keywords.has(KEYWORD_RETURN):
		# Short cooldown: back to hand immediately, unless the hand is full —
		# then it falls through to discard so the card is never lost.
		if hand.size() < config.max_hand:
			hand.append(card)
		else:
			discard_pile.append(card)
	else:
		discard_pile.append(card)
	return true


## Discard a specific card from hand to the discard pile, ignoring keywords
## (e.g. an end-of-turn forced discard). Returns true if it was in hand.
func discard_from_hand(card: CardData) -> bool:
	var idx: int = hand.find(card)
	if idx == -1:
		return false
	hand.remove_at(idx)
	discard_pile.append(card)
	return true


## Discard the entire hand to the discard pile (standard end-of-turn cleanup).
## Returns the number of cards discarded.
func discard_hand() -> int:
	var n: int = hand.size()
	discard_pile.append_array(hand)
	hand.clear()
	return n


# --- Queries ----------------------------------------------------------------

## Total cards still in the cooldown cycle (draw + hand + discard). Exhausted
## cards have left the cycle and are NOT counted.
func total_in_cycle() -> int:
	return draw_pile.size() + hand.size() + discard_pile.size()


## Every card the deck currently tracks, across all four zones. Useful for
## asserting the card multiset is preserved across reshuffles.
func all_cards() -> Array[CardData]:
	var out: Array[CardData] = []
	out.append_array(draw_pile)
	out.append_array(hand)
	out.append_array(discard_pile)
	out.append_array(exhaust_pile)
	return out
