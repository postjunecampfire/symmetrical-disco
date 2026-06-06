extends GutTest
## GUT suite for the card-play flow (task P1·07): src/cards/card_play.gd.
##
## Builds a small real battle IN CODE (no JSON/.tres): a tiny grid, a couple of
## player combatants and an enemy, a BattleConfig, a shared Deck, and CardData
## built in-memory. Exercises the full play flow against the REAL BattleState so
## effects are asserted via live combat state (hp/block/energy), and card movement
## via the real Deck piles.
##
## Asserts each acceptance criterion:
##   * a successful play applies effects (battle state) AND moves the card to the
##     expected pile (discard / exhaust);
##   * rejection on insufficient energy;
##   * rejection on an out-of-range target;
##   * rejection on the wrong target_type;
##   * rejection on a character_tag mismatch;
##   * innate Strike/Defend play without touching the deck (and still spend energy
##     + resolve effects).
##
## Balance numbers (hp, energy, costs, ranges, effect magnitudes) live on the
## constructed data resources, never as bare assertion literals of "rules".

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


## A TargetSpec with explicit type + range.
func _spec(target_type: StringName, range_tiles: int) -> TargetSpec:
	var s := TargetSpec.new()
	s.target_type = target_type
	s.range = range_tiles
	return s


## A single effect.
func _effect(type: StringName, amount: int = 0, status: StringName = &"",
		stacks: int = 0) -> Effect:
	var e := Effect.new()
	e.type = type
	e.amount = amount
	e.status = status
	e.stacks = stacks
	return e


## A CardData with the fields the play flow cares about.
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


## CharacterData with an id (= its cards' tag) and a list of innate action ids.
func _char_data(char_id: String, innates: Array[StringName] = []) -> CharacterData:
	var d := CharacterData.new()
	d.id = StringName(char_id)
	d.display_name = char_id.capitalize()
	d.max_hp = 30
	d.move_range = 3
	d.innate_actions = innates
	return d


## A player Combatant built from CharacterData at `pos`, registered in `battle`.
func _player(battle: BattleState, char_data: CharacterData, pos: Vector2i,
		hp: int = 30) -> Combatant:
	var c := CombatantScript.from_character(char_data, pos)
	c.team = Combatant.Team.PLAYER
	c.hp = hp
	c.max_hp = hp
	battle.add_combatant(c)
	return c


## An enemy Combatant at `pos`, registered in `battle`.
func _enemy(battle: BattleState, pos: Vector2i, hp: int = 20) -> Combatant:
	var c := CombatantScript.new()
	c.team = Combatant.Team.ENEMY
	c.display_name = "Grunt"
	c.hp = hp
	c.max_hp = hp
	c.grid_position = pos
	battle.add_combatant(c)
	return c


## A fresh BattleState with a 6x6 grid and the given energy pool.
func _battle(energy: int = 3) -> BattleState:
	var cfg := _config(energy)
	var grid := GridModel.new(Vector2i(6, 6))
	var deck: Deck = DeckScript.new(cfg)
	var b: BattleState = BattleStateScript.new(cfg, grid, deck, {})
	b.energy = energy
	return b


# --- Successful play: effects applied + card to discard ---------------------

func test_successful_play_applies_effects_and_discards() -> void:
	var battle := _battle(3)
	var hero_data := _char_data("hero")
	var hero := _player(battle, hero_data, Vector2i(1, 1))
	var foe := _enemy(battle, Vector2i(2, 1), 20)  # adjacent (range 1)

	# A 1-cost vanguard-tagged... here neutral attack: 6 damage to an enemy in range 1.
	var strike := _card("hard_strike", "neutral", 1, _spec(&"enemy", 1),
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
	var hero := _player(battle, _char_data("hero"), Vector2i(1, 1))
	var foe := _enemy(battle, Vector2i(2, 1), 20)

	var one_shot := _card("nova", "neutral", 1, _spec(&"enemy", 2),
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


func test_self_target_block_card_applies_block() -> void:
	# A self-targeted defend-like skill applies block to the acting unit.
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero"), Vector2i(2, 2), 30)

	var guard := _card("guard", "neutral", 1, _spec(&"self", 0),
		[_effect(&"block", 5)])
	battle.deck.hand.append(guard)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(hero, guard, hero)

	assert_true(result.ok, "Self-target play succeeds: %s" % result.reason)
	assert_eq(hero.block, 5, "Block applied to the acting unit.")
	assert_eq(battle.energy, 2, "Energy spent.")


# --- Rejection: insufficient energy -----------------------------------------

func test_reject_insufficient_energy() -> void:
	var battle := _battle(1)  # only 1 energy in the pool
	var hero := _player(battle, _char_data("hero"), Vector2i(1, 1))
	var foe := _enemy(battle, Vector2i(2, 1), 20)

	# 2-cost card vs a 1-energy pool.
	var pricey := _card("big_hit", "neutral", 2, _spec(&"enemy", 1),
		[_effect(&"damage", 9)])
	battle.deck.hand.append(pricey)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(hero, pricey, foe)

	assert_false(result.ok, "Play rejected: cost exceeds the energy pool.")
	assert_eq(foe.hp, 20, "No effect applied on a rejected play.")
	assert_eq(battle.energy, 1, "No energy spent on a rejected play.")
	assert_true(battle.deck.hand.has(pricey), "Rejected card stays in hand.")


# --- Rejection: out-of-range target -----------------------------------------

func test_reject_out_of_range_target() -> void:
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero"), Vector2i(0, 0))
	# Enemy 5 tiles away (Manhattan), card range only 1.
	var foe := _enemy(battle, Vector2i(3, 2), 20)

	var melee := _card("jab", "neutral", 1, _spec(&"enemy", 1),
		[_effect(&"damage", 6)])
	battle.deck.hand.append(melee)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(hero, melee, foe)

	assert_false(result.ok, "Play rejected: target is out of range.")
	assert_eq(foe.hp, 20, "No effect applied to an out-of-range target.")
	assert_eq(battle.energy, 3, "No energy spent on a rejected play.")
	assert_true(battle.deck.hand.has(melee), "Card remains in hand.")


# --- Rejection: wrong target_type -------------------------------------------

func test_reject_wrong_target_type() -> void:
	# An `enemy`-typed card aimed at a friendly unit must be rejected.
	var battle := _battle(3)
	var hero_data := _char_data("hero")
	var hero := _player(battle, hero_data, Vector2i(1, 1))
	var ally := _player(battle, _char_data("ranger"), Vector2i(2, 1), 30)

	var attack := _card("smite", "neutral", 1, _spec(&"enemy", 2),
		[_effect(&"damage", 6)])
	battle.deck.hand.append(attack)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(hero, attack, ally)

	assert_false(result.ok, "Play rejected: enemy-typed card aimed at an ally.")
	assert_eq(ally.hp, 30, "Friendly unit takes no damage from the rejected play.")
	assert_eq(battle.energy, 3, "No energy spent.")
	assert_true(battle.deck.hand.has(attack), "Card stays in hand.")


func test_reject_empty_tile_when_occupied() -> void:
	# An empty_tile card aimed at an occupied tile is rejected.
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero"), Vector2i(1, 1))
	var foe := _enemy(battle, Vector2i(2, 1), 20)  # occupies (2,1)

	var teleport := _card("blink", "neutral", 1, _spec(&"empty_tile", 3),
		[_effect(&"move")])
	battle.deck.hand.append(teleport)

	var play: CardPlay = CardPlayScript.new(battle)
	# Aim the empty_tile card at the tile the enemy occupies.
	var result := play.play_card(hero, teleport, foe.grid_position)

	assert_false(result.ok, "empty_tile card rejected: target tile is occupied.")
	assert_true(battle.deck.hand.has(teleport), "Card stays in hand.")


# --- Rejection: character_tag mismatch --------------------------------------

func test_reject_character_tag_mismatch() -> void:
	# A card tagged for "mage" cannot be played by the "hero" unit (ADR-0004).
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero"), Vector2i(1, 1))
	var foe := _enemy(battle, Vector2i(2, 1), 20)

	var mage_card := _card("fireball", "mage", 1, _spec(&"enemy", 3),
		[_effect(&"damage", 8)])
	battle.deck.hand.append(mage_card)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(hero, mage_card, foe)

	assert_false(result.ok, "Play rejected: wrong character_tag for this unit.")
	assert_eq(foe.hp, 20, "No effect applied on a tag-mismatched play.")
	assert_eq(battle.energy, 3, "No energy spent.")
	assert_true(battle.deck.hand.has(mage_card), "Card stays in hand.")


func test_owner_can_play_tagged_card() -> void:
	# The matching owner CAN play their own tagged card.
	var battle := _battle(3)
	var mage := _player(battle, _char_data("mage"), Vector2i(1, 1))
	var foe := _enemy(battle, Vector2i(2, 1), 20)

	var mage_card := _card("fireball", "mage", 1, _spec(&"enemy", 3),
		[_effect(&"damage", 8)])
	battle.deck.hand.append(mage_card)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(mage, mage_card, foe)

	assert_true(result.ok, "Owner may play their own tagged card: %s" % result.reason)
	assert_eq(foe.hp, 12, "8 damage applied.")


# --- Innate Strike/Defend: plays without touching the deck ------------------

func test_innate_strike_plays_without_touching_deck() -> void:
	var battle := _battle(3)
	var hero_data := _char_data("hero", [&"strike", &"defend"])
	var hero := _player(battle, hero_data, Vector2i(1, 1))
	var foe := _enemy(battle, Vector2i(2, 1), 20)

	# Innate Strike: 4 damage, never in the deck.
	var strike := _card("strike", "neutral", 1, _spec(&"enemy", 1),
		[_effect(&"damage", 4)], true)

	# Pre-existing deck content to prove the deck is untouched by the innate play.
	var deck_card := _card("filler", "neutral", 1, _spec(&"enemy", 1),
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

	# The deck is completely untouched: no pile changed and the innate card is in
	# none of them.
	assert_eq(battle.deck.draw_pile.size(), draw_before, "Draw pile unchanged.")
	assert_eq(battle.deck.hand.size(), hand_before, "Hand unchanged.")
	assert_eq(battle.deck.discard_pile.size(), discard_before, "Discard unchanged.")
	assert_false(battle.deck.discard_pile.has(strike), "Innate never enters discard.")
	assert_false(battle.deck.exhaust_pile.has(strike), "Innate never enters exhaust.")
	assert_false(battle.deck.hand.has(strike), "Innate never enters the hand.")


func test_innate_defend_applies_block_to_self() -> void:
	var battle := _battle(3)
	var hero_data := _char_data("hero", [&"strike", &"defend"])
	var hero := _player(battle, hero_data, Vector2i(2, 2), 30)

	var defend := _card("defend", "neutral", 1, _spec(&"self", 0),
		[_effect(&"block", 5)], true)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_innate(hero, defend, hero)

	assert_true(result.ok, "Innate Defend plays: %s" % result.reason)
	assert_eq(hero.block, 5, "Innate Defend applies block to the acting unit.")
	assert_eq(battle.energy, 2, "Innate Defend spends energy.")


func test_reject_innate_not_on_action_bar() -> void:
	# An innate card the unit does NOT have on its action bar is rejected.
	var battle := _battle(3)
	var hero_data := _char_data("hero", [&"strike"])  # no "defend"
	var hero := _player(battle, hero_data, Vector2i(2, 2), 30)

	var defend := _card("defend", "neutral", 1, _spec(&"self", 0),
		[_effect(&"block", 5)], true)

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_innate(hero, defend, hero)

	assert_false(result.ok, "Innate not on the unit's action bar is rejected.")
	assert_eq(hero.block, 0, "No block applied on a rejected innate play.")
	assert_eq(battle.energy, 3, "No energy spent.")


func test_reject_non_innate_card_via_play_innate() -> void:
	# A normal deck card cannot be routed through play_innate.
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero", [&"strike"]), Vector2i(1, 1))
	var foe := _enemy(battle, Vector2i(2, 1), 20)

	var normal := _card("jab", "neutral", 1, _spec(&"enemy", 1),
		[_effect(&"damage", 6)])

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_innate(hero, normal, foe)

	assert_false(result.ok, "A non-innate card is rejected by play_innate.")
	assert_eq(foe.hp, 20, "No effect applied.")
	assert_eq(battle.energy, 3, "No energy spent.")


# --- Rejection: card not in hand --------------------------------------------

func test_reject_card_not_in_hand() -> void:
	var battle := _battle(3)
	var hero := _player(battle, _char_data("hero"), Vector2i(1, 1))
	var foe := _enemy(battle, Vector2i(2, 1), 20)

	# Card is NOT added to the hand.
	var stray := _card("ghost", "neutral", 1, _spec(&"enemy", 1),
		[_effect(&"damage", 6)])

	var play: CardPlay = CardPlayScript.new(battle)
	var result := play.play_card(hero, stray, foe)

	assert_false(result.ok, "A card not in hand cannot be played.")
	assert_eq(foe.hp, 20, "No effect applied.")
	assert_eq(battle.energy, 3, "No energy spent.")
