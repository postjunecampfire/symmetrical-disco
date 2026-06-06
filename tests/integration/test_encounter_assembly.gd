extends "res://addons/gut/test.gd"
## GUT integration suite for task P1·09 — Encounter assembly & win/lose wiring.
##
## This is the END-TO-END seam test: it loads the REAL authored content from
## res://data (validating P1·11's content as a side effect), assembles the
## `skirmish_01` encounter for a chosen party through EncounterAssembler, and
## drives the resulting EncounterBattle to assert:
##   - the real /data load is ok (and, if not, surfaces the exact errors);
##   - the assembled battle has the right grid size, the right player/enemy
##     Combatants at the encounter's spawn positions, and a deck assembled from
##     the party's starting decks with innate cards excluded;
##   - the enemy AI is wired into the turn loop (enemies act on the enemy phase:
##     a player takes damage and/or an enemy moves);
##   - a scripted path to all-enemies-dead reports a WIN via check_outcome();
##   - a scripted path to all-players-dead reports a LOSS.
##
## It builds nothing by hand that the assembler should build — the point is to
## exercise the integration, not to mock around it.

const EncounterAssemblerScript := preload("res://src/combat/encounter_assembler.gd")
const EncounterBattleScript := preload("res://src/combat/encounter_battle.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")

const DATA_DIR := "res://data"
const ENCOUNTER_ID: StringName = &"skirmish_01"

var _db: ContentDatabase
var _load_ok: bool = false


# --- Shared setup -----------------------------------------------------------

## Load the real content once per test. Kept here (not before_all) so each test
## gets a clean database and the load itself is part of what every test exercises.
func before_each() -> void:
	_db = ContentDatabaseScript.new()
	var result: ContentDatabase.LoadResult = _db.load_from_dir(DATA_DIR)
	_load_ok = result.ok
	if not result.ok:
		# Surface the EXACT validation errors so a content regression in /data is
		# diagnosable from the test output (the task asks us to report, not edit).
		for msg in result.errors:
			push_warning("[/data load error] " + msg)


func _assembler() -> EncounterAssembler:
	return EncounterAssemblerScript.new()


func _party() -> Array[StringName]:
	return [&"vanguard", &"mage"] as Array[StringName]


func _build() -> EncounterBattle:
	var encounter: EncounterData = _db.get_encounter(ENCOUNTER_ID)
	assert_not_null(encounter, "encounter '%s' loaded from /data" % ENCOUNTER_ID)
	return _assembler().build(encounter, _db, _party(), 12345)


# ============================================================================
#  1. Real content loads and validates (end-to-end check of P1·11)
# ============================================================================

func test_real_data_loads_ok() -> void:
	assert_true(
		_load_ok,
		"ContentDatabase.load_from_dir('res://data') reports ok (see warnings for any errors)"
	)
	assert_not_null(_db.get_battle_config(), "battle_config loaded")
	assert_not_null(_db.get_encounter(ENCOUNTER_ID), "skirmish_01 encounter present")
	assert_not_null(_db.get_character(&"vanguard"), "vanguard character present")
	assert_not_null(_db.get_character(&"mage"), "mage character present")


# ============================================================================
#  2. Assembly: grid, combatants at spawns, deck (innate excluded)
# ============================================================================

func test_assembled_grid_matches_encounter_size() -> void:
	var battle: EncounterBattle = _build()
	var encounter: EncounterData = _db.get_encounter(ENCOUNTER_ID)
	assert_eq(battle.grid.size, encounter.grid_size, "grid sized to encounter.grid_size")
	assert_eq(battle.grid.size, Vector2i(6, 6), "skirmish_01 is a 6x6 grid")


func test_assembled_spawns_players_and_enemies_at_positions() -> void:
	var battle: EncounterBattle = _build()
	var encounter: EncounterData = _db.get_encounter(ENCOUNTER_ID)

	var players: Array[Combatant] = battle.living_players()
	var enemies: Array[Combatant] = battle.living_enemies()
	assert_eq(players.size(), 2, "two party members spawned (vanguard, mage)")
	assert_eq(
		enemies.size(), encounter.enemy_spawns.size(),
		"one enemy spawned per enemy_spawns entry"
	)
	assert_eq(enemies.size(), 3, "skirmish_01 has three enemies (grunt, archer, brute)")

	# Players occupy the encounter's player_spawns (order preserved by the assembler).
	for i in range(players.size()):
		assert_eq(
			players[i].grid_position, encounter.player_spawns[i],
			"player %d at its spawn %s" % [i, encounter.player_spawns[i]]
		)
		# The grid occupant registry is in sync with the unit.
		assert_eq(
			battle.grid.get_occupant(players[i].grid_position), players[i],
			"player %d registered on the grid" % i
		)

	# Each enemy spawn position holds an enemy of the named id.
	for spawn in encounter.enemy_spawns:
		var pos: Vector2i = spawn.get("pos", Vector2i.ZERO)
		var enemy_id: StringName = spawn.get("enemy", &"")
		var occupant: Variant = battle.grid.get_occupant(pos)
		assert_true(occupant is Combatant, "an enemy occupies spawn %s" % pos)
		var unit: Combatant = occupant as Combatant
		assert_eq(unit.team, Combatant.Team.ENEMY, "occupant at %s is on the enemy team" % pos)
		var data: EnemyData = unit.source_data as EnemyData
		assert_eq(data.id, enemy_id, "enemy at %s is '%s'" % [pos, enemy_id])


func test_deck_assembled_from_party_and_excludes_innate() -> void:
	var battle: EncounterBattle = _build()
	var vanguard: CharacterData = _db.get_character(&"vanguard")
	var mage: CharacterData = _db.get_character(&"mage")

	# Expected non-innate count = union of both starting decks minus any innate card.
	var expected: int = 0
	for character in [vanguard, mage]:
		for card_id in character.starting_deck:
			var card: CardData = _db.get_card(card_id)
			if card != null and not card.innate:
				expected += 1

	assert_gt(expected, 0, "the party contributes a non-empty starting deck")
	assert_eq(
		battle.deck.total_in_cycle(), expected,
		"deck holds exactly the party's non-innate starting cards"
	)

	# Innate Strike/Defend must NOT be in the assembled deck (ADR-0005).
	for card in battle.deck.all_cards():
		assert_false(card.innate, "no innate card '%s' is in the deck" % card.id)
		assert_false(
			card.id == &"strike" or card.id == &"defend",
			"innate '%s' is excluded from the deck" % card.id
		)


# ============================================================================
#  3. Enemy AI wired into the turn loop
# ============================================================================

func test_enemy_phase_drives_ai_enemies_act() -> void:
	var battle: EncounterBattle = _build()
	assert_not_null(battle.enemy_ai, "an EnemyAI is injected into the battle")

	# Snapshot pre-phase state: total player HP and each enemy's position.
	var players_hp_before: int = 0
	for p in battle.living_players():
		players_hp_before += p.hp
	var enemy_positions_before: Dictionary = {}
	for e in battle.living_enemies():
		enemy_positions_before[e] = e.grid_position

	# Run one full player turn so the enemy phase fires (end_player_turn ->
	# _run_enemy_phase -> _take_enemy_action -> enemy_ai.take_turn).
	battle.start_player_turn()
	battle.end_player_turn()

	var players_hp_after: int = 0
	for p in battle.living_players():
		players_hp_after += p.hp

	var any_enemy_moved: bool = false
	for e in battle.living_enemies():
		if enemy_positions_before.has(e) and enemy_positions_before[e] != e.grid_position:
			any_enemy_moved = true
			break

	# The AI either closed distance (moved) or struck a player (hp dropped). Both
	# only happen if take_turn() actually ran via the overridden hook.
	assert_true(
		any_enemy_moved or players_hp_after < players_hp_before,
		"enemies acted via the AI on the enemy phase (a player took damage or an enemy moved)"
	)


# ============================================================================
#  4. Win: scripted defeat of all enemies -> WIN
# ============================================================================

func test_killing_all_enemies_reports_win() -> void:
	var battle: EncounterBattle = _build()
	assert_eq(
		battle.check_outcome(), BattleState.Outcome.ONGOING,
		"battle starts ONGOING with both sides alive"
	)

	# Script lethal damage onto every enemy through the real damage path.
	for enemy in battle.living_enemies():
		battle.deal_damage(enemy, enemy.hp + enemy.block + 1)

	assert_eq(battle.living_enemies().size(), 0, "all enemies are dead")
	assert_eq(battle.check_outcome(), BattleState.Outcome.WIN, "all enemies dead => WIN")

	# Convenience reader returns the same outcome.
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
