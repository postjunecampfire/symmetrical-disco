class_name EncounterAssembler
extends RefCounted

## Applies relic effects (P2·12) at assembly (passive + combat_start).
var _relic_engine: RelicEngine = RelicEngine.new()
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
## `run_deck` (optional, P2·06 / ADR-0015): when non-empty, the shared combat deck
## is assembled from these card ids — the run's accumulated deck (starting cards +
## race custom cards + drafted rewards) — instead of the party starting decks, so
## race/reward cards actually appear in fights. Omitted/empty -> fall back to the
## party starting decks (original behaviour). Race STAT mods apply regardless (via
## `party_races`); this wires only the CARDS.
## `allocated_stats` (optional, P3·05 / ADR-0015): character_id -> {str,dex,con,int}
## player-allocated level-up points; applied on top of class + race so a levelled
## character fights with its chosen growth (CON points also raise max HP). Applied
## BEFORE carried HP so the carried value clamps to the grown max.
## `relics` (optional, P2·12): RelicData the run carries. Their `passive` effects
## (max_hp_up) apply before carried HP (so the carried value clamps to the raised
## max) and their `combat_start` effects (block/strength) apply after HP is set;
## `turn_start` relics fire each player turn via EncounterBattle. Stored on the
## battle so the turn hook can read them.
func build(
	encounter: EncounterData,
	db: ContentDatabase,
	party_ids: Array[StringName],
	rng_seed: int = 0,
	carried_hp: Dictionary = {},
	party_races: Dictionary = {},
	run_deck: Array[StringName] = [],
	allocated_stats: Dictionary = {},
	relics: Array = []
) -> EncounterBattle:
	var config: BattleConfig = db.get_battle_config()
	if config == null:
		config = BattleConfig.new()

	var party: Array[CharacterData] = _resolve_party(db, party_ids)

	var deck: Deck = Deck.new(config, rng_seed)
	if run_deck.is_empty():
		deck.assemble(party, db.cards)
	else:
		deck.assemble_from_card_ids(run_deck, db.cards)

	var ai: EnemyAI = EnemyAI.new(rng_seed)
	var battle: EncounterBattle = EncounterBattle.new(config, deck, db.statuses, ai)
	battle.win_condition = encounter.win_condition
	battle.win_param = encounter.win_param

	_spawn_players(battle, party)
	# Race modifiers (ADR-0015) apply on top of the base class before carried HP,
	# so race CON raises max HP and carried HP then sets current HP correctly.
	if not party_races.is_empty():
		_apply_races(battle, party_races, db, config.hp_per_con)
	# Player-allocated level-up points (P3·05) land on top of class + race, before
	# carried HP, so CON points raise max HP and the carried value clamps to it.
	if not allocated_stats.is_empty():
		_apply_allocations(battle, allocated_stats, config.hp_per_con)
	# Relics (P2·12): store on the battle (turn_start fires each turn), apply passive
	# max-HP before carried HP, then combat_start buffs after HP is set.
	battle.relics = relics
	if not relics.is_empty():
		_relic_engine.apply_passive(battle, relics)
	if not carried_hp.is_empty():
		_apply_carried_hp(battle, carried_hp)
	if not relics.is_empty():
		_relic_engine.apply_combat_start(battle, relics)
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


## Apply each player's allocated level-up points (character_id -> {stat -> points})
## on top of class + race (P3·05 / ADR-0015).
func _apply_allocations(battle: BattleState, allocated_stats: Dictionary, hp_per_con: int) -> void:
	for unit in battle.combatants:
		if not unit.is_player():
			continue
		var data := unit.source_data as CharacterData
		if data == null:
			continue
		var alloc_v: Variant = allocated_stats.get(data.id, {})
		if alloc_v is Dictionary and not (alloc_v as Dictionary).is_empty():
			unit.apply_stat_allocation(alloc_v, hp_per_con)


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
