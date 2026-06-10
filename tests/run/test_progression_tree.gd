extends "res://addons/gut/test.gd"
## ADR-0022: binary tree picks at the Act 6/9/12 boundaries + Act-15 Ascension.
## Eligibility is the ACT boundary; picks are final; Ascension applies the
## capstone's stat_mult step to every card and grants the Ult as a rare skill.

const RunControllerScript := preload("res://src/run/run_controller.gd")
const ContentDatabaseScript := preload("res://src/data/content_database.gd")

var _db: ContentDatabase


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	_db.load_from_dir("res://data")


func _classed(at_act: int = 6) -> RunController:
	var rc := RunControllerScript.new(_db)
	rc.start_run([&"hero_1"] as Array[StringName], 5, {&"hero_1": &"orc"})
	rc.choose_class(&"hero_1", &"fighter")
	rc.run.act = at_act
	return rc


func test_trees_load_with_resolving_ults() -> void:
	# fighter/mage/rogue (ADR-0022) + the DCC lines brawler/charmer (ADR-0028).
	for line in [&"fighter", &"mage", &"rogue", &"brawler", &"charmer"]:
		var tree: Dictionary = _db.progression_trees.get(line, {})
		assert_eq(tree.size(), 14, "line '%s' has 2+4+8 nodes" % line)
		var caps: int = 0
		for nid: Variant in tree:
			var node: Dictionary = tree[nid]
			if node.has("ult_card_id"):
				caps += 1
				assert_not_null(_db.get_card(StringName(String(node["ult_card_id"]))), "ult resolves")
		assert_eq(caps, 8, "8 capstones per line (40 Ults total)")


func test_options_gate_on_act_boundary_and_walk() -> void:
	var rc := _classed(5)
	assert_true(rc.progression_options(&"hero_1").is_empty(), "no pick before Act 6")
	rc.run.act = 6
	var arch: Array[Dictionary] = rc.progression_options(&"hero_1")
	assert_eq(arch.size(), 2, "archetype is a 1-of-2")
	assert_true(rc.apply_progression(&"hero_1", StringName(String(arch[0].get("id")))), "pick applies")
	assert_true(rc.progression_options(&"hero_1").is_empty(), "next beat waits for Act 9")
	rc.run.act = 9
	var spec: Array[Dictionary] = rc.progression_options(&"hero_1")
	assert_eq(spec.size(), 2, "specialization is a 1-of-2 under the chosen archetype")
	for node in spec:
		assert_eq(String(node.get("parent")), String(arch[0].get("id")), "children of the pick only")


func test_pick_applies_stat_bonus() -> void:
	var rc := _classed(6)
	var before: int = PartyStats.effective_max_hp(_db, rc.run, &"hero_1")
	var arch: Array[Dictionary] = rc.progression_options(&"hero_1")
	rc.apply_progression(&"hero_1", StringName(String(arch[0].get("id"))))
	assert_gt(
		PartyStats.effective_max_hp(_db, rc.run, &"hero_1"), before,
		"the node's CON bonus raises effective max HP"
	)


func test_ascension_grants_mult_step_and_ult() -> void:
	var rc := _classed(6)
	for act in [6, 9, 12]:
		rc.run.act = act
		var options: Array[Dictionary] = rc.progression_options(&"hero_1")
		assert_eq(options.size(), 2, "1-of-2 at act %d" % act)
		rc.apply_progression(&"hero_1", StringName(String(options[0].get("id"))))
	rc.run.act = 14
	assert_false(rc.ascension_available(&"hero_1"), "no Ascension before Act 15")
	rc.run.act = 15
	assert_true(rc.ascend(&"hero_1"), "Ascension fires at Act 15")
	assert_false(rc.ascend(&"hero_1"), "Ascension is once")
	var ch: CharacterData = PartyMember.character_for(_db, rc.run, &"hero_1")
	assert_gt(ch.ascension_mult, 0.0, "the flat stat_mult step is on the sheet")
	assert_true(ch.display_name.begins_with("Ascended"), "Ascended <name>")
	var has_ult: bool = false
	for sid: Variant in rc.run.skill_collections[&"hero_1"]:
		if String(sid).begins_with("ult_"):
			has_ult = true
	assert_true(has_ult, "the capstone's Ult joined the collection")
