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
## character_id -> race_id chosen at run start (ADR-0015). Persisted so a resumed
## run reapplies race mods (and so effective max-HP can be derived from RunState
## alone).
@export var party_races: Dictionary = {}
## member_id -> class id chosen at the Act-3 pick (ADR-0021 pt2); &""/absent =
## classless. Legacy class-keyed members record themselves here.
@export var member_classes: Dictionary = {}
## member_id -> Array of chosen tree node ids, in beat order (ADR-0022:
## archetype @6, specialization @9, capstone @12).
@export var member_progression: Dictionary = {}
## member_id -> ascension stat_mult step (ADR-0022 Act-15 Ascension); absent =
## not ascended.
@export var ascended: Dictionary = {}
## Per-member skill state (ADR-0026 — supersedes the shared run_deck). The deck
## is no longer stored state: it is DERIVED per member from the active loadout
## (SkillLoadout.derive_deck) at combat assembly.
## member_id -> Array[StringName] of every skill (card id) acquired this run.
@export var skill_collections: Dictionary = {}
## member_id -> Array[StringName] of the ≤ skill_slots ACTIVE skill ids.
@export var active_loadouts: Dictionary = {}
## Injected card layer (ADR-0029). Curses are PER MEMBER (inflicted by enemy
## intents / event outcomes on a specific member; removal is targeted): each
## curse rides that member's derived deck, COUNTING toward the auto-fill floor
## (junk displaces basics). member_id -> Array[StringName] of curse card ids.
@export var member_curses: Dictionary = {}
## Consumable item cards are a PARTY-LEVEL inventory (ADR-0029): injected ON TOP
## of the floor at deck assembly, consumed from here when played; unplayed ones
## persist to future combats. Duplicates allowed.
@export var consumables: Array[StringName] = []
## Run currency (ADR-0023 slice): earned from won combats, spent at future
## shops. Display name "Gold" in the UI.
@export var currency: int = 0
## Relic ids acquired this run (§7).
@export var relics: Array[StringName] = []
## Fame (ADR-0028): the per-act celebrity counter (0..50). Earned by combat
## triggers (flawless wins, fast wins, elites, Charm executes); cashed out as a
## Sponsor Box relic at the act boss, then reset for the next act.
@export var fame: int = 0
## The generated map (§3).
@export var map: MapGraph
## Current node id.
@export var position: StringName = &""
## Resolved node ids.
@export var cleared: Array[StringName] = []
## Current act, 1-based (ADR-0019 18-act dungeon). The map/position/cleared above
## describe THIS act; RunController.advance_act() regenerates them per act.
@export var act: int = 1

# --- Leveling (ADR-0015, P3·05) ---------------------------------------------
## character_id -> current level (1-based). Absent key == level 1.
@export var party_level: Dictionary = {}
## character_id -> XP accumulated toward the NEXT level (resets each level-up).
@export var party_xp: Dictionary = {}
## character_id -> unspent stat points available to allocate.
@export var unspent_points: Dictionary = {}
## character_id -> {"str","dex","con","int"} points the player has allocated.
## These apply on top of class + race each fight (ADR-0015). Class promotions
## (P3·06) also fold their stat mods in here.
@export var allocated_stats: Dictionary = {}
## character_id -> Array[StringName] of promotion ids taken (P3·06). Drives accrual
## (the Nth promotion needs level >= promotion_level * N).
@export var party_promotions: Dictionary = {}


# --- Injected card layer accessors (ADR-0029) -------------------------------

## `cid`'s curse list as a typed LIVE reference into member_curses (mutations
## stick). Creates (and stores) an empty list for an unseen member, so callers
## never branch on key presence.
func curses_of(cid: StringName) -> Array[StringName]:
	var v: Variant = member_curses.get(cid)
	if v is Array[StringName]:
		return v
	var out: Array[StringName] = []
	if v is Array:
		for item: Variant in v:
			out.append(StringName(String(item)))
	member_curses[cid] = out
	return out


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
		"skill_collections": _sn_arrays_to_strings(skill_collections),
		"active_loadouts": _sn_arrays_to_strings(active_loadouts),
		"member_curses": _sn_arrays_to_strings(member_curses),
		"consumables": _sn_array_to_strings(consumables),
		"currency": currency,
		"relics": _sn_array_to_strings(relics),
		"fame": fame,
		"map": map_out,
		"position": String(position),
		"cleared": _sn_array_to_strings(cleared),
		"act": act,
		"party_races": _sn_dict_to_strings(party_races),
		"member_classes": _sn_dict_to_strings(member_classes),
		"member_progression": _sn_arrays_to_strings(member_progression),
		"ascended": ascended.duplicate(),
		"party_level": _int_dict_to_strings(party_level),
		"party_xp": _int_dict_to_strings(party_xp),
		"unspent_points": _int_dict_to_strings(unspent_points),
		"allocated_stats": _alloc_dict_to_strings(allocated_stats),
		"party_promotions": _sn_arrays_to_strings(party_promotions),
	}


## Reconstruct a typed RunState from its plain-Dictionary form. Tolerant of
## missing keys (each falls back to its default).
static func from_dict(d: Dictionary) -> RunState:
	var state := RunState.new()
	var seed_v: Variant = d.get("seed", 0)
	state.seed = int(seed_v)
	state.party = _strings_to_sn_array(d.get("party", []))
	state.downed = _strings_to_sn_array(d.get("downed", []))
	state.skill_collections = _strings_to_sn_arrays(d.get("skill_collections", {}))
	state.active_loadouts = _strings_to_sn_arrays(d.get("active_loadouts", {}))
	state.member_curses = _strings_to_sn_arrays(d.get("member_curses", {}))
	state.consumables = _strings_to_sn_array(d.get("consumables", []))
	state.currency = maxi(0, int(d.get("currency", 0)))
	state.relics = _strings_to_sn_array(d.get("relics", []))
	state.fame = int(d.get("fame", 0))
	state.cleared = _strings_to_sn_array(d.get("cleared", []))
	state.position = StringName(String(d.get("position", "")))
	state.act = maxi(1, int(d.get("act", 1)))
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
	state.party_races = _strings_to_sn_dict(d.get("party_races", {}))
	state.member_classes = _strings_to_sn_dict(d.get("member_classes", {}))
	state.member_progression = _strings_to_sn_arrays(d.get("member_progression", {}))
	var asc_v: Variant = d.get("ascended", {})
	if asc_v is Dictionary:
		for k: Variant in asc_v:
			state.ascended[StringName(String(k))] = float(asc_v[k])
	state.party_level = _strings_to_int_dict(d.get("party_level", {}))
	state.party_xp = _strings_to_int_dict(d.get("party_xp", {}))
	state.unspent_points = _strings_to_int_dict(d.get("unspent_points", {}))
	state.allocated_stats = _strings_to_alloc_dict(d.get("allocated_stats", {}))
	state.party_promotions = _strings_to_sn_arrays(d.get("party_promotions", {}))
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


## {StringName -> StringName} -> {String -> String} (for JSON).
func _sn_dict_to_strings(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in src.keys():
		out[String(key)] = String(src[key])
	return out


## A JSON object of {String -> String} -> {StringName -> StringName}.
static func _strings_to_sn_dict(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	if v is Dictionary:
		var d: Dictionary = v
		for key: Variant in d.keys():
			out[StringName(String(key))] = StringName(String(d[key]))
	return out


## {StringName -> Array[StringName]} -> {String -> Array[String]} (for JSON).
func _sn_arrays_to_strings(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in src.keys():
		out[String(key)] = _sn_array_to_strings(src[key])
	return out


## A JSON object of {String -> Array[String]} -> {StringName -> Array[StringName]}.
static func _strings_to_sn_arrays(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	if v is Dictionary:
		var d: Dictionary = v
		for key: Variant in d.keys():
			out[StringName(String(key))] = _strings_to_sn_array(d[key])
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
