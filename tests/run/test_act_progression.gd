extends GutTest
## GUT tests for the 18-act progression loader + §5 invariants (ADR-0019).
##
## Happy path loads the REAL authored curve (res://data) and asserts it is well
## formed — so this suite also guards the authored act_progression.json. The
## failure cases build a known-good 18-act progression in memory and break exactly
## one invariant each, asserting ActProgression.validation_errors flags it.

const BOSS_CURVE := [
	5, 11, 18, 28, 36, 44, 62, 82, 105, 150,
	198, 250, 360, 465, 580, 820, 1050, 1300,
]


# --- Happy path: the real curve loads and validates ---
func test_real_curve_loads_and_is_valid() -> void:
	var db := ContentDatabase.new()
	var result := db.load_from_dir("res://data")
	assert_true(result.ok, "real /data should load cleanly: %s" % str(result.errors))

	var prog := db.get_act_progression()
	assert_not_null(prog, "act progression should load from data/acts")
	assert_eq(prog.count(), 18, "the dungeon has 18 acts")
	assert_eq(ActProgression.validation_errors(prog).size(), 0,
		"authored curve must satisfy every §5 invariant")


func test_real_curve_anchor_and_lookups() -> void:
	var db := ContentDatabase.new()
	db.load_from_dir("res://data")

	assert_eq(db.get_act(12).boss_level, 250, "Act 12 boss is the level-250 anchor")
	assert_eq(db.get_act(1).tier, 1, "Act 1 is tier 1")
	assert_eq(db.get_act(18).tier, 6, "Act 18 is tier 6")
	assert_eq(db.get_act(18).boss_level, 1300, "final boss level")
	assert_null(db.get_act(19), "no act 19")


func test_real_curve_parses_map_config() -> void:
	var db := ContentDatabase.new()
	db.load_from_dir("res://data")

	var m := db.get_act(1).map
	assert_not_null(m, "act 1 has a map config")
	assert_eq(m.late_row_bias, &"low", "late_row_bias parsed off the JSON")
	assert_true(bool(m.guarantees.get(&"rest_before_boss", false)),
		"rest_before_boss guarantee parsed")
	assert_eq(int(m.type_weights.get(&"combat", 0)), 6, "type_weights parsed")


# --- Failure cases: each breaks exactly one §5 invariant ---
func test_missing_act_fails() -> void:
	var prog := _make_valid()
	prog.acts.remove_at(17)  # drop act 18
	var errs := ActProgression.validation_errors(prog)
	assert_true(_has(errs, "expected 18"), "count mismatch reported: %s" % str(errs))
	assert_true(_has(errs, "missing act 18"), "missing spine member reported")


func test_anchor_must_be_250() -> void:
	var prog := _make_valid()
	prog.act_at(12).boss_level = 251  # still strictly increasing, only the anchor breaks
	var errs := ActProgression.validation_errors(prog)
	assert_true(_has(errs, "anchor"), "broken anchor reported: %s" % str(errs))


func test_boss_levels_must_strictly_increase() -> void:
	var prog := _make_valid()
	prog.act_at(5).boss_level = prog.act_at(4).boss_level  # flat step
	var errs := ActProgression.validation_errors(prog)
	assert_true(_has(errs, "strictly increasing"), "non-increasing reported: %s" % str(errs))


func test_tier_formula_enforced() -> void:
	var prog := _make_valid()
	prog.act_at(5).tier = 3  # act 5 is tier 2
	var errs := ActProgression.validation_errors(prog)
	assert_true(_has(errs, "tier"), "wrong tier reported: %s" % str(errs))


func test_rest_before_boss_required() -> void:
	var prog := _make_valid()
	prog.act_at(7).map.guarantees = {&"rest_before_boss": false}
	var errs := ActProgression.validation_errors(prog)
	assert_true(_has(errs, "rest_before_boss"), "missing guarantee reported: %s" % str(errs))


func test_tier_gate_must_be_steeper_than_within_tier() -> void:
	var prog := _make_valid()
	# Flatten the act-4 gate (18 -> 19) so the within-tier steps dwarf it, while
	# keeping the curve strictly increasing and the anchor intact.
	prog.act_at(4).boss_level = 19
	var errs := ActProgression.validation_errors(prog)
	assert_true(_has(errs, "tier gate at act 4"), "shallow gate reported: %s" % str(errs))


# --- Helpers ---
## Build a well-formed 18-act progression that passes every §5 invariant, so each
## test can break a single field in isolation.
func _make_valid() -> ActProgression:
	var prog := ActProgression.new()
	var list: Array[ActConfig] = []
	for i in range(1, 19):
		var a := ActConfig.new()
		a.act = i
		a.tier = int(floor(float(i - 1) / 3.0)) + 1
		a.boss_level = BOSS_CURVE[i - 1]
		a.trash_level = i
		a.elite_level = i * 2
		a.map = MapGenConfig.new()  # default guarantees include rest_before_boss = true
		list.append(a)
	prog.acts = list
	return prog


func _has(errors: PackedStringArray, substr: String) -> bool:
	for e in errors:
		if e.findn(substr) != -1:
			return true
	return false
