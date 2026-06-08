extends SceneTree
## Attrition measurement harness (run-structure thesis test, P3·09 follow-up).
##
## Re-runs the headless auto-runner with the FULL run loop live — run-deck combat
## decks (P2·06), leveling with auto-allocation (P3·05), and relics (P2·12) — to
## measure whether greed gets punished across an act. Two cohorts play the SAME
## fixed sequence of fights under identical seeds; only the play policy (and the
## stat each auto-spends on level-up) differs:
##   greedy     — all offense, never blocks; allocates level points to STR.
##   defensive  — blocks once per turn, then attacks; allocates points to CON.
##
## Both carry HP across fights (ADR-0011) and earn XP/relics identically, so the
## win-rate and final-HP gap isolates the policy. Reports win %, avg nodes cleared,
## avg surviving HP, and a death-node histogram — the read that informs the
## owner-led balance pass. NOT a gate (lives in tools/, not tests/).
##
## Run:  godot --headless --script res://tools/attrition_sim.gd [seeds]

const DATA_DIR := "res://data"
const DEFAULT_SEEDS := 40

## A representative act of rising difficulty (Basic A→Hard, elite, boss). Both
## cohorts face this identical ladder so attrition is comparable.
const ACT: Array[StringName] = [
	&"enc_combat_01", &"enc_combat_02", &"enc_combat_03", &"enc_combat_04",
	&"enc_elite_01", &"enc_boss_01",
]
## Granted to BOTH cohorts after the elite, so the relic path is exercised without
## biasing the comparison.
const ELITE_RELIC: StringName = &"iron_brand"
const PARTY: Array[StringName] = [&"fighter", &"mage"]
const RACES := {&"fighter": &"orc", &"mage": &"elf"}

var _db: ContentDatabase


func _initialize() -> void:
	_db = ContentDatabase.new()
	var result: ContentDatabase.LoadResult = _db.load_from_dir(DATA_DIR)
	if not result.ok:
		push_error("Content failed to load: %s" % str(result.errors))
		quit()
		return

	var seeds: int = DEFAULT_SEEDS
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		seeds = args[0].to_int()

	var greedy: Dictionary = _run_cohort("greedy", seeds)
	var defensive: Dictionary = _run_cohort("defensive", seeds)
	var turtle: Dictionary = _run_cohort("turtle", seeds)
	_print_report([greedy, defensive, turtle], seeds)
	quit()


# --- Cohort run -------------------------------------------------------------

func _run_cohort(mode: String, seeds: int) -> Dictionary:
	var wins: int = 0
	var cleared_total: int = 0
	var final_hp_total: int = 0
	var deaths: Dictionary = {}  # encounter_id -> count

	for s in range(seeds):
		var rc := RunController.new(_db)
		rc.start_run(PARTY, s, RACES)
		var policy: Callable
		match mode:
			"greedy":
				policy = func(b: Variant, cp: Variant) -> void: _greedy_turn(b, cp)
			"turtle":
				policy = func(b: Variant, cp: Variant) -> void: _turtle_turn(b, cp)
			_:
				policy = func(b: Variant, cp: Variant) -> void: _defensive_turn(b, cp)

		var cleared: int = 0
		for enc_id in ACT:
			var outcome: int = rc.resolve_combat(enc_id, policy)
			if outcome != BattleState.Outcome.WIN:
				deaths[enc_id] = int(deaths.get(enc_id, 0)) + 1
				break
			cleared += 1
			_auto_allocate(rc, mode)
			if enc_id == &"enc_elite_01":
				rc.grant_relic(ELITE_RELIC, "elite")

		cleared_total += cleared
		if cleared == ACT.size():
			wins += 1
		final_hp_total += _party_hp_sum(rc)

	return {
		"mode": mode,
		"wins": wins,
		"avg_cleared": float(cleared_total) / float(seeds),
		"avg_final_hp": float(final_hp_total) / float(seeds),
		"deaths": deaths,
	}


## Spend every unspent level point: greedy pumps STR (more damage), defensive pumps
## CON (more HP) — so the builds diverge the way the policies imply.
func _auto_allocate(rc: RunController, mode: String) -> void:
	var stat: StringName = &"str" if mode == "greedy" else &"con"
	for cid in rc.run.party:
		while rc.unspent_points(cid) > 0:
			if not rc.allocate_stat_point(cid, stat):
				break


func _party_hp_sum(rc: RunController) -> int:
	var total: int = 0
	for cid in rc.run.party:
		total += maxi(0, int(rc.run.party_hp.get(cid, 0)))
	return total


# --- Policies ---------------------------------------------------------------

## All offense: spend energy on damage cards (then innate Strike) at the lowest-HP
## living enemy. Never blocks.
func _greedy_turn(battle: Variant, cp: Variant) -> void:
	var guard: int = 0
	while battle.energy > 0 and guard < 40:
		guard += 1
		var enemies: Array[Combatant] = battle.living_enemies()
		if enemies.is_empty():
			return
		if not _play_one_offense(battle, cp, _lowest_hp(enemies)):
			return


## Plays ONE block/defend (self) first if affordable, then attacks with the rest —
## lower damage output, more survivability.
func _defensive_turn(battle: Variant, cp: Variant) -> void:
	_play_one_defense(battle, cp)
	var guard: int = 0
	while battle.energy > 0 and guard < 40:
		guard += 1
		var enemies: Array[Combatant] = battle.living_enemies()
		if enemies.is_empty():
			return
		if not _play_one_offense(battle, cp, _lowest_hp(enemies)):
			return


## Try one offensive play (a damage card, else innate Strike). Returns true if
## something was played (so the caller keeps spending).
func _play_one_offense(battle: Variant, cp: Variant, target: Combatant) -> bool:
	for card in battle.deck.hand.duplicate():
		if card.energy_cost > battle.energy or not _is_offensive(card):
			continue
		var actor: Combatant = _actor_for_card(battle, card)
		if actor != null and cp.play_card(actor, card, _resolve_tgt(card, actor, target)).ok:
			return true
	var strike: CardData = _db.get_card(&"strike")
	for actor in battle.living_players():
		if strike != null and strike.energy_cost <= battle.energy:
			if cp.play_innate(actor, strike, target).ok:
				return true
	return false


## Turtle: block as much as possible, then chip with a single attack. Drags fights
## out on purpose — the enemy Strength ramp should make this bleed.
func _turtle_turn(battle: Variant, cp: Variant) -> void:
	var guard: int = 0
	while battle.energy > 1 and guard < 40:
		guard += 1
		if not _play_one_defense(battle, cp):
			break
	var enemies: Array[Combatant] = battle.living_enemies()
	if not enemies.is_empty():
		_play_one_offense(battle, cp, _lowest_hp(enemies))


## Play one block/defend (self) action if affordable: a block card from hand, else
## innate Defend. Returns true if something was played.
func _play_one_defense(battle: Variant, cp: Variant) -> bool:
	for card in battle.deck.hand.duplicate():
		if card.energy_cost > battle.energy or not _is_defensive(card):
			continue
		var actor: Combatant = _actor_for_card(battle, card)
		if actor != null and cp.play_card(actor, card, actor).ok:
			return true
	var defend: CardData = _db.get_card(&"defend")
	for actor in battle.living_players():
		if defend != null and defend.energy_cost <= battle.energy:
			if cp.play_innate(actor, defend, actor).ok:
				return true
	return false


# --- Policy helpers ---------------------------------------------------------

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


func _actor_for_card(battle: Variant, card: CardData) -> Combatant:
	if card.character_tag == &"neutral":
		var ps: Array[Combatant] = battle.living_players()
		return ps[0] if not ps.is_empty() else null
	for p in battle.living_players():
		var d := p.source_data as CharacterData
		if d != null and d.id == card.character_tag:
			return p
	return null


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


# --- Report -----------------------------------------------------------------

func _print_report(cohorts: Array, seeds: int) -> void:
	print("\n========================================================")
	print("  ATTRITION READ — full loop (run decks + leveling + relics)")
	print("========================================================")
	print("Act: %d fights %s" % [ACT.size(), str(ACT)])
	print("Party: Fighter(Orc) + Mage(Elf).  Relic after elite: %s.  Seeds: %d" % [ELITE_RELIC, seeds])
	print("--------------------------------------------------------")
	print("%-11s %7s %12s %12s" % ["policy", "win%", "avgCleared", "avgFinalHP"])
	for c in cohorts:
		print("%-11s %6.1f%% %12.2f %12.1f" % [
			c["mode"], 100.0 * float(c["wins"]) / float(seeds), c["avg_cleared"], c["avg_final_hp"],
		])
	print("--------------------------------------------------------")
	print("Deaths by node:")
	for c in cohorts:
		print("  %-10s %s" % [c["mode"], _deaths_str(c["deaths"])])
	print("========================================================")
	# Win tension: ideal is a "Goldilocks" middle — greedy (too fast) AND turtle
	# (too slow) should both fare worse than balanced defensive play.
	var win := {}
	for c in cohorts:
		win[c["mode"]] = 100.0 * float(c["wins"]) / float(seeds)
	print("Read: greedy %.1f%%  |  defensive %.1f%%  |  turtle %.1f%% (win rate)." % [
		win.get("greedy", 0.0), win.get("defensive", 0.0), win.get("turtle", 0.0)])
	var g: float = win.get("greedy", 0.0)
	var d: float = win.get("defensive", 0.0)
	var t: float = win.get("turtle", 0.0)
	if d >= g + 5.0 and d >= t + 5.0:
		print("GOLDILOCKS: balanced play beats both rushing AND turtling — the fast/slow tension works.")
	elif g >= 99.0 and d >= 99.0 and t >= 99.0:
		print("All ~100% -> combat still too easy; keep tuning harder.")
	elif d <= t and d <= g:
		print("Balanced isn't ahead yet -> tune so BOTH greed (burst) and turtling (ramp) get punished.")
	else:
		print("Partial: one failure mode bites, the other doesn't yet -> keep tuning.")
	print("")


func _deaths_str(deaths: Dictionary) -> String:
	if deaths.is_empty():
		return "(none — all runs cleared)"
	var parts: Array[String] = []
	for key: Variant in deaths.keys():
		parts.append("%s×%d" % [String(key), int(deaths[key])])
	return ", ".join(parts)
