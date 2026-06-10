extends "res://addons/gut/test.gd"
## GUT suite for Fame + Sponsor Boxes (ADR-0028, the DCC celebrity loop):
##   * Fame triggers on WON combats: flawless (+2), fast win (+1), elite (+3),
##     Charm executes (+2 each); capped at 50; banked on RunState.
##   * Sponsor Box at the act boundary: final Fame buys a relic by tier —
##     Bronze 10+ (common) / Silver 25+ (uncommon|rare) / Gold 50 (boss) —
##     seeded, deduplicated, then Fame resets for the new act.
##   * Fame survives the save/resume round-trip.

const RunControllerScript := preload("res://src/run/run_controller.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _controller() -> RunController:
	var rc := RunControllerScript.new(_db)
	rc.start_run([&"fighter", &"mage"] as Array[StringName], 7)
	return rc


## Begin enc_combat_01 at `band`, slaughter every enemy, and settle it as a
## `turns`-turn win. Returns the controller's banked Fame delta via run.fame.
func _win_fight(rc: RunController, band: StringName, turns: int, executes: int = 0) -> void:
	var battle: EncounterBattle = rc.begin_combat(&"enc_combat_01", band)
	assert_not_null(battle, "fight assembles")
	for foe in battle.living_enemies():
		foe.hp = 0
	battle.charm_executes = executes
	assert_eq(rc.finish_combat(&"enc_combat_01", battle, turns), BattleState.Outcome.WIN, "fight is won")


# --- Fame triggers ------------------------------------------------------------

func test_flawless_fast_win_banks_fame() -> void:
	var rc := _controller()
	_win_fight(rc, &"trash", 1)
	# No damage taken (+2) and a 1-turn win (+1).
	assert_eq(rc.run.fame, 3, "flawless (+2) + fast (+1) = 3 Fame")


func test_elite_band_and_charm_executes_add_fame() -> void:
	var rc := _controller()
	_win_fight(rc, &"elite", 1, 2)
	# Flawless +2, fast +1, elite +3, two executes +4.
	assert_eq(rc.run.fame, 10, "all four triggers stack")


func test_slow_damaged_win_banks_nothing() -> void:
	var rc := _controller()
	var battle: EncounterBattle = rc.begin_combat(&"enc_combat_01", &"trash")
	for foe in battle.living_enemies():
		foe.hp = 0
	# Chip a player so the fight is neither flawless nor fast.
	var unit: Combatant = battle.living_players()[0]
	unit.hp = maxi(1, unit.hp - 5)
	rc.finish_combat(&"enc_combat_01", battle, 6)
	assert_eq(rc.run.fame, 0, "no trigger fired, no Fame")


func test_fame_caps_at_fifty() -> void:
	var rc := _controller()
	rc.run.fame = 49
	_win_fight(rc, &"elite", 1, 5)
	assert_eq(rc.run.fame, 50, "Fame never exceeds the cap")


# --- Sponsor Box --------------------------------------------------------------

func test_gold_box_grants_a_boss_relic_and_resets_fame() -> void:
	var rc := _controller()
	rc.run.fame = 50
	assert_true(rc.advance_act(), "act 1 -> 2")
	assert_eq(rc.run.fame, 0, "Fame resets for the new act")
	assert_ne(rc.last_sponsor_relic, &"", "the Gold box granted a relic")
	assert_true(rc.run.relics.has(rc.last_sponsor_relic), "…and it joined the run")
	var relic: RelicData = _db.get_relic(rc.last_sponsor_relic)
	assert_eq(String(relic.rarity), "boss", "Gold tier draws from the boss pool")


func test_bronze_box_draws_common_and_silver_draws_higher() -> void:
	var rc := _controller()
	rc.run.fame = 10
	rc.advance_act()
	assert_eq(String(_db.get_relic(rc.last_sponsor_relic).rarity), "common", "Bronze -> common relic")

	var rc2 := _controller()
	rc2.run.fame = 25
	rc2.advance_act()
	var rarity: String = String(_db.get_relic(rc2.last_sponsor_relic).rarity)
	assert_true(rarity == "uncommon" or rarity == "rare", "Silver -> uncommon/rare relic")


func test_below_bronze_grants_no_box() -> void:
	var rc := _controller()
	rc.run.fame = 9
	rc.advance_act()
	assert_eq(rc.last_sponsor_relic, &"", "9 Fame is below every tier")
	assert_true(rc.run.relics.is_empty(), "no relic granted")


func test_sponsor_box_never_duplicates_an_owned_relic() -> void:
	var rc := _controller()
	# Own every boss relic up front: the Gold box must forfeit, not duplicate.
	for rid in _db.relics:
		var relic: RelicData = _db.relics[rid]
		if relic != null and String(relic.rarity) == "boss":
			rc.run.relics.append(rid)
	var owned: int = rc.run.relics.size()
	rc.run.fame = 50
	rc.advance_act()
	assert_eq(rc.last_sponsor_relic, &"", "an exhausted pool forfeits the box")
	assert_eq(rc.run.relics.size(), owned, "nothing was duplicated")


# --- Persistence ---------------------------------------------------------------

func test_fame_survives_the_save_round_trip() -> void:
	var rc := _controller()
	rc.run.fame = 23
	var copy: RunState = RunState.from_dict(rc.run.to_dict())
	assert_eq(copy.fame, 23, "Fame serializes with the run")
