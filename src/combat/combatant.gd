class_name Combatant
extends RefCounted
## Runtime state for ONE unit in a battle (task P1·04). This is the mutable,
## per-battle counterpart to the authored data Resource (CharacterData /
## EnemyData, data-schemas.md §4/§5): the Resource is the immutable definition,
## this is the live unit that takes damage, holds block, accrues statuses, and
## stands on a tile. Many Combatants can share one data Resource (e.g. three
## copies of the same grunt) without mutating it.
##
## Statuses are stored as a flat dictionary `status_id (StringName) -> stacks
## (int)`. BattleState owns the BEHAVIOUR keyed by id (poison damages, stun
## skips, …); the Combatant only stores the magnitudes. `block` is modelled as a
## first-class field (not a status entry) because incoming damage consumes it
## every hit, while StatusData drives how/whether it decays per turn.

## Team a unit fights for. Strict two-side prototype (data-schemas.md §12 turn
## order resolved as player-phase / enemy-phase).
enum Team { PLAYER, ENEMY }

## Stable display name for logs/UI, copied from the source data on construction.
var display_name: String = ""

## Current / maximum hit points. `hp` is clamped to [0, max_hp]; a unit with
## hp == 0 is dead (see `is_alive`).
var hp: int = 1
var max_hp: int = 1

## Current block (armour). Consumed by incoming damage before hp; how it carries
## or resets across turns is driven by the `block` StatusData in BattleState.
var block: int = 0

## Active statuses: status_id -> stacks. Absent key == zero stacks. BattleState
## reads/ticks this; the Combatant just stores it.
var statuses: Dictionary = {}

## Grid position (tile coord). BattleState keeps this in sync with the GridModel
## occupant registry when the unit moves.
var grid_position: Vector2i = Vector2i.ZERO

## Which side this unit fights for.
var team: Team = Team.PLAYER

## Tiles this unit may move per move action (from the source data's move_range).
var move_range: int = 0

## Link back to the authored definition (CharacterData or EnemyData). Kept as the
## seam to source values (speed, intents, innate_actions, …) without copying them
## all onto the runtime unit. Never mutated.
var source_data: Resource = null


## Build a player combatant from CharacterData, spawned at `spawn`.
static func from_character(data: CharacterData, spawn: Vector2i) -> Combatant:
	var c := Combatant.new()
	c.source_data = data
	c.team = Team.PLAYER
	c.display_name = data.display_name
	c.max_hp = data.max_hp
	c.hp = data.max_hp
	c.move_range = data.move_range
	c.grid_position = spawn
	return c


## Build an enemy combatant from EnemyData, spawned at `spawn`.
static func from_enemy(data: EnemyData, spawn: Vector2i) -> Combatant:
	var c := Combatant.new()
	c.source_data = data
	c.team = Team.ENEMY
	c.display_name = data.display_name
	c.max_hp = data.max_hp
	c.hp = data.max_hp
	c.move_range = data.move_range
	c.grid_position = spawn
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


## Add `stacks` of `status_id`. Stacking math (add vs refresh) lives in
## BattleState, which consults StatusData; the Combatant just records the result.
## Negative or zero totals erase the key so absent == zero.
func set_status(status_id: StringName, stacks: int) -> void:
	if stacks <= 0:
		statuses.erase(status_id)
	else:
		statuses[status_id] = stacks


## Convenience: add `delta` stacks to whatever is already there.
func add_status_stacks(status_id: StringName, delta: int) -> void:
	set_status(status_id, status_stacks(status_id) + delta)
