extends "res://addons/gut/test.gd"
## GUT integration suite for task P1·09 — Encounter assembly & win/lose wiring
## (positionless, ADR-0013).
##
## This is the END-TO-END seam test: it loads the REAL authored content from
## res://data, assembles the `skirmish_01` encounter for a chosen party through
## EncounterAssembler, and drives the resulting EncounterBattle to assert:
##   - the real /data load is ok (and, if not, surfaces the exact errors);
##   - the assembled battle has the right player/enemy Combatants and a deck
##     assembled from the party's starting decks with innate cards excluded;
##   - the enemy AI is wired into the turn loop (a player takes damage on the
##     enemy phase within a few turns);
##   - a scripted path to all-enemies-dead reports a WIN via check_outcome();
##   - a scripted path to all-players-dead reports a LOSS.

const EncounterAssemblerScript := preload("res://src/combat/encounter_assembler.gd")
const EncounterBattleScript := preload("res://src/combat/encounter_battle.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")

const DATA_DIR := "res://data"
const ENCOUNTER_ID: StringName = &"skirmish_01"

var _db: ContentDatabase
var _load_ok: bool = false


# --- Shared setup -----------------------------------------------------------

func before_each() -> void:
	_db = ContentDatabaseScript.new()
	var result: ContentDatabase.LoadResult = _db.load_from_dir(DATA_DIR)
	_load_ok = result.ok
	if not result.ok:
		for msg in result.errors:
			push_warning("[/data load error] " + msg)


func _assembler() -> EncounterAssembler:
	return EncounterAssemblerScript.new()


func _party() -> Array[StringName]:
	return [&"fighter", &"mage"] as Array[StringName]


func _build() -> EncounterBattle:
	var encounter: EncounterData = _db.get_encounter(ENCOUNTER_ID)
	assert_not_null(encounter, "encounter '%s' loaded from /data" % ENCOUNTER_ID)
	return _assembler().build(encounter, _db, _party(), 12345)


# ============================================================================
#  1. Real content loads and validates
# ============================================================================

func test_real_data_loads_ok() -> void:
	assert_true(
		_load_ok,
		"ContentDatabase.load_from_dir('res://data') reports ok (see warnings for any errors)"
	)
	assert_not_null(_db.get_battle_config(), "battle_config loaded")
	assert_not_null(_db.get_encounter(ENCOUNTER_ID), "skirmish_01 encounter present")
	assert_not_null(_db.get_character(&"fighter"), "vanguard character present")
	assert_not_null(_db.get_character(&"mage"), "mage character present")


# ============================================================================
#  2. Assembly: combatants, deck (innate excluded)
# ============================================================================

func test_assembled_spawns_players_and_enemies() -> void:
	var battle: EncounterBattle = _build()
	var encounter: EncounterData = _db.get_encounter(ENCOUNTER_ID)

	var players: Array[Combatant] = battle.living_players()
	var enemies: Array[Combatant] = battle.living_enemies()
	assert_eq(players.size(), 2, "two party members spawned (vanguard, mage)")
	assert_eq(
		enemies.size(), encounter.enemies.size(),
		"one enemy spawned per encounter.enemies entry"
	)
	assert_eq(enemies.size(), 3, "skirmish_01 has three enemies (grunt, archer, brute)")

	# Each enemy combatant carries the matching authored EnemyData.
	var spawned_ids: Array = []
	for unit in enemies:
		assert_eq(unit.team, Combatant.Team.ENEMY, "enemy unit is on the enemy team")
		var data: EnemyData = unit.source_data as EnemyData
		assert_not_null(data, "enemy carries EnemyData")
		spawned_ids.append(data.id)
	for enemy_id in encounter.enemies:
		assert_true(spawned_ids.has(enemy_id), "enemy '%s' was spawned" % enemy_id)


func test_each_member_gets_a_derived_deck_with_basics(  ) -> void:
	# ADR-0026: each member fights with their OWN deck, derived from their kit;
	# Strike/Defend are ordinary commons that pad the deck to the floor (the
	# ADR-0005 innate model is reversed).
	var battle: EncounterBattle = _build()
	var floor_n: int = _db.get_battle_config().derived_deck_floor
	for unit in battle.living_players():
		var deck: Deck = battle.deck_of(unit)
		assert_gte(deck.total_in_cycle(), floor_n, "member deck meets the %d-card floor" % floor_n)
		var has_basic: bool = false
		for card in deck.all_cards():
			if card.id == &"strike" or card.id == &"defend":
				has_basic = true
				break
		assert_true(has_basic, "auto-fill basics are present in the derived deck")
	# The two members' decks are independent objects.
	var players := battle.living_players()
	if players.size() >= 2:
		assert_ne(battle.deck_of(players[0]), battle.deck_of(players[1]), "per-member decks are distinct (ADR-0026)")


# ============================================================================
#  3. Enemy AI wired into the turn loop
# ============================================================================

func test_enemy_phase_drives_ai_enemies_act() -> void:
	var battle: EncounterBattle = _build()
	assert_not_null(battle.enemy_ai, "an EnemyAI is injected into the battle")

	# Run up to a few full turns; with mostly-offensive enemies, a player takes
	# damage on the enemy phase. (Positionless: enemies attack rather than move.)
	var hp_before: int = _total_player_hp(battle)
	var damaged: bool = false
	for _turn in range(3):
		battle.start_player_turn()
		battle.end_player_turn()
		if _total_player_hp(battle) < hp_before:
			damaged = true
			break

	assert_true(damaged, "a player took damage on the enemy phase (AI ran via the hook)")


func _total_player_hp(battle: BattleState) -> int:
	var total: int = 0
	for p in battle.living_players():
		total += p.hp
	return total


# ============================================================================
#  4. Win: scripted defeat of all enemies -> WIN
# ============================================================================

func test_killing_all_enemies_reports_win() -> void:
	var battle: EncounterBattle = _build()
	assert_eq(
		battle.check_outcome(), BattleState.Outcome.ONGOING,
		"battle starts ONGOING with both sides alive"
	)

	for enemy in battle.living_enemies():
		battle.deal_damage(enemy, enemy.hp + enemy.block + 1)

	assert_eq(battle.living_enemies().size(), 0, "all enemies are dead")
	assert_eq(battle.check_outcome(), BattleState.Outcome.WIN, "all enemies dead => WIN")

	assert_eq(
		_assembler().current_outcome(battle), BattleState.Outcome.WIN,
		"current_outcome() mirrors check_outcome()"
	)


# ============================================================================
#  5. Loss: scripted defeat of all players -> LOSS
# ============================================================================

func test_killing_all_players_reports_loss() -> void:
	var battle: EncounterBattle = _build()
	assert_eq(
		battle.check_outcome(), BattleState.Outcome.ONGOING,
		"battle starts ONGOING"
	)

	for player in battle.living_players():
		battle.deal_damage(player, player.hp + player.block + 1)

	assert_eq(battle.living_players().size(), 0, "all players are dead")
	assert_eq(battle.check_outcome(), BattleState.Outcome.LOSS, "all players dead => LOSS")
