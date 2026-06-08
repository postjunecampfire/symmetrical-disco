extends "res://addons/gut/test.gd"
## Smoke test for the run/map screen (P2·10). The UI is asset-free and code-driven
## (no unit tests on rendering), but we boot MapView in a real tree to prove it
## wires up: content loads, a run starts, the map generates, and the start row is
## reachable. The node-resolution LOGIC it calls is covered by test_run_navigator /
## the resolver suites.

const MapViewScript := preload("res://src/ui/map_view.gd")


func test_map_view_boots_and_generates_a_run() -> void:
	var mv: MapView = MapViewScript.new()
	mv.party = [&"fighter", &"mage"] as Array[StringName]
	mv.party_races = {&"fighter": &"orc", &"mage": &"elf"}
	mv.run_seed = 42
	add_child_autofree(mv)  # triggers _ready

	assert_not_null(mv._controller, "RunController built")
	assert_not_null(mv._controller.run, "a run was started")
	assert_not_null(mv._controller.run.map, "a map was generated")
	assert_eq(mv._controller.run.party.size(), 2, "party carried into the run")
	assert_gt(mv._nav.reachable().size(), 0, "the start row is reachable")
	assert_false(mv._nav.is_complete(), "a fresh run is not complete")


func test_map_view_starts_combat_through_the_run_layer() -> void:
	# Travelling to a combat-type start node should assemble a battle via the run
	# controller (begin_combat) — proving the UI->run-layer combat seam is wired.
	var mv: MapView = MapViewScript.new()
	mv.party = [&"fighter", &"mage"] as Array[StringName]
	mv.run_seed = 7
	add_child_autofree(mv)

	var combat_node: MapNode = null
	for n in mv._nav.reachable():
		if n.node_type == &"combat" or n.node_type == &"elite" or n.node_type == &"boss":
			combat_node = n
			break
	if combat_node == null:
		pass_test("no combat node in the start row for this seed; nothing to assemble")
		return

	mv._on_node_chosen(combat_node)
	assert_not_null(mv._active_battle, "a battle was assembled for the combat node")
	assert_gt(mv._active_battle.living_enemies().size(), 0, "the assembled fight has enemies")
