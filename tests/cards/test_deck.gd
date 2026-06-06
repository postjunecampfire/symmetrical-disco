extends GutTest
## GUT suite for the SHARED deck (task P1·06): deck assembly (excludes innate
## cards per ADR-0005, unions party starting decks per ADR-0004), draw respecting
## draw_per_turn and max_hand, discard, empty-pile reshuffle as the cooldown cycle
## (ADR-0006) preserving the card multiset, exhaust (permanent removal), return
## (back to hand), and seeded determinism.
##
## All resources are constructed in-memory (CardData / CharacterData /
## BattleConfig from src/data) — no JSON loading needed. Balance numbers live on
## the BattleConfig instances, never inline assertions of "magic" deck behaviour.

const DeckScript := preload("res://src/cards/deck.gd")


# --- Fixtures ---------------------------------------------------------------

## Build a CardData with the fields the deck cares about.
func _card(card_id: String, character_tag: String = "neutral",
		innate: bool = false, keywords: Array[StringName] = []) -> CardData:
	var c := CardData.new()
	c.id = StringName(card_id)
	c.display_name = card_id.capitalize()
	c.character_tag = StringName(character_tag)
	c.innate = innate
	c.keywords = keywords
	return c


## A BattleConfig with explicit tunables (so each test states the numbers it
## relies on rather than depending on schema defaults).
func _config(draw_per_turn: int = 5, max_hand: int = 10,
		reshuffle: bool = true) -> BattleConfig:
	var cfg := BattleConfig.new()
	cfg.draw_per_turn = draw_per_turn
	cfg.max_hand = max_hand
	cfg.reshuffle_discard = reshuffle
	return cfg


## A character contributing the given card ids to the shared deck.
func _character(char_id: String, deck_ids: Array[StringName]) -> CharacterData:
	var ch := CharacterData.new()
	ch.id = StringName(char_id)
	ch.display_name = char_id.capitalize()
	ch.starting_deck = deck_ids
	return ch


## Build a {id -> CardData} lookup from a list of cards.
func _lookup(cards: Array) -> Dictionary:
	var d: Dictionary = {}
	for c in cards:
		d[c.id] = c
	return d


# --- Deck assembly: union + innate exclusion (ADR-0004 / ADR-0005) ----------

func test_assembly_unions_party_starting_decks() -> void:
	var c_strike := _card("strike", "neutral", true)   # innate, excluded
	var c_a := _card("vanguard_skill")
	var c_b := _card("mage_skill")
	var lookup := _lookup([c_strike, c_a, c_b])

	var van := _character("vanguard", [&"vanguard_skill"])
	var mage := _character("mage", [&"mage_skill"])

	var deck: Deck = DeckScript.new(_config())
	deck.assemble([van, mage], lookup)

	assert_eq(deck.draw_pile.size(), 2, "Deck = union of both starting decks.")
	var ids := _ids(deck.draw_pile)
	assert_true(ids.has(&"vanguard_skill"), "Vanguard's card is in the deck.")
	assert_true(ids.has(&"mage_skill"), "Mage's card is in the deck.")


func test_assembly_excludes_innate_cards() -> void:
	# Even if a character lists an innate card in starting_deck, it must NOT enter
	# the deck — innate Strike/Defend live on the action bar (ADR-0005).
	var c_strike := _card("strike", "neutral", true)
	var c_defend := _card("defend", "neutral", true)
	var c_signature := _card("shield_bash", "vanguard")
	var lookup := _lookup([c_strike, c_defend, c_signature])

	var van := _character("vanguard", [&"strike", &"defend", &"shield_bash"])

	var deck: Deck = DeckScript.new(_config())
	deck.assemble([van], lookup)

	assert_eq(deck.draw_pile.size(), 1, "Only the non-innate card enters the deck.")
	assert_eq(deck.draw_pile[0].id, &"shield_bash", "Signature card included.")
	var ids := _ids(deck.draw_pile)
	assert_false(ids.has(&"strike"), "Innate strike excluded from the deck.")
	assert_false(ids.has(&"defend"), "Innate defend excluded from the deck.")


func test_assembly_skips_unknown_ids() -> void:
	# Unknown ids (not in the lookup) are skipped; resolution/validation is the
	# loader's job, not the deck's.
	var c_a := _card("known")
	var lookup := _lookup([c_a])
	var ch := _character("x", [&"known", &"missing"])

	var deck: Deck = DeckScript.new(_config())
	deck.assemble([ch], lookup)

	assert_eq(deck.draw_pile.size(), 1, "Unknown id skipped, known kept.")
	assert_eq(deck.draw_pile[0].id, &"known")


func test_assembly_clears_other_piles() -> void:
	var deck: Deck = DeckScript.new(_config())
	deck.hand.append(_card("leftover"))
	deck.discard_pile.append(_card("old"))
	deck.exhaust_pile.append(_card("gone"))

	var c_a := _card("fresh")
	deck.assemble([_character("x", [&"fresh"])], _lookup([c_a]))

	assert_eq(deck.hand.size(), 0, "Hand cleared on assembly.")
	assert_eq(deck.discard_pile.size(), 0, "Discard cleared on assembly.")
	assert_eq(deck.exhaust_pile.size(), 0, "Exhaust cleared on assembly.")
	assert_eq(deck.draw_pile.size(), 1, "Only freshly assembled cards remain.")


# --- Draw: draw_per_turn + max_hand (data, not hardcoded) -------------------

func test_draw_for_turn_respects_draw_per_turn() -> void:
	var deck := _deck_with_n_cards(10, _config(3, 10))  # draw_per_turn = 3
	deck.draw_for_turn()
	assert_eq(deck.hand.size(), 3, "Draw exactly draw_per_turn (3) cards.")
	assert_eq(deck.draw_pile.size(), 7, "Remaining cards stay in the draw pile.")


func test_draw_respects_max_hand_cap() -> void:
	# draw_per_turn 5 but max_hand 4: cannot exceed the hand cap.
	var deck := _deck_with_n_cards(10, _config(5, 4))
	var drawn := deck.draw_for_turn()
	assert_eq(deck.hand.size(), 4, "Hand never exceeds max_hand (4).")
	assert_eq(drawn.size(), 4, "Only 4 cards reported drawn.")
	# Drawing again with a full hand draws nothing.
	var more := deck.draw(2)
	assert_eq(more.size(), 0, "No draw when hand is at the cap.")
	assert_eq(deck.hand.size(), 4, "Hand still at the cap.")


func test_draw_stops_when_cycle_empty() -> void:
	# Only 2 cards in the whole cycle; asking for 5 yields just 2.
	var deck := _deck_with_n_cards(2, _config(5, 10))
	var drawn := deck.draw_for_turn()
	assert_eq(drawn.size(), 2, "Draw stops once the cycle is exhausted.")
	assert_eq(deck.hand.size(), 2)
	assert_eq(deck.draw_pile.size(), 0)


# --- Discard ----------------------------------------------------------------

func test_discard_hand_moves_all_to_discard() -> void:
	var deck := _deck_with_n_cards(5, _config(3, 10))
	deck.draw_for_turn()  # 3 in hand
	var n := deck.discard_hand()
	assert_eq(n, 3, "discard_hand reports the count discarded.")
	assert_eq(deck.hand.size(), 0, "Hand is emptied.")
	assert_eq(deck.discard_pile.size(), 3, "All hand cards moved to discard.")


func test_discard_from_hand_single_card() -> void:
	var deck := _deck_with_n_cards(5, _config(3, 10))
	var drawn := deck.draw_for_turn()
	var target: CardData = drawn[0]
	assert_true(deck.discard_from_hand(target), "Card in hand is discarded.")
	assert_false(deck.hand.has(target), "Discarded card left the hand.")
	assert_true(deck.discard_pile.has(target), "Discarded card is in discard.")
	# Discarding a card not in hand returns false.
	assert_false(deck.discard_from_hand(_card("stranger")), "Unknown card -> false.")


# --- Reshuffle: the cooldown cycle (ADR-0006) -------------------------------

func test_reshuffle_triggers_when_draw_pile_empties() -> void:
	# 3 cards total. Draw all 3, discard them, then draw again: the empty draw
	# pile must reshuffle the discard back in to keep drawing (the cooldown cycle).
	var deck := _deck_with_n_cards(3, _config(3, 10))
	deck.draw_for_turn()
	assert_eq(deck.draw_pile.size(), 0, "Draw pile emptied by the turn draw.")
	deck.discard_hand()
	assert_eq(deck.discard_pile.size(), 3, "All 3 cards now in discard.")

	var card := deck.draw_one()
	assert_not_null(card, "Drawing reshuffles the discard back into the draw pile.")
	assert_eq(deck.hand.size(), 1, "One card drawn after the reshuffle.")
	assert_eq(deck.draw_pile.size(), 2, "Remaining reshuffled cards sit in draw.")
	assert_eq(deck.discard_pile.size(), 0, "Discard emptied by the reshuffle.")


func test_reshuffle_preserves_card_multiset() -> void:
	var deck := _deck_with_n_cards(6, _config(6, 10))
	var before := _id_multiset(deck.all_cards())

	deck.draw_for_turn()       # all 6 into hand
	deck.discard_hand()        # all 6 into discard
	assert_true(deck.reshuffle_discard_into_draw(), "Reshuffle runs with a non-empty discard.")

	var after := _id_multiset(deck.all_cards())
	assert_eq(after, before, "Reshuffle preserves the exact card multiset.")
	assert_eq(deck.draw_pile.size(), 6, "All cards returned to the draw pile.")
	assert_eq(deck.discard_pile.size(), 0, "Discard is empty after reshuffle.")


func test_reshuffle_noop_when_disabled() -> void:
	# reshuffle_discard = false: an empty draw pile does NOT pull from discard.
	var deck := _deck_with_n_cards(2, _config(2, 10, false))
	deck.draw_for_turn()
	deck.discard_hand()
	assert_eq(deck.draw_pile.size(), 0)
	assert_false(deck.reshuffle_discard_into_draw(), "Disabled reshuffle is a no-op.")
	assert_null(deck.draw_one(), "With reshuffle off, an empty draw pile yields nothing.")
	assert_eq(deck.discard_pile.size(), 2, "Discard untouched while reshuffle is off.")


# --- Exhaust: permanent removal from the cycle (ADR-0006) -------------------

func test_exhaust_permanently_removes_card() -> void:
	var exhaust_card := _card("one_shot", "neutral", false, [Deck.KEYWORD_EXHAUST])
	var deck: Deck = DeckScript.new(_config(1, 10))
	deck.draw_pile.append(exhaust_card)
	deck.draw_one()  # into hand

	assert_true(deck.play_from_hand(exhaust_card), "Exhaust card is played from hand.")
	assert_false(deck.hand.has(exhaust_card), "Played card left the hand.")
	assert_true(deck.exhaust_pile.has(exhaust_card), "Card moved to the exhaust pile.")
	assert_false(deck.discard_pile.has(exhaust_card), "Exhausted card is NOT in discard.")

	# It must never come back, even across a reshuffle (it left the cycle).
	deck.reshuffle_discard_into_draw()
	assert_false(deck.draw_pile.has(exhaust_card), "Exhausted card never re-enters the cycle.")
	assert_eq(deck.total_in_cycle(), 0, "Exhausted card no longer counts in the cycle.")


# --- Return: short cooldown (back to hand) ----------------------------------

func test_return_card_goes_back_to_hand() -> void:
	var return_card := _card("rebound", "neutral", false, [Deck.KEYWORD_RETURN])
	var deck: Deck = DeckScript.new(_config(1, 10))
	deck.draw_pile.append(return_card)
	deck.draw_one()

	assert_true(deck.play_from_hand(return_card), "Return card is played from hand.")
	assert_true(deck.hand.has(return_card), "Return card is back in the hand (short cooldown).")
	assert_false(deck.discard_pile.has(return_card), "Return card did not go to discard.")
	assert_false(deck.exhaust_pile.has(return_card), "Return card was not exhausted.")


func test_plain_card_goes_to_discard_on_play() -> void:
	var plain := _card("plain")
	var deck: Deck = DeckScript.new(_config(1, 10))
	deck.draw_pile.append(plain)
	deck.draw_one()

	assert_true(deck.play_from_hand(plain))
	assert_true(deck.discard_pile.has(plain), "A plain card rejoins the cycle via discard.")
	assert_false(deck.hand.has(plain), "Plain card leaves the hand on play.")


# --- Seeded determinism -----------------------------------------------------

func test_same_seed_same_draw_order() -> void:
	var ids: Array[StringName] = [&"a", &"b", &"c", &"d", &"e", &"f", &"g", &"h"]

	var order_1 := _draw_order_with_seed(ids, 12345)
	var order_2 := _draw_order_with_seed(ids, 12345)
	assert_eq(order_1, order_2, "Same seed -> identical draw order.")


func test_different_seed_likely_different_order() -> void:
	var ids: Array[StringName] = [&"a", &"b", &"c", &"d", &"e", &"f", &"g", &"h"]
	var order_1 := _draw_order_with_seed(ids, 1)
	var order_2 := _draw_order_with_seed(ids, 999)
	# Not a hard guarantee, but with 8 distinct cards a collision is vanishingly
	# unlikely; this proves the seed actually drives the shuffle.
	assert_ne(order_1, order_2, "Different seeds -> different draw order (8! space).")


func test_set_seed_resets_determinism() -> void:
	var ids: Array[StringName] = [&"a", &"b", &"c", &"d", &"e"]
	var deck := _deck_from_ids(ids, _config(5, 10))
	deck.set_seed(42)
	deck.shuffle_draw_pile()
	var first := _ids(deck.draw_pile)

	var deck2 := _deck_from_ids(ids, _config(5, 10))
	deck2.set_seed(42)
	deck2.shuffle_draw_pile()
	var second := _ids(deck2.draw_pile)

	assert_eq(first, second, "set_seed makes shuffles reproducible.")


# --- Helpers ----------------------------------------------------------------

## A deck pre-loaded with `n` distinct non-innate cards directly in the draw pile
## (bypassing assembly) so draw/discard/reshuffle tests have a known pile.
func _deck_with_n_cards(n: int, cfg: BattleConfig) -> Deck:
	var deck: Deck = DeckScript.new(cfg)
	for i in range(n):
		deck.draw_pile.append(_card("card_%d" % i))
	return deck


## A deck whose draw pile is exactly the given ids (in order).
func _deck_from_ids(ids: Array[StringName], cfg: BattleConfig) -> Deck:
	var deck: Deck = DeckScript.new(cfg)
	for card_id in ids:
		deck.draw_pile.append(_card(String(card_id)))
	return deck


## Seed a deck, shuffle, then draw the whole pile and return the id sequence.
func _draw_order_with_seed(ids: Array[StringName], rng_seed: int) -> Array[StringName]:
	var deck := _deck_from_ids(ids, _config(ids.size(), ids.size()))
	deck.set_seed(rng_seed)
	deck.start_battle()  # shuffles
	var drawn := deck.draw(ids.size())
	return _ids(drawn)


## Ordered list of ids from a pile.
func _ids(cards: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for c in cards:
		out.append(c.id)
	return out


## Frequency map {id -> count} — an order-independent multiset for comparison.
func _id_multiset(cards: Array) -> Dictionary:
	var m: Dictionary = {}
	for c in cards:
		m[c.id] = int(m.get(c.id, 0)) + 1
	return m
