class_name EventResolver
extends RefCounted
## Applies an event choice's typed outcomes to the RunState (run-structure.md §6,
## ADR-0012, P2·08). Events are the run-layer counterpart to combat: an event node
## presents an EventData; a policy/UI picks a choice; this applies that choice's
## ordered outcome deltas to the persistent run. Minimal v1 vocabulary
## (EventOutcome.KINDS); broad scripting is deferred.
##
## Like CardReward, it depends only on the data registry (a ContentDatabase, for
## base max HP when capping heals) and mutates the RunState in place. It never
## touches combat or the deck cycle.
##
## Outcome semantics:
##   heal          restore `amount` HP to each LIVING member, capped so it never
##                 exceeds the member's base max HP (or current, if already above).
##   damage_party  subtract `amount` HP from each member (floored at 0); a member
##                 reduced to 0 is recorded as downed.
##   add_card      append card `id` to run_deck.
##   remove_card   remove ONE copy of card `id` from run_deck (first occurrence).
##   add_relic     append relic `id` to run.relics (recorded even before the relic
##                 engine, P2·12, consumes it).
##   nothing       no-op.

## card/relic registry source for HP caps. A ContentDatabase or null.
var _db: ContentDatabase


func _init(database: ContentDatabase = null) -> void:
	_db = database


# --- Public API -------------------------------------------------------------

## Apply every outcome of `choice` to `run`, in order. A null choice is a no-op.
func apply(run: RunState, choice: EventChoice) -> void:
	if choice == null:
		return
	for outcome in choice.outcomes:
		_apply_outcome(run, outcome)


## Convenience: resolve choice `index` of `event` against `run`. Returns true if
## the index was valid and applied; false otherwise (out-of-range / null event).
func apply_choice_index(run: RunState, event: EventData, index: int) -> bool:
	if event == null or index < 0 or index >= event.choices.size():
		return false
	apply(run, event.choices[index])
	return true


# --- Outcome handlers -------------------------------------------------------

func _apply_outcome(run: RunState, outcome: EventOutcome) -> void:
	if outcome == null:
		return
	match outcome.kind:
		&"heal":
			_heal(run, outcome.amount)
		&"damage_party":
			_damage_party(run, outcome.amount)
		&"add_card":
			if outcome.id != &"":
				run.run_deck.append(outcome.id)
		&"remove_card":
			var idx: int = run.run_deck.find(outcome.id)
			if idx >= 0:
				run.run_deck.remove_at(idx)
		&"add_relic":
			if outcome.id != &"":
				run.relics.append(outcome.id)
		_:
			pass  # `nothing` and any unknown kind: no effect.


## Heal each living member by `amount`, capped at the higher of base max HP or the
## member's current HP (so a heal never lowers an already-boosted pool). Downed
## members (hp <= 0) are not healed by a plain event heal.
func _heal(run: RunState, amount: int) -> void:
	if amount <= 0:
		return
	for cid in run.party:
		var cur: int = int(run.party_hp.get(cid, 0))
		if cur <= 0:
			continue
		var cap: int = maxi(PartyStats.effective_max_hp(_db, run, cid), cur)
		run.party_hp[cid] = mini(cap, cur + amount)


## Subtract `amount` from each member (floored at 0); a member reduced to 0 is
## recorded as downed (deduped), matching combat write-back.
func _damage_party(run: RunState, amount: int) -> void:
	if amount <= 0:
		return
	for cid in run.party:
		var cur: int = int(run.party_hp.get(cid, 0))
		var next_hp: int = maxi(0, cur - amount)
		run.party_hp[cid] = next_hp
		if next_hp <= 0 and not run.downed.has(cid):
			run.downed.append(cid)
