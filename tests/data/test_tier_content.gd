extends "res://addons/gut/test.gd"
## GUT suite for the M3 per-tier content pass (ADR-0019 deferred tier modifiers —
## act-progression.md §4b): the new roster + tier bosses load from the REAL
## /data, every tier's pool resolves, every tier has its OWN boss, and each
## tier's combat pool actually carries its mechanical identity.

const ContentDatabaseScript := preload("res://src/data/content_database.gd")
const DATA_DIR := "res://data"

## The roster added by the tier-mechanics pass (act-progression.md §4b).
const NEW_ENEMIES: Array[StringName] = [
	# tier 1
	&"tunnel_rat", &"burrow_beetle",
	# tier 2 — debuff escalation
	&"ember_wisp", &"cinder_acolyte", &"dread_imp", &"grave_chanter",
	# tier 3 — attrition
	&"leech_swarm", &"rot_priest", &"plague_bearer", &"wall_breaker",
	# tier 4 — action economy
	&"bone_servant", &"gravecaller", &"mind_leech", &"chain_warden",
	# tier 5 — punish patterns
	&"bramble_fiend", &"pit_champion", &"huntmaster", &"blood_zealot",
	# tier 6 — legion
	&"legion_bannerman", &"legion_shieldbearer", &"legion_blade", &"void_herald",
	# bosses + their broods
	&"hollow_matron", &"carrion_king", &"broodling", &"broodmother",
	&"the_duelist", &"legion_king",
]

## tier -> its boss encounter (boss variety: 6 DISTINCT kits, Iron Warden = T1).
const TIER_BOSSES: Dictionary = {
	1: &"enc_boss_01",
	2: &"enc_boss_t2_matron",
	3: &"enc_boss_t3_carrion",
	4: &"enc_boss_t4_brood",
	5: &"enc_boss_t5_duelist",
	6: &"enc_boss_t6_legion",
}

var _db: ContentDatabase
var _load_ok: bool = false


func before_each() -> void:
	_db = ContentDatabaseScript.new()
	var result: ContentDatabase.LoadResult = _db.load_from_dir(DATA_DIR)
	_load_ok = result.ok
	if not result.ok:
		for msg in result.errors:
			push_warning("[/data load error] " + msg)


# ============================================================================
#  1. Everything loads & resolves
# ============================================================================

func test_real_data_loads_with_tier_content() -> void:
	assert_true(_load_ok, "/data loads cleanly with the tier-mechanics content")


func test_every_new_enemy_loads() -> void:
	for id in NEW_ENEMIES:
		assert_not_null(_db.get_enemy(id), "enemy '%s' loads" % id)
	assert_gte(_db.enemies.size(), 37, "roster reached the 37+ target (19 + the tier pass)")


func test_new_statuses_load() -> void:
	assert_not_null(_db.get_status(&"thorns"), "thorns StatusData present")
	assert_not_null(_db.get_status(&"enrage"), "enrage StatusData present")
	assert_false(_db.get_status(&"thorns").decays_each_turn, "thorns does not decay")
	assert_false(_db.get_status(&"enrage").decays_each_turn, "enrage does not decay")


func test_every_boss_encounter_loads_and_resolves() -> void:
	for tier: int in TIER_BOSSES:
		var enc_id: StringName = TIER_BOSSES[tier]
		var enc: EncounterData = _db.get_encounter(enc_id)
		assert_not_null(enc, "tier %d boss encounter '%s' loads" % [tier, enc_id])
		if enc == null:
			continue
		for enemy_id in enc.enemies:
			assert_not_null(_db.get_enemy(enemy_id),
				"boss encounter '%s' enemy '%s' resolves" % [enc_id, enemy_id])


# ============================================================================
#  2. tier_pools validation — every act of every tier has resolving pools
#     and at least one boss (extends the §5 invariants at the content level)
# ============================================================================

func test_every_act_pool_is_complete_and_resolves() -> void:
	for act_n in range(1, 19):
		var cfg: ActConfig = _db.get_act(act_n)
		assert_not_null(cfg, "act %d present" % act_n)
		if cfg == null:
			continue
		for node_type: StringName in ([&"combat", &"elite", &"boss"] as Array):
			var pool_v: Variant = cfg.encounter_pool.get(node_type, [])
			var pool: Array = pool_v if pool_v is Array else []
			assert_gt(pool.size(), 0, "act %d has a non-empty %s pool" % [act_n, node_type])
			for enc_id: Variant in pool:
				assert_true(_db.encounters.has(StringName(String(enc_id))),
					"act %d %s pool id '%s' resolves" % [act_n, node_type, enc_id])


func test_each_tier_has_its_own_boss() -> void:
	for act_n in range(1, 19):
		var cfg: ActConfig = _db.get_act(act_n)
		if cfg == null:
			continue
		var expected: StringName = TIER_BOSSES.get(cfg.tier, &"")
		var pool_v: Variant = cfg.encounter_pool.get(&"boss", [])
		var pool: Array = pool_v if pool_v is Array else []
		assert_true(pool.has(expected),
			"act %d (tier %d) boss pool carries '%s'" % [act_n, cfg.tier, expected])
	# The six tiers field six DISTINCT boss encounters.
	var distinct := {}
	for tier: int in TIER_BOSSES:
		distinct[TIER_BOSSES[tier]] = true
	assert_eq(distinct.size(), 6, "six distinct tier-boss encounters")


func test_iron_warden_is_tier_one_only() -> void:
	for tier: int in TIER_BOSSES:
		var enc: EncounterData = _db.get_encounter(TIER_BOSSES[tier])
		if enc == null:
			continue
		if tier == 1:
			assert_true(enc.enemies.has(&"iron_warden"), "tier 1 boss stays the Iron Warden")
		else:
			assert_false(enc.enemies.has(&"iron_warden"),
				"tier %d boss is NOT a scaled Iron Warden" % tier)


# ============================================================================
#  3. Tier mechanical identities — the combat/elite pools actually carry
#     their tier's signature mechanics (act-progression.md §4b table)
# ============================================================================

## All enemy ids reachable from a tier's combat+elite pools.
func _tier_enemy_ids(tier: int) -> Dictionary:
	var ids := {}
	var cfg: ActConfig = _db.get_act((tier - 1) * 3 + 1)
	if cfg == null:
		return ids
	for node_type: StringName in ([&"combat", &"elite"] as Array):
		var pool_v: Variant = cfg.encounter_pool.get(node_type, [])
		if not (pool_v is Array):
			continue
		for enc_id: Variant in pool_v:
			var enc: EncounterData = _db.get_encounter(StringName(String(enc_id)))
			if enc == null:
				continue
			for enemy_id in enc.enemies:
				ids[enemy_id] = true
	return ids


## True if any enemy in `ids` has an intent effect satisfying `pred`.
func _tier_has_effect(ids: Dictionary, pred: Callable) -> bool:
	for id: Variant in ids:
		var data: EnemyData = _db.get_enemy(StringName(String(id)))
		if data == null:
			continue
		for it in data.intents:
			for e in it.effects:
				if pred.call(e, data):
					return true
	return false


func test_tier2_pools_carry_curses_and_burn() -> void:
	var ids := _tier_enemy_ids(2)
	assert_true(_tier_has_effect(ids,
		func(e: Effect, _d: EnemyData) -> bool: return e.type == &"inflict_curse"),
		"tier 2 fields a curse inflictor")
	assert_true(_tier_has_effect(ids,
		func(e: Effect, _d: EnemyData) -> bool:
			return e.type == &"apply_status" and e.status == &"burn"),
		"tier 2 fields the first burn users")


func test_tier3_pools_carry_attrition_tools() -> void:
	var ids := _tier_enemy_ids(3)
	assert_true(_tier_has_effect(ids,
		func(e: Effect, _d: EnemyData) -> bool:
			return e.type == &"apply_status" and (e.status == &"bleed" or e.status == &"poison")),
		"tier 3 fields DoT stackers")
	assert_true(_tier_has_effect(ids,
		func(e: Effect, _d: EnemyData) -> bool: return e.type == &"pierce_damage"),
		"tier 3 punishes block (pierce_damage)")
	assert_true(_tier_has_effect(ids,
		func(e: Effect, _d: EnemyData) -> bool: return e.type == &"heal"),
		"tier 3 fields a healer")


func test_tier4_pools_attack_the_action_economy() -> void:
	var ids := _tier_enemy_ids(4)
	var has_summoner := false
	for id: Variant in ids:
		var data: EnemyData = _db.get_enemy(StringName(String(id)))
		if data != null and data.summon_id != &"" and data.summon_every > 0:
			has_summoner = true
	assert_true(has_summoner, "tier 4 fields a mid-fight summoner")
	assert_true(_tier_has_effect(ids,
		func(e: Effect, _d: EnemyData) -> bool: return e.type == &"inflict_curse"),
		"tier 4 disrupts the hand (mid-combat curses)")


func test_tier5_pools_carry_punish_patterns() -> void:
	var ids := _tier_enemy_ids(5)
	assert_true(_tier_has_effect(ids,
		func(e: Effect, _d: EnemyData) -> bool:
			return e.type == &"apply_status" and e.status == &"thorns"),
		"tier 5 fields a thorns user")
	assert_true(_tier_has_effect(ids,
		func(e: Effect, _d: EnemyData) -> bool:
			return e.type == &"apply_status" and e.status == &"enrage"),
		"tier 5 fields an enrage user")
	assert_true(_tier_has_effect(ids,
		func(e: Effect, _d: EnemyData) -> bool:
			return e.type == &"apply_status" and e.status == &"mark"),
		"tier 5 fields a mark user")


func test_tier6_pools_carry_legion_synergy() -> void:
	var ids := _tier_enemy_ids(6)
	var has_ally_buffer := false
	var has_shield_bearer := false
	for id: Variant in ids:
		var data: EnemyData = _db.get_enemy(StringName(String(id)))
		if data == null:
			continue
		for it in data.intents:
			if it.target == null or it.target.target_type != &"all_allies":
				continue
			for e in it.effects:
				if e.type == &"apply_status" and e.status == &"strength":
					has_ally_buffer = true
				if e.type == &"block":
					has_shield_bearer = true
	assert_true(has_ally_buffer, "tier 6 fields an ally strength buffer")
	assert_true(has_shield_bearer, "tier 6 fields a shield-bearer that blocks for allies")
