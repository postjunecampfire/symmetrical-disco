extends GutTest
## GUT tests for EnemyScaler (ADR-0019 enemy level->stat scaling).
##
## Asserts the structural invariants the scaler owns (factor shape, HP and damage
## sharing one factor, status stacks untouched, source never mutated) rather than
## any specific act magnitudes — those are a deferred balance decision.

var _db: ContentDatabase


func before_all() -> void:
	_db = ContentDatabase.new()
	_db.load_from_dir("res://data")


# --- factor() shape ---
func test_factor_is_one_at_baseline() -> void:
	var cfg := BattleConfig.new()
	cfg.enemy_scale_baseline_level = 5
	cfg.enemy_scale_exponent = 1.0
	var s := EnemyScaler.new(cfg)
	assert_almost_eq(s.factor(5), 1.0, 0.0001, "an enemy at the baseline level is unscaled")


func test_factor_is_monotonic_increasing() -> void:
	var s := EnemyScaler.new()  # baseline 1, exponent 1.0 -> factor == level
	assert_almost_eq(s.factor(1), 1.0, 0.0001)
	assert_true(s.factor(2) > s.factor(1), "factor rises with level")
	assert_true(s.factor(10) > s.factor(2), "factor keeps rising")


func test_exponent_bends_the_curve_convex() -> void:
	var cfg := BattleConfig.new()
	cfg.enemy_scale_baseline_level = 1
	cfg.enemy_scale_exponent = 2.0
	var s := EnemyScaler.new(cfg)
	assert_almost_eq(s.factor(3), 9.0, 0.0001, "(3/1)^2 == 9")
	assert_true(s.factor(3) > 3.0 * s.factor(1), "convex: grows faster than proportional")


func test_level_clamped_to_one() -> void:
	var s := EnemyScaler.new()
	assert_almost_eq(s.factor(0), 1.0, 0.0001, "level 0 clamps to the baseline, never 0x")


# --- apply_to(): HP + damage + block share one factor; statuses untouched ---
func test_hp_and_damage_and_block_scale_by_the_same_factor() -> void:
	var s := EnemyScaler.new()  # factor(level) == level
	var footman := _db.get_enemy(&"footman")
	assert_not_null(footman, "footman fixture present")
	# Derive expectations from the loaded data (not hardcoded magnitudes) so
	# balance passes on data/enemies/* can't break this structural invariant.
	var base_hp: int = footman.max_hp
	var base_dmg: int = _first_amount(footman, &"damage")
	var base_block: int = _first_amount(footman, &"block")
	var scaled := s.apply_to(footman, 10)  # factor 10

	assert_eq(scaled.max_hp, base_hp * 10, "HP x10")
	assert_eq(_first_amount(scaled, &"damage"), base_dmg * 10, "damage x10")
	assert_eq(_first_amount(scaled, &"block"), base_block * 10, "block x10")


func test_status_stacks_are_not_scaled() -> void:
	var s := EnemyScaler.new()
	var footman := _db.get_enemy(&"footman")
	var scaled := s.apply_to(footman, 10)
	assert_eq(_first_stacks(scaled, &"weak"), 1, "Weak stays 1 stack — control, not magnitude")


func test_source_enemy_is_not_mutated() -> void:
	var s := EnemyScaler.new()
	var footman := _db.get_enemy(&"footman")
	var hp_before: int = footman.max_hp
	var dmg_before: int = _first_amount(footman, &"damage")
	s.apply_to(footman, 25)
	assert_eq(footman.max_hp, hp_before, "base enemy HP untouched by scaling")
	assert_eq(_first_amount(footman, &"damage"), dmg_before, "base intent amount untouched")


func test_scaled_helper_floors() -> void:
	var s := EnemyScaler.new()
	assert_eq(s.scaled(0, 10, 0), 0, "a zero amount stays zero")
	assert_eq(s.scaled(30, 10, 1), 300, "normal scale")
	assert_eq(s.scaled(0, 10, 1), 1, "HP floor keeps at least 1")


# --- band_level() convenience ---
func test_band_level_reads_actconfig() -> void:
	var a := ActConfig.new()
	a.trash_level = 5
	a.elite_level = 9
	a.boss_level = 11
	assert_eq(EnemyScaler.band_level(a, &"trash"), 5)
	assert_eq(EnemyScaler.band_level(a, &"elite"), 9)
	assert_eq(EnemyScaler.band_level(a, &"boss"), 11)
	assert_eq(EnemyScaler.band_level(a, &"unknown"), 1, "unknown band -> 1")
	assert_eq(EnemyScaler.band_level(null, &"trash"), 1, "null act -> 1")


# --- helpers ---
func _first_amount(enemy: EnemyData, effect_type: StringName) -> int:
	for intent in enemy.intents:
		for e in intent.effects:
			if e.type == effect_type:
				return e.amount
	return -1


func _first_stacks(enemy: EnemyData, status: StringName) -> int:
	for intent in enemy.intents:
		for e in intent.effects:
			if e.type == &"apply_status" and e.status == status:
				return e.stacks
	return -1


# --- Lockstep guard (HANDOFF §5 DIRECTION / act-1-3-balance-proposal §7) ------

func test_factor_is_linear_lockstep() -> void:
	# The balance invariant: enemy-damage growth must keep pace with the player's
	# linear DEX->block growth, i.e. the scale factor stays LINEAR in level
	# (factor(L)/L constant). A convex curve here silently re-opens the
	# high-DEX turtle at depth — this guard fails loudly if the exponent or
	# factor shape ever changes.
	var db := ContentDatabase.new()
	db.load_from_dir("res://data")
	var cfg: BattleConfig = db.get_battle_config()
	var scaler := EnemyScaler.new(cfg)
	var baseline: float = float(cfg.enemy_scale_baseline_level)
	for level in [2, 5, 8, 18, 44, 105, 250, 1300]:
		var expected: float = float(level) / baseline
		assert_almost_eq(
			scaler.factor(level), expected, 0.001,
			"factor(%d) is linear in level (lockstep with DEX->block)" % level
		)
