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
## `carried_hp` (character_id -> hp) lets the run layer (ADR-0012 §8) spawn party
## members at their carried-over HP instead of full; a downed unit's revive value
## is resolved by the caller before this. Omitted/empty -> everyone spawns full.
func build(
	encounter: EncounterData,
	db: ContentDatabase,
	party_ids: Array[StringName],
	rng_seed: int = 0,
	carried_hp: Dictionary = {},
	party_races: Dictionary = {}
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
	# Race modifiers (ADR-0015) apply on top of the base class before carried HP,
	# so race CON raises max HP and carried HP then sets current HP correctly.
	if not party_races.is_empty():
		_apply_races(battle, party_races, db, config.hp_per_con)
	if not carried_hp.is_empty():
		_apply_carried_hp(battle, carried_hp)
	_spawn_enemies(battle, encounter, db)

	return battle


## Apply each player's chosen race (character_id -> race_id) on top of its class.
func _apply_races(battle: BattleState, party_races: Dictionary, db: ContentDatabase, hp_per_con: int) -> void:
	for unit in battle.combatants:
		if not unit.is_player():
			continue
		var data := unit.source_data as CharacterData
		if data == null:
			continue
		var race_id: StringName = party_races.get(data.id, &"")
		if race_id == &"":
			continue
		var race: RaceData = db.get_race(race_id)
		if race != null:
			unit.apply_race(race, hp_per_con)


## Override each player's spawn HP from `carried_hp` (clamped to max_hp).
func _apply_carried_hp(battle: BattleState, carried_hp: Dictionary) -> void:
	for unit in battle.combatants:
		if not unit.is_player():
			continue
		var data := unit.source_data as CharacterData
		if data != null and carried_hp.has(data.id):
			unit.hp = clampi(int(carried_hp[data.id]), 0, unit.max_hp)


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
