class_name RunState
extends Resource
## The persistent state of an in-progress run (run-structure.md §2).
##
## Serializable to user:// for mid-run save/resume: a run is resumable from its
## current `position`. Persistence builds a plain-Dictionary (JSON-safe)
## representation — StringName -> String — then reconstructs the typed Resources
## (including the MapGraph of MapNodes) on load. Missing or malformed save files
## degrade gracefully: load_from() returns null and save_to() returns false
## rather than crashing.

## Default directory and file for the active run save.
const SAVE_DIR: String = "user://saves"
const DEFAULT_SAVE_PATH: String = "user://saves/run.json"

## Run RNG seed (map gen, draws, rewards derive from it).
@export var seed: int = 0
## Character ids in the party (2–3, ADR-0004).
@export var party: Array[StringName] = []
## character_id -> current_hp, carried across nodes (ADR-0011).
@export var party_hp: Dictionary = {}
## Character ids currently downed (revive next encounter at low HP).
@export var downed: Array[StringName] = []
## Card ids in the run deck (starting decks + drafted cards).
@export var run_deck: Array[StringName] = []
## Relic ids acquired this run (§7).
@export var relics: Array[StringName] = []
## The generated map (§3).
@export var map: MapGraph
## Current node id.
@export var position: StringName = &""
## Resolved node ids.
@export var cleared: Array[StringName] = []

# --- Leveling (ADR-0015, P3·05) ---------------------------------------------
## character_id -> current level (1-based). Absent key == level 1.
@export var party_level: Dictionary = {}
## character_id -> XP accumulated toward the NEXT level (resets each level-up).
@export var party_xp: Dictionary = {}
## character_id -> unspent stat points available to allocate.
@export var unspent_points: Dictionary = {}
## character_id -> {"str","dex","con","int"} points the player has allocated.
## These apply on top of class + race each fight (ADR-0015).
@export var allocated_stats: Dictionary = {}


# --- Persistence ---

## Serialize this run to `path` (default DEFAULT_SAVE_PATH) as JSON under
## user://. Creates the save directory if needed. Returns true on success,
## false if the file could not be written (never crashes).
func save_to(path: String = DEFAULT_SAVE_PATH) -> bool:
	var dir_path: String = path.get_base_dir()
	if dir_path != "":
		DirAccess.make_dir_recursive_absolute(dir_path)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var text: String = JSON.stringify(to_dict(), "\t")
	file.store_string(text)
	file.close()
	return true


## Load a run previously written by save_to(). Returns a fully reconstructed
## RunState, or null if the file is missing or malformed (never crashes).
static func load_from(path: String = DEFAULT_SAVE_PATH) -> RunState:
	if not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text: String = file.get_as_text()
	file.close()
	# Use the instance JSON API: parse() returns an error code without printing
	# an engine error on malformed input (JSON.parse_string would push one,
	# which a strict test run flags as an unexpected error).
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		return null
	var data: Dictionary = parsed
	return from_dict(data)


# --- Dictionary <-> Resource conversion ---

## Plain-Dictionary (JSON-safe) form of this run. StringNames become Strings;
## the map is delegated to MapGraph.to_dict().
func to_dict() -> Dictionary:
	var hp_out: Dictionary = {}
	for key: Variant in party_hp.keys():
		var hp_v: Variant = party_hp[key]
		hp_out[String(key)] = int(hp_v)
	var map_out: Dictionary = {}
	if map != null:
		map_out = map.to_dict()
	return {
		"seed": seed,
		"party": _sn_array_to_strings(party),
		"party_hp": hp_out,
		"downed": _sn_array_to_strings(downed),
		"run_deck": _sn_array_to_strings(run_deck),
		"relics": _sn_array_to_strings(relics),
		"map": map_out,
		"position": String(position),
		"cleared": _sn_array_to_strings(cleared),
		"party_level": _int_dict_to_strings(party_level),
		"party_xp": _int_dict_to_strings(party_xp),
		"unspent_points": _int_dict_to_strings(unspent_points),
		"allocated_stats": _alloc_dict_to_strings(allocated_stats),
	}


## Reconstruct a typed RunState from its plain-Dictionary form. Tolerant of
## missing keys (each falls back to its default).
static func from_dict(d: Dictionary) -> RunState:
	var state := RunState.new()
	var seed_v: Variant = d.get("seed", 0)
	state.seed = int(seed_v)
	state.party = _strings_to_sn_array(d.get("party", []))
	state.downed = _strings_to_sn_array(d.get("downed", []))
	state.run_deck = _strings_to_sn_array(d.get("run_deck", []))
	state.relics = _strings_to_sn_array(d.get("relics", []))
	state.cleared = _strings_to_sn_array(d.get("cleared", []))
	state.position = StringName(String(d.get("position", "")))
	var hp_in: Dictionary = {}
	var hp_v: Variant = d.get("party_hp", {})
	if hp_v is Dictionary:
		var hp_dict: Dictionary = hp_v
		for key: Variant in hp_dict.keys():
			var val_v: Variant = hp_dict[key]
			hp_in[StringName(String(key))] = int(val_v)
	state.party_hp = hp_in
	var map_v: Variant = d.get("map", {})
	if map_v is Dictionary:
		var map_dict: Dictionary = map_v
		if not map_dict.is_empty():
			state.map = MapGraph.from_dict(map_dict)
	state.party_level = _strings_to_int_dict(d.get("party_level", {}))
	state.party_xp = _strings_to_int_dict(d.get("party_xp", {}))
	state.unspent_points = _strings_to_int_dict(d.get("unspent_points", {}))
	state.allocated_stats = _strings_to_alloc_dict(d.get("allocated_stats", {}))
	return state


# --- Helpers ---

## Array[StringName] -> Array of plain Strings (for JSON).
static func _sn_array_to_strings(arr: Array) -> Array:
	var out: Array = []
	for item: Variant in arr:
		out.append(String(item))
	return out


## A JSON Array (of Strings) -> typed Array[StringName].
static func _strings_to_sn_array(v: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if v is Array:
		var arr: Array = v
		for item: Variant in arr:
			out.append(StringName(String(item)))
	return out


## {StringName -> int} -> {String -> int} (for JSON).
func _int_dict_to_strings(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in src.keys():
		out[String(key)] = int(src[key])
	return out


## A JSON object of {String -> number} -> {StringName -> int}.
static func _strings_to_int_dict(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	if v is Dictionary:
		var d: Dictionary = v
		for key: Variant in d.keys():
			out[StringName(String(key))] = int(d[key])
	return out


## {StringName -> {stat -> int}} -> {String -> {String -> int}} (for JSON).
func _alloc_dict_to_strings(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in src.keys():
		var inner_v: Variant = src[key]
		var inner_out: Dictionary = {}
		if inner_v is Dictionary:
			var inner: Dictionary = inner_v
			for stat: Variant in inner.keys():
				inner_out[String(stat)] = int(inner[stat])
		out[String(key)] = inner_out
	return out


## A JSON object of {String -> {String -> number}} -> {StringName -> {StringName -> int}}.
static func _strings_to_alloc_dict(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	if v is Dictionary:
		var d: Dictionary = v
		for key: Variant in d.keys():
			var inner_v: Variant = d[key]
			var inner_out: Dictionary = {}
			if inner_v is Dictionary:
				var inner: Dictionary = inner_v
				for stat: Variant in inner.keys():
					inner_out[StringName(String(stat))] = int(inner[stat])
			out[StringName(String(key))] = inner_out
	return out
