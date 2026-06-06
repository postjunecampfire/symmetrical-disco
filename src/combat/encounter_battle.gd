class_name EncounterBattle
extends BattleState
## A BattleState wired to drive its enemy phase through an injected EnemyAI
## (task P1·09 integration). This is the ONLY seam needed to connect the
## standalone EnemyAI (P1·08) into the strict-phase turn loop (P1·04, ADR-0010)
## WITHOUT modifying battle_state.gd: BattleState exposes an overridable
## `_take_enemy_action(enemy)` hook, called once per living, un-stunned enemy
## during `_run_enemy_phase()`. EncounterBattle overrides exactly that hook to
## delegate to `enemy_ai.take_turn(self, enemy, enemy.source_data)`.
##
## Stun-skip and the enemy status tick already happen in BattleState BEFORE the
## hook fires, so this subclass adds only the AI delegation — no turn-loop logic
## is duplicated or overridden. The EncounterAssembler constructs this subclass
## and injects the EnemyAI so a fully assembled encounter runs its enemy phase
## end to end.

## The injected enemy controller. Selection/telegraph/movement/execution all live
## in EnemyAI (P1·08); this subclass only forwards the per-enemy action to it.
## Public so a caller (e.g. UI) can read telegraphs via `enemy_ai.get_telegraph`.
var enemy_ai: EnemyAI = null


## Forwards all BattleState construction to the base, then leaves `enemy_ai` to be
## injected (the assembler sets it after construction so the base `_init`
## signature is untouched). `controller` may be passed to wire the AI in one step.
func _init(
	battle_config: BattleConfig = null,
	grid_model: GridModel = null,
	battle_deck: Deck = null,
	status_definitions: Dictionary = {},
	controller: EnemyAI = null
) -> void:
	super(battle_config, grid_model, battle_deck, status_definitions)
	enemy_ai = controller


## Override of BattleState's enemy-action hook. Called once per living,
## un-stunned enemy during the enemy phase (the stun-skip is handled by the base
## before this runs). Delegates the whole action — intent selection, movement,
## and effect resolution — to the injected EnemyAI, passing this battle as the
## context and the enemy's authored EnemyData (its `source_data`). A no-op if no
## AI was injected or the enemy carries no EnemyData, so the phase loop stays safe.
func _take_enemy_action(enemy: Combatant) -> void:
	if enemy_ai == null:
		return
	var data: EnemyData = enemy.source_data as EnemyData
	if data == null:
		return
	enemy_ai.take_turn(self, enemy, data)
