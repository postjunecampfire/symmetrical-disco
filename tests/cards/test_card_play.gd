extends GutTest
## GUT suite for the card-play flow (task P1·07, positionless ADR-0013):
## src/cards/card_play.gd.
##
## Builds a small real battle IN CODE (no JSON/.tres): a couple of player
## combatants and enemies, a BattleConfig, a shared Deck, and CardData built
## in-memory. Exercises the full play flow against the REAL BattleState so effects
## are asserted via live combat state (hp/block/energy), and card movement via the
## real Deck piles.
##
## Asserts each acceptance criterion:
##   * a successful play applies effects AND moves the card to the expected pile;
##   * an all_enemies card hits every enemy;
##   * rejection on insufficient energy;
##   * rejection on the wrong target_type;
##   * rejection on a character_tag mismatch;
##   * innate Strike/Defend play without touching the deck.

const CardPlayScript := preload("res://src/cards/card_play.gd")
const BattleStateScript := preload("res://src/combat/battle_state.gd")
const CombatantScript := preload("res://src/combat/combatant.gd")
const DeckScript := preload("res://src/cards/deck.gd")


# --- Fixtures ---------------------------------------------------------------

func _config(energy: int = 3) -> BattleConfig:
	var c := BattleConfig.new()
	c.energy_per_turn = energy
	c.draw_per_turn = 5
	c.max_hand = 10
	c.reshuffle_discard = true
	return c


## A positionless TargetSpec (kind only).
func _spec(target_type: StringName) -> TargetSpec:
	var s := TargetSpec.new()
	s.target_type = target_type
	return s


func _effect(type: StringName, amount: int = 0, status: StringName = &"",
		stacks: int = 0) -> Effect:
	var e := Effect.new()
	e.type = type
	e.amount = amount
	e.status = status
	e.stacks = stacks
	return e


func _card(card_id: String, tag: String, cost: int, spec: TargetSpec,
		effects: Array[Effect], innate: bool = false,
		keywords: Array[StringName] = []) -> CardData:
	var c := CardData.new()
	c.id = StringName(card_id)
	c.display_name = card_id.capitalize()
	c.character_tag = StringName(tag)
	c.energy_cost = cost
	c.target = spec
	c.effects = effects
	c.innate = innate
	c.keywords = keywords
	return c


func _char_data(char_id: String, innates: Array[StringName] = []) -> CharacterData:
	var d := CharacterData.new()
	d.id = StringName(char_id)
	d.display_name = char_id.capitalize()
	d.max_hp = 30
	d.innate_actions = innates
	return d


func _player(battle: BattleState, char_data: CharacterData, hp: int = 30) -> Combatant:
	var c := CombatantScript.from_character(char_data)
	c.hp = hp
	c.max_hp = hp
	battle.add_combatant(c)
	return c


func _enemy(battle: BattleState, hp: int = 20) -> Combatant:
	var c := CombatantScript.new()
	c.team = Combatant.Team.ENEMY
	c.display_name = "Grunt"
	c.hp = hp
	c.max_hp = hp
	battle.add_combatant(c)
	return c


## A fresh positionless BattleState with the given energy pool.
func _battle(energy: int = 3) -> BattleState:
	var cfg := _config(energy)
	var deck: Deck = DeckScript.new(cfg)
	var b: BattleState = BattleStateScript.new(cfg, deck, {})
	b.energy = energy
	return b


# --- Successful play: effects applied + card to discard ---------------------

func test_successful_play_applies_effects_and_discards() -> void:
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero"))
	var foe := _enemy(battle, 20)

	var strike := _card("hard_strike", "neutral", 1, _spec(&"enemy"),
		[_effect(&"damage", 6)])
	battle.deck.hand.append(strike)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(hero, strike, foe)

	assert_true(result.ok, "Legal play succeeds: %s" % result.reason)
	assert_eq(foe.hp, 14, "6 damage applied to the enemy via the real battle state.")
	assert_eq(battle.energy, 2, "Energy spent from the shared pool (3 - 1).")
	assert_false(battle.deck.hand.has(strike), "Played card left the hand.")
	assert_true(battle.deck.discard_pile.has(strike),
		"A plain card rejoins the cycle via discard.")


func test_successful_play_routes_exhaust_keyword() -> void:
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero"))
	var foe := _enemy(battle, 20)

	var one_shot := _card("nova", "neutral", 1, _spec(&"enemy"),
		[_effect(&"damage", 5)], false, [Deck.KEYWORD_EXHAUST])
	battle.deck.hand.append(one_shot)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(hero, one_shot, foe)

	assert_true(result.ok, "Legal exhaust card plays: %s" % result.reason)
	assert_eq(foe.hp, 15, "Effect applied (5 damage).")
	assert_true(battle.deck.exhaust_pile.has(one_shot),
		"Exhaust-keyword card moves to the exhaust pile, not discard.")
	assert_false(battle.deck.discard_pile.has(one_shot),
		"Exhausted card is NOT in discard.")


func test_all_enemies_card_hits_every_enemy() -> void:
	# An all_enemies (AoE) card resolves to every living enemy.
	var battle := _battle(3)
	var mage := _player(battle, _char_data("mage"))
	var e1 := _enemy(battle, 20)
	var e2 := _enemy(battle, 20)

	var nova := _card("frost", "mage", 2, _spec(&"all_enemies"),
		[_effect(&"damage", 4)])
	battle.deck.hand.append(nova)

	var play: CardPlay = CardPlayScript.new(battle)
	# AoE needs no specific pick; pass null as the chosen target.
	var result := play.play_card(mage, nova, null)

	assert_true(result.ok, "AoE play succeeds: %s" % result.reason)
	assert_eq(e1.hp, 16, "first enemy took the AoE")
	assert_eq(e2.hp, 16, "second enemy took the AoE")


func test_self_target_block_card_applies_block() -> void:
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero"), 30)

	var guard := _card("guard", "neutral", 1, _spec(&"self"),
		[_effect(&"block", 5)])
	battle.deck.hand.append(guard)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(hero, guard, hero)

	assert_true(result.ok, "Self-target play succeeds: %s" % result.reason)
	assert_eq(hero.block, 5, "Block applied to the acting unit.")
	assert_eq(battle.energy, 2, "Energy spent.")


# --- Rejection: insufficient energy -----------------------------------------

func test_reject_insufficient_energy() -> void:
	var battle := _battle(1)
	var hero := _player(battle, _char_data("hero"))
	var foe := _enemy(battle, 20)

	var pricey := _card("big_hit", "neutral", 2, _spec(&"enemy"),
		[_effect(&"damage", 9)])
	battle.deck.hand.append(pricey)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(hero, pricey, foe)

	assert_false(result.ok, "Play rejected: cost exceeds the energy pool.")
	assert_eq(foe.hp, 20, "No effect applied on a rejected play.")
	assert_eq(battle.energy, 1, "No energy spent on a rejected play.")
	assert_true(battle.deck.hand.has(pricey), "Rejected card stays in hand.")


# --- Rejection: wrong target_type -------------------------------------------

func test_reject_wrong_target_type() -> void:
	# An `enemy`-typed card aimed at a friendly unit must be rejected.
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero"))
	var ally := _player(battle, _char_data("ranger"), 30)

	var attack := _card("smite", "neutral", 1, _spec(&"enemy"),
		[_effect(&"damage", 6)])
	battle.deck.hand.append(attack)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(hero, attack, ally)

	assert_false(result.ok, "Play rejected: enemy-typed card aimed at an ally.")
	assert_eq(ally.hp, 30, "Friendly unit takes no damage from the rejected play.")
	assert_eq(battle.energy, 3, "No energy spent.")
	assert_true(battle.deck.hand.has(attack), "Card stays in hand.")


func test_self_card_rejected_when_aimed_at_another() -> void:
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero"))
	var ally := _player(battle, _char_data("ranger"), 30)

	var guard := _card("guard", "neutral", 1, _spec(&"self"),
		[_effect(&"block", 5)])
	battle.deck.hand.append(guard)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(hero, guard, ally)

	assert_false(result.ok, "self card must target the acting unit, not an ally.")
	assert_true(battle.deck.hand.has(guard), "Card stays in hand.")


# --- Rejection: character_tag mismatch --------------------------------------

func test_reject_character_tag_mismatch() -> void:
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero"))
	var foe := _enemy(battle, 20)

	var mage_card := _card("fireball", "mage", 1, _spec(&"enemy"),
		[_effect(&"damage", 8)])
	battle.deck.hand.append(mage_card)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(hero, mage_card, foe)

	assert_false(result.ok, "Play rejected: wrong character_tag for this unit.")
	assert_eq(foe.hp, 20, "No effect applied on a tag-mismatched play.")
	assert_eq(battle.energy, 3, "No energy spent.")
	assert_true(battle.deck.hand.has(mage_card), "Card stays in hand.")


func test_owner_can_play_tagged_card() -> void:
	var battle := _battle(3)
	var mage := _player(battle, _char_data("mage"))
	var foe := _enemy(battle, 20)

	var mage_card := _card("fireball", "mage", 1, _spec(&"enemy"),
		[_effect(&"damage", 8)])
	battle.deck.hand.append(mage_card)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(mage, mage_card, foe)

	assert_true(result.ok, "Owner may play their own tagged card: %s" % result.reason)
	assert_eq(foe.hp, 12, "8 damage applied.")


# --- Innate Strike/Defend: plays without touching the deck ------------------

func test_innate_strike_plays_without_touching_deck() -> void:
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero", [&"strike", &"defend"]))
	var foe := _enemy(battle, 20)

	var strike := _card("strike", "neutral", 1, _spec(&"enemy"),
		[_effect(&"damage", 4)], true)

	var deck_card := _card("filler", "neutral", 1, _spec(&"enemy"),
		[_effect(&"damage", 1)])
	battle.deck.draw_pile.append(deck_card)
	var draw_before := battle.deck.draw_pile.size()
	var hand_before := battle.deck.hand.size()
	var discard_before := battle.deck.discard_pile.size()

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_innate(hero, strike, foe)

	assert_true(result.ok, "Innate Strike plays: %s" % result.reason)
	assert_eq(foe.hp, 16, "Innate Strike still resolves its effects (4 damage).")
	assert_eq(battle.energy, 2, "Innate Strike still spends energy (3 - 1).")

	assert_eq(battle.deck.draw_pile.size(), draw_before, "Draw pile unchanged.")
	assert_eq(battle.deck.hand.size(), hand_before, "Hand unchanged.")
	assert_eq(battle.deck.discard_pile.size(), discard_before, "Discard unchanged.")
	assert_false(battle.deck.discard_pile.has(strike), "Innate never enters discard.")
	assert_false(battle.deck.exhaust_pile.has(strike), "Innate never enters exhaust.")
	assert_false(battle.deck.hand.has(strike), "Innate never enters the hand.")


func test_innate_defend_applies_block_to_self() -> void:
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero", [&"strike", &"defend"]), 30)

	var defend := _card("defend", "neutral", 1, _spec(&"self"),
		[_effect(&"block", 5)], true)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_innate(hero, defend, hero)

	assert_true(result.ok, "Innate Defend plays: %s" % result.reason)
	assert_eq(hero.block, 5, "Innate Defend applies block to the acting unit.")
	assert_eq(battle.energy, 2, "Innate Defend spends energy.")


func test_reject_innate_not_on_action_bar() -> void:
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero", [&"strike"]), 30)

	var defend := _card("defend", "neutral", 1, _spec(&"self"),
		[_effect(&"block", 5)], true)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_innate(hero, defend, hero)

	assert_false(result.ok, "Innate not on the unit's action bar is rejected.")
	assert_eq(hero.block, 0, "No block applied on a rejected innate play.")
	assert_eq(battle.energy, 3, "No energy spent.")


func test_reject_non_innate_card_via_play_innate() -> void:
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero", [&"strike"]))
	var foe := _enemy(battle, 20)

	var normal := _card("jab", "neutral", 1, _spec(&"enemy"),
		[_effect(&"damage", 6)])

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_innate(hero, normal, foe)

	assert_false(result.ok, "A non-innate card is rejected by play_innate.")
	assert_eq(foe.hp, 20, "No effect applied.")
	assert_eq(battle.energy, 3, "No energy spent.")


# --- Rejection: card not in hand --------------------------------------------

func test_reject_card_not_in_hand() -> void:
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero"))
	var foe := _enemy(battle, 20)

	var stray := _card("ghost", "neutral", 1, _spec(&"enemy"),
		[_effect(&"damage", 6)])

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(hero, stray, foe)

	assert_false(result.ok, "A card not in hand cannot be played.")
	assert_eq(foe.hp, 20, "No effect applied.")
	assert_eq(battle.energy, 3, "No energy spent.")
