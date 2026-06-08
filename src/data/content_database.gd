class_name ContentDatabase
extends RefCounted
## Loads JSON content from /data into typed Resource registries and validates it
## against the contract in docs/systems/data-schemas.md.
##
## Usage:
##   var db := ContentDatabase.new()
##   var result := db.load_from_dir("res://data")
##   if result.ok:
##       var card := db.get_card(&"strike")
##
## Detection and reporting are separated so the validation path stays free of
## engine errors (which makes it unit-testable):
##   - load_from_dir() only COLLECTS problems into the returned
##     LoadResult.errors array and reports ok == false; it never push_error()s.
##   - load_and_report() wraps load_from_dir() and additionally push_error()s
##     each collected problem, preserving "fail LOUDLY" for real game runs.
## Either way a load with any error leaves the registries partially populated
## but reports ok == false; callers must treat a failed load as fatal.

## The §2.3 prototype effect-type registry. Any effect.type outside this set is
## an unknown-effect error.
const EFFECT_TYPES: Array[StringName] = [
	&"damage",
	&"block",
	&"heal",
	&"apply_status",
	&"draw",
	&"gain_energy",
]

## Reserved character_tag meaning "any unit can play" (data-schemas.md §3).
const NEUTRAL_TAG: StringName = &"neutral"

## Result of a load attempt. ok is true only when errors is empty.
class LoadResult extends RefCounted:
	var ok: bool = false
	var errors: PackedStringArray = PackedStringArray()

	## Record a problem. Detection-only: this never emits an engine error, so the
	## validation path can be exercised by tests without tripping GUT's error
	## tracker. Loud reporting is done separately by ContentDatabase.load_and_report().
	func add_error(msg: String) -> void:
		errors.append(msg)


# --- Registries, keyed by id (StringName) ---
var statuses: Dictionary = {}
var cards: Dictionary = {}
var characters: Dictionary = {}
var enemies: Dictionary = {}
var encounters: Dictionary = {}
var races: Dictionary = {}
var battle_config: BattleConfig

var _result: LoadResult


# --- Public lookups ---
func get_status(id: StringName) -> StatusData:
	return statuses.get(id, null)


func get_card(id: StringName) -> CardData:
	return cards.get(id, null)


func get_character(id: StringName) -> CharacterData:
	return characters.get(id, null)


func get_enemy(id: StringName) -> EnemyData:
	return enemies.get(id, null)


func get_race(id: StringName) -> RaceData:
	return races.get(id, null)


func get_encounter(id: StringName) -> EncounterData:
	return encounters.get(id, null)


func get_battle_config() -> BattleConfig:
	return battle_config


## Load every content category from a /data-style directory. Returns a LoadResult.
func load_from_dir(data_dir: String) -> LoadResult:
	_result = LoadResult.new()
	statuses.clear()
	cards.clear()
	characters.clear()
	enemies.clear()
	encounters.clear()
	races.clear()
	battle_config = null

	# Order matters for reference validation: load referenced entities before
	# the ones that reference them where practical, but we validate references
	# in a dedicated pass after all parsing so order is not load-bearing.
	_load_category(data_dir.path_join("status"), _parse_status, statuses, "status")
	_load_category(data_dir.path_join("characters"), _parse_character, characters, "character")
	_load_category(data_dir.path_join("enemies"), _parse_enemy, enemies, "enemy")
	_load_category(data_dir.path_join("cards"), _parse_card, cards, "card")
	_load_category(data_dir.path_join("encounters"), _parse_encounter, encounters, "encounter")
	_load_category(data_dir.path_join("races"), _parse_race, races, "race")
	_load_battle_config(data_dir.path_join("battle_config.json"))
	_derive_character_hp()

	_validate_references()

	_result.ok = _result.errors.is_empty()
	return _result


## Load like load_from_dir(), then fail LOUDLY: push_error() every collected
## problem so a real game boot surfaces bad data in the editor/console. Detection
## itself stays in load_from_dir(); this only adds the loud reporting on top, so
## tests can exercise validation via load_from_dir() without engine-error noise.
func load_and_report(data_dir: String) -> LoadResult:
	var result := load_from_dir(data_dir)
	if not result.ok:
		for msg in result.errors:
			push_error("[ContentDatabase] " + msg)
	return result


# --- Generic directory loader ---
# parse_fn: Callable(dict, source_path) -> { "id": StringName, "value": Resource } or {} on error.
func _load_category(dir_path: String, parse_fn: Callable, registry: Dictionary, label: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		# A missing category directory is not fatal on its own (a project may
		# legitimately have no encounters yet); reference validation will catch
		# any dangling pointers into an absent category.
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_result.add_error("Cannot open %s directory: %s" % [label, dir_path])
		return
	for file_name in dir.get_files():
		if not file_name.to_lower().ends_with(".json"):
			continue
		var path := dir_path.path_join(file_name)
		var entries := _read_json_array(path)
		for entry in entries:
			if typeof(entry) != TYPE_DICTIONARY:
				_result.add_error("%s file %s contains a non-object entry" % [label, path])
				continue
			var parsed: Dictionary = parse_fn.call(entry, path)
			if parsed.is_empty():
				continue # parse_fn already recorded the error
			var id: StringName = parsed["id"]
			if registry.has(id):
				_result.add_error(
					"Duplicate %s id '%s' (in %s)" % [label, id, path]
				)
				continue
			registry[id] = parsed["value"]


# Reads a JSON file and always returns an Array of raw entries. A file may hold
# either a single object or an array of objects.
func _read_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		_result.add_error("File not found: %s" % path)
		return []
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_result.add_error("File is empty or unreadable: %s" % path)
		return []
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		_result.add_error(
			"Invalid JSON in %s (line %d): %s" % [path, json.get_error_line(), json.get_error_message()]
		)
		return []
	var data: Variant = json.data
	if typeof(data) == TYPE_ARRAY:
		return data
	if typeof(data) == TYPE_DICTIONARY:
		return [data]
	_result.add_error("Top-level JSON in %s must be an object or array" % path)
	return []


# --- Field helpers ---
func _require(d: Dictionary, key: String, source: String, label: String) -> bool:
	if not d.has(key) or d[key] == null:
		_result.add_error("%s in %s is missing required field '%s'" % [label, source, key])
		return false
	return true


func _sn(value: Variant, fallback: StringName = &"") -> StringName:
	if value == null:
		return fallback
	return StringName(str(value))


func _int(value: Variant, fallback: int) -> int:
	if value == null:
		return fallback
	return int(value)


func _str(value: Variant, fallback: String = "") -> String:
	if value == null:
		return fallback
	return str(value)


func _bool(value: Variant, fallback: bool) -> bool:
	if value == null:
		return fallback
	return bool(value)


func _sn_array(value: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if typeof(value) == TYPE_ARRAY:
		for v in value:
			out.append(StringName(str(v)))
	return out


func _vector2i(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO


# --- Per-entity parsers ---
func _parse_target(value: Variant) -> TargetSpec:
	var t := TargetSpec.new()
	if typeof(value) != TYPE_DICTIONARY:
		return t
	var d: Dictionary = value
	t.target_type = _sn(d.get("target_type"), &"enemy")
	return t


# effects are validated for required `type` here; unknown-type validation also
# happens here so the source path can be reported precisely.
func _parse_effects(value: Variant, source: String, label: String) -> Array[Effect]:
	var out: Array[Effect] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for raw in value:
		if typeof(raw) != TYPE_DICTIONARY:
			_result.add_error("%s in %s has a non-object effect" % [label, source])
			continue
		var d: Dictionary = raw
		var e := Effect.new()
		if not _require(d, "type", source, "%s effect" % label):
			continue
		e.type = _sn(d.get("type"))
		if not EFFECT_TYPES.has(e.type):
			_result.add_error(
				"%s in %s uses unknown effect.type '%s'" % [label, source, e.type]
			)
			# Keep the effect so reference validation can still run; the load
			# is already marked failed.
		e.amount = _int(d.get("amount"), 0)
		e.status = _sn(d.get("status"), &"")
		e.stacks = _int(d.get("stacks"), 0)
		# Positionless (ADR-0013): per-effect target_override was removed; every
		# effect applies to its card/intent's resolved target set.
		if d.has("params") and typeof(d["params"]) == TYPE_DICTIONARY:
			e.params = d["params"]
		out.append(e)
	return out


func _parse_status(d: Dictionary, source: String) -> Dictionary:
	var ok := true
	ok = _require(d, "id", source, "status") and ok
	ok = _require(d, "display_name", source, "status") and ok
	if not ok:
		return {}
	var s := StatusData.new()
	s.id = _sn(d.get("id"))
	s.display_name = _str(d.get("display_name"))
	s.stacking = _sn(d.get("stacking"), &"intensity")
	s.decays_each_turn = _bool(d.get("decays_each_turn"), true)
	return {"id": s.id, "value": s}


func _parse_race(d: Dictionary, source: String) -> Dictionary:
	var ok := true
	ok = _require(d, "id", source, "race") and ok
	ok = _require(d, "display_name", source, "race") and ok
	if not ok:
		return {}
	var r := RaceData.new()
	r.id = _sn(d.get("id"))
	r.display_name = _str(d.get("display_name"))
	r.str_mod = _int(d.get("str_mod"), 0)
	r.dex_mod = _int(d.get("dex_mod"), 0)
	r.con_mod = _int(d.get("con_mod"), 0)
	r.int_mod = _int(d.get("int_mod"), 0)
	r.custom_card = _sn(d.get("custom_card"), &"")
	return {"id": r.id, "value": r}


func _parse_card(d: Dictionary, source: String) -> Dictionary:
	var ok := true
	ok = _require(d, "id", source, "card") and ok
	ok = _require(d, "display_name", source, "card") and ok
	ok = _require(d, "target", source, "card") and ok
	ok = _require(d, "effects", source, "card") and ok
	if not ok:
		return {}
	var c := CardData.new()
	c.id = _sn(d.get("id"))
	c.display_name = _str(d.get("display_name"))
	c.description = _str(d.get("description"), "")
	c.character_tag = _sn(d.get("character_tag"), &"neutral")
	c.energy_cost = _int(d.get("energy_cost"), 1)
	c.keywords = _sn_array(d.get("keywords"))
	c.innate = _bool(d.get("innate"), false)
	c.rarity = _sn(d.get("rarity"), &"common")
	c.target = _parse_target(d.get("target"))
	c.effects = _parse_effects(d.get("effects"), source, "card '%s'" % c.id)
	c.upgrade_of = _sn(d.get("upgrade_of"), &"")
	return {"id": c.id, "value": c}


func _parse_character(d: Dictionary, source: String) -> Dictionary:
	var ok := true
	ok = _require(d, "id", source, "character") and ok
	ok = _require(d, "display_name", source, "character") and ok
	ok = _require(d, "constitution", source, "character") and ok
	ok = _require(d, "attack_stat", source, "character") and ok
	if not ok:
		return {}
	var ch := CharacterData.new()
	ch.id = _sn(d.get("id"))
	ch.display_name = _str(d.get("display_name"))
	ch.speed = _int(d.get("speed"), 10)
	# Stats (ADR-0014). max_hp is derived from CON in _derive_character_hp() once
	# battle_config (hp_per_con) has loaded.
	ch.strength = _int(d.get("strength"), 0)
	ch.dexterity = _int(d.get("dexterity"), 0)
	ch.constitution = _int(d.get("constitution"), 0)
	ch.intelligence = _int(d.get("intelligence"), 0)
	ch.attack_stat = _sn(d.get("attack_stat"), &"str")
	if d.has("innate_actions"):
		ch.innate_actions = _sn_array(d.get("innate_actions"))
	if d.has("starting_deck"):
		ch.starting_deck = _sn_array(d.get("starting_deck"))
	ch.tags = _sn_array(d.get("tags"))
	return {"id": ch.id, "value": ch}


func _parse_enemy(d: Dictionary, source: String) -> Dictionary:
	var ok := true
	ok = _require(d, "id", source, "enemy") and ok
	ok = _require(d, "display_name", source, "enemy") and ok
	ok = _require(d, "max_hp", source, "enemy") and ok
	ok = _require(d, "intents", source, "enemy") and ok
	if not ok:
		return {}
	var en := EnemyData.new()
	en.id = _sn(d.get("id"))
	en.display_name = _str(d.get("display_name"))
	en.max_hp = _int(d.get("max_hp"), 20)
	en.speed = _int(d.get("speed"), 8)
	en.intent_pattern = _sn(d.get("intent_pattern"), &"random_weighted")
	en.intents = _parse_intents(d.get("intents"), source, en.id)
	return {"id": en.id, "value": en}


func _parse_intents(value: Variant, source: String, enemy_id: StringName) -> Array[IntentData]:
	var out: Array[IntentData] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for raw in value:
		if typeof(raw) != TYPE_DICTIONARY:
			_result.add_error("enemy '%s' in %s has a non-object intent" % [enemy_id, source])
			continue
		var d: Dictionary = raw
		var label := "enemy '%s' intent" % enemy_id
		var ok := true
		ok = _require(d, "id", source, label) and ok
		ok = _require(d, "target", source, label) and ok
		ok = _require(d, "effects", source, label) and ok
		if not ok:
			continue
		var it := IntentData.new()
		it.id = _sn(d.get("id"))
		it.telegraph = _sn(d.get("telegraph"), &"attack")
		it.target = _parse_target(d.get("target"))
		it.effects = _parse_effects(d.get("effects"), source, "%s '%s'" % [label, it.id])
		it.weight = _int(d.get("weight"), 1)
		out.append(it)
	return out


func _parse_encounter(d: Dictionary, source: String) -> Dictionary:
	var ok := true
	ok = _require(d, "id", source, "encounter") and ok
	ok = _require(d, "display_name", source, "encounter") and ok
	ok = _require(d, "enemies", source, "encounter") and ok
	if not ok:
		return {}
	var enc := EncounterData.new()
	enc.id = _sn(d.get("id"))
	enc.display_name = _str(d.get("display_name"))
	enc.win_condition = _sn(d.get("win_condition"), &"defeat_all")
	enc.win_param = _int(d.get("win_param"), 0)
	enc.rewards = _sn_array(d.get("rewards"))
	# Positionless (ADR-0013): an encounter is a flat roster of enemy ids.
	enc.enemies = _sn_array(d.get("enemies"))

	return {"id": enc.id, "value": enc}


func _load_battle_config(path: String) -> void:
	if not FileAccess.file_exists(path):
		# Fall back to schema defaults rather than failing; the file is optional
		# at the loader level. Content task P1·11 supplies the real file.
		battle_config = BattleConfig.new()
		return
	var entries := _read_json_array(path)
	if entries.is_empty():
		battle_config = BattleConfig.new()
		return
	var d: Variant = entries[0]
	if typeof(d) != TYPE_DICTIONARY:
		_result.add_error("battle_config.json top-level must be an object: %s" % path)
		battle_config = BattleConfig.new()
		return
	var bc := BattleConfig.new()
	bc.energy_per_turn = _int(d.get("energy_per_turn"), 3)
	bc.draw_per_turn = _int(d.get("draw_per_turn"), 5)
	bc.max_hand = _int(d.get("max_hand"), 10)
	bc.reshuffle_discard = _bool(d.get("reshuffle_discard"), true)
	bc.hp_per_con = _int(d.get("hp_per_con"), 2)
	bc.revive_hp = _int(d.get("revive_hp"), 8)
	bc.post_combat_heal = _int(d.get("post_combat_heal"), 5)
	bc.stat_points_per_level = _int(d.get("stat_points_per_level"), 3)
	bc.xp_per_combat = _int(d.get("xp_per_combat"), 10)
	bc.xp_curve_base = _int(d.get("xp_curve_base"), 30)
	bc.xp_curve_step = _int(d.get("xp_curve_step"), 20)
	battle_config = bc


## Derive every character's max_hp from CON (ADR-0014: CON -> max HP) using the
## loaded BattleConfig.hp_per_con. Runs after both characters and battle_config
## have loaded so the formula's knob comes from data.
func _derive_character_hp() -> void:
	var per_con: int = battle_config.hp_per_con if battle_config != null else 2
	for id in characters:
		var ch: CharacterData = characters[id]
		ch.max_hp = ch.constitution * per_con


# --- Reference validation (data-schemas.md §8 relationships) ---
func _validate_references() -> void:
	# card.character_tag -> a character id or "neutral"
	# effect.status -> a status id (for apply_status effects)
	for id in cards:
		var card: CardData = cards[id]
		if card.character_tag != NEUTRAL_TAG and not characters.has(card.character_tag):
			_result.add_error(
				"card '%s' references unknown character_tag '%s'" % [card.id, card.character_tag]
			)
		_validate_effect_statuses(card.effects, "card '%s'" % card.id)
		# ADR-0017: `return` is banned on a card that deals stat-scaling damage
		# (an owned, i.e. non-neutral, damage card). It would let a cheap nuke
		# skip the deck-cooldown cycle entirely. `return` stays legal on neutral
		# (flat) cards and non-damage utility.
		if card.keywords.has(&"return") and card.character_tag != NEUTRAL_TAG:
			for e in card.effects:
				if e is Effect and e.type == &"damage":
					_result.add_error(
						"card '%s' has `return` on stat-scaling damage (banned, ADR-0017)" % card.id
					)
					break

	# character.starting_deck / innate_actions -> card ids
	for id in characters:
		var ch: CharacterData = characters[id]
		for card_id in ch.starting_deck:
			if not cards.has(card_id):
				_result.add_error(
					"character '%s' starting_deck references unknown card '%s'" % [ch.id, card_id]
				)
		for card_id in ch.innate_actions:
			if not cards.has(card_id):
				_result.add_error(
					"character '%s' innate_actions references unknown card '%s'" % [ch.id, card_id]
				)

	# enemy intents' effects -> status ids
	for id in enemies:
		var en: EnemyData = enemies[id]
		for it in en.intents:
			_validate_effect_statuses(it.effects, "enemy '%s' intent '%s'" % [en.id, it.id])

	# encounter.enemies -> enemy ids
	for id in encounters:
		var enc: EncounterData = encounters[id]
		for enemy_id in enc.enemies:
			if not enemies.has(enemy_id):
				_result.add_error(
					"encounter '%s' spawns unknown enemy '%s'" % [enc.id, enemy_id]
				)

	# race.custom_card -> a card id
	for id in races:
		var race: RaceData = races[id]
		if race.custom_card != &"" and not cards.has(race.custom_card):
			_result.add_error(
				"race '%s' references unknown custom_card '%s'" % [race.id, race.custom_card]
			)


func _validate_effect_statuses(effects: Array[Effect], owner_label: String) -> void:
	for e in effects:
		if e.type == &"apply_status":
			if e.status == &"":
				_result.add_error(
					"%s has an apply_status effect with no 'status' id" % owner_label
				)
			elif not statuses.has(e.status):
				_result.add_error(
					"%s references unknown status '%s'" % [owner_label, e.status]
				)
