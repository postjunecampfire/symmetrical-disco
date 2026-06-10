extends "res://addons/gut/test.gd"
## Races as BASE STAT TEMPLATES (ADR-0021 pt1, supersedes the small-modifier
## model of ADR-0015): each race carries the member's low base stat line
## (pinned: Human 3/3/3/3 · Elf 2/5/2/5 · Orc 5/3/4/2) plus one custom card,
## applied additively to a unit (CON also raises max HP via hp_per_con).

const ContentDatabaseScript := preload("res://src/data/content_database.gd")
const CombatantScript := preload("res://src/combat/combatant.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	var result: ContentDatabase.LoadResult = _db.load_from_dir("res://data")
	assert_true(result.ok, "real /data (incl. races) loads cleanly")


func test_three_races_load_with_resolvable_custom_cards() -> void:
	for rid in [&"human", &"elf", &"orc"]:
		var r: RaceData = _db.get_race(rid)
		assert_not_null(r, "race '%s' loaded" % rid)
		assert_ne(r.custom_card, &"", "race '%s' has a custom card" % rid)
		assert_not_null(_db.get_card(r.custom_card), "race '%s' custom card resolves" % rid)


func test_race_base_templates_match_pinned_lines() -> void:
	# ADR-0021 pt1 pinned base lines (HANDOFF / readiness doc).
	var orc: RaceData = _db.get_race(&"orc")
	assert_eq(orc.str_mod, 5, "Orc base STR 5")
	assert_eq(orc.dex_mod, 3, "Orc base DEX 3")
	assert_eq(orc.con_mod, 4, "Orc base CON 4")
	assert_eq(orc.int_mod, 2, "Orc base INT 2")
	var elf: RaceData = _db.get_race(&"elf")
	assert_eq(elf.str_mod, 2, "Elf base STR 2")
	assert_eq(elf.dex_mod, 5, "Elf base DEX 5")
	assert_eq(elf.con_mod, 2, "Elf base CON 2")
	assert_eq(elf.int_mod, 5, "Elf base INT 5")
	var human: RaceData = _db.get_race(&"human")
	for v in [human.str_mod, human.dex_mod, human.con_mod, human.int_mod]:
		assert_eq(v, 3, "Human is balanced (3 across)")


func test_apply_race_adds_base_template_and_hp() -> void:
	# Applying Orc (base 5/3/4/2) on top of a small class overlay (ADR-0021 pt1
	# composition): stats add, and max_hp gains CON(4) * hp_per_con(2) = 8.
	var c: Combatant = CombatantScript.new()
	c.strength = 2
	c.constitution = 1
	c.max_hp = 6  # base_hp 4 + class CON 1 * 2
	c.hp = 6
	c.apply_race(_db.get_race(&"orc"), 2)
	assert_eq(c.strength, 7, "STR = class 2 + Orc base 5")
	assert_eq(c.constitution, 5, "CON = class 1 + Orc base 4")
	assert_eq(c.max_hp, 14, "max_hp += race CON(4) * hp_per_con(2)")
	assert_eq(c.hp, 14, "current hp tracks the gain so a fresh unit stays full")


func test_legacy_mod_keys_still_parse() -> void:
	# The loader accepts the pre-ADR-0021 `*_mod` JSON keys (fixtures, old content).
	var parsed: Dictionary = _db._parse_race(
		{"id": "fixture_race", "display_name": "Fixture", "str_mod": 2, "con_mod": 1}, "test"
	)
	var r: RaceData = parsed.get("value")
	assert_not_null(r, "legacy-keyed race parses")
	assert_eq(r.str_mod, 2, "legacy str_mod honoured")
	assert_eq(r.con_mod, 1, "legacy con_mod honoured")


func test_apply_null_race_is_safe() -> void:
	var c: Combatant = CombatantScript.new()
	c.strength = 3
	c.apply_race(null, 2)
	assert_eq(c.strength, 3, "a null race is a no-op")
