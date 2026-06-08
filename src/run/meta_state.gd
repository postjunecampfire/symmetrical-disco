class_name MetaState
extends Resource
## CROSS-RUN persistent progression (P3·08, ADR-0018), distinct from the per-run
## RunState. Tracks total acts cleared across all runs and the exit-package boons
## the player has banked; those boons apply at the start of every future run.
##
## Saved to its own slot under user:// so it outlives any single run (which is
## cleared on win/death). Degrades gracefully: a missing/bad file -> a fresh meta.

const SAVE_DIR: String = "user://saves"
const DEFAULT_SAVE_PATH: String = "user://saves/meta.json"

## Total acts cleared across all runs (drives cash-out eligibility).
@export var acts_cleared: int = 0
## Banked boon ids (BoonData), applied at every future run start.
@export var boons: Array[StringName] = []


func save_to(path: String = DEFAULT_SAVE_PATH) -> bool:
	var dir_path: String = path.get_base_dir()
	if dir_path != "":
		DirAccess.make_dir_recursive_absolute(dir_path)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true


## Load the meta, or a FRESH (empty) MetaState if none exists / is malformed —
## meta-progression should never block starting a run.
static func load_from(path: String = DEFAULT_SAVE_PATH) -> MetaState:
	if not FileAccess.file_exists(path):
		return MetaState.new()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return MetaState.new()
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return MetaState.new()
	return from_dict(json.data)


func to_dict() -> Dictionary:
	var boon_out: Array = []
	for b: StringName in boons:
		boon_out.append(String(b))
	return {"acts_cleared": acts_cleared, "boons": boon_out}


static func from_dict(d: Dictionary) -> MetaState:
	var m := MetaState.new()
	m.acts_cleared = int(d.get("acts_cleared", 0))
	var out: Array[StringName] = []
	var v: Variant = d.get("boons", [])
	if v is Array:
		for item: Variant in v:
			out.append(StringName(String(item)))
	m.boons = out
	return m
