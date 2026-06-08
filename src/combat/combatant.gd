class_name Combatant
extends RefCounted
## Runtime state for ONE unit in a battle (task P1·04). This is the mutable,
## per-battle counterpart to the authored data Resource (CharacterData /
## EnemyData, data-schemas.md §4/§5): the Resource is the immutable definition,
## this is the live unit that takes damage, holds block, and accrues statuses.
##
## Positionless (ADR-0013): a unit has no tile or movement — it is a bag of
## hp/block/statuses (and, for party members, RPG stats) fighting for a team.
##
## Stats (ADR-0014): players carry STR/DEX/CON/INT and an `attack_stat` that
## selects which stat boosts their attacks. Enemies leave stats at 0 and
## `attack_stat` empty (their intent damage is authored flat).

## Team a unit fights for. Strict two-side prototype.
enum Team { PLAYER, ENEMY }

## Stable display name for logs/UI, copied from the source data on construction.
var display_name: String = ""

## Current / maximum hit points. `hp` is clamped to [0, max_hp]; a unit with
## hp == 0 is dead (see `is_alive`).
var hp: int = 1
var max_hp: int = 1

## Current block (armour). Consumed by incoming damage before hp.
var block: int = 0

## Active statuses: status_id -> stacks. Absent key == zero stacks.
var statuses: Dictionary = {}

## Which side this unit fights for.
var team: Team = Team.PLAYER

## RPG stats (ADR-0014). Players copy these from CharacterData; enemies leave 0.
var strength: int = 0
var dexterity: int = 0
var constitution: int = 0
var intelligence: int = 0
## Which stat powers this unit's attacks: `str`, `int`, or `&""` (none, enemies).
var attack_stat: StringName = &""

## How many times this unit has taken an enemy-phase action (drives the scheduled
## ramp's cadence, EnemyData.ramp_every). Player units leave this at 0.
var turns_taken: int = 0
## How many minions this unit has summoned (capped by EnemyData.summon_max).
var summons_done: int = 0

## Link back to the authored definition (CharacterData or EnemyData).
var source_data: Resource = null


## Build a player combatant from CharacterData (max_hp already derived from CON by
## the loader, ADR-0014).
static func from_character(data: CharacterData) -> Combatant:
	var c := Combatant.new()
	c.source_data = data
	c.team = Team.PLAYER
	c.display_name = data.display_name
	c.max_hp = data.max_hp
	c.hp = data.max_hp
	c.strength = data.strength
	c.dexterity = data.dexterity
	c.constitution = data.constitution
	c.intelligence = data.intelligence
	c.attack_stat = data.attack_stat
	return c


## Build an enemy combatant from EnemyData. Enemies carry no RPG stats; their
## intent damage is authored directly.
static func from_enemy(data: EnemyData) -> Combatant:
	var c := Combatant.new()
	c.source_data = data
	c.team = Team.ENEMY
	c.display_name = data.display_name
	c.max_hp = data.max_hp
	c.hp = data.max_hp
	return c


## True while the unit still has hit points.
func is_alive() -> bool:
	return hp > 0


func is_player() -> bool:
	return team == Team.PLAYER


func is_enemy() -> bool:
	return team == Team.ENEMY


# --- Status helpers ---------------------------------------------------------

## Current stacks of `status_id` (0 if absent).
func status_stacks(status_id: StringName) -> int:
	return int(statuses.get(status_id, 0))


func has_status(status_id: StringName) -> bool:
	return status_stacks(status_id) > 0


## Add `stacks` of `status_id`. Stacking math lives in BattleState; the Combatant
## just records the result. Negative or zero totals erase the key.
func set_status(status_id: StringName, stacks: int) -> void:
	if stacks <= 0:
		statuses.erase(status_id)
	else:
		statuses[status_id] = stacks


## Convenience: add `delta` stacks to whatever is already there.
func add_status_stacks(status_id: StringName, delta: int) -> void:
	set_status(status_id, status_stacks(status_id) + delta)


# --- Stat helpers -----------------------------------------------------------

## The value of this unit's attack stat (STR or INT per `attack_stat`); 0 if none.
## This is the flat bonus added to the unit's outgoing attack damage (ADR-0014).
func attack_power() -> int:
	match attack_stat:
		&"str":
			return strength
		&"dex":
			return dexterity
		&"int":
			return intelligence
		_:
			return 0


## Apply a race's stat modifiers to this unit (ADR-0015). CON also raises derived
## max HP by `con_mod * hp_per_con` (and current hp, so a fresh unit stays full).
## The race's custom card is granted to the deck elsewhere (creation flow).
func apply_race(race: RaceData, hp_per_con: int = 2) -> void:
	if race == null:
		return
	strength += race.str_mod
	dexterity += race.dex_mod
	constitution += race.con_mod
	intelligence += race.int_mod
	var hp_gain: int = race.con_mod * hp_per_con
	max_hp += hp_gain
	hp += hp_gain


## Apply player-allocated level-up stat points to this unit (ADR-0015, P3·05).
## `alloc` maps a stat key (`str`/`dex`/`con`/`int`) to allocated points; CON also
## raises derived max HP (and current hp) by `con_points * hp_per_con`, matching
## how class CON and race CON derive HP. Missing/zero keys are no-ops. Applied on
## top of the class base and any race mods, so call AFTER apply_race.
func apply_stat_allocation(alloc: Dictionary, hp_per_con: int = 2) -> void:
	if alloc == null or alloc.is_empty():
		return
	strength += int(alloc.get(&"str", 0))
	dexterity += int(alloc.get(&"dex", 0))
	intelligence += int(alloc.get(&"int", 0))
	var con_points: int = int(alloc.get(&"con", 0))
	constitution += con_points
	var hp_gain: int = con_points * hp_per_con
	max_hp += hp_gain
	hp += hp_gain
