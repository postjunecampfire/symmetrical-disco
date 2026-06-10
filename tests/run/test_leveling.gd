extends "res://addons/gut/test.gd"
## GUT suite for the leveling engine (ADR-0015 / P3·05): XP from combats levels a
## character up, each level-up grants a tunable pool of stat points, and the
## player allocates those points across STR/DEX/CON/INT. All numbers come from a
## BattleConfig; the engine only applies its rules to a RunState.

const LevelingScript := preload("res://src/run/leveling.gd")
const RunStateScript := preload("res://src/run/run_state.gd")


## A BattleConfig with explicit leveling tunables so each test states its numbers.
func _config(points: int = 3, base: int = 30, step: int = 20) -> BattleConfig:
	var cfg := BattleConfig.new()
	cfg.stat_points_per_level = points
	cfg.xp_curve_base = base
	cfg.xp_curve_step = step
	return cfg


func _run_with(cid: StringName, lv: Leveling) -> RunState:
	var run := RunStateScript.new()
	run.party = [cid] as Array[StringName]
	lv.init_character(run, cid)
	return run


# --- XP curve ---------------------------------------------------------------

func test_xp_curve_is_linear_ramp() -> void:
	var lv := LevelingScript.new(_config(3, 30, 20))
	assert_eq(lv.xp_to_next(1), 30, "L1->L2 = base")
	assert_eq(lv.xp_to_next(2), 50, "L2->L3 = base + step")
	assert_eq(lv.xp_to_next(3), 70, "L3->L4 = base + 2*step")


func test_xp_curve_clamps_bad_level() -> void:
	var lv := LevelingScript.new(_config(3, 30, 20))
	assert_eq(lv.xp_to_next(0), 30, "level < 1 is clamped to 1 (never negative)")


# --- Init -------------------------------------------------------------------

func test_init_character_starts_at_level_one() -> void:
	var lv := LevelingScript.new(_config())
	var run := _run_with(&"hero", lv)
	assert_eq(lv.level_of(run, &"hero"), 1, "starts at level 1")
	assert_eq(int(run.party_xp[&"hero"]), 0, "starts at 0 XP")
	assert_eq(lv.unspent(run, &"hero"), 0, "no points before any level-up")


# --- Granting XP / level-ups ------------------------------------------------

func test_xp_below_threshold_does_not_level() -> void:
	var lv := LevelingScript.new(_config(3, 30, 20))
	var run := _run_with(&"hero", lv)
	var gained: int = lv.grant_xp(run, &"hero", 29)
	assert_eq(gained, 0, "29 < 30: no level gained")
	assert_eq(lv.level_of(run, &"hero"), 1, "still level 1")
	assert_eq(int(run.party_xp[&"hero"]), 29, "XP accumulates toward next level")
	assert_eq(lv.unspent(run, &"hero"), 0, "no points granted")


func test_single_level_up_grants_points_and_keeps_remainder() -> void:
	var lv := LevelingScript.new(_config(3, 30, 20))
	var run := _run_with(&"hero", lv)
	var gained: int = lv.grant_xp(run, &"hero", 35)
	assert_eq(gained, 1, "35 >= 30: one level")
	assert_eq(lv.level_of(run, &"hero"), 2, "now level 2")
	assert_eq(int(run.party_xp[&"hero"]), 5, "remainder (35-30) carries to next level")
	assert_eq(lv.unspent(run, &"hero"), 3, "one level-up grants stat_points_per_level")


func test_one_award_can_cross_multiple_levels() -> void:
	# 30 (L1->2) + 50 (L2->3) = 80 needed for two levels; 90 grants two and leaves 10.
	var lv := LevelingScript.new(_config(3, 30, 20))
	var run := _run_with(&"hero", lv)
	var gained: int = lv.grant_xp(run, &"hero", 90)
	assert_eq(gained, 2, "a single big award crosses two levels")
	assert_eq(lv.level_of(run, &"hero"), 3, "now level 3")
	assert_eq(int(run.party_xp[&"hero"]), 10, "remainder after two thresholds")
	assert_eq(lv.unspent(run, &"hero"), 6, "two level-ups -> 2 * points")


func test_grant_zero_or_negative_is_noop() -> void:
	var lv := LevelingScript.new(_config())
	var run := _run_with(&"hero", lv)
	assert_eq(lv.grant_xp(run, &"hero", 0), 0, "0 XP does nothing")
	assert_eq(lv.grant_xp(run, &"hero", -5), 0, "negative XP does nothing")
	assert_eq(lv.level_of(run, &"hero"), 1, "still level 1")


# --- Allocation -------------------------------------------------------------

func test_allocate_spends_points_into_chosen_stat() -> void:
	var lv := LevelingScript.new(_config(3, 30, 20))
	var run := _run_with(&"hero", lv)
	lv.grant_xp(run, &"hero", 30)  # -> 3 points
	assert_true(lv.allocate_point(run, &"hero", &"str"), "spends a point into STR")
	assert_true(lv.allocate_point(run, &"hero", &"con"), "spends a point into CON")
	assert_eq(lv.unspent(run, &"hero"), 1, "two of three points spent")
	var alloc: Dictionary = run.allocated_stats[&"hero"]
	# One level-up granted auto_stats_per_level (1) to EVERY stat (owner,
	# 2026-06-10); the two spent points stack on top of that floor.
	var auto: int = _config().auto_stats_per_level
	assert_eq(int(alloc[&"str"]), auto + 1, "STR = auto growth + spent point")
	assert_eq(int(alloc[&"con"]), auto + 1, "CON = auto growth + spent point")
	assert_eq(int(alloc[&"dex"]), auto, "DEX rose by the automatic growth alone")


func test_allocate_fails_without_points() -> void:
	var lv := LevelingScript.new(_config())
	var run := _run_with(&"hero", lv)
	assert_false(lv.allocate_point(run, &"hero", &"str"), "cannot spend with 0 unspent")
	assert_eq(int(run.allocated_stats[&"hero"][&"str"]), 0, "nothing allocated")


func test_allocate_rejects_unknown_stat() -> void:
	var lv := LevelingScript.new(_config(3, 30, 20))
	var run := _run_with(&"hero", lv)
	lv.grant_xp(run, &"hero", 30)  # 3 points
	assert_false(lv.allocate_point(run, &"hero", &"luck"), "unknown stat rejected")
	assert_eq(lv.unspent(run, &"hero"), 3, "no point consumed on rejection")
