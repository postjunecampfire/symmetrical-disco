extends "res://addons/gut/test.gd"
## Race placeholders (P3·04, ADR-0015): three races (Human/Elf/Orc) each carry a
## small stat modifier + one custom card, and apply their modifiers to a unit.

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


func test_race_stat_profiles() -> void:
	var orc: RaceData = _db.get_race(&"orc")
	assert_eq(orc.str_mod, 2, "Orc leans STR")
	assert_eq(orc.con_mod, 2, "Orc leans CON")
	var elf: RaceData = _db.get_race(&"elf")
	assert_eq(elf.dex_mod, 2, "Elf leans DEX")
	assert_eq(elf.int_mod, 2, "Elf leans INT")
	var human: RaceData = _db.get_race(&"human")
	assert_eq(human.str_mod, 1, "Human is balanced (+1 all)")
	assert_eq(human.intelligence if false else human.int_mod, 1, "Human +1 INT")


func test_apply_race_modifies_stats_and_hp() -> void:
	# Applying Orc (+2 STR, +2 CON) raises STR and max_hp (+ CON_mod * hp_per_con).
	var c: Combatant = CombatantScript.new()
	c.strength = 4
	c.constitution = 10
	c.max_hp = 20
	c.hp = 20
	c.apply_race(_db.get_race(&"orc"), 2)
	assert_eq(c.strength, 6, "STR +2 from Orc")
	assert_eq(c.constitution, 12, "CON +2 from Orc")
	assert_eq(c.max_hp, 24, "max_hp += CON_mod(2) * hp_per_con(2)")
	assert_eq(c.hp, 24, "current hp tracks the gain so a fresh unit stays full")


func test_apply_null_race_is_safe() -> void:
	var c: Combatant = CombatantScript.new()
	c.strength = 3
	c.apply_race(null, 2)
	assert_eq(c.strength, 3, "a null race is a no-op")
