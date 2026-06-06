class_name TelemetryLogger
extends RefCounted
## A design-analytics gameplay logger (additive, non-combat). It records
## design-relevant events from a battle to a per-run JSONL file under
## `user://telemetry/` so a developer can replay and aggregate sessions offline.
##
## It owns NO game rules and mutates NO combat state: BattleView (the only caller)
## hands it already-computed snapshots/dictionaries; this class just serialises
## them one JSON object per line. Each write is flushed so a crash mid-run still
## leaves a readable, append-only log up to the last event.
##
## Robustness contract: any FileAccess/DirAccess failure degrades to a silent
## no-op — telemetry must NEVER crash or stall the game. Flip `ENABLED` to false
## to compile the logger out of the hot path entirely (every entry point early
## returns).
##
## File layout (real macOS path:
## ~/Library/Application Support/Godot/app_userdata/Unnamed Game/telemetry/):
##   * user://telemetry/run_<unix_seconds>.jsonl — one file per run; a `run_start`
##     line, then every gameplay event, then a `run_end` line.
##   * user://telemetry/runs_summary.jsonl — a ROLLING file appended once per
##     completed run with a compact summary (outcome / turns / hp / totals) for
##     quick cross-run aggregate analysis.

## Master switch. `false` turns every public entry point into a no-op (no files
## are opened, nothing is written) without touching the call sites in BattleView.
const ENABLED: bool = true

## Directory (under user://) all telemetry files live in.
const TELEMETRY_DIR: String = "user://telemetry"

## The rolling cross-run summary file (one line per completed run).
const SUMMARY_PATH: String = "user://telemetry/runs_summary.jsonl"


# --- Per-run state ----------------------------------------------------------

## The open run file, or null when no run is active / the open failed.
var _file: FileAccess = null

## Absolute (user://) path of the current run file; "" when no run is active.
var _run_path: String = ""

## Monotonic event counter for the current run (reset on start_run).
var _seq: int = 0

## True between a successful start_run and end_run (the file is open & writable).
var _active: bool = false


# ============================================================================
#  Public API
# ============================================================================

## Begin a new run: ensure the telemetry directory exists, open a fresh
## `run_<unix>.jsonl` for writing, and emit the opening `run_start` event with
## `meta` (encounter id, party ids, grid size, initial HP snapshot, …). Any
## failure leaves the logger inactive (subsequent calls no-op) and never raises.
func start_run(meta: Dictionary) -> void:
	if not ENABLED:
		return
	_active = false
	_file = null
	_seq = 0
	_run_path = ""

	var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(TELEMETRY_DIR)
	if mkdir_err != OK and mkdir_err != ERR_ALREADY_EXISTS:
		return  # cannot create the directory → degrade to no-op

	var unix_seconds: int = int(Time.get_unix_time_from_system())
	_run_path = "%s/run_%d.jsonl" % [TELEMETRY_DIR, unix_seconds]
	_file = FileAccess.open(_run_path, FileAccess.WRITE)
	if _file == null:
		_run_path = ""
		return  # could not open the run file → no-op

	_active = true
	log_event(&"run_start", meta)


## Append one event line: a JSON object carrying `t` (wall-clock seconds), `seq`
## (per-run counter), and `type`, merged with `data`. The write is flushed so the
## line survives a crash. No-op unless a run is active.
func log_event(type: StringName, data: Dictionary) -> void:
	if not ENABLED or not _active or _file == null:
		return
	var obj: Dictionary = {
		"t": Time.get_unix_time_from_system(),
		"seq": _seq,
		"type": String(type),
	}
	_seq += 1
	for key in data.keys():
		obj[key] = data[key]
	_file.store_line(JSON.stringify(obj))
	_file.flush()


## Close out the active run: write a final `run_end` event with `summary`, append
## the same summary as one line to the rolling `runs_summary.jsonl`, then close the
## run file. No-op unless a run is active; safe to call more than once (the second
## call sees an inactive logger and returns).
func end_run(summary: Dictionary) -> void:
	if not ENABLED or not _active:
		return
	log_event(&"run_end", summary)
	_append_summary(summary)
	if _file != null:
		_file.close()
		_file = null
	_active = false


## Whether a run is currently open for writing.
func is_active() -> bool:
	return _active


## The path of the current (or most recent) run file; "" if none was opened.
func run_path() -> String:
	return _run_path


# ============================================================================
#  Internals
# ============================================================================

## Append `summary` (plus the originating run file path and a timestamp) as one
## JSON line to the rolling cross-run summary file. Opens READ_WRITE + seek_end to
## append when the file already exists, WRITE to create it otherwise. Any failure
## is swallowed.
func _append_summary(summary: Dictionary) -> void:
	var line_obj: Dictionary = {
		"t": Time.get_unix_time_from_system(),
		"run_file": _run_path,
	}
	for key in summary.keys():
		line_obj[key] = summary[key]

	var file: FileAccess = null
	if FileAccess.file_exists(SUMMARY_PATH):
		file = FileAccess.open(SUMMARY_PATH, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(SUMMARY_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_line(JSON.stringify(line_obj))
	file.flush()
	file.close()
