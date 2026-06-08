class_name RunController
extends RefCounted
## The run spine (P2·04 + P2·05): wraps the existing combat (ADR-0012) and carries
## HP across encounters (ADR-0011). It resolves a sequence of combat encounters,
## carrying each character's HP from one fight to the next; downed units (0 HP)
## revive at the next encounter at a low HP value; survivors heal a fixed amount
## after each won combat; a Total Party Kill ends the run.
##
## Combat is driven by an injected POLICY — a Callable `func(battle, card_play)`
## that performs the player's plays for the current turn (the controller has
## already started the turn and telegraphed enemy intents). This lets a headless
## auto-runner (or a UI) drive the same loop. The combat layer is untouched: a
## fight is assembled by EncounterAssembler with the carried HP, run via the
## normal turn loop, and the surviving HP is written back to RunState.
##
## v1 scope: resolves an explicit ordered encounter sequence (the "path"). Map
## graph traversal / node-type handlers (rest/event/relic) and run-deck drafting
## wire in on top of this; this is the attrition spine the thesis test needs.

## The injected world.
var db: ContentDatabase
## Optional run-level telemetry (TelemetryLogger). Null = no logging.
var telemetry: TelemetryLogger
## The active run state (party, carried HP, downed, deck, seed).
var run: RunState

var _assembler: EncounterAssembler = EncounterAssembler.new()
## character_id -> race_id chosen at run start (ADR-0015). Applied each fight.
var _party_races: Dictionary = {}


func _init(database: ContentDatabase, logger: TelemetryLogger = null) -> void:
	db = database
	telemetry = logger


# --- Run lifecycle ----------------------------------------------------------

## Begin a run: full HP for each party member, run deck = union of starting decks
## (tracked for future drafting; combat currently uses the assembled starting deck).
## `races` (optional) maps a party character id to a race id (ADR-0015); race CON
## raises that member's starting/max HP, and the race's custom card joins the run deck.
func start_run(party: Array[StringName], seed: int, races: Dictionary = {}) -> void:
	run = RunState.new()
	run.seed = seed
	run.party = party.duplicate()
	run.party_hp = {}
	run.downed = []
	run.run_deck = []
	_party_races = races.duplicate()
	var per_con: int = _config().hp_per_con
	for cid in party:
		var ch: CharacterData = db.get_character(cid)
		var base_max: int = ch.max_hp if ch != null else 1
		var race: RaceData = db.get_race(races.get(cid, &""))
		run.party_hp[cid] = base_max + (race.con_mod * per_con if race != null else 0)
		if ch != null:
			for card_id in ch.starting_deck:
				run.run_deck.append(card_id)
		if race != null and race.custom_card != &"":
			run.run_deck.append(race.custom_card)


## Resolve one combat encounter with `policy`, carrying HP in and writing it back
## out. Returns the BattleState.Outcome (WIN / LOSS). `max_turns` caps runaway
## fights (a stalemate counts as a loss for the run's purposes via the caller).
func resolve_combat(encounter_id: StringName, policy: Callable, max_turns: int = 80) -> int:
	var encounter: EncounterData = db.get_encounter(encounter_id)
	if encounter == null:
		return BattleState.Outcome.LOSS

	var carried: Dictionary = _carried_for_next_fight()
	var battle: EncounterBattle = _assembler.build(
		encounter, db, run.party, run.seed, carried, _party_races
	)
	var card_play: CardPlay = CardPlay.new(battle)

	var turns: int = 0
	while battle.check_outcome() == BattleState.Outcome.ONGOING and turns < max_turns:
		battle.start_player_turn()
		_telegraph_enemies(battle)
		policy.call(battle, card_play)
		battle.end_player_turn()
		turns += 1

	var outcome: int = battle.check_outcome()
	_write_back_hp(battle, outcome)

	if telemetry != null:
		telemetry.log_event(&"combat_result", {
			"encounter": String(encounter_id),
			"outcome": _outcome_name(outcome),
			"turns": turns,
			"party_hp": _hp_snapshot(),
			"downed": _ids(run.downed),
		})
	return outcome


## Resolve an ordered list of combat encounters as one act. Stops at the first
## TPK. Returns a summary Dictionary (cleared / total / won / death node / final HP).
func run_act(encounter_sequence: Array, policy: Callable) -> Dictionary:
	var cleared: int = 0
	var death_node: StringName = &""
	for enc_id in encounter_sequence:
		var outcome: int = resolve_combat(enc_id, policy)
		if outcome != BattleState.Outcome.WIN:
			death_node = enc_id
			break
		cleared += 1
		run.cleared.append(enc_id)

	var won: bool = death_node == &"" and cleared == encounter_sequence.size()
	var summary: Dictionary = {
		"cleared": cleared,
		"total": encounter_sequence.size(),
		"won": won,
		"death_node": String(death_node),
		"final_hp": _hp_snapshot(),
	}
	if telemetry != null:
		telemetry.end_run(summary)
	return summary


# --- HP attrition (ADR-0011) ------------------------------------------------

## The carried HP to spawn the next fight with: each member's stored HP, except a
## downed member (or one at <= 0) revives at the configured revive HP.
func _carried_for_next_fight() -> Dictionary:
	var revive: int = _config().revive_hp
	var carried: Dictionary = {}
	for cid in run.party:
		var hp: int = int(run.party_hp.get(cid, 0))
		if run.downed.has(cid) or hp <= 0:
			hp = revive
		carried[cid] = hp
	return carried


## After a fight: store each player's HP; mark 0-HP players as downed; on a WIN,
## heal each survivor by the configured post-combat amount (capped at max HP).
func _write_back_hp(battle: BattleState, outcome: int) -> void:
	run.downed = []
	for unit in battle.combatants:
		if not unit.is_player():
			continue
		var data := unit.source_data as CharacterData
		if data == null:
			continue
		run.party_hp[data.id] = unit.hp
		if unit.hp <= 0:
			run.downed.append(data.id)

	if outcome == BattleState.Outcome.WIN:
		var heal: int = _config().post_combat_heal
		for cid in run.party:
			if run.downed.has(cid):
				continue
			var ch: CharacterData = db.get_character(cid)
			var max_hp: int = ch.max_hp if ch != null else 0
			run.party_hp[cid] = min(max_hp, int(run.party_hp.get(cid, 0)) + heal)


# --- Helpers ----------------------------------------------------------------

func _telegraph_enemies(battle: EncounterBattle) -> void:
	if battle.enemy_ai == null:
		return
	for enemy in battle.living_enemies():
		var data := enemy.source_data as EnemyData
		if data != null:
			battle.enemy_ai.select_intent(enemy, data, battle)


func _config() -> BattleConfig:
	var c: BattleConfig = db.get_battle_config()
	return c if c != null else BattleConfig.new()


func _hp_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for cid in run.party:
		out[String(cid)] = int(run.party_hp.get(cid, 0))
	return out


func _ids(arr: Array) -> Array:
	var out: Array = []
	for x in arr:
		out.append(String(x))
	return out


func _outcome_name(outcome: int) -> String:
	match outcome:
		BattleState.Outcome.WIN:
			return "win"
		BattleState.Outcome.LOSS:
			return "loss"
		_:
			return "ongoing"
