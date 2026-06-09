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
## Leveling engine (ADR-0015 / P3·05): XP -> levels -> player-allocated points.
var _leveling: Leveling
## Event-node resolver (run-structure.md §6 / P2·08): applies choice outcomes.
var _event_resolver: EventResolver
## Rest-node resolver (run-structure.md §5 / P2·07): heal or upgrade a card.
var _rest_resolver: RestResolver


func _init(database: ContentDatabase, logger: TelemetryLogger = null) -> void:
	db = database
	telemetry = logger
	_leveling = Leveling.new(_config())
	_event_resolver = EventResolver.new(database)
	_rest_resolver = RestResolver.new(database)


# --- Run lifecycle ----------------------------------------------------------

## Begin a run: full HP for each party member, run deck = union of starting decks
## (plus each race's custom card). This run deck drives the combat deck (P2·06), so
## race custom cards and later drafted rewards appear in fights.
## `races` (optional) maps a party character id to a race id (ADR-0015); race CON
## raises that member's starting/max HP, and the race's custom card joins the run deck.
func start_run(party: Array[StringName], seed: int, races: Dictionary = {}) -> void:
	run = RunState.new()
	run.seed = seed
	run.act = 1
	run.party = party.duplicate()
	run.party_hp = {}
	run.downed = []
	run.run_deck = []
	run.party_races = races.duplicate()
	run.party_level = {}
	run.party_xp = {}
	run.unspent_points = {}
	run.allocated_stats = {}
	run.party_promotions = {}
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
		_leveling.init_character(run, cid)


## Assemble (but do NOT run) the battle for `encounter_id`, applying the run's
## carried HP, race mods, run deck (P2·06) and allocated stats (P3·05). Returns a
## ready EncounterBattle the caller drives — synchronously via a policy
## (`resolve_combat`) or turn-by-turn from the UI (MapView/BattleView) — then hands
## back to `finish_combat`. Returns null if the encounter id is unknown.
func begin_combat(encounter_id: StringName, band: StringName = &"") -> EncounterBattle:
	var encounter: EncounterData = db.get_encounter(encounter_id)
	if encounter == null:
		return null
	var carried: Dictionary = _carried_for_next_fight()
	# Enemy level scaling (ADR-0019): when the caller names the node's band
	# ("trash" | "elite" | "boss"), enemies are scaled to the current act's level
	# band via EnemyScaler. An empty band (legacy callers, the attrition sim,
	# tests) keeps the authored stat blocks unscaled.
	var enemy_level: int = 0
	if band != &"":
		var act_cfg: ActConfig = db.get_act(run.act)
		if act_cfg != null:
			enemy_level = EnemyScaler.band_level(act_cfg, band)
	# Combat deck is built from the accumulated run deck (P2·06): race custom cards
	# and drafted rewards in RunState.run_deck now appear in the fight, not just the
	# class starting decks. The assembler falls back to starting decks if it is empty.
	return _assembler.build(
		encounter, db, run.party, run.seed, carried, run.party_races, run.run_deck,
		run.allocated_stats, _active_relics(), enemy_level
	)


## Boss cleared (ADR-0019): move the run to the next authored act. Regenerates the
## map from the next act's MapGenConfig (seed derived from the run seed + act so
## each act's map is deterministic but distinct), resets position/cleared, and
## keeps HP / deck / relics / levels — the run carries on. Returns false when no
## next act exists (the cleared act was the last authored one -> true victory).
func advance_act() -> bool:
	var next_cfg: ActConfig = db.get_act(run.act + 1)
	if next_cfg == null or next_cfg.map == null:
		return false
	run.act += 1
	run.map = MapGenerator.new().generate(next_cfg.map, run.seed + run.act * 7919)
	run.position = &""
	run.cleared = []
	if telemetry != null:
		telemetry.log_event(&"act_advanced", {"act": run.act})
	return true


## Resolve the run's relic ids (RunState.relics) to RelicData via the db, skipping
## any that don't resolve. The list the assembler/RelicEngine apply each fight.
func _active_relics() -> Array[RelicData]:
	var out: Array[RelicData] = []
	for rid in run.relics:
		var relic: RelicData = db.get_relic(rid)
		if relic != null:
			out.append(relic)
	return out


## Settle a finished `battle`: write each player's HP back to the run, mark downed,
## and on a WIN heal survivors + award combat XP (P3·05). Logs a `combat_result`
## telemetry event. Returns the final outcome. `turns` is for telemetry only. Call
## once after the battle has reached WIN/LOSS (the UI calls this when combat ends;
## `resolve_combat` calls it after its auto-run loop).
func finish_combat(encounter_id: StringName, battle: BattleState, turns: int = 0) -> int:
	var outcome: int = battle.check_outcome()
	# Telemetry fidelity (balance pass): snapshot HP entering the fight (run.party_hp
	# is not yet written back here) and at the final blow (battle units, BEFORE the
	# post-combat heal), so combat_result shows TRUE damage taken — the post-heal
	# party_hp snapshot masked up to post_combat_heal points of chip per fight.
	var hp_before: Dictionary = _hp_snapshot()
	var hp_end_of_fight: Dictionary = {}
	var damage_taken: Dictionary = {}  # net of in-fight healing
	for unit in battle.combatants:
		if not unit.is_player():
			continue
		var data := unit.source_data as CharacterData
		if data == null:
			continue
		var cid: String = String(data.id)
		hp_end_of_fight[cid] = unit.hp
		damage_taken[cid] = int(hp_before.get(cid, unit.hp)) - unit.hp
	_write_back_hp(battle, outcome)
	if outcome == BattleState.Outcome.WIN:
		_award_combat_xp()

	if telemetry != null:
		telemetry.log_event(&"combat_result", {
			"encounter": String(encounter_id),
			"outcome": _outcome_name(outcome),
			"turns": turns,
			"hp_before": hp_before,
			"hp_end_of_fight": hp_end_of_fight,
			"damage_taken": damage_taken,
			"party_hp": _hp_snapshot(),
			"downed": _ids(run.downed),
		})
	return outcome


## Resolve one combat encounter with `policy`, carrying HP in and writing it back
## out. Returns the BattleState.Outcome (WIN / LOSS). `max_turns` caps runaway
## fights (a stalemate counts as a loss for the run's purposes via the caller).
## Composition of begin_combat + an auto-run loop + finish_combat.
func resolve_combat(encounter_id: StringName, policy: Callable, max_turns: int = 80) -> int:
	var battle: EncounterBattle = begin_combat(encounter_id)
	if battle == null:
		return BattleState.Outcome.LOSS
	var card_play: CardPlay = CardPlay.new(battle)

	var turns: int = 0
	while battle.check_outcome() == BattleState.Outcome.ONGOING and turns < max_turns:
		battle.start_player_turn()
		_telegraph_enemies(battle)
		policy.call(battle, card_play)
		battle.end_player_turn()
		turns += 1

	return finish_combat(encounter_id, battle, turns)


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


# --- Event nodes (run-structure.md §6 / P2·08) ------------------------------

## Resolve an event node: apply choice `choice_index` of event `event_id` to the
## run (heal/damage/card/relic deltas). Returns true if the event + choice were
## valid and applied. The choice index is supplied by a policy or UI — the same
## injection pattern combat uses. Logs an `event_choice` telemetry event.
func resolve_event(event_id: StringName, choice_index: int) -> bool:
	var event: EventData = db.get_event(event_id)
	if event == null:
		return false
	if not _event_resolver.apply_choice_index(run, event, choice_index):
		return false
	if telemetry != null:
		telemetry.log_event(&"event_choice", {
			"event": String(event_id),
			"choice": choice_index,
			"party_hp": _hp_snapshot(),
			"deck_size": run.run_deck.size(),
		})
	return true


# --- Class promotion (P3·06 / ADR-0015) -------------------------------------

## The promotion branches `cid` may currently pick (1 of 2 per class): non-empty
## only once the character has reached the threshold for its NEXT promotion
## (`promotion_level * (promotions_taken + 1)`). Already-taken branches are excluded
## so accrual offers the remaining branch. A UI calls this at an act boundary.
func eligible_promotions(cid: StringName) -> Array[PromotionData]:
	var out: Array[PromotionData] = []
	var taken: Array = run.party_promotions.get(cid, [])
	if _leveling.level_of(run, cid) < _config().promotion_level * (taken.size() + 1):
		return out
	for p in db.get_promotions_for_class(cid):
		if not taken.has(p.id):
			out.append(p)
	return out


## Apply promotion `promotion_id` to `cid` (must be a currently-eligible branch of
## that class). Folds the branch's stat mods into allocated_stats and appends its
## signature card to the run deck — both flow through the assembler automatically —
## and records it for accrual. Returns false if not eligible / wrong class. Logs a
## `promotion` telemetry event.
func apply_promotion(cid: StringName, promotion_id: StringName) -> bool:
	var promo: PromotionData = db.get_promotion(promotion_id)
	if promo == null or promo.from_class != cid:
		return false
	var offered: Dictionary = {}
	for p in eligible_promotions(cid):
		offered[p.id] = true
	if not offered.has(promotion_id):
		return false

	if not run.allocated_stats.has(cid):
		run.allocated_stats[cid] = {&"str": 0, &"dex": 0, &"con": 0, &"int": 0}
	var a: Dictionary = run.allocated_stats[cid]
	a[&"str"] = int(a.get(&"str", 0)) + promo.str_mod
	a[&"dex"] = int(a.get(&"dex", 0)) + promo.dex_mod
	a[&"con"] = int(a.get(&"con", 0)) + promo.con_mod
	a[&"int"] = int(a.get(&"int", 0)) + promo.int_mod
	if promo.signature_card != &"":
		run.run_deck.append(promo.signature_card)
	if not run.party_promotions.has(cid):
		run.party_promotions[cid] = [] as Array[StringName]
	run.party_promotions[cid].append(promotion_id)

	if telemetry != null:
		telemetry.log_event(&"promotion", {"character": String(cid), "promotion": String(promotion_id)})
	return true


# --- Relics (run-structure.md §7 / P2·12) -----------------------------------

## Add `relic_id` to the run (elite/boss/event acquisition). Skips unknown ids and
## duplicates. Its effects apply from the NEXT assembled combat onward (and, for
## passive/combat_start, that fight's assembly). Logs a `relic_gained` event.
func grant_relic(relic_id: StringName, source: String = "") -> bool:
	if relic_id == &"" or db.get_relic(relic_id) == null:
		return false
	if run.relics.has(relic_id):
		return false
	run.relics.append(relic_id)
	if telemetry != null:
		telemetry.log_event(&"relic_gained", {"relic": String(relic_id), "source": source})
	return true


## Relic ids the run does not yet own (acquisition candidates), sorted for
## deterministic selection by a caller.
func available_relics() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in db.relics.keys():
		var rid: StringName = StringName(String(key))
		if not run.relics.has(rid):
			out.append(rid)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


# --- Rest nodes (run-structure.md §5 / P2·07) -------------------------------

## Resolve a rest node. `kind` is `heal` or `upgrade`; for `upgrade`, `card_id` is
## the base card to upgrade in the run deck. Returns true if the choice applied
## (heal always applies; upgrade only if the base card is present and has an
## upgrade variant). The choice is supplied by a policy or UI, like combat/events.
## Logs a `rest_choice` telemetry event on success.
func resolve_rest(kind: StringName, card_id: StringName = &"") -> bool:
	var applied: bool = false
	var detail: String = ""
	match kind:
		&"heal":
			_rest_resolver.heal(run)
			applied = true
			detail = "heal"
		&"upgrade":
			applied = _rest_resolver.upgrade_card(run, card_id)
			detail = "upgrade:%s" % card_id
		_:
			return false
	if applied and telemetry != null:
		telemetry.log_event(&"rest_choice", {
			"kind": String(kind),
			"detail": detail,
			"party_hp": _hp_snapshot(),
			"deck_size": run.run_deck.size(),
		})
	return applied


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
			# Cap at EFFECTIVE max (base + race + allocated + passive relics), so a
			# high-CON / max_hp_up build can actually heal into its headroom (review #1).
			var max_hp: int = PartyStats.effective_max_hp(db, run, cid)
			run.party_hp[cid] = min(max_hp, int(run.party_hp.get(cid, 0)) + heal)


# --- Leveling (ADR-0015 / P3·05) --------------------------------------------

## Award the per-combat XP to each surviving (non-downed) party member after a
## win, levelling them up and granting unspent stat points via the engine. Downed
## members earn nothing this fight (they were defeated), matching post-combat heal.
func _award_combat_xp() -> void:
	var amount: int = _config().xp_per_combat
	for cid in run.party:
		if run.downed.has(cid):
			continue
		_leveling.grant_xp(run, cid, amount)


## Spend one of `character_id`'s unspent stat points into `stat`
## (`str`/`dex`/`con`/`int`). The choice persists in RunState.allocated_stats and
## reaches the next fight via the assembler. Returns true if a point was spent.
## This is the seam a creation/level-up UI (or an auto-policy) calls.
func allocate_stat_point(character_id: StringName, stat: StringName) -> bool:
	return _leveling.allocate_point(run, character_id, stat)


## Unspent stat points `character_id` may still allocate (convenience for callers).
func unspent_points(character_id: StringName) -> int:
	return _leveling.unspent(run, character_id)


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
