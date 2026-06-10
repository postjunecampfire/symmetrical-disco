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

## Applies relic effects (P2·12) at assembly (passive + combat_start).
var _relic_engine: RelicEngine = RelicEngine.new()


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
	member_decks: Dictionary = {},
	allocated_stats: Dictionary = {},
	relics: Array[RelicData] = [],
	enemy_level: int = 0,
	party_data: Array[CharacterData] = []
) -> EncounterBattle:
	var config: BattleConfig = db.get_battle_config()
	if config == null:
		config = BattleConfig.new()

	# ADR-0024/0021-pt2: the run layer passes SYNTHESIZED member sheets
	# (PartyMember.character_for — race base + optional class overlay); legacy
	# callers resolve ids straight from the class registry.
	var party: Array[CharacterData] = party_data if not party_data.is_empty() else _resolve_party(db, party_ids)

	# ADR-0026: each member fights with their OWN deck, derived from their active
	# skill loadout (member_decks: member_id -> Array of card ids). When the run
	# layer supplies no decks (legacy/standalone callers), each member's deck is
	# derived on the spot from their starting kit so the battle is always playable.
	var ai: EnemyAI = EnemyAI.new(rng_seed)
	var battle: EncounterBattle = EncounterBattle.new(config, Deck.new(config, rng_seed), db.statuses, ai)
	battle.win_condition = encounter.win_condition
	battle.win_param = encounter.win_param
	battle.enemy_db = db.enemies  # lets summoners spawn minions mid-fight (P2·12 kit)
	battle.card_lookup = db.cards  # token generation (add_card, ADR-0028)

	_spawn_players(battle, party)
	# Per-member decks (ADR-0026), seeded per fight and SHUFFLED at assembly
	# (start_battle — the initial-shuffle fix: draws no longer come off authoring
	# order). Seed is offset per member so the two hands differ.
	var member_i: int = 0
	for unit in battle.combatants:
		if not unit.is_player():
			continue
		var data := unit.source_data as CharacterData
		if data == null:
			continue
		var ids_v: Variant = member_decks.get(data.id)
		var ids: Array[StringName] = []
		if ids_v is Array:
			for item: Variant in ids_v:
				ids.append(StringName(String(item)))
		if ids.is_empty():
			# Fallback: derive from the class starting kit + auto-fill.
			var kit: Array[StringName] = []
			for card_id in data.starting_deck:
				kit.append(card_id)
			ids = SkillLoadout.derive_deck(kit, db)
		var member_deck: Deck = Deck.new(config, rng_seed + member_i * 7919)
		member_deck.assemble_from_card_ids(ids, db.cards)
		member_deck.start_battle()
		battle.decks[unit] = member_deck
		member_i += 1
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
	_spawn_enemies(battle, encounter, db, enemy_level, config)

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
## `enemy_level` > 0 (ADR-0019) scales every spawned enemy to that act-band level
## via EnemyScaler (factor shape from BattleConfig); 0 spawns authored blocks
## unscaled. Mid-fight summons (enemy_db) spawn at authored stats — a known v1
## simplification, revisit if summoners reach deep acts.
func _spawn_enemies(
	battle: BattleState,
	encounter: EncounterData,
	db: ContentDatabase,
	enemy_level: int = 0,
	config: BattleConfig = null
) -> void:
	var scaler: EnemyScaler = null
	if enemy_level > 0:
		scaler = EnemyScaler.new(config)
	for enemy_id in encounter.enemies:
		var data: EnemyData = db.get_enemy(enemy_id)
		if data == null:
			continue
		if scaler != null:
			data = scaler.apply_to(data, enemy_level)
		battle.add_combatant(Combatant.from_enemy(data))
