extends "res://addons/gut/test.gd"
## GUT smoke test for the playable battle scene (task P1·10, BattleView).
##
## SCOPE: this is a HEADLESS BUILD smoke test, not a rendering test. It adds a
## BattleView into the scene tree so its `_ready()` runs end to end — loading the
## real /data via ContentDatabase, assembling `skirmish_01` for [vanguard, mage]
## through EncounterAssembler, wrapping it in CardPlay, and starting the first
## player turn — and asserts the battle was built and is in a playable state.
##
## It does NOT exercise drawing: the board's `_draw` only fires on an actual
## render pass, which does not happen under --headless, so nothing here depends on
## fonts or pixels. If the project's content or any wired system regresses,
## BattleView._ready() fails to build a battle and these assertions catch it.

const BattleViewScript := preload("res://src/ui/battle_view.gd")


## Add a fresh BattleView under the test's scene tree (so _ready runs) and return
## it. add_child_autofree frees it when the test ends.
func _make_view() -> BattleView:
	var view: BattleView = BattleViewScript.new()
	add_child_autofree(view)
	return view


func test_ready_builds_a_playable_battle() -> void:
	var view: BattleView = _make_view()

	# The data load must have succeeded (no error label was created) and the
	# battle must exist with the expected combatants.
	assert_null(view._error_label, "content load should succeed (no error surface)")
	assert_not_null(view._battle, "BattleView should assemble a battle in _ready()")
	if view._battle == null:
		return

	var battle: EncounterBattle = view._battle
	assert_eq(battle.grid.size, Vector2i(6, 6), "skirmish_01 is a 6x6 grid")
	assert_eq(battle.living_players().size(), 2, "party of two should spawn")
	assert_eq(battle.living_enemies().size(), 3, "skirmish_01 has three enemies")


func test_first_player_turn_is_started_with_energy_and_hand() -> void:
	var view: BattleView = _make_view()
	assert_not_null(view._battle, "battle should be assembled")
	if view._battle == null:
		return

	var battle: EncounterBattle = view._battle
	assert_eq(battle.turn_number, 1, "the first player turn should have started")
	assert_eq(battle.energy, battle.config.energy_per_turn, "energy refilled for turn 1")
	assert_gt(battle.deck.hand.size(), 0, "an opening hand should have been drawn")
	assert_not_null(view._card_play, "a CardPlay controller should be created")


func test_default_selection_targets_a_living_player() -> void:
	var view: BattleView = _make_view()
	if view._battle == null:
		assert_not_null(view._battle, "battle should be assembled")
		return
	assert_not_null(view._selected, "a default unit should be selected for the player")
	if view._selected != null:
		assert_true(view._selected.is_player(), "the default selection is a player unit")
		assert_true(view._selected.is_alive(), "the default selection is alive")
