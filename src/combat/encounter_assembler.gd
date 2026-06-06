class_name EncounterAssembler
extends RefCounted
## Turns authored content (an EncounterData + the loaded ContentDatabase + a chosen
## party) into a ready-to-run battle (task P1·09 integration). This is the seam
## that binds the data layer (ContentDatabase, P1·11) to the runtime combat spine
## (BattleState/Combatant/Deck/GridModel, P1·04) and wires the enemy AI (P1·08)
## into the turn loop via the EncounterBattle subclass.
##
## It only ORCHESTRATES existing, passing modules through their public APIs; it
## adds no game rules and hardcodes no balance numbers (ADR-0003) — every tunable
## comes from the BattleConfig and the authored resources the database supplies.
##
## build() does, in order:
##   1. GridModel from `encounter.grid_size`, with `encounter.terrain` cells whose
##      kind is `blocked` marked impassable.
##   2. The shared Deck (BattleConfig from the db) assembled from the chosen party
##      characters' `starting_deck`s (innate cards excluded by Deck.assemble,
##      ADR-0005), resolving card ids through the db.
##   3. An EncounterBattle (BattleState subclass) holding the grid, deck, and the
##      db's status definitions, with an injected EnemyAI wired into its enemy hook.
##   4. Player Combatants via from_character at `encounter.player_spawns`, enemy
##      Combatants via from_enemy (looked up in the db) at each `enemy_spawns`
##      entry, all registered through add_combatant (which also places them on the
##      grid).
##
## Win/lose is left to BattleState.check_outcome() (defeat_all is the prototype
## condition); current_outcome() below is a thin convenience over it.

## Terrain kind (data-schemas.md §6 / GridModel) that makes a tile impassable.
const TERRAIN_BLOCKED: StringName = &"blocked"


## Assemble a runnable EncounterBattle for `encounter`, drawing all content from
## `db` and spawning the party named by `party_ids` (resolved to CharacterData via
## the db). `rng_seed` seeds both the shared deck's shuffle and the enemy AI so a
## fixed seed reproduces a battle (determinism the underlying modules already
## guarantee). The returned battle is registered and placed but NOT yet started —
## the caller drives the turn loop (start_player_turn / end_player_turn).
func build(
	encounter: EncounterData,
	db: ContentDatabase,
	party_ids: Array[StringName],
	rng_seed: int = 0
) -> EncounterBattle:
	var config: BattleConfig = db.get_battle_config()
	if config == null:
		config = BattleConfig.new()

	var grid: GridModel = _build_grid(encounter)
	var party: Array[CharacterData] = _resolve_party(db, party_ids)

	var deck: Deck = Deck.new(config, rng_seed)
	deck.assemble(party, db.cards)

	var ai: EnemyAI = EnemyAI.new(rng_seed)
	var battle: EncounterBattle = EncounterBattle.new(
		config, grid, deck, db.statuses, ai
	)
	battle.win_condition = encounter.win_condition
	battle.win_param = encounter.win_param

	_spawn_players(battle, encounter, party)
	_spawn_enemies(battle, encounter, db)

	return battle


## Read the current battle outcome (convenience over BattleState.check_outcome()).
## ONGOING until defeat_all is met; WIN when all enemies are dead, LOSS when all
## players are dead.
func current_outcome(battle: BattleState) -> BattleState.Outcome:
	return battle.check_outcome()


# --- Grid -------------------------------------------------------------------

## Build the GridModel sized to the encounter and mark `blocked` terrain cells
## impassable. Non-blocked terrain (cover/hazard) is accepted but left as plains
## (the prototype's terrain-cost table is deferred — data-schemas.md §6).
func _build_grid(encounter: EncounterData) -> GridModel:
	var grid: GridModel = GridModel.new(encounter.grid_size)
	for cell in encounter.terrain:
		if typeof(cell) != TYPE_DICTIONARY:
			continue
		var kind: StringName = cell.get("terrain", &"plains")
		if kind == TERRAIN_BLOCKED:
			var pos: Vector2i = cell.get("pos", Vector2i.ZERO)
			grid.set_blocked(pos, true)
	return grid


# --- Party / spawning -------------------------------------------------------

## Resolve party character ids to CharacterData via the db, preserving order and
## skipping any id that does not resolve (a dangling party id is a caller error;
## reference validity within /data is the loader's job, not the assembler's).
func _resolve_party(db: ContentDatabase, party_ids: Array[StringName]) -> Array[CharacterData]:
	var party: Array[CharacterData] = []
	for id in party_ids:
		var character: CharacterData = db.get_character(id)
		if character != null:
			party.append(character)
	return party


## Spawn one player Combatant per resolved party character at the matching
## `player_spawns` index, registering each with the battle (which places it on the
## grid). Spawns are paired by index; extra characters or extra spawns beyond the
## shorter list are ignored (a content authoring concern flagged by P1·11, not the
## assembler's to enforce).
func _spawn_players(battle: BattleState, encounter: EncounterData, party: Array[CharacterData]) -> void:
	var count: int = min(party.size(), encounter.player_spawns.size())
	for i in range(count):
		var unit: Combatant = Combatant.from_character(party[i], encounter.player_spawns[i])
		battle.add_combatant(unit)


## Spawn one enemy Combatant per `enemy_spawns` entry, looking up its EnemyData in
## the db and placing it at the entry's `pos`. Entries whose enemy id does not
## resolve are skipped (loader validation guarantees ids resolve for /data; this
## keeps assembly robust if called with partial content).
func _spawn_enemies(battle: BattleState, encounter: EncounterData, db: ContentDatabase) -> void:
	for spawn in encounter.enemy_spawns:
		if typeof(spawn) != TYPE_DICTIONARY:
			continue
		var enemy_id: StringName = spawn.get("enemy", &"")
		var data: EnemyData = db.get_enemy(enemy_id)
		if data == null:
			continue
		var pos: Vector2i = spawn.get("pos", Vector2i.ZERO)
		var unit: Combatant = Combatant.from_enemy(data, pos)
		battle.add_combatant(unit)
