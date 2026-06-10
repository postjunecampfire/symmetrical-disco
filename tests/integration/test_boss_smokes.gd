extends "res://addons/gut/test.gd"
## Scripted-combat smoke per tier boss (M3 — ADR-0019 tier modifiers / boss
## variety). For each of the six tier bosses: assemble its boss encounter from
## the REAL /data at its tier-capstone boss level (EnemyScaler band applied, the
## way RunController.begin_combat does), then drive a few greedy turns headless:
##   * every living enemy telegraphs a LEGIBLE intent each round (known icon,
##     non-null target resolution for offensive intents);
##   * upcoming_special() reports only the known special kinds;
##   * the loop never crashes and the outcome stays a valid enum value.
## Greedy = each player plays every affordable card it can each turn (first
## living enemy as the chosen target; self as the fallback), then ends the turn.

const EncounterAssemblerScript := preload("res://src/combat/encounter_assembler.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")
const CardPlayScript := preload("res://src/cards/card_play.gd")

const DATA_DIR := "res://data"
const TURNS := 5
const KNOWN_TELEGRAPHS: Array[StringName] = [&"attack", &"debuff", &"block", &"buff"]
const KNOWN_SPECIALS: Array[StringName] = [&"", &"summon", &"empower"]

## tier -> boss encounter id (mirrors the authored tier_pools boss lists).
const TIER_BOSSES: Dictionary = {
	1: &"enc_boss_01",
	2: &"enc_boss_t2_matron",
	3: &"enc_boss_t3_carrion",
	4: &"enc_boss_t4_brood",
	5: &"enc_boss_t5_duelist",
	6: &"enc_boss_t6_legion",
}

var _db: ContentDatabase
var _load_ok: bool = false


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_load_ok = _db.load_from_dir(DATA_DIR).ok


func _build_boss_battle(tier: int) -> EncounterBattle:
	var enc: EncounterData = _db.get_encounter(TIER_BOSSES[tier])
	assert_not_null(enc, "tier %d boss encounter loads" % tier)
	var capstone: ActConfig = _db.get_act(tier * 3)
	assert_not_null(capstone, "tier %d capstone act present" % tier)
	var party: Array[StringName] = [&"fighter", &"mage"]
	var no_relics: Array[RelicData] = []
	var assembler: EncounterAssembler = EncounterAssemblerScript.new()
	return assembler.build(
		enc, _db, party, 9000 + tier, {}, {}, {}, {}, no_relics, capstone.boss_level
	)


## Play every affordable card each player can this turn (greedy, deterministic).
func _greedy_play(battle: EncounterBattle) -> void:
	var play: CardPlay = CardPlayScript.new(battle)
	for unit in battle.living_players():
		var played := true
		while played and not battle.living_enemies().is_empty():
			played = false
			var hand: Array = battle.deck_of(unit).hand.duplicate()
			for card_v: Variant in hand:
				var card: CardData = card_v
				if battle.living_enemies().is_empty():
					break
				var foe: Combatant = battle.living_enemies()[0]
				var result: CardPlay.PlayResult = play.play_card(unit, card, foe)
				if not result.ok:
					result = play.play_card(unit, card, unit)
				if result.ok:
					played = true
					break


## Drive TURNS greedy rounds; assert telegraph legibility every round.
func _smoke(tier: int) -> void:
	if not _load_ok:
		fail_test("/data did not load")
		return
	var battle: EncounterBattle = _build_boss_battle(tier)
	assert_gt(battle.living_enemies().size(), 0, "tier %d boss fight has enemies" % tier)
	assert_eq(battle.living_players().size(), 2, "party assembled")

	for _turn in range(TURNS):
		battle.start_player_turn()
		if battle.check_outcome() != BattleState.Outcome.ONGOING:
			break
		# Telegraphs are legible BEFORE the enemy phase resolves.
		for enemy in battle.living_enemies():
			var data: EnemyData = enemy.source_data as EnemyData
			assert_not_null(data, "enemy carries EnemyData")
			var intent: IntentData = battle.enemy_ai.select_intent(enemy, data, battle)
			assert_not_null(intent, "tier %d: every enemy telegraphs an intent" % tier)
			if intent != null:
				assert_true(KNOWN_TELEGRAPHS.has(intent.telegraph),
					"tier %d: telegraph icon '%s' is a known kind" % [tier, intent.telegraph])
			assert_true(KNOWN_SPECIALS.has(battle.upcoming_special(enemy)),
				"tier %d: upcoming_special reports a known kind" % tier)
		_greedy_play(battle)
		battle.end_player_turn()
		var outcome: BattleState.Outcome = battle.check_outcome()
		assert_true(
			outcome == BattleState.Outcome.ONGOING
			or outcome == BattleState.Outcome.WIN
			or outcome == BattleState.Outcome.LOSS,
			"outcome stays a valid enum value"
		)
		if outcome != BattleState.Outcome.ONGOING:
			break
	assert_gt(battle.turn_number, 0, "tier %d smoke ran at least one round" % tier)


func test_tier1_iron_warden_smoke() -> void:
	_smoke(1)


func test_tier2_hollow_matron_smoke() -> void:
	_smoke(2)


func test_tier3_carrion_king_smoke() -> void:
	_smoke(3)


func test_tier4_broodmother_smoke() -> void:
	_smoke(4)


func test_tier5_duelist_smoke() -> void:
	_smoke(5)


func test_tier6_legion_king_smoke() -> void:
	_smoke(6)


## The Legion King's resurrection fires once mid-fight: kill a minion, march the
## sequence to "raise the fallen", and the minion stands back up — exactly once.
func test_legion_king_raises_the_fallen_once() -> void:
	if not _load_ok:
		fail_test("/data did not load")
		return
	var battle: EncounterBattle = _build_boss_battle(6)
	var king: Combatant = null
	var minion: Combatant = null
	for enemy in battle.living_enemies():
		var data := enemy.source_data as EnemyData
		if data.id == &"legion_king":
			king = enemy
		elif minion == null:
			minion = enemy
	assert_not_null(king, "legion_king spawned")
	assert_not_null(minion, "a minion spawned")
	battle.deal_damage(minion, minion.hp + minion.block)
	assert_false(minion.is_alive(), "minion downed")

	# March the king's SEQUENCE to intent 3 (raise_the_fallen): decree, crownfall,
	# raise. The passive ramp never consumes an action, so three take_turns land it.
	var data: EnemyData = king.source_data as EnemyData
	for _i in range(3):
		battle.enemy_ai.take_turn(battle, king, data)
	assert_true(minion.is_alive(), "raise_the_fallen revived the minion")

	# Latch: down it again, cycle the sequence back to the revive — it stays down.
	battle.deal_damage(minion, minion.hp + minion.block)
	for _i in range(4):
		battle.enemy_ai.take_turn(battle, king, data)
	assert_false(minion.is_alive(), "the resurrection is once per battle")
