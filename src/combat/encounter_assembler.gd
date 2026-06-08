class_name EncounterAssembler
extends RefCounted
## Turns authored content (an EncounterData + the loaded ContentDatabase + a chosen
## party) into a ready-to-run battle (task P1·09 integration). This is the seam
## that binds the data layer (ContentDatabase, P1·11) to the runtime combat spine
## (BattleState/Combatant/Deck, P1·04) and wires the enemy AI (P1·08) into the
## turn loop via the EncounterBattle subclass.
##
## Positionless (ADR-0013): no grid is built. The party spawns as Combatants from
## the resolved CharacterData; enemies spawn from `encounter.enemies` (a list of
## ids resolved to EnemyData via the db). The run layer's combat node feeds the
## RunState's party + carried HP + run deck through this same seam (ADR-0012).
##
## It only ORCHESTRATES existing modules through their public APIs; it adds no game
## rules and hardcodes no balance numbers (ADR-0003).
##
## build() does, in order:
##   1. The shared Deck (BattleConfig from the db) assembled from the chosen party
##      characters' `starting_deck`s (innate cards excluded by Deck.assemble,
##      ADR-0005), resolving card ids through the db.
##   2. An EncounterBattle (BattleState subclass) holding the deck and the db's
##      status definitions, with an injected EnemyAI wired into its enemy hook.
##   3. Player Combatants via from_character for each resolved party member; enemy
##      Combatants via from_enemy for each id in `encounter.enemies`, all
##      registered through add_combatant.


## Assemble a runnable EncounterBattle for `encounter`, drawing all content from
## `db` and spawning the party named by `party_ids` (resolved to CharacterData via
## the db). `rng_seed` seeds both the shared deck's shuffle and the enemy AI so a
## fixed seed reproduces a battle. The returned battle is registered but NOT yet
## started — the caller drives the turn loop (start_player_turn / end_player_turn).
func build(
	encounter: EncounterData,
	db: ContentDatabase,
	party_ids: Array[StringName],
	rng_seed: int = 0
) -> EncounterBattle:
	var config: BattleConfig = db.get_battle_config()
	if config == null:
		config = BattleConfig.new()

	var party: Array[CharacterData] = _resolve_party(db, party_ids)

	var deck: Deck = Deck.new(config, rng_seed)
	deck.assemble(party, db.cards)

	var ai: EnemyAI = EnemyAI.new(rng_seed)
	var battle: EncounterBattle = EncounterBattle.new(config, deck, db.statuses, ai)
	battle.win_condition = encounter.win_condition
	battle.win_param = encounter.win_param

	_spawn_players(battle, party)
	_spawn_enemies(battle, encounter, db)

	return battle


## Read the current battle outcome (convenience over BattleState.check_outcome()).
func current_outcome(battle: BattleState) -> BattleState.Outcome:
	return battle.check_outcome()


# --- Party / spawning -------------------------------------------------------

## Resolve party character ids to CharacterData via the db, preserving order and
## skipping any id that does not resolve (a dangling party id is a caller error;
## reference validity within /data is the loader's job).
func _resolve_party(db: ContentDatabase, party_ids: Array[StringName]) -> Array[CharacterData]:
	var party: Array[CharacterData] = []
	for id in party_ids:
		var character: CharacterData = db.get_character(id)
		if character != null:
			party.append(character)
	return party


## Spawn one player Combatant per resolved party character, registering each with
## the battle.
func _spawn_players(battle: BattleState, party: Array[CharacterData]) -> void:
	for character in party:
		battle.add_combatant(Combatant.from_character(character))


## Spawn one enemy Combatant per id in `encounter.enemies`, looking up its
## EnemyData in the db. Ids that do not resolve are skipped (loader validation
## guarantees ids resolve for /data; this keeps assembly robust with partial content).
func _spawn_enemies(battle: BattleState, encounter: EncounterData, db: ContentDatabase) -> void:
	for enemy_id in encounter.enemies:
		var data: EnemyData = db.get_enemy(enemy_id)
		if data == null:
			continue
		battle.add_combatant(Combatant.from_enemy(data))
