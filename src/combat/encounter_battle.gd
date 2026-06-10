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

## The injected enemy controller. Selection/telegraph/execution all live in
## EnemyAI (P1·08); this subclass only forwards the per-enemy action to it.
## Public so a caller (e.g. UI) can read telegraphs via `enemy_ai.get_telegraph`.
var enemy_ai: EnemyAI = null

## Active run relics (RelicData, P2·12). The assembler applies their combat_start
## and passive effects once at build; this subclass applies their turn_start
## effects at each player turn via the override below. Empty in a plain battle.
var relics: Array[RelicData] = []
var _relic_engine: RelicEngine = RelicEngine.new()

## id -> EnemyData, so a summoner can spawn its minion mid-fight (set by the
## assembler from the ContentDatabase). Empty -> summons are skipped.
var enemy_db: Dictionary = {}


## Forwards all BattleState construction to the base, then leaves `enemy_ai` to be
## injected (the assembler sets it after construction so the base `_init`
## signature is untouched). `controller` may be passed to wire the AI in one step.
func _init(
	battle_config: BattleConfig = null,
	battle_deck: Deck = null,
	status_definitions: Dictionary = {},
	controller: EnemyAI = null
) -> void:
	super(battle_config, battle_deck, status_definitions)
	enemy_ai = controller


## Override of BattleState's enemy-action hook. Called once per living,
## un-stunned enemy during the enemy phase (the stun-skip is handled by the base
## before this runs). Delegates the whole action — intent selection and effect
## resolution — to the injected EnemyAI, passing this battle as the context and
## the enemy's authored EnemyData (its `source_data`). A no-op if no AI was
## injected or the enemy carries no EnemyData, so the phase loop stays safe.
func _take_enemy_action(enemy: Combatant) -> void:
	if enemy_ai == null:
		return
	var data: EnemyData = enemy.source_data as EnemyData
	if data == null:
		return
	# A summon turn CONSUMES the action (reinforcements instead of attacking). Then
	# ramp: a scheduled buff turn also consumes the action; a passive ramp is free and
	# the enemy still attacks.
	if _apply_enemy_summon(enemy, data):
		return
	if _apply_enemy_ramp(enemy, data):
		return
	enemy_ai.take_turn(self, enemy, data)


## Spawn a minion if `enemy` is a summoner and this is a summon turn. Every
## `summon_every` turns it summons one `summon_id` (resolved via `enemy_db`) into
## the enemy team, up to `summon_max` total, INSTEAD of acting (returns true). The
## new minion joins from the next enemy phase (the current phase iterates a snapshot
## of living enemies). Dragging the fight out keeps the board growing — the
## anti-turtle lever. False if not configured / not a summon turn / cap reached.
func _apply_enemy_summon(enemy: Combatant, data: EnemyData) -> bool:
	if data.summon_id == &"" or data.summon_every <= 0:
		return false
	enemy.turns_taken += 1
	if enemy.turns_taken % data.summon_every != 0:
		return false
	if enemy.summons_done >= data.summon_max:
		return false
	var minion_data: Variant = enemy_db.get(data.summon_id, null)
	if not (minion_data is EnemyData):
		return false
	add_combatant(Combatant.from_enemy(minion_data))
	enemy.summons_done += 1
	return true


## Peek at whether `enemy`'s NEXT action will be a special turn that REPLACES its
## attack — so the UI can telegraph it honestly (a ramp/summon turn otherwise shows
## the rolled attack and then the enemy buffs/summons instead). Returns &"summon",
## &"empower" (scheduled Strength ramp), or &"" (a normal/attack turn — passive ramp
## counts as normal since it doesn't replace the action). Mirrors the cadence used
## in _take_enemy_action (summon checked before ramp).
func upcoming_special(enemy: Combatant) -> StringName:
	var data := enemy.source_data as EnemyData
	if data == null:
		return &""
	var next_turn: int = enemy.turns_taken + 1
	if data.summon_id != &"" and data.summon_every > 0 \
			and next_turn % data.summon_every == 0 and enemy.summons_done < data.summon_max:
		return &"summon"
	if data.ramp_amount > 0 and not data.ramp_passive and data.ramp_every > 0 \
			and next_turn % data.ramp_every == 0:
		return &"empower"
	return &""


## Apply `enemy`'s damage ramp for the turn it is about to take. Passive ramp grants
## Strength every turn for free (returns false → the enemy still acts). A scheduled
## ramp (`ramp_every` > 0) counts the enemy's turns and, every Nth, grants Strength
## as a BUFF TURN that replaces the action (returns true → caller skips the attack).
## No ramp configured → false. Strength is the permanent +damage status, so it
## compounds across a long fight (punishing slow play) without nerfing burst.
func _apply_enemy_ramp(enemy: Combatant, data: EnemyData) -> bool:
	if data.ramp_amount <= 0:
		return false
	if data.ramp_passive:
		enemy.add_status_stacks(BattleState.STATUS_STRENGTH, data.ramp_amount)
		return false
	if data.ramp_every > 0:
		enemy.turns_taken += 1
		if enemy.turns_taken % data.ramp_every == 0:
			enemy.add_status_stacks(BattleState.STATUS_STRENGTH, data.ramp_amount)
			return true
	return false


## Begin a player turn, then apply any turn_start relic effects (gain_energy /
## draw_extra, P2·12) on top of the base energy refill + draw. Additive — the base
## turn logic is untouched.
func start_player_turn() -> void:
	super()
	if not relics.is_empty():
		_relic_engine.apply_turn_start(self, relics)


# --- M3 relic-trigger hook overrides (BattleState fires them; we route them) ---

## on_kill relics: an enemy died (any cause — attack, DoT, Charm execute).
func _on_enemy_killed(_unit: Combatant) -> void:
	if not relics.is_empty():
		_relic_engine.apply_on_kill(self, relics)


## hp_threshold relics: a member fell below half HP for the first time this combat.
func _on_player_low_hp(unit: Combatant) -> void:
	if not relics.is_empty():
		_relic_engine.apply_hp_threshold(self, relics, unit)


## on_curse_drawn relics: the drawing member is credited.
func _on_curse_drawn(unit: Combatant, _card: CardData) -> void:
	if not relics.is_empty():
		_relic_engine.apply_on_curse_drawn(self, relics, unit)


## on_status_applied relics: amplify a debuff that landed on an ENEMY. The bonus
## is added DIRECTLY (add_status_stacks) so it can never re-trigger this hook.
## Player-side applications (enemy debuffs on the party, self-buffs) are exempt —
## the relics read "whenever YOU apply X".
func _on_status_applied(target: Combatant, status_id: StringName, _stacks: int) -> void:
	if relics.is_empty() or target == null or target.is_player():
		return
	var bonus: int = RelicEngine.status_bonus(relics, status_id)
	if bonus > 0:
		target.add_status_stacks(status_id, bonus)


## on_card_played relics: flat damage bonus from the 3rd party card each turn.
func _combo_damage_bonus() -> int:
	if relics.is_empty():
		return 0
	return RelicEngine.combo_bonus(relics, cards_played_this_turn)
