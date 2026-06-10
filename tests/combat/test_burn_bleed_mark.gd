extends "res://addons/gut/test.gd"
## GUT suite for the three M3 statuses (mage DoT ≠ rogue poison):
##   Burn  — ticks at the owner's phase start like poison (stacks as damage, then
##           -1 stack) but block CAN absorb it (poison pierces; burn doesn't).
##   Bleed — procs when the unit ACTS (player card play / enemy intent): stacks
##           as block-ignoring damage, then -1 per proc. No per-turn tick/decay.
##   Mark  — the target takes +stacks FLAT damage on each attack hit, added AFTER
##           multipliers (Vulnerable), then loses ONE stack per hit.
## Mixed fixtures: in-code battles (the test_battle_state/test_card_play pattern)
## for precise numbers, plus a real assembled battle so the loaded StatusData and
## the enemy-phase act hook are exercised end to end.

const BattleStateScript := preload("res://src/combat/battle_state.gd")
const CombatantScript := preload("res://src/combat/combatant.gd")
const CardPlayScript := preload("res://src/cards/card_play.gd")
const EncounterAssemblerScript := preload("res://src/combat/encounter_assembler.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")


# --- In-code fixtures (mirrors test_battle_state.gd) -------------------------

func _config() -> BattleConfig:
	var c := BattleConfig.new()
	c.energy_per_character = 3
	c.draw_per_turn = 0
	c.max_hand = 10
	c.reshuffle_discard = true
	return c


func _status(id: StringName, stacking: StringName, decays: bool) -> StatusData:
	var s := StatusData.new()
	s.id = id
	s.display_name = String(id)
	s.stacking = stacking
	s.decays_each_turn = decays
	return s


## StatusData map matching data/status/*.json flags for the statuses under test.
func _status_defs() -> Dictionary:
	var defs := {}
	defs[&"poison"] = _status(&"poison", &"intensity", true)
	defs[&"block"] = _status(&"block", &"intensity", true)
	defs[&"burn"] = _status(&"burn", &"intensity", true)
	defs[&"bleed"] = _status(&"bleed", &"intensity", false)
	defs[&"mark"] = _status(&"mark", &"intensity", false)
	defs[&"vulnerable"] = _status(&"vulnerable", &"duration", true)
	return defs


func _state() -> BattleState:
	var cfg := _config()
	return BattleStateScript.new(cfg, Deck.new(cfg), _status_defs())


func _character(hp: int) -> CharacterData:
	var d := CharacterData.new()
	d.id = &"hero"
	d.display_name = "Hero"
	d.max_hp = hp
	return d


func _add_player(state: BattleState, hp: int) -> Combatant:
	return state.add_combatant(CombatantScript.from_character(_character(hp)))


func _add_enemy(state: BattleState, hp: int) -> Combatant:
	var c := CombatantScript.new()
	c.team = Combatant.Team.ENEMY
	c.display_name = "Grunt"
	c.max_hp = hp
	c.hp = hp
	return state.add_combatant(c)


func _spec(target_type: StringName) -> TargetSpec:
	var s := TargetSpec.new()
	s.target_type = target_type
	return s


func _effect(type: StringName, amount: int = 0) -> Effect:
	var e := Effect.new()
	e.type = type
	e.amount = amount
	return e


# --- Assembled-battle fixture (mirrors test_vulnerable_frail.gd) -------------

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _battle() -> EncounterBattle:
	# enc_combat_01 = grunt ×2 → two flat enemies (attack_power 0).
	return EncounterAssemblerScript.new().build(
		_db.get_encounter(&"enc_combat_01"), _db, [&"fighter", &"mage"] as Array[StringName], 1
	)


# --- Burn ---------------------------------------------------------------------

func test_burn_ticks_at_turn_start_and_decays() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	_add_enemy(state, 20)
	state.apply_status(player, &"burn", 3)
	state.start_player_turn()
	assert_eq(player.hp, 27, "burn dealt its 3 stacks as damage")
	assert_eq(player.status_stacks(&"burn"), 2, "burn decayed by one")


func test_burn_is_absorbed_by_block_unlike_poison() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	_add_enemy(state, 20)
	player.block = 5
	state.apply_status(player, &"burn", 8)
	state.start_player_turn()  # burn ticks BEFORE the block reset, so block soaks it
	assert_eq(player.hp, 27, "block absorbed 5 of the 8 burn (3 to hp)")
	assert_eq(player.status_stacks(&"burn"), 7, "burn decayed by one")


func test_poison_still_pierces_block_where_burn_does_not() -> void:
	# The differentiator pinned in one place: same stacks, same block — poison
	# lands in full, burn is soaked first.
	var state := _state()
	var burned := _add_player(state, 30)
	var poisoned := _add_player(state, 30)
	_add_enemy(state, 20)
	burned.block = 10
	poisoned.block = 10
	state.apply_status(burned, &"burn", 4)
	state.apply_status(poisoned, &"poison", 4)
	state.start_player_turn()
	assert_eq(burned.hp, 30, "burn fully absorbed by block")
	assert_eq(poisoned.hp, 26, "poison ignored block entirely")


# --- Bleed ----------------------------------------------------------------------

func test_bleed_procs_when_player_plays_card_and_decays() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	var enemy := _add_enemy(state, 20)
	state.add_energy(3, player)
	state.apply_status(player, &"bleed", 3)
	var card := CardData.new()
	card.id = &"jab"
	card.display_name = "Jab"
	card.character_tag = &"neutral"
	card.energy_cost = 1
	card.target = _spec(&"enemy")
	card.effects = [_effect(&"damage", 5)] as Array[Effect]
	state.deck.hand.append(card)
	var result: CardPlay.PlayResult = CardPlayScript.new(state).play_card(player, card, enemy)
	assert_true(result.ok, "the play itself succeeds")
	assert_eq(player.hp, 27, "acting cost the bleeding caster its 3 stacks in hp")
	assert_eq(player.status_stacks(&"bleed"), 2, "bleed decayed one stack per proc")


func test_bleed_ignores_block() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	player.block = 10
	state.apply_status(player, &"bleed", 4)
	state.on_unit_acted(player)
	assert_eq(player.hp, 26, "bleed went straight to hp")
	assert_eq(player.block, 10, "block untouched — armor can't stitch a wound")


func test_bleed_does_not_tick_or_decay_per_turn() -> void:
	var state := _state()
	var player := _add_player(state, 30)
	_add_enemy(state, 20)
	state.apply_status(player, &"bleed", 3)
	state.start_player_turn()
	assert_eq(player.hp, 30, "a unit that holds still bleeds nothing")
	assert_eq(player.status_stacks(&"bleed"), 3, "no per-turn decay either")


func test_bleed_procs_when_enemy_acts() -> void:
	var battle := _battle()
	var enemy: Combatant = battle.living_enemies()[0]
	battle.apply_status(enemy, &"bleed", 4)
	var hp_before: int = enemy.hp
	battle.start_player_turn()
	battle.end_player_turn()  # enemy phase: the enemy executes its intent → proc
	assert_eq(enemy.hp, hp_before - 4, "acting enemy took its 4 bleed stacks")
	assert_eq(enemy.status_stacks(&"bleed"), 3, "bleed decayed one stack per act")


func test_stunned_enemy_does_not_proc_bleed() -> void:
	var battle := _battle()
	var enemy: Combatant = battle.living_enemies()[0]
	battle.apply_status(enemy, &"bleed", 4)
	battle.apply_status(enemy, &"stun", 1)
	var hp_before: int = enemy.hp
	battle.start_player_turn()
	battle.end_player_turn()  # stun consumes the action — no act, no proc
	assert_eq(enemy.hp, hp_before, "skipped unit did not bleed")
	assert_eq(enemy.status_stacks(&"bleed"), 4, "stacks held for the next act")


# --- Mark -----------------------------------------------------------------------

func test_mark_adds_flat_damage_per_hit_and_decrements() -> void:
	var battle := _battle()
	var enemies: Array[Combatant] = battle.living_enemies()
	var atk: Combatant = enemies[0]  # 0 attack stat → clean numbers
	var tgt: Combatant = enemies[1]
	tgt.block = 0
	tgt.hp = 50
	battle.apply_status(tgt, &"mark", 3)
	battle.deal_damage_from(atk, tgt, 10)
	assert_eq(tgt.hp, 37, "first hit: 10 + 3 mark bonus")
	assert_eq(tgt.status_stacks(&"mark"), 2, "one stack consumed per hit")
	battle.deal_damage_from(atk, tgt, 10)
	assert_eq(tgt.hp, 25, "second hit: 10 + 2 mark bonus")
	assert_eq(tgt.status_stacks(&"mark"), 1, "decrements again")


func test_mark_applies_after_vulnerable_multiplier() -> void:
	var battle := _battle()
	var enemies: Array[Combatant] = battle.living_enemies()
	var atk: Combatant = enemies[0]
	var tgt: Combatant = enemies[1]
	tgt.block = 0
	tgt.hp = 50
	battle.apply_status(tgt, &"vulnerable", 2)
	battle.apply_status(tgt, &"mark", 3)
	battle.deal_damage_from(atk, tgt, 10)
	assert_eq(tgt.hp, 32, "floor(10 × 1.5) + 3 = 18 — flat bonus AFTER the multiplier")


func test_mark_amplifies_card_effect_damage() -> void:
	# The apply_effects (card/intent) path consumes Mark exactly like the
	# source-aware path.
	var state := _state()
	var player := _add_player(state, 30)
	var enemy := _add_enemy(state, 50)
	state.apply_status(enemy, &"mark", 2)
	state.apply_effects(player, enemy, [_effect(&"damage", 5)])
	assert_eq(enemy.hp, 43, "5 + 2 mark bonus")
	assert_eq(enemy.status_stacks(&"mark"), 1, "one stack consumed")


func test_mark_does_not_affect_bare_damage_or_dots() -> void:
	# Mark is attack-only, like Vulnerable: bare deal_damage (the poison/burn tick
	# path) neither gains the bonus nor consumes a stack.
	var battle := _battle()
	var tgt: Combatant = battle.living_enemies()[0]
	tgt.block = 0
	tgt.hp = 50
	battle.apply_status(tgt, &"mark", 3)
	battle.deal_damage(tgt, 6)
	assert_eq(tgt.hp, 44, "bare damage unamplified")
	assert_eq(tgt.status_stacks(&"mark"), 3, "no stack consumed")


# --- Loaded as real statuses ----------------------------------------------------

func test_new_statuses_load() -> void:
	assert_not_null(_db.get_status(&"burn"), "burn StatusData loads")
	assert_not_null(_db.get_status(&"bleed"), "bleed StatusData loads")
	assert_not_null(_db.get_status(&"mark"), "mark StatusData loads")
	assert_true(_db.get_status(&"burn").decays_each_turn, "burn decays per turn")
	assert_false(_db.get_status(&"bleed").decays_each_turn, "bleed decays per ACT instead")
	assert_false(_db.get_status(&"mark").decays_each_turn, "mark decays per HIT instead")


func test_ult_firestorm_applies_real_burn() -> void:
	# HANDOFF: "Burn is currently faked with poison in Ult recipes" — no longer.
	var card: CardData = _db.get_card(&"ult_firestorm")
	assert_not_null(card, "ult_firestorm loads")
	var statuses: Array[StringName] = []
	for e in card.effects:
		if e.type == &"apply_status":
			statuses.append(e.status)
	assert_has(statuses, &"burn", "Firestorm applies burn")
	assert_does_not_have(statuses, &"poison", "the poison fake is gone")
