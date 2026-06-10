extends RefCounted
## Per-line cohort construction + cell runner for the M3 exit-gate sweep.
## Driven by tools/cohort_sweep.gd (CLI); pinned by tests/run/test_cohort_sweep.gd.
##
## A COHORT = race x class line x act-6 archetype. For a sweep at act N the
## party is built as it would ENTER act N, with one uniform boundary nudge: any
## pick whose beat act IS N (class @3, archetype @6, spec @9, capstone @12,
## ascension @15) is applied before the ladder, so the wall act is measured
## WITH the pick that lands during it. The nudge is identical for every cohort,
## so the SPREAD read the gate cares about is unaffected.
##
## Emulation per seed (all through the real RunController seams):
##  * party: 2 members of the SAME race, classless at start (race origin kit +
##    custom card) via start_run — isolates the line under test.
##  * chronological acts a = 1..N-1: K_a seeded drafts via CardReward
##    (eligible_pool + weights_for_act(a), so min_act / signature / class-tag
##    gating all apply exactly as in a real run), owner alternating between the
##    two members; then the end-of-act picks: choose_class at a>=3,
##    apply_progression while options exist (the cohort's archetype at depth 0,
##    seeded-uniform among children for spec/capstone), ascend at a>=15.
##    K_total = roundi(1.3 * acts_cleared) — the harness's draft-emulation dial.
##  * loadout curation: each member's loadout is rebuilt as the top skill_slots
##    collection entries ranked signature > rarity > latest-acquired (a "keep
##    the shiny stuff" player; uniform across cohorts).
##  * pre-leveling: 3 pts x acts cleared per member, 2/3 into the policy's
##    primary stat (greedy: the class attack_stat; defensive: CON), remainder
##    CON; HP tops to effective max (same shape as tools/attrition_sim.gd).
##  * ladder: the act's 4 combats + first elite + first boss, band-scaled via
##    EnemyScaler; iron_brand granted after the elite (same as attrition_sim).
##
## Known gaps (lower-bound read, shared with attrition_sim): no shop/treasure
## relics beyond the elite grant, no rest upgrades, no curses/consumables, and
## the policy bots only play damage/block cards (draw/status engines idle).

const ELITE_RELIC: StringName = &"iron_brand"
const DEFAULT_DRAFTS_PER_ACT := 1.3
const MEMBERS: Array[StringName] = [&"hero_1", &"hero_2"]

var db: ContentDatabase
## Drafted skills granted per emulated act (K dial). The gate read uses the
## prescribed 1.3; sensitivity reads may raise it to approximate a real act's
## ~6-9 draft offers when the lower-bound read is degenerate (all-zero).
var drafts_per_act: float = DEFAULT_DRAFTS_PER_ACT


func _init(database: ContentDatabase, drafts_per_act_v: float = DEFAULT_DRAFTS_PER_ACT) -> void:
	db = database
	drafts_per_act = drafts_per_act_v


# --- Cohort construction ------------------------------------------------------

## Drafts granted during act `a`: roundi(K*a) - roundi(K*(a-1)), summing to
## roundi(K * acts_cleared) with the grants spread evenly across the acts.
func drafts_in_act(a: int) -> int:
	return roundi(drafts_per_act * a) - roundi(drafts_per_act * (a - 1))


## A cohort triple is valid when the race, the class line and the archetype
## (a depth-1 node of the line's tree) all resolve in content. The sweep
## REFUSES invalid cohorts — a typo'd line would otherwise run a
## silently-classless party and poison the spread read. Quiet by design (GUT
## fails on push_error); the CLI wrapper reports refusals.
func validate_cohort(race: StringName, line: StringName, archetype: StringName) -> bool:
	if db.get_race(race) == null:
		return false
	if db.get_character(line) == null:
		return false
	var tree_v: Variant = db.progression_trees.get(line, {})
	var node_v: Variant = (tree_v as Dictionary).get(archetype)
	if not (node_v is Dictionary) or int((node_v as Dictionary).get("act", 0)) != 6:
		return false
	return true


## Build the cohort's RunController as it enters `act` (see header for the
## emulation contract). Deterministic for a given (race, line, archetype, act,
## seed, mode). Returns null for an invalid cohort triple.
func build_controller(
	race: StringName, line: StringName, archetype: StringName,
	act: int, run_seed: int, mode: String
) -> RunController:
	if not validate_cohort(race, line, archetype):
		return null
	var rc := RunController.new(db)
	rc.start_run(MEMBERS.duplicate(), run_seed, {&"hero_1": race, &"hero_2": race})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, race, line, archetype, "cohort"])
	for a in range(1, act):
		rc.run.act = a
		_draft_for_act(rc, a, drafts_in_act(a), rng)
		_end_of_act_picks(rc, line, archetype, rng)
	rc.run.act = act
	_end_of_act_picks(rc, line, archetype, rng)
	for cid in rc.run.party:
		_curate_loadout(rc, cid)
	_prelevel(rc, mode, act - 1)
	return rc


## K seeded drafts at act `a` through the real CardReward path (rarity weights
## for the act, min_act/signature/class gating). The pick is seeded-uniform over
## the 3-card offer; ownership alternates between the two members.
func _draft_for_act(rc: RunController, a: int, k: int, rng: RandomNumberGenerator) -> void:
	var reward := CardReward.new(db, CardReward.weights_for_act(a))
	var cfg: BattleConfig = db.get_battle_config()
	for i in range(k):
		var offer: Array[CardData] = reward.draft(rc.run, 3, hash([rc.run.seed, a, i, "draft"]))
		if offer.is_empty():
			continue
		var card: CardData = offer[rng.randi_range(0, offer.size() - 1)]
		var cid: StringName = rc.run.party[(a + i) % rc.run.party.size()]
		SkillLoadout.acquire(rc.collection_of(cid), rc.loadout_of(cid), card.id, cfg)


## The end-of-act pick chain (mirrors MapView._resolve_act_end): class pick at
## act >= 3, tree picks while options exist (depth 0 takes the cohort's
## archetype; deeper picks sample seeded-uniform among the children), Ascension
## at act >= 15. Idempotent — safe to call when nothing is due.
func _end_of_act_picks(rc: RunController, line: StringName, archetype: StringName, rng: RandomNumberGenerator) -> void:
	if rc.run.act >= 3:
		for cid in rc.run.party:
			if rc.is_classless(cid):
				rc.choose_class(cid, line)
	for cid in rc.run.party:
		var guard: int = 0
		while guard < 4:
			guard += 1
			var options: Array[Dictionary] = rc.progression_options(cid)
			if options.is_empty():
				break
			var chosen: StringName = &""
			for node in options:
				if StringName(String(node.get("id", ""))) == archetype:
					chosen = archetype
			if chosen == &"":
				chosen = StringName(String(options[rng.randi_range(0, options.size() - 1)].get("id", "")))
			if not rc.apply_progression(cid, chosen):
				break
	for cid in rc.run.party:
		if rc.ascension_available(cid):
			rc.ascend(cid)


## Rebuild `cid`'s loadout as the top skill_slots collection entries, ranked
## signature > rarity > latest-acquired (later grants gate at higher min_act,
## so recency is a fair power proxy). Uniform across cohorts.
func _curate_loadout(rc: RunController, cid: StringName) -> void:
	var coll: Array[StringName] = rc.collection_of(cid)
	var slots: int = db.get_battle_config().skill_slots
	var entries: Array[Dictionary] = []
	for i in range(coll.size()):
		var card: CardData = db.get_card(coll[i])
		if card == null:
			continue
		var rank: int = 1
		match card.rarity:
			&"rare":
				rank = 3
			&"uncommon":
				rank = 2
		entries.append({"id": coll[i], "sig": 1 if card.signature else 0, "rank": rank, "idx": i})
	entries.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(x["sig"]) != int(y["sig"]):
			return int(x["sig"]) > int(y["sig"])
		if int(x["rank"]) != int(y["rank"]):
			return int(x["rank"]) > int(y["rank"])
		return int(x["idx"]) > int(y["idx"]))
	var loadout: Array[StringName] = rc.loadout_of(cid)
	loadout.clear()
	for e in entries:
		if loadout.size() >= slots:
			break
		loadout.append(StringName(String(e["id"])))


## Emulate carried levels (~1 level / cleared act, 3 pts each): 2/3 into the
## policy's primary stat, the rest into CON; HP tops to effective max.
func _prelevel(rc: RunController, mode: String, acts_cleared: int) -> void:
	if acts_cleared <= 0:
		return
	var pts: int = 3 * acts_cleared
	for cid in rc.run.party:
		var stat: StringName = _primary_stat(rc, cid, mode)
		var alloc_v: Variant = rc.run.allocated_stats.get(cid, {&"str": 0, &"dex": 0, &"con": 0, &"int": 0})
		var alloc: Dictionary = alloc_v if alloc_v is Dictionary else {}
		alloc[stat] = int(alloc.get(stat, 0)) + (pts * 2 / 3)
		alloc[&"con"] = int(alloc.get(&"con", 0)) + (pts - pts * 2 / 3)
		rc.run.allocated_stats[cid] = alloc
		rc.run.party_hp[cid] = PartyStats.effective_max_hp(db, rc.run, cid)


## greedy pumps the member's class attack_stat (the line's damage scaler);
## everything else pumps CON.
func _primary_stat(rc: RunController, cid: StringName, mode: String) -> StringName:
	if mode != "greedy":
		return &"con"
	var ch: CharacterData = PartyMember.character_for(db, rc.run, cid)
	if ch != null and ch.attack_stat in [&"str", &"dex", &"int"]:
		return ch.attack_stat
	return &"str"


# --- Ladder + cell runner -----------------------------------------------------

## The act's 6-fight ladder: its 4 combats (cycled) + first elite + first boss
## (same construction as attrition_sim._act_ladder).
func act_ladder(act: int) -> Array[StringName]:
	var cfg: ActConfig = db.get_act(act)
	var fallback: Array[StringName] = [
		&"enc_combat_01", &"enc_combat_02", &"enc_combat_03", &"enc_combat_04",
		&"enc_elite_01", &"enc_boss_01",
	]
	if cfg == null or cfg.encounter_pool.is_empty():
		return fallback
	var combats: Array[StringName] = []
	var c_v: Variant = cfg.encounter_pool.get(&"combat", [])
	if c_v is Array:
		for item: Variant in c_v:
			combats.append(StringName(String(item)))
	if combats.is_empty():
		return fallback
	var out: Array[StringName] = []
	for i in range(4):
		out.append(combats[i % combats.size()])
	var e_v: Variant = cfg.encounter_pool.get(&"elite", [])
	out.append(StringName(String((e_v as Array)[0])) if e_v is Array and not (e_v as Array).is_empty() else &"enc_elite_01")
	var b_v: Variant = cfg.encounter_pool.get(&"boss", [])
	out.append(StringName(String((b_v as Array)[0])) if b_v is Array and not (b_v as Array).is_empty() else &"enc_boss_01")
	return out


func _band_for(enc_id: StringName) -> StringName:
	var s_id := String(enc_id)
	if s_id.contains("elite"):
		return &"elite"
	if s_id.contains("boss"):
		return &"boss"
	return &"trash"


## Run one sweep cell: `seeds` ladders of (race, line, archetype) at `act`
## under policy `mode` ("greedy" | "defensive"). Returns the machine row.
func run_cell(
	race: StringName, line: StringName, archetype: StringName,
	act: int, seeds: int, mode: String
) -> Dictionary:
	if not validate_cohort(race, line, archetype):
		return {}
	var wins: int = 0
	var cleared_total: int = 0
	var hp_total: int = 0
	var deaths: Dictionary = {}
	var ladder: Array[StringName] = act_ladder(act)
	for s in range(seeds):
		var rc: RunController = build_controller(race, line, archetype, act, s, mode)
		var policy: Callable = policy_for(mode)
		var cleared: int = 0
		for enc_id in ladder:
			var outcome: int = rc.resolve_combat(enc_id, policy, 80, _band_for(enc_id))
			if outcome != BattleState.Outcome.WIN:
				deaths[String(enc_id)] = int(deaths.get(String(enc_id), 0)) + 1
				break
			cleared += 1
			_auto_allocate(rc, mode)
			if String(enc_id).contains("elite"):
				rc.grant_relic(ELITE_RELIC, "elite")
		cleared_total += cleared
		if cleared == ladder.size():
			wins += 1
		hp_total += _party_hp_sum(rc)
	return {
		"race": String(race),
		"line": String(line),
		"archetype": String(archetype),
		"act": act,
		"policy": mode,
		"seeds": seeds,
		"drafts_per_act": drafts_per_act,
		"wins": wins,
		"win_rate": float(wins) / float(seeds) if seeds > 0 else 0.0,
		"avg_cleared": float(cleared_total) / float(seeds) if seeds > 0 else 0.0,
		"avg_final_hp": float(hp_total) / float(seeds) if seeds > 0 else 0.0,
		"deaths": deaths,
	}


func _auto_allocate(rc: RunController, mode: String) -> void:
	for cid in rc.run.party:
		var stat: StringName = _primary_stat(rc, cid, mode)
		while rc.unspent_points(cid) > 0:
			if not rc.allocate_stat_point(cid, stat):
				break


func _party_hp_sum(rc: RunController) -> int:
	var total: int = 0
	for cid in rc.run.party:
		total += maxi(0, int(rc.run.party_hp.get(cid, 0)))
	return total


# --- Policies (same bots as tools/attrition_sim.gd) ---------------------------

func policy_for(mode: String) -> Callable:
	match mode:
		"greedy":
			return func(b: Variant, cp: Variant) -> void: _greedy_turn(b, cp)
		_:
			return func(b: Variant, cp: Variant) -> void: _defensive_turn(b, cp)


## All offense: spend energy on damage cards at the lowest-HP living enemy.
func _greedy_turn(battle: Variant, cp: Variant) -> void:
	var guard: int = 0
	while battle.total_energy() > 0 and guard < 40:
		guard += 1
		var enemies: Array[Combatant] = battle.living_enemies()
		if enemies.is_empty():
			return
		if not _play_one_offense(battle, cp, _lowest_hp(enemies)):
			return


## One block first if affordable, then attack with the rest.
func _defensive_turn(battle: Variant, cp: Variant) -> void:
	_play_one_defense(battle, cp)
	var guard: int = 0
	while battle.total_energy() > 0 and guard < 40:
		guard += 1
		var enemies: Array[Combatant] = battle.living_enemies()
		if enemies.is_empty():
			return
		if not _play_one_offense(battle, cp, _lowest_hp(enemies)):
			return


func _play_one_offense(battle: Variant, cp: Variant, target: Combatant) -> bool:
	for actor in battle.living_players():
		for card in battle.deck_of(actor).hand.duplicate():
			if not _is_offensive(card):
				continue
			if card.energy_cost > battle.energy_of(actor):
				continue
			if cp.play_card(actor, card, _resolve_tgt(card, actor, target)).ok:
				return true
	return false


func _play_one_defense(battle: Variant, cp: Variant) -> bool:
	for actor in battle.living_players():
		for card in battle.deck_of(actor).hand.duplicate():
			if not _is_defensive(card):
				continue
			if card.energy_cost > battle.energy_of(actor):
				continue
			if cp.play_card(actor, card, actor).ok:
				return true
	return false


func _is_offensive(card: CardData) -> bool:
	for e in card.effects:
		if e is Effect and e.type == &"damage":
			return true
	return false


func _is_defensive(card: CardData) -> bool:
	for e in card.effects:
		if e is Effect and e.type == &"block":
			return true
	return false


func _resolve_tgt(card: CardData, actor: Combatant, target: Combatant) -> Variant:
	match card.target.target_type:
		&"self":
			return actor
		&"enemy":
			return target
		_:
			return null  # all_enemies / all_allies / random_enemy resolve internally


func _lowest_hp(units: Array[Combatant]) -> Combatant:
	var best: Combatant = units[0]
	for u in units:
		if u.hp < best.hp:
			best = u
	return best
