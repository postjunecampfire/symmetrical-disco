class_name EnemyScaler
extends RefCounted
## Scales a base enemy stat block to an act's enemy level band (ADR-0019).
##
## The per-act level CURVE — and its tier-gate spikes — is authored in
## act_progression.json (trash/elite/boss bands per act). This class is just the
## pure level->stat FUNCTION applied on top: it turns a level into a multiplier and
## stamps it onto an enemy's HP and numeric intent magnitudes.
##
## Two structural guarantees (the half of the HANDOFF §5 invariant the scaler owns,
## pinned on the Asana scaler task):
##   * HP and every numeric intent amount (damage AND block) scale by the SAME
##     factor, so enemy OFFENSE and DEFENSE grow together by construction — they
##     can never drift apart at depth.
##   * Status STACKS (poison/weak/frail/vulnerable, Strength ramp) are CONTROL, not
##     magnitude, and are left unscaled — a 2-stack Weak stays 2-stack at any level.
##
## The factor SHAPE is data (BattleConfig.enemy_scale_baseline_level / _exponent)
## and defaults to proportional (factor proportional to level), since the gate
## spikes already live in the bands. Linear-vs-mild-exponential and the baseline
## calibration against the authored Act-1 roster are balance-pass decisions
## (ADR-0019 open question); this code is the mechanism, not the final numbers.

const EFFECT_DAMAGE: StringName = &"damage"
const EFFECT_BLOCK: StringName = &"block"
## M3 tier mechanics: pierce/heal/revive are MAGNITUDES like damage/block (an
## unscaled self-heal or pierce would vanish against deep-act HP pools), so they
## ride the same factor. Status STACKS stay control and stay unscaled.
const SCALED_EFFECT_TYPES: Array[StringName] = [
	&"damage", &"block", &"pierce_damage", &"heal", &"revive_allies",
]

var _baseline_level: int = 1
var _exponent: float = 1.0


func _init(config: BattleConfig = null) -> void:
	if config != null:
		_baseline_level = maxi(1, config.enemy_scale_baseline_level)
		_exponent = config.enemy_scale_exponent


## Multiplier for an enemy authored at the baseline level when fought at `level`.
## factor(baseline) == 1.0 and the result is strictly increasing in level. With
## exponent 1.0 the factor tracks level proportionally; exponent > 1.0 bends it
## convex (mild-exponential). Level is clamped to >= 1 so a malformed band never
## yields a zero/negative multiplier.
func factor(level: int) -> float:
	var l: float = float(maxi(1, level))
	var base: float = float(maxi(1, _baseline_level))
	return pow(l / base, _exponent)


## Base `value` scaled to `level` and rounded; floored at `floor_to` (1 for HP so a
## scaled enemy never has 0 max HP, 0 for damage/block so a 0 stays 0).
func scaled(value: int, level: int, floor_to: int = 0) -> int:
	return maxi(floor_to, int(round(float(value) * factor(level))))


## A DEEP COPY of `enemy` scaled to `level`: max_hp and every damage/block intent
## amount multiplied by factor(level); status stacks, weights, ramp and summon
## fields untouched. The loaded resource is never mutated, so the same base enemy
## can be scaled to many acts independently. Copies are built explicitly (rather
## than relying on duplicate(true)'s nested-array semantics) so the deep copy is
## version-robust, matching the `e.duplicate() as Effect` idiom in battle_state.
func apply_to(enemy: EnemyData, level: int) -> EnemyData:
	var f: float = factor(level)
	var copy := enemy.duplicate() as EnemyData  # shallow: scalar fields
	copy.max_hp = maxi(1, int(round(float(enemy.max_hp) * f)))
	var new_intents: Array[IntentData] = []
	for intent in enemy.intents:
		if intent == null:
			continue
		var ic := intent.duplicate() as IntentData
		var new_effects: Array[Effect] = []
		for e in intent.effects:
			if e == null:
				continue
			var ec := e.duplicate() as Effect
			if SCALED_EFFECT_TYPES.has(ec.type):
				ec.amount = maxi(0, int(round(float(ec.amount) * f)))
			new_effects.append(ec)
		ic.effects = new_effects
		new_intents.append(ic)
	copy.intents = new_intents
	return copy


## Convenience: the enemy level for a `band` ("trash" | "elite" | "boss") of an
## act, read straight off ActConfig. Lets the (later) encounter-assembly task pick
## a level per enemy role without re-deriving the bands. Returns 1 for an unknown
## band or a null act.
static func band_level(act: ActConfig, band: StringName) -> int:
	if act == null:
		return 1
	match band:
		&"trash":
			return act.trash_level
		&"elite":
			return act.elite_level
		&"boss":
			return act.boss_level
		_:
			return 1
