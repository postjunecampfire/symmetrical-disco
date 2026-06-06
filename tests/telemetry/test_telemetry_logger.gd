extends "res://addons/gut/test.gd"
## GUT suite for src/telemetry/telemetry_logger.gd (gameplay telemetry logger).
##
## SCOPE: the logger in isolation (no battle/combat needed). It drives the full
## run lifecycle — start_run → log_event ×N → end_run — against the real user://
## filesystem (which works under --headless), then reads the run file back and
## asserts: the file exists, every line parses as a JSON object carrying the
## required envelope keys (t / seq / type), the seq counter increments, the first
## and last lines are run_start / run_end, and the rolling runs_summary.jsonl
## received an appended line for the completed run.

const TelemetryLoggerScript := preload("res://src/telemetry/telemetry_logger.gd")

const SUMMARY_PATH: String = "user://telemetry/runs_summary.jsonl"


# --- Helpers ----------------------------------------------------------------

## Read every non-blank line of `path` back as a PackedStringArray.
func _read_nonempty_lines(path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.strip_edges() != "":
			out.append(line)
	file.close()
	return out


## Run a complete logging session and return the logger so callers can read its
## run_path() and the files it produced.
func _run_a_session() -> TelemetryLogger:
	var logger: TelemetryLogger = TelemetryLoggerScript.new()
	logger.start_run({
		"encounter": "skirmish_01",
		"party": ["vanguard", "mage"],
		"grid": [6, 6],
	})
	logger.log_event(&"card_played", {"card": "strike", "actor": 0, "damage": 6})
	logger.log_event(&"unit_moved", {"unit": 1, "from": [0, 0], "to": [1, 0]})
	logger.log_event(&"unit_downed", {"unit": 3, "team": "enemy", "turn": 2})
	logger.end_run({
		"outcome": "WIN",
		"turns": 3,
		"party_hp_remaining": 21,
		"cards_played": 1,
		"damage_dealt": 6,
		"damage_taken": 0,
	})
	return logger


# --- Tests ------------------------------------------------------------------

func test_run_file_exists_and_every_line_is_valid_json() -> void:
	var logger: TelemetryLogger = _run_a_session()
	var path: String = logger.run_path()

	assert_ne(path, "", "start_run should set a non-empty run path")
	assert_false(logger.is_active(), "end_run should mark the logger inactive")
	assert_true(FileAccess.file_exists(path), "the run file should exist on disk")

	var lines: PackedStringArray = _read_nonempty_lines(path)
	# run_start + 3 events + run_end == 5 lines.
	assert_eq(lines.size(), 5, "all five events should be written, one per line")

	var expected_seq: int = 0
	for line in lines:
		var parsed: Variant = JSON.parse_string(line)
		assert_true(parsed is Dictionary, "each line should parse as a JSON object")
		if not (parsed is Dictionary):
			continue
		var obj: Dictionary = parsed
		assert_true(obj.has("t"), "every event has a 't' timestamp")
		assert_true(obj.has("seq"), "every event has a 'seq' counter")
		assert_true(obj.has("type"), "every event has a 'type'")
		assert_eq(int(obj["seq"]), expected_seq, "seq increments by one per event")
		expected_seq += 1


func test_first_and_last_events_bracket_the_run() -> void:
	var logger: TelemetryLogger = _run_a_session()
	var lines: PackedStringArray = _read_nonempty_lines(logger.run_path())
	assert_gt(lines.size(), 1, "a completed run has at least a start and an end line")
	if lines.size() < 2:
		return

	var first: Dictionary = JSON.parse_string(lines[0])
	var last: Dictionary = JSON.parse_string(lines[lines.size() - 1])
	assert_eq(String(first["type"]), "run_start", "the first line is the run_start event")
	assert_eq(String(first["encounter"]), "skirmish_01", "run_start carries the meta")
	assert_eq(String(last["type"]), "run_end", "the last line is the run_end event")


func test_summary_file_gets_a_line_for_the_completed_run() -> void:
	var logger: TelemetryLogger = _run_a_session()
	assert_true(FileAccess.file_exists(SUMMARY_PATH), "the rolling summary file should exist")

	var lines: PackedStringArray = _read_nonempty_lines(SUMMARY_PATH)
	assert_gt(lines.size(), 0, "the summary file should have at least one line")
	if lines.is_empty():
		return

	# The line just written by THIS run's end_run is the final one.
	var last: Dictionary = JSON.parse_string(lines[lines.size() - 1])
	assert_true(last is Dictionary, "the summary line parses as JSON")
	assert_eq(String(last["outcome"]), "WIN", "summary records the run outcome")
	assert_eq(int(last["turns"]), 3, "summary records the turn count")
	assert_eq(String(last["run_file"]), logger.run_path(), "summary links back to its run file")


func test_disabled_or_unstarted_logger_never_writes_or_crashes() -> void:
	# A fresh logger that was never started must no-op (and not crash) on log/end.
	var logger: TelemetryLogger = TelemetryLoggerScript.new()
	assert_false(logger.is_active(), "a fresh logger is not active")
	logger.log_event(&"card_played", {"card": "strike"})  # must be a safe no-op
	logger.end_run({"outcome": "abandoned"})              # must be a safe no-op
	assert_eq(logger.run_path(), "", "no run file path without a start_run")
