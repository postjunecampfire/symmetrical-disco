extends SceneTree
## M3 exit-gate cohort sweep driver (automated half of the gate): runs
## tools/cohort_lib.gd cells from the CLI and prints one machine-readable line
## per cell, prefixed "CELL " (a JSON object — see CohortLib.run_cell).
##
## Run:
##   godot --headless --script res://tools/cohort_sweep.gd -- \
##     <races_csv> <line> <archetypes_csv> <acts_csv> <seeds> <policies_csv> [drafts_per_act]
## e.g.  -- human,orc fighter brigand,knight 3,6,9,12,15,18 20 greedy,defensive 1.3
##
## Each cell is independent, so callers chunk the matrix across invocations and
## aggregate the CELL lines (the 45s tool-call cap makes one-shot sweeps moot).

const DATA_DIR := "res://data"
const CohortLibScript := preload("res://tools/cohort_lib.gd")


func _initialize() -> void:
	var db := ContentDatabase.new()
	var result: ContentDatabase.LoadResult = db.load_from_dir(DATA_DIR)
	if not result.ok:
		push_error("Content failed to load: %s" % str(result.errors))
		quit(1)
		return

	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 6:
		push_error("usage: -- races_csv line archetypes_csv acts_csv seeds policies_csv")
		quit(1)
		return
	var races: PackedStringArray = args[0].split(",", false)
	var line := StringName(args[1])
	var archetypes: PackedStringArray = args[2].split(",", false)
	var acts: PackedStringArray = args[3].split(",", false)
	var seeds: int = args[4].to_int()
	var policies: PackedStringArray = args[5].split(",", false)
	var k: float = args[6].to_float() if args.size() > 6 else CohortLibScript.DEFAULT_DRAFTS_PER_ACT

	var lib: RefCounted = CohortLibScript.new(db, k)
	for race_s in races:
		for arch_s in archetypes:
			for act_s in acts:
				for mode in policies:
					var cell: Dictionary = lib.run_cell(
						StringName(race_s), line, StringName(arch_s),
						act_s.to_int(), seeds, mode
					)
					if cell.is_empty():
						push_error("invalid cohort: race=%s line=%s archetype=%s (unknown id or not an act-6 node)" % [race_s, args[1], arch_s])
						quit(1)
						return
					print("CELL " + JSON.stringify(cell))
	quit()
