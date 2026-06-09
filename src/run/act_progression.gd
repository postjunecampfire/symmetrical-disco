class_name ActProgression
extends Resource
## The ordered list of 18 acts that make up the dungeon descent (ADR-0019,
## act-progression.md §5). Pure data shell — authored in /data/acts and loaded
## by the content database. The read-only convenience accessors below hold no
## balance numbers; the §5 invariant checks (validation_errors) are pure and
## live here so they can be unit-tested without the loader.

## Expected number of acts in a complete dungeon (ADR-0019: 6 tiers x 3 acts).
const EXPECTED_ACTS: int = 18
## The fixed calibration point of the power curve (act-progression.md §2): the
## Act 12 boss is level 250. Anchors the whole curve.
const ANCHOR_ACT: int = 12
const ANCHOR_BOSS_LEVEL: int = 250
## Acts that OPEN a new tier (act-progression.md §4): each is a difficulty gate.
const TIER_GATE_ACTS: Array[int] = [4, 7, 10, 13, 16]

## Acts in descent order; expected length 18 (act 1..18).
@export var acts: Array[ActConfig] = []

## The act with the given number (1-based), or null if absent.
func act_at(n: int) -> ActConfig:
	for a in acts:
		if a != null and a.act == n:
			return a
	return null

## Number of acts defined (should be 18 for a complete dungeon).
func count() -> int:
	return acts.size()


## Check every §5 invariant and return a list of human-readable problems (empty
## == valid). Pure: it only reads `prog`, so the loader appends these into its
## LoadResult and tests can call it on a hand-built progression. Checks are
## structure-first (count/contiguity) so the curve checks can assume a
## well-formed 1..18 spine.
static func validation_errors(prog: ActProgression) -> PackedStringArray:
	var errors := PackedStringArray()
	if prog == null:
		errors.append("act progression is null")
		return errors

	# --- Structure: exactly EXPECTED_ACTS, contiguous act 1..N, one each. ---
	var n: int = prog.acts.size()
	if n != EXPECTED_ACTS:
		errors.append("act progression has %d acts, expected %d" % [n, EXPECTED_ACTS])

	# Index by act number so the curve checks read in descent order. Duplicate or
	# out-of-range act numbers are reported and leave the spine incomplete.
	var by_act: Dictionary = {}
	for a in prog.acts:
		if a == null:
			errors.append("act progression contains a null act")
			continue
		if a.act < 1 or a.act > EXPECTED_ACTS:
			errors.append("act number %d out of range 1..%d" % [a.act, EXPECTED_ACTS])
			continue
		if by_act.has(a.act):
			errors.append("duplicate act number %d" % a.act)
			continue
		by_act[a.act] = a

	var spine_complete: bool = true
	for i in range(1, EXPECTED_ACTS + 1):
		if not by_act.has(i):
			errors.append("act progression missing act %d" % i)
			spine_complete = false

	# --- Per-act: tier formula + rest_before_boss guarantee. ---
	for i in range(1, EXPECTED_ACTS + 1):
		if not by_act.has(i):
			continue
		var a: ActConfig = by_act[i]
		# Float division + floor (not int `/`) to stay warning-clean under the
		# project's warnings-as-errors (AGENTS.md): integer `/` trips INTEGER_DIVISION.
		var expected_tier: int = int(floor(float(a.act - 1) / 3.0)) + 1
		if a.tier != expected_tier:
			errors.append("act %d has tier %d, expected %d" % [a.act, a.tier, expected_tier])
		if a.map == null:
			errors.append("act %d has no map config" % a.act)
		elif not bool(a.map.guarantees.get(&"rest_before_boss", false)):
			errors.append("act %d map must guarantee rest_before_boss" % a.act)

	# The remaining checks read consecutive boss levels; skip them if the spine is
	# incomplete so we never index a missing act.
	if not spine_complete:
		return errors

	# --- Anchor: act 12 boss is exactly 250. ---
	var anchor: ActConfig = by_act[ANCHOR_ACT]
	if anchor.boss_level != ANCHOR_BOSS_LEVEL:
		errors.append("act %d boss_level is %d, must be the anchor %d"
			% [ANCHOR_ACT, anchor.boss_level, ANCHOR_BOSS_LEVEL])

	# --- Boss levels strictly increasing across the descent. ---
	for i in range(2, EXPECTED_ACTS + 1):
		var prev: ActConfig = by_act[i - 1]
		var cur: ActConfig = by_act[i]
		if cur.boss_level <= prev.boss_level:
			errors.append("boss_level not strictly increasing at act %d (%d <= %d)"
				% [i, cur.boss_level, prev.boss_level])

	# --- Tier gates: each tier-opening jump is a larger %-step than the within-
	# tier steps inside the tier it opens (the ramp is "noticeable every 3 acts").
	for gate in TIER_GATE_ACTS:
		# Narrow Dictionary values to typed locals before reading fields (avoids the
		# UNSAFE_PROPERTY_ACCESS warning on Variant access).
		var gate_prev: ActConfig = by_act[gate - 1]
		var gate_cur: ActConfig = by_act[gate]
		var gate_step: float = _pct_step(gate_prev.boss_level, gate_cur.boss_level)
		# The tier opened by `gate` spans acts gate..gate+2; its internal steps are
		# gate->gate+1 and gate+1->gate+2.
		for k in [gate, gate + 1]:
			if not by_act.has(k + 1):
				continue
			var lo: ActConfig = by_act[k]
			var hi: ActConfig = by_act[k + 1]
			var within: float = _pct_step(lo.boss_level, hi.boss_level)
			if gate_step <= within:
				errors.append(
					"tier gate at act %d (%.1f%%) is not steeper than within-tier step act %d->%d (%.1f%%)"
					% [gate, gate_step * 100.0, k, k + 1, within * 100.0])

	return errors


## Fractional increase from `from_level` to `to_level` (e.g. 18 -> 28 == 0.556).
## Guards a zero/negative base so a malformed curve can't divide by zero.
static func _pct_step(from_level: int, to_level: int) -> float:
	if from_level <= 0:
		return 0.0
	return float(to_level - from_level) / float(from_level)
