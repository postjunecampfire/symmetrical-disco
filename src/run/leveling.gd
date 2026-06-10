class_name Leveling
extends RefCounted
## Per-character leveling (ADR-0015, P3·05): characters earn XP from combats and,
## on level-up, gain a pool of stat points the PLAYER allocates across
## STR/DEX/CON/INT. Growth is a deliberate choice, never fixed or random
## (ADR-0015). The allocated points apply on top of class + race each fight via
## Combatant.apply_stat_allocation (wired through EncounterAssembler).
##
## All numbers are tunable data on BattleConfig (ADR-0003): stat_points_per_level,
## xp_per_combat, and a linear XP curve (xp_curve_base + xp_curve_step * (L-1)).
## This class holds NO numbers itself — it only applies the config's rules to a
## RunState. It mutates the RunState's leveling dictionaries in place; it does not
## touch HP, the deck, or combat.
##
## State lives on RunState (persisted, ADR-0012):
##   party_level    character_id -> level (1-based; absent == 1)
##   party_xp       character_id -> XP toward the NEXT level (resets on level-up)
##   unspent_points character_id -> points available to allocate
##   allocated_stats character_id -> {str,dex,con,int} chosen by the player

const STAT_KEYS: Array[StringName] = [&"str", &"dex", &"con", &"int"]

## The injected tunables (curve + points-per-level + xp-per-combat).
var config: BattleConfig


func _init(battle_config: BattleConfig = null) -> void:
	config = battle_config if battle_config != null else BattleConfig.new()


# --- Queries ----------------------------------------------------------------

## The XP required to advance FROM `level` to `level + 1` (linear ramp). Level is
## clamped to >= 1 so a malformed level never produces a negative requirement.
func xp_to_next(level: int) -> int:
	var l: int = maxi(level, 1)
	return config.xp_curve_base + config.xp_curve_step * (l - 1)


## Current level of `cid` (1 if it has never levelled).
func level_of(run: RunState, cid: StringName) -> int:
	return int(run.party_level.get(cid, 1))


## Unspent stat points `cid` may still allocate.
func unspent(run: RunState, cid: StringName) -> int:
	return int(run.unspent_points.get(cid, 0))


# --- Lifecycle --------------------------------------------------------------

## Initialise a character's leveling state to level 1 / 0 XP / 0 points / empty
## allocation. Idempotent setup called at run start for each party member.
func init_character(run: RunState, cid: StringName) -> void:
	run.party_level[cid] = 1
	run.party_xp[cid] = 0
	run.unspent_points[cid] = 0
	run.allocated_stats[cid] = {&"str": 0, &"dex": 0, &"con": 0, &"int": 0}


## Award `amount` XP to `cid`, applying as many level-ups as the XP allows (a
## single award can cross several levels). Each level-up grants
## `config.stat_points_per_level` unspent points. Returns the number of levels
## gained. Non-positive `amount` is a no-op (returns 0).
func grant_xp(run: RunState, cid: StringName, amount: int) -> int:
	if amount <= 0:
		return 0
	if not run.party_level.has(cid):
		init_character(run, cid)
	var xp: int = int(run.party_xp.get(cid, 0)) + amount
	var level: int = int(run.party_level.get(cid, 1))
	var levels_gained: int = 0
	while xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		levels_gained += 1
		run.unspent_points[cid] = int(run.unspent_points.get(cid, 0)) + config.stat_points_per_level
		# Automatic growth (owner, 2026-06-10): every stat +auto_stats_per_level
		# per level, recorded in allocated_stats so it flows to combat, max-HP
		# derivation and heal caps through the existing seams.
		if config.auto_stats_per_level > 0:
			var alloc_v: Variant = run.allocated_stats.get(cid, {&"str": 0, &"dex": 0, &"con": 0, &"int": 0})
			var alloc: Dictionary = alloc_v if alloc_v is Dictionary else {}
			for stat in [&"str", &"dex", &"con", &"int"]:
				alloc[stat] = int(alloc.get(stat, 0)) + config.auto_stats_per_level
			run.allocated_stats[cid] = alloc
	run.party_level[cid] = level
	run.party_xp[cid] = xp
	return levels_gained


## Spend one unspent point of `cid` into `stat` (`str`/`dex`/`con`/`int`).
## Returns true if a point was spent; false if the stat is unknown or there are
## no unspent points. The choice is recorded in allocated_stats and the unspent
## pool decremented; the effect reaches combat via apply_stat_allocation.
func allocate_point(run: RunState, cid: StringName, stat: StringName) -> bool:
	if not STAT_KEYS.has(stat):
		return false
	if int(run.unspent_points.get(cid, 0)) <= 0:
		return false
	if not run.allocated_stats.has(cid):
		run.allocated_stats[cid] = {&"str": 0, &"dex": 0, &"con": 0, &"int": 0}
	var alloc: Dictionary = run.allocated_stats[cid]
	alloc[stat] = int(alloc.get(stat, 0)) + 1
	run.unspent_points[cid] = int(run.unspent_points[cid]) - 1
	return true
