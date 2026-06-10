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
	# ADR-0028 (DCC adaptation) extensions:
	&"self_damage",            # caster-side damage tax (bombs): once per card, block absorbs, never stat-amplified
	&"self_block",             # caster-side block rider: once per card, DEX-scaled like any block grant
	&"charm_damage",           # attack that applies Charm equal to UNBLOCKED damage dealt
	&"consume_status_damage",  # deal damage equal to the target's stacks of `status`, then remove them (Coup de Grace)
	&"add_card",               # add the card `params.card_id` to the caster's hand (token generation)
	# ADR-0029 (injected card layer) extensions:
	&"inflict_curse",          # shuffle curse `params.card_id` into the target PLAYER's discard; persists to the run after combat
	&"cleanse",                # remove all stacks of each status in `params.statuses` from the target (antidote)
	&"gain_gold",              # bank `amount` run gold (credited by finish_combat; lucky_coin)
	# M3 per-tier enemy mechanics (ADR-0019 deferred tier modifiers):
	&"pierce_damage",          # damage that IGNORES block (anti-turtle intents; authored raw, no stat fold)
	&"revive_allies",          # raise the caster's dead allies to `amount` HP, once per source per battle
]

## ADR-0029: the card-kind discriminator values (`card_kind` on CardData).
const CARD_KINDS: Array[StringName] = [&"skill", &"curse", &"consumable"]

## M3 event-choice condition vocabulary (docs/systems/events.md). Evaluated by
## EventResolver.is_choice_available; unknown keys are a load error.
const EVENT_CONDITION_KEYS: Array[String] = ["race", "class", "min_gold", "has_curse", "has_relic"]

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
var events: Dictionary = {}
var relics: Dictionary = {}
var promotions: Dictionary = {}
var boons: Dictionary = {}
## node_type (StringName) -> Array[StringName] of encounter ids (run-structure.md
## §9 / P2·09): which encounters feed which node types when a MapNode has no
## explicit payload. Loaded from data/encounter_pool.json.
var encounter_pool: Dictionary = {}
## class_id -> {node_id -> node Dictionary} (ADR-0022 progression trees,
## data/progression/*.json). Raw dictionaries: {id, display_name, parent, act,
## stat_bonus{...}; capstones += ult_card_id, ascension_stat_mult}.
var progression_trees: Dictionary = {}
var battle_config: BattleConfig
## The 18-act dungeon curve (ADR-0019), loaded from data/acts/act_progression.json.
## Null when no acts file is present (the loader treats it as optional content, so
## fixture sets without a dungeon still load); §5 invariants are validated when it
## IS present.
var act_progression: ActProgression

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


func get_event(id: StringName) -> EventData:
	return events.get(id, null)


func get_relic(id: StringName) -> RelicData:
	return relics.get(id, null)


func get_promotion(id: StringName) -> PromotionData:
	return promotions.get(id, null)


func get_boon(id: StringName) -> BoonData:
	return boons.get(id, null)


## The promotion branches available to class `class_id` (sorted by id for a stable
## choice order).
func get_promotions_for_class(class_id: StringName) -> Array[PromotionData]:
	var out: Array[PromotionData] = []
	for key: Variant in promotions.keys():
		var p: PromotionData = promotions[key]
		if p != null and p.from_class == class_id:
			out.append(p)
	out.sort_custom(func(a: PromotionData, b: PromotionData) -> bool: return String(a.id) < String(b.id))
	return out


## Encounter ids that feed `node_type` (combat/elite/boss). Empty if none defined.
func get_encounters_for_type(node_type: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var v: Variant = encounter_pool.get(node_type, [])
	if v is Array:
		for item: Variant in v:
			out.append(StringName(String(item)))
	return out


## The upgraded variant of card `base_id` — the card whose `upgrade_of` points at
## it (run-structure.md §5, rest upgrade). Returns null if no upgrade exists. If
## several cards claim the same base (authoring error), returns the first by id
## for determinism; the loader flags duplicates.
func get_upgrade_for(base_id: StringName) -> CardData:
	var best: CardData = null
	for key: Variant in cards.keys():
		var card: CardData = cards[key]
		if card != null and card.upgrade_of == base_id:
			if best == null or String(card.id) < String(best.id):
				best = card
	return best


func get_battle_config() -> BattleConfig:
	return battle_config


## The loaded 18-act dungeon curve, or null if no acts file was present.
func get_act_progression() -> ActProgression:
	return act_progression


## The ActConfig for act `n` (1..18), or null if absent / no progression loaded.
func get_act(n: int) -> ActConfig:
	if act_progression == null:
		return null
	return act_progression.act_at(n)


## Load every content category from a /data-style directory. Returns a LoadResult.
func load_from_dir(data_dir: String) -> LoadResult:
	_result = LoadResult.new()
	statuses.clear()
	cards.clear()
	characters.clear()
	enemies.clear()
	encounters.clear()
	races.clear()
	events.clear()
	relics.clear()
	promotions.clear()
	boons.clear()
	encounter_pool.clear()
	progression_trees.clear()
	battle_config = null
	act_progression = null

	# Order matters for reference validation: load referenced entities before
	# the ones that reference them where practical, but we validate references
	# in a dedicated pass after all parsing so order is not load-bearing.
	_load_category(data_dir.path_join("status"), _parse_status, statuses, "status")
	_load_category(data_dir.path_join("characters"), _parse_character, characters, "character")
	_load_category(data_dir.path_join("enemies"), _parse_enemy, enemies, "enemy")
	_load_category(data_dir.path_join("cards"), _parse_card, cards, "card")
	_load_category(data_dir.path_join("encounters"), _parse_encounter, encounters, "encounter")
	_load_category(data_dir.path_join("races"), _parse_race, races, "race")
	_load_category(data_dir.path_join("events"), _parse_event, events, "event")
	_load_category(data_dir.path_join("relics"), _parse_relic, relics, "relic")
	_load_category(data_dir.path_join("promotions"), _parse_promotion, promotions, "promotion")
	_load_category(data_dir.path_join("boons"), _parse_boon, boons, "boon")
	_load_progression_trees(data_dir.path_join("progression"))
	_load_encounter_pool(data_dir.path_join("encounter_pool.json"))
	_load_battle_config(data_dir.path_join("battle_config.json"))
	_load_act_progression(data_dir.path_join("acts").path_join("act_progression.json"))
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


func _float(value: Variant, fallback: float) -> float:
	if value == null:
		return fallback
	return float(value)


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
		# ADR-0020 scaling ladder: optional float, 1.0 (absent) == flat behavior.
		e.stat_mult = _float(d.get("stat_mult"), 1.0)
		if e.stat_mult < 0.0:
			_result.add_error(
				"%s in %s has a negative stat_mult (%s)" % [label, source, e.stat_mult]
			)
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
	# ADR-0021 pt1: races are base stat templates. Plain stat keys are canonical;
	# the legacy *_mod keys are still accepted (loader fixtures, older content).
	r.str_mod = _int(d.get("strength"), _int(d.get("str_mod"), 0))
	r.dex_mod = _int(d.get("dexterity"), _int(d.get("dex_mod"), 0))
	r.con_mod = _int(d.get("constitution"), _int(d.get("con_mod"), 0))
	r.int_mod = _int(d.get("intelligence"), _int(d.get("int_mod"), 0))
	r.custom_card = _sn(d.get("custom_card"), &"")
	if d.has("starting_kit"):
		r.starting_kit = _sn_array(d.get("starting_kit"))
	return {"id": r.id, "value": r}


# Event nodes (run-structure.md §6). An event has display text + 2..3 choices,
# each choice a label + a list of typed outcome deltas. Outcome `kind` is
# validated against EventResolver.KINDS here; card/relic id references are checked
# in _validate_references so the source path can be reported precisely.
func _parse_event(d: Dictionary, source: String) -> Dictionary:
	var ok := true
	ok = _require(d, "id", source, "event") and ok
	ok = _require(d, "choices", source, "event") and ok
	if not ok:
		return {}
	var ev := EventData.new()
	ev.id = _sn(d.get("id"))
	ev.title = _str(d.get("title"))
	ev.body = _str(d.get("body"))
	ev.choices = _parse_event_choices(d.get("choices"), source, ev.id)
	# M3 tier banding: optional `tiers` array of ints in 1..6 (ADR-0019's six
	# dungeon tiers). Empty/absent = the event is global.
	var tiers_v: Variant = d.get("tiers")
	if tiers_v != null:
		if typeof(tiers_v) != TYPE_ARRAY:
			_result.add_error("event '%s' in %s: tiers must be an array" % [ev.id, source])
		else:
			for t_v: Variant in (tiers_v as Array):
				var t: int = _int(t_v, 0)
				if t < 1 or t > 6:
					_result.add_error(
						"event '%s' in %s has out-of-range tier %s (must be 1..6)" % [ev.id, source, t_v]
					)
					continue
				ev.tiers.append(t)
	return {"id": ev.id, "value": ev}


func _parse_event_choices(value: Variant, source: String, event_id: StringName) -> Array[EventChoice]:
	var out: Array[EventChoice] = []
	if typeof(value) != TYPE_ARRAY:
		_result.add_error("event '%s' in %s: choices must be an array" % [event_id, source])
		return out
	for raw in value:
		if typeof(raw) != TYPE_DICTIONARY:
			_result.add_error("event '%s' in %s has a non-object choice" % [event_id, source])
			continue
		var cd: Dictionary = raw
		var choice := EventChoice.new()
		choice.label = _str(cd.get("label"))
		choice.outcomes = _parse_event_outcomes(cd.get("outcomes"), source, event_id)
		# M3: optional availability gate. Keys are validated against the known
		# vocabulary here; race/class id references in _validate_references.
		var cond_v: Variant = cd.get("condition")
		if cond_v != null:
			if typeof(cond_v) != TYPE_DICTIONARY:
				_result.add_error("event '%s' in %s: condition must be an object" % [event_id, source])
			else:
				choice.condition = (cond_v as Dictionary).duplicate()
				for key: Variant in choice.condition.keys():
					if not EVENT_CONDITION_KEYS.has(String(key)):
						_result.add_error(
							"event '%s' in %s uses unknown condition key '%s'" % [event_id, source, key]
						)
		# M3: optional weighted gamble table (applied INSTEAD of outcomes).
		var rnd_v: Variant = cd.get("random_outcomes")
		if rnd_v != null:
			if typeof(rnd_v) != TYPE_ARRAY:
				_result.add_error("event '%s' in %s: random_outcomes must be an array" % [event_id, source])
			else:
				for group_v: Variant in (rnd_v as Array):
					if typeof(group_v) != TYPE_DICTIONARY:
						_result.add_error(
							"event '%s' in %s has a non-object random_outcomes group" % [event_id, source]
						)
						continue
					var gd: Dictionary = group_v
					var weight: int = _int(gd.get("weight"), 1)
					if weight < 1:
						_result.add_error(
							"event '%s' in %s has a random_outcomes group with weight < 1" % [event_id, source]
						)
						weight = 1
					choice.random_weights.append(weight)
					choice.random_groups.append(_parse_event_outcomes(gd.get("outcomes"), source, event_id))
		out.append(choice)
	return out


func _parse_event_outcomes(value: Variant, source: String, event_id: StringName) -> Array[EventOutcome]:
	var out: Array[EventOutcome] = []
	if value == null:
		return out
	if typeof(value) != TYPE_ARRAY:
		_result.add_error("event '%s' in %s: outcomes must be an array" % [event_id, source])
		return out
	for raw in value:
		if typeof(raw) != TYPE_DICTIONARY:
			_result.add_error("event '%s' in %s has a non-object outcome" % [event_id, source])
			continue
		var od: Dictionary = raw
		var outcome := EventOutcome.new()
		if not _require(od, "kind", source, "event '%s' outcome" % event_id):
			continue
		outcome.kind = _sn(od.get("kind"))
		if not EventOutcome.KINDS.has(outcome.kind):
			_result.add_error(
				"event '%s' in %s uses unknown outcome.kind '%s'" % [event_id, source, outcome.kind]
			)
		outcome.amount = _int(od.get("amount"), 0)
		outcome.id = _sn(od.get("id"), &"")
		out.append(outcome)
	return out


# Relic (run-structure.md §7 / P2·12): a trigger+effect+amount modifier. Unknown
# trigger/effect values are flagged here so the bad file is named precisely.
func _parse_relic(d: Dictionary, source: String) -> Dictionary:
	var ok := true
	ok = _require(d, "id", source, "relic") and ok
	ok = _require(d, "display_name", source, "relic") and ok
	if not ok:
		return {}
	var r := RelicData.new()
	r.id = _sn(d.get("id"))
	r.display_name = _str(d.get("display_name"))
	r.description = _str(d.get("description"), "")
	r.rarity = _sn(d.get("rarity"), &"common")
	r.trigger = _sn(d.get("trigger"), &"combat_start")
	r.effect = _sn(d.get("effect"), &"gain_block")
	r.amount = _int(d.get("amount"), 0)
	if not RelicData.TRIGGERS.has(r.trigger):
		_result.add_error("relic '%s' in %s uses unknown trigger '%s'" % [r.id, source, r.trigger])
	if not RelicData.EFFECTS.has(r.effect):
		_result.add_error("relic '%s' in %s uses unknown effect '%s'" % [r.id, source, r.effect])
	return {"id": r.id, "value": r}


# Promotion branch (P3·06). Stat mods + a signature card; from_class/signature_card
# references are checked in _validate_references.
func _parse_promotion(d: Dictionary, source: String) -> Dictionary:
	var ok := true
	ok = _require(d, "id", source, "promotion") and ok
	ok = _require(d, "display_name", source, "promotion") and ok
	ok = _require(d, "from_class", source, "promotion") and ok
	if not ok:
		return {}
	var p := PromotionData.new()
	p.id = _sn(d.get("id"))
	p.display_name = _str(d.get("display_name"))
	p.from_class = _sn(d.get("from_class"))
	p.str_mod = _int(d.get("str_mod"), 0)
	p.dex_mod = _int(d.get("dex_mod"), 0)
	p.con_mod = _int(d.get("con_mod"), 0)
	p.int_mod = _int(d.get("int_mod"), 0)
	p.signature_card = _sn(d.get("signature_card"), &"")
	return {"id": p.id, "value": p}


# Cross-run boon (P3·08). relic/card targets are checked in _validate_references.
func _parse_boon(d: Dictionary, source: String) -> Dictionary:
	var ok := true
	ok = _require(d, "id", source, "boon") and ok
	ok = _require(d, "display_name", source, "boon") and ok
	if not ok:
		return {}
	var b := BoonData.new()
	b.id = _sn(d.get("id"))
	b.display_name = _str(d.get("display_name"))
	b.description = _str(d.get("description"), "")
	b.kind = _sn(d.get("kind"), &"relic")
	b.target = _sn(d.get("target"), &"")
	b.amount = _int(d.get("amount"), 0)
	return {"id": b.id, "value": b}


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
	c.signature = _bool(d.get("signature"), false)
	# ADR-0020 crossover gate (M3 pool hygiene): earliest draftable act.
	c.min_act = _int(d.get("min_act"), 0)
	if c.min_act < 0:
		_result.add_error(
			"card '%s' in %s has a negative min_act (%d)" % [c.id, source, c.min_act]
		)
	# ADR-0029: injected-layer discriminator + curse when-drawn downside.
	c.card_kind = _sn(d.get("card_kind"), &"skill")
	if not CARD_KINDS.has(c.card_kind):
		_result.add_error(
			"card '%s' in %s uses unknown card_kind '%s'" % [c.id, source, c.card_kind]
		)
	c.on_draw_damage = _int(d.get("on_draw_damage"), 0)
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
	# Damage ramp (enemy kit redesign): scheduled buff turn or free passive ramp.
	en.ramp_amount = _int(d.get("ramp_amount"), 0)
	en.ramp_every = _int(d.get("ramp_every"), 0)
	en.ramp_passive = _bool(d.get("ramp_passive"), false)
	en.summon_id = _sn(d.get("summon_id"), &"")
	en.summon_every = _int(d.get("summon_every"), 0)
	en.summon_max = _int(d.get("summon_max"), 0)
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


# Encounter pool (run-structure.md §9 / P2·09): a single object mapping node-type
# keys (combat/elite/boss) to arrays of encounter ids. `id`/`display_name` strings
# are metadata and ignored; any key whose value is an array is read as a type list.
# Optional file: a missing pool just leaves the map to rely on node payloads.
func _load_encounter_pool(path: String) -> void:
	encounter_pool = {}
	if not FileAccess.file_exists(path):
		return
	var entries := _read_json_array(path)
	if entries.is_empty():
		return
	var d: Variant = entries[0]
	if typeof(d) != TYPE_DICTIONARY:
		_result.add_error("encounter_pool.json top-level must be an object: %s" % path)
		return
	var dict: Dictionary = d
	for key: Variant in dict.keys():
		var value: Variant = dict[key]
		if typeof(value) != TYPE_ARRAY:
			continue  # id / display_name metadata, etc.
		encounter_pool[StringName(String(key))] = _sn_array(value)


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
	bc.energy_per_character = _int(d.get("energy_per_character"), 2)
	bc.draw_per_turn = _int(d.get("draw_per_turn"), 5)
	bc.skill_slots = _int(d.get("skill_slots"), 10)
	bc.copies_common = _int(d.get("copies_common"), 3)
	bc.copies_uncommon = _int(d.get("copies_uncommon"), 2)
	bc.copies_rare = _int(d.get("copies_rare"), 1)
	bc.derived_deck_floor = _int(d.get("derived_deck_floor"), 20)
	bc.derived_deck_floor_min = _int(d.get("derived_deck_floor_min"), 12)
	bc.gold_per_combat = _int(d.get("gold_per_combat"), 12)
	bc.gold_per_elite = _int(d.get("gold_per_elite"), 25)
	bc.gold_per_boss = _int(d.get("gold_per_boss"), 40)
	bc.shop_price_common = _int(d.get("shop_price_common"), 55)
	bc.shop_price_uncommon = _int(d.get("shop_price_uncommon"), 85)
	bc.shop_price_rare = _int(d.get("shop_price_rare"), 140)
	bc.shop_price_relic = _int(d.get("shop_price_relic"), 120)
	bc.shop_price_heal = _int(d.get("shop_price_heal"), 35)
	bc.shop_price_consumable = _int(d.get("shop_price_consumable"), 40)
	bc.shop_price_curse_removal = _int(d.get("shop_price_curse_removal"), 75)
	bc.shop_act_scale = _float(d.get("shop_act_scale"), 0.15)
	bc.treasure_gold_min = _int(d.get("treasure_gold_min"), 25)
	bc.treasure_gold_max = _int(d.get("treasure_gold_max"), 60)
	bc.relic_weight_common = _int(d.get("relic_weight_common"), 50)
	bc.relic_weight_uncommon = _int(d.get("relic_weight_uncommon"), 35)
	bc.relic_weight_rare = _int(d.get("relic_weight_rare"), 15)
	bc.max_hand = _int(d.get("max_hand"), 10)
	bc.reshuffle_discard = _bool(d.get("reshuffle_discard"), true)
	bc.hp_per_con = _int(d.get("hp_per_con"), 2)
	bc.base_hp = _int(d.get("base_hp"), 4)
	bc.revive_hp = _int(d.get("revive_hp"), 8)
	bc.post_combat_heal = _int(d.get("post_combat_heal"), 5)
	bc.rest_heal = _int(d.get("rest_heal"), 12)
	bc.stat_points_per_level = _int(d.get("stat_points_per_level"), 3)
	bc.auto_stats_per_level = _int(d.get("auto_stats_per_level"), 1)
	bc.xp_per_combat = _int(d.get("xp_per_combat"), 10)
	bc.xp_curve_base = _int(d.get("xp_curve_base"), 30)
	bc.xp_curve_step = _int(d.get("xp_curve_step"), 20)
	bc.promotion_level = _int(d.get("promotion_level"), 20)
	bc.meta_cash_out_acts = _int(d.get("meta_cash_out_acts"), 9)
	bc.enemy_scale_baseline_level = _int(d.get("enemy_scale_baseline_level"), 1)
	bc.enemy_scale_exponent = _float(d.get("enemy_scale_exponent"), 1.0)
	battle_config = bc


## Load the 18-act dungeon curve (ADR-0019). OPTIONAL like the other single-file
## content: a missing acts file leaves act_progression null without error (fixture
## sets and the early prototype have no dungeon). When the file IS present it is
## parsed into typed ActConfig/MapGenConfig resources and its §5 invariants
## (ActProgression.validation_errors) are collected into the LoadResult.
func _load_act_progression(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var entries := _read_json_array(path)
	if entries.is_empty():
		return
	var d: Variant = entries[0]
	if typeof(d) != TYPE_DICTIONARY:
		_result.add_error("act_progression.json top-level must be an object: %s" % path)
		return
	var dict: Dictionary = d
	# Per-tier encounter rosters (ADR-0019 remainder): "tier_pools" maps tier
	# ("1".."6") -> {combat/elite/boss -> [encounter ids]}; each act inherits
	# its tier's pool. Optional — absent pools fall back to encounter_pool.json.
	var tier_pools: Dictionary = {}
	var tp_v: Variant = dict.get("tier_pools", {})
	if tp_v is Dictionary:
		for tier_key: Variant in (tp_v as Dictionary):
			var pool_v: Variant = (tp_v as Dictionary)[tier_key]
			if not (pool_v is Dictionary):
				continue
			var pool: Dictionary = {}
			for node_type: Variant in (pool_v as Dictionary):
				pool[StringName(String(node_type))] = _sn_array((pool_v as Dictionary)[node_type])
			tier_pools[int(String(tier_key))] = pool
	var prog := ActProgression.new()
	var raw_acts: Variant = dict.get("acts")
	if typeof(raw_acts) != TYPE_ARRAY:
		_result.add_error("act_progression.json must have an 'acts' array: %s" % path)
		return
	var list: Array[ActConfig] = []
	for raw in raw_acts:
		if typeof(raw) != TYPE_DICTIONARY:
			_result.add_error("act_progression.json has a non-object act entry: %s" % path)
			continue
		var act_dict: Dictionary = raw
		var cfg: ActConfig = _parse_act_config(act_dict, path)
		# Attach the act's tier roster (ADR-0019 remainder); per-act "encounters"
		# overrides its tier pool when authored.
		var own_pool_v: Variant = act_dict.get("encounters")
		if own_pool_v is Dictionary:
			var own: Dictionary = {}
			for node_type: Variant in (own_pool_v as Dictionary):
				own[StringName(String(node_type))] = _sn_array((own_pool_v as Dictionary)[node_type])
			cfg.encounter_pool = own
		else:
			cfg.encounter_pool = tier_pools.get(cfg.tier, {})
		# Every pooled encounter id must resolve (same rule as encounter_pool.json).
		for node_type: Variant in cfg.encounter_pool:
			for enc_id: StringName in cfg.encounter_pool[node_type]:
				if not encounters.has(enc_id):
					_result.add_error(
						"act %d %s pool references unknown encounter '%s'" % [cfg.act, node_type, enc_id]
					)
		list.append(cfg)
	prog.acts = list
	act_progression = prog
	# §5 invariants: collect every problem so a bad curve fails the load loudly.
	for msg in ActProgression.validation_errors(prog):
		_result.add_error("act_progression: %s (%s)" % [msg, path])


## Parse one act entry into a typed ActConfig (act-progression.md §5). Missing
## numeric fields fall back to 0 so the §5 validation — not the parser — is the
## single place that judges a malformed curve.
func _parse_act_config(d: Dictionary, source: String) -> ActConfig:
	var a := ActConfig.new()
	_require(d, "act", source, "act")
	a.act = _int(d.get("act"), 0)
	a.tier = _int(d.get("tier"), 0)
	a.boss_level = _int(d.get("boss_level"), 0)
	a.trash_level = _int(d.get("trash_level"), 0)
	a.elite_level = _int(d.get("elite_level"), 0)
	a.boss_payload = _sn(d.get("boss_payload"), &"")
	a.map = _parse_map_gen_config(d.get("map"))
	return a


## Parse a map block into a MapGenConfig (run-structure.md §4 + ADR-0019 late-row
## bias). A null/absent block yields a default-constructed config so a partially
## authored act still produces a usable shell; the rest_before_boss guarantee is
## checked by §5 validation, not here.
func _parse_map_gen_config(value: Variant) -> MapGenConfig:
	var m := MapGenConfig.new()
	if typeof(value) != TYPE_DICTIONARY:
		return m
	var d: Dictionary = value
	m.rows = _int(d.get("rows"), m.rows)
	m.width_min = _int(d.get("width_min"), m.width_min)
	m.width_max = _int(d.get("width_max"), m.width_max)
	m.branchiness = _float(d.get("branchiness"), m.branchiness)
	m.late_row_bias = _sn(d.get("late_row_bias"), m.late_row_bias)
	var raw_weights: Variant = d.get("type_weights")
	if typeof(raw_weights) == TYPE_DICTIONARY:
		var weights_src: Dictionary = raw_weights
		var tw: Dictionary = {}
		for key: Variant in weights_src.keys():
			tw[StringName(String(key))] = _int(weights_src[key], 0)
		m.type_weights = tw
	var raw_guarantees: Variant = d.get("guarantees")
	if typeof(raw_guarantees) == TYPE_DICTIONARY:
		var guarantees_src: Dictionary = raw_guarantees
		var g: Dictionary = {}
		for key: Variant in guarantees_src.keys():
			g[StringName(String(key))] = guarantees_src[key]
		m.guarantees = g
	return m


## Load the ADR-0022 progression trees (optional content). Each file is one
## class line: {"id": class_id, "nodes": [...]}; capstone ult_card_id refs are
## validated against the card registry.
func _load_progression_trees(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var entries := _read_json_array(dir_path.path_join(file))
		for raw: Variant in entries:
			if not (raw is Dictionary):
				continue
			var doc: Dictionary = raw
			var line_id := StringName(String(doc.get("id", "")))
			if line_id == &"":
				_result.add_error("progression file %s has no line id" % file)
				continue
			var nodes: Dictionary = {}
			var nodes_v: Variant = doc.get("nodes", [])
			if nodes_v is Array:
				for n_v: Variant in nodes_v:
					if not (n_v is Dictionary):
						continue
					var node: Dictionary = n_v
					var nid := StringName(String(node.get("id", "")))
					if nid == &"":
						continue
					nodes[nid] = node
					var ult := StringName(String(node.get("ult_card_id", "")))
					if ult != &"" and not cards.has(ult):
						_result.add_error("progression node '%s' references unknown ult '%s'" % [nid, ult])
					# M3 signatures: a node pick grants these skills (apply_progression).
					var unlocks_v: Variant = node.get("unlock_cards", [])
					if unlocks_v is Array:
						for u_v: Variant in unlocks_v:
							var uid := StringName(String(u_v))
							if uid == &"" or not cards.has(uid):
								_result.add_error(
									"progression node '%s' unlock_cards references unknown card '%s'" % [nid, uid]
								)
			progression_trees[line_id] = nodes


## Derive every character's max_hp from CON (ADR-0014: CON -> max HP) using the
## loaded BattleConfig.hp_per_con. Runs after both characters and battle_config
## have loaded so the formula's knob comes from data.
func _derive_character_hp() -> void:
	var per_con: int = battle_config.hp_per_con if battle_config != null else 2
	var base: int = battle_config.base_hp if battle_config != null else 4
	for id in characters:
		var ch: CharacterData = characters[id]
		# ADR-0021 pt1: class CON is now a small overlay, so a flat base_hp floor
		# keeps low-CON race lines (Elf CON 2) above one-shot range. Full member
		# HP = base_hp + (class + race + allocated CON) × hp_per_con; the race and
		# allocated parts stack additively downstream (apply_race /
		# apply_stat_allocation / PartyStats), all sharing hp_per_con.
		ch.max_hp = base + ch.constitution * per_con


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
		# upgrade_of (if set) must point at an existing base card (run-structure §5).
		if card.upgrade_of != &"" and not cards.has(card.upgrade_of):
			_result.add_error(
				"card '%s' upgrade_of references unknown card '%s'" % [card.id, card.upgrade_of]
			)
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

	# enemy intents' effects -> status ids; summon_id -> an enemy id
	for id in enemies:
		var en: EnemyData = enemies[id]
		for it in en.intents:
			_validate_effect_statuses(it.effects, "enemy '%s' intent '%s'" % [en.id, it.id])
		if en.summon_id != &"" and not enemies.has(en.summon_id):
			_result.add_error(
				"enemy '%s' summon_id references unknown enemy '%s'" % [en.id, en.summon_id]
			)

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

	# encounter_pool: every listed id must be a defined encounter.
	for node_type: Variant in encounter_pool.keys():
		var ids: Variant = encounter_pool[node_type]
		if ids is Array:
			for enc_id: Variant in ids:
				if not encounters.has(StringName(String(enc_id))):
					_result.add_error(
						"encounter_pool '%s' references unknown encounter '%s'" % [node_type, enc_id]
					)

	# promotions: from_class -> a character id; signature_card -> a card id.
	for id in promotions:
		var promo: PromotionData = promotions[id]
		if not characters.has(promo.from_class):
			_result.add_error(
				"promotion '%s' from_class references unknown character '%s'" % [promo.id, promo.from_class]
			)
		if promo.signature_card != &"" and not cards.has(promo.signature_card):
			_result.add_error(
				"promotion '%s' signature_card references unknown card '%s'" % [promo.id, promo.signature_card]
			)

	# boons: relic/card kinds must reference a real relic/card.
	for id in boons:
		var boon: BoonData = boons[id]
		if boon.kind == &"relic" and not relics.has(boon.target):
			_result.add_error("boon '%s' references unknown relic '%s'" % [boon.id, boon.target])
		elif boon.kind == &"card" and not cards.has(boon.target):
			_result.add_error("boon '%s' references unknown card '%s'" % [boon.id, boon.target])

	# event outcomes: add_card/remove_card -> card ids; add_relic -> relic ids
	# (the relic registry is live since P2·12). ADR-0029: add_curse must name a
	# curse card; add_consumable a consumable; remove_curse may carry an empty id
	# ("remove the first curse found"). M3: gamble groups are validated like
	# plain outcomes; condition race/class ids must exist; every event keeps at
	# least one UNCONDITIONAL choice so no party composition can soft-lock.
	for id in events:
		var ev: EventData = events[id]
		var has_unconditional := false
		for choice in ev.choices:
			if choice.condition.is_empty():
				has_unconditional = true
			if choice.condition.has("race") and not races.has(_sn(choice.condition.get("race"))):
				_result.add_error(
					"event '%s' condition references unknown race '%s'" % [ev.id, choice.condition.get("race")]
				)
			if choice.condition.has("class") and not characters.has(_sn(choice.condition.get("class"))):
				_result.add_error(
					"event '%s' condition references unknown class '%s'" % [ev.id, choice.condition.get("class")]
				)
			if choice.condition.has("has_relic") and not relics.has(_sn(choice.condition.get("has_relic"))):
				_result.add_error(
					"event '%s' condition references unknown relic '%s'" % [ev.id, choice.condition.get("has_relic")]
				)
			var all_outcomes: Array = choice.outcomes.duplicate()
			for group_v: Variant in choice.random_groups:
				all_outcomes.append_array(group_v as Array)
			for outcome_v: Variant in all_outcomes:
				var outcome: EventOutcome = outcome_v
				if outcome.kind == &"add_card" or outcome.kind == &"remove_card":
					if outcome.id == &"" or not cards.has(outcome.id):
						_result.add_error(
							"event '%s' %s references unknown card '%s'" % [ev.id, outcome.kind, outcome.id]
						)
				elif outcome.kind == &"add_relic":
					if outcome.id == &"" or not relics.has(outcome.id):
						_result.add_error(
							"event '%s' add_relic references unknown relic '%s'" % [ev.id, outcome.id]
						)
				elif outcome.kind == &"add_curse" or outcome.kind == &"add_consumable":
					var want: StringName = &"curse" if outcome.kind == &"add_curse" else &"consumable"
					var ref: CardData = cards.get(outcome.id, null)
					if ref == null or ref.card_kind != want:
						_result.add_error(
							"event '%s' %s must reference a %s card (got '%s')" % [ev.id, outcome.kind, want, outcome.id]
						)
				elif outcome.kind == &"remove_curse" and outcome.id != &"":
					var rc: CardData = cards.get(outcome.id, null)
					if rc == null or rc.card_kind != &"curse":
						_result.add_error(
							"event '%s' remove_curse references non-curse card '%s'" % [ev.id, outcome.id]
						)
		if not ev.choices.is_empty() and not has_unconditional:
			_result.add_error(
				"event '%s' has no unconditional choice (every option could be hidden)" % ev.id
			)


func _validate_effect_statuses(effects: Array[Effect], owner_label: String) -> void:
	for e in effects:
		if e.type == &"apply_status" or e.type == &"consume_status_damage":
			if e.status == &"":
				_result.add_error(
					"%s has a %s effect with no 'status' id" % [owner_label, e.type]
				)
			elif not statuses.has(e.status):
				_result.add_error(
					"%s references unknown status '%s'" % [owner_label, e.status]
				)
		# ADR-0028: a token generator must name a real card.
		if e.type == &"add_card":
			var token_id := StringName(String(e.params.get("card_id", "")))
			if token_id == &"":
				_result.add_error(
					"%s has an add_card effect with no params.card_id" % owner_label
				)
			elif not cards.has(token_id):
				_result.add_error(
					"%s add_card references unknown card '%s'" % [owner_label, token_id]
				)
		# ADR-0029: inflict_curse must name a real CURSE card.
		if e.type == &"inflict_curse":
			var curse_id := StringName(String(e.params.get("card_id", "")))
			if curse_id == &"":
				_result.add_error(
					"%s has an inflict_curse effect with no params.card_id" % owner_label
				)
			elif not cards.has(curse_id):
				_result.add_error(
					"%s inflict_curse references unknown card '%s'" % [owner_label, curse_id]
				)
			elif (cards[curse_id] as CardData).card_kind != &"curse":
				_result.add_error(
					"%s inflict_curse references non-curse card '%s'" % [owner_label, curse_id]
				)
		# ADR-0029: cleanse must list known statuses.
		if e.type == &"cleanse":
			var listed: Variant = e.params.get("statuses", [])
			if not (listed is Array) or (listed as Array).is_empty():
				_result.add_error(
					"%s has a cleanse effect with no params.statuses list" % owner_label
				)
			elif listed is Array:
				for s_v: Variant in (listed as Array):
					if not statuses.has(StringName(String(s_v))):
						_result.add_error(
							"%s cleanse references unknown status '%s'" % [owner_label, s_v]
						)
