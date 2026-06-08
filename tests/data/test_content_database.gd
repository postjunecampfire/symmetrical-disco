extends GutTest
## GUT tests for ContentDatabase (P1·02).
##
## These tests use the loader's OWN minimal fixture JSON under
## tests/data/fixtures/ and never touch the real /data game content (authored
## separately in P1·11). Each broken-fixture directory isolates exactly one
## validation path.

const FIXTURES := "res://tests/data/fixtures"


func _db() -> ContentDatabase:
	return ContentDatabase.new()


# --- Happy path ---
func test_happy_path_loads_all_categories() -> void:
	var db := _db()
	var result := db.load_from_dir(FIXTURES.path_join("valid"))

	assert_true(result.ok, "valid fixtures should load cleanly")
	assert_eq(result.errors.size(), 0, "no errors expected: %s" % str(result.errors))

	# Registries populated.
	assert_eq(db.statuses.size(), 2, "two statuses loaded")
	assert_eq(db.cards.size(), 2, "two cards loaded")
	assert_eq(db.characters.size(), 1, "one character loaded")
	assert_eq(db.enemies.size(), 1, "one enemy loaded")
	assert_eq(db.encounters.size(), 1, "one encounter loaded")


func test_happy_path_lookups_return_typed_resources() -> void:
	var db := _db()
	db.load_from_dir(FIXTURES.path_join("valid"))

	var card := db.get_card(&"shield_bash")
	assert_not_null(card, "shield_bash should resolve")
	assert_is(card, CardData)
	assert_eq(card.energy_cost, 1)
	assert_eq(card.effects.size(), 2, "two effects parsed")
	assert_eq(card.effects[0].type, &"damage")
	assert_eq(card.effects[0].amount, 6)
	assert_eq(card.effects[1].type, &"apply_status")
	assert_eq(card.effects[1].status, &"stun")
	assert_not_null(card.target, "target spec parsed")
	assert_eq(card.target.target_type, &"enemy")


func test_happy_path_nested_intents_and_config() -> void:
	var db := _db()
	db.load_from_dir(FIXTURES.path_join("valid"))

	var enemy := db.get_enemy(&"grunt")
	assert_not_null(enemy)
	assert_eq(enemy.intents.size(), 2, "two intents parsed")
	assert_eq(enemy.intents[0].id, &"grunt_swing")
	assert_eq(enemy.intents[0].weight, 2)

	var cfg := db.get_battle_config()
	assert_not_null(cfg, "battle config loaded")
	assert_eq(cfg.energy_per_turn, 3)
	assert_eq(cfg.draw_per_turn, 5)


# --- Stats: parsed, and max_hp derived from CON (ADR-0014) ---
func test_character_stats_and_con_derived_hp() -> void:
	var db := _db()
	db.load_from_dir(FIXTURES.path_join("valid"))

	var ch := db.get_character(&"vanguard")
	assert_not_null(ch, "character resolves")
	assert_eq(ch.constitution, 15, "CON parsed from data")
	assert_eq(ch.strength, 5, "STR parsed")
	assert_eq(ch.attack_stat, &"str", "attack_stat parsed")
	# max_hp is derived: constitution (15) * hp_per_con (default 2) = 30.
	assert_eq(ch.max_hp, 30, "max_hp derived from CON * hp_per_con")


# --- Validation: duplicate id ---
func test_duplicate_id_fails_loudly() -> void:
	var db := _db()
	var result := db.load_from_dir(FIXTURES.path_join("duplicate_id"))

	assert_false(result.ok, "duplicate id must fail the load")
	assert_true(_any_contains(result.errors, "Duplicate"), "error should mention duplicate: %s" % str(result.errors))
	# First definition wins; duplicate is rejected, not silently overwritten.
	assert_eq(db.cards.size(), 1, "only the first card kept")


# --- Validation: missing required field ---
func test_missing_required_field_fails_loudly() -> void:
	var db := _db()
	var result := db.load_from_dir(FIXTURES.path_join("missing_field"))

	assert_false(result.ok, "missing display_name must fail the load")
	assert_true(
		_any_contains(result.errors, "missing required field"),
		"error should mention the missing field: %s" % str(result.errors)
	)
	# The malformed card is dropped, not partially registered.
	assert_eq(db.cards.size(), 0, "broken card not registered")


# --- Validation: unknown effect type ---
func test_unknown_effect_type_fails_loudly() -> void:
	var db := _db()
	var result := db.load_from_dir(FIXTURES.path_join("unknown_effect"))

	assert_false(result.ok, "unknown effect.type must fail the load")
	assert_true(
		_any_contains(result.errors, "unknown effect.type"),
		"error should name the unknown effect type: %s" % str(result.errors)
	)


# --- Validation: dangling reference ---
func test_dangling_reference_fails_loudly() -> void:
	var db := _db()
	var result := db.load_from_dir(FIXTURES.path_join("dangling_ref"))

	assert_false(result.ok, "dangling enemy reference must fail the load")
	assert_true(
		_any_contains(result.errors, "unknown enemy"),
		"error should name the dangling enemy id: %s" % str(result.errors)
	)


# --- Validation: `return` on a stat-scaling damage card (ADR-0017) ---
func test_return_on_scaling_damage_fails_loudly() -> void:
	var db := _db()
	var result := db.load_from_dir(FIXTURES.path_join("return_on_scaling"))

	assert_false(result.ok, "`return` on an owned (scaling) damage card must fail the load")
	assert_true(
		_any_contains(result.errors, "return"),
		"error should name the banned `return` rule: %s" % str(result.errors)
	)


# --- Helper ---
func _any_contains(errors: PackedStringArray, needle: String) -> bool:
	for e in errors:
		if e.findn(needle) != -1:
			return true
	return false
