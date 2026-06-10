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
##   add_card      grant skill `id` to the FIRST party member (ADR-0026).
##   remove_card   remove ONE copy of skill `id` from whichever member owns it.
##   add_relic     append relic `id` to run.relics (recorded even before the relic
##                 engine, P2·12, consumes it).
##   add_curse     inflict curse `id` on the FIRST party member (ADR-0029): it
##                 joins their per-member curse list and rides every derived deck
##                 until removed (shop service / remove_curse).
##   remove_curse  remove ONE copy of curse `id` from whichever member carries it
##                 (party order); empty id = the first curse found at all.
##   add_consumable  append consumable `id` to the party inventory (ADR-0029).
##   gain_gold     add `amount` to run.currency.
##   lose_gold     subtract `amount` from run.currency, floored at 0.
##   nothing       no-op.
##
## M3 extensions (docs/systems/events.md): choices may carry a `condition` gate
## (race / class / min_gold / has_curse / has_relic — evaluated by
## is_choice_available; unmet
## choices are hidden by the UI and rejected here) and a weighted gamble table
## (`random_groups`), resolved with run-seeded RNG so the same event node in the
## same run always rolls the same fate.

## card/relic registry source for HP caps. A ContentDatabase or null.
var _db: ContentDatabase


func _init(database: ContentDatabase = null) -> void:
	_db = database


# --- Public API -------------------------------------------------------------

## Apply every outcome of `choice` to `run`, in order. A null choice is a no-op.
## `salt` seeds the gamble roll (callers pass the event id); a choice with a
## random table applies exactly ONE weighted group instead of `outcomes`.
func apply(run: RunState, choice: EventChoice, salt: StringName = &"") -> void:
	if choice == null:
		return
	if choice.is_gamble():
		var group: Array = _pick_gamble_group(run, choice, salt)
		for outcome_v: Variant in group:
			_apply_outcome(run, outcome_v as EventOutcome)
		return
	for outcome in choice.outcomes:
		_apply_outcome(run, outcome)


## Convenience: resolve choice `index` of `event` against `run`. Returns true if
## the index was valid, its condition (if any) is met, and it was applied; false
## otherwise (out-of-range / null event / gated choice).
func apply_choice_index(run: RunState, event: EventData, index: int) -> bool:
	if event == null or index < 0 or index >= event.choices.size():
		return false
	var choice: EventChoice = event.choices[index]
	if not is_choice_available(run, choice):
		return false
	apply(run, choice, event.id)
	return true


# --- Choice conditions (M3) --------------------------------------------------

## True if `choice` may be offered/taken given the run's current state. An empty
## condition is always available. Recognized keys (ANDed): "race", "class",
## "min_gold", "has_curse", "has_relic" — see EventChoice's class doc. Unknown
## keys are ignored here (the loader flags them at load time).
static func is_choice_available(run: RunState, choice: EventChoice) -> bool:
	if run == null or choice == null:
		return choice != null
	var cond: Dictionary = choice.condition
	if cond.is_empty():
		return true
	if cond.has("race"):
		var want_race := StringName(String(cond.get("race")))
		var found_race := false
		for cid in run.party:
			if StringName(String(run.party_races.get(cid, &""))) == want_race:
				found_race = true
				break
		if not found_race:
			return false
	if cond.has("class"):
		# Pre-class members record &"" (ADR-0021 pt2) and never match, so class
		# branches simply stay hidden until the Act-3 pick.
		var want_class := StringName(String(cond.get("class")))
		var found_class := false
		for cid in run.party:
			if StringName(String(run.member_classes.get(cid, &""))) == want_class:
				found_class = true
				break
		if not found_class:
			return false
	if cond.has("min_gold"):
		if run.currency < int(cond.get("min_gold")):
			return false
	if cond.has("has_relic"):
		if not run.relics.has(StringName(String(cond.get("has_relic")))):
			return false
	if cond.has("has_curse"):
		var any_curse := false
		for cid in run.party:
			if not run.curses_of(cid).is_empty():
				any_curse = true
				break
		if any_curse != bool(cond.get("has_curse")):
			return false
	return true


# --- Gamble resolution (M3) ---------------------------------------------------

## Pick one weighted outcome group. Seeded by run.seed ^ hash(salt): the same
## event node in the same run is deterministic (no save-scumming the wheel), but
## different runs/seeds roll differently.
func _pick_gamble_group(run: RunState, choice: EventChoice, salt: StringName) -> Array:
	if choice.random_groups.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = run.seed ^ hash(salt)
	var total: int = 0
	for w in choice.random_weights:
		total += maxi(1, w)
	var roll: int = rng.randi_range(0, maxi(1, total) - 1)
	for i in choice.random_groups.size():
		var w_i: int = maxi(1, choice.random_weights[i] if i < choice.random_weights.size() else 1)
		if roll < w_i:
			return choice.random_groups[i]
		roll -= w_i
	return choice.random_groups.back()


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
				if not run.party.is_empty():
					var first: StringName = run.party[0]
					var coll_v: Variant = run.skill_collections.get(first)
					var load_v: Variant = run.active_loadouts.get(first)
					if coll_v is Array and load_v is Array:
						(coll_v as Array).append(outcome.id)
						if (load_v as Array).size() < 10:
							(load_v as Array).append(outcome.id)
		&"remove_card":
			# ADR-0026: remove ONE copy of the skill from whichever member owns it.
			for cid in run.party:
				var c_v: Variant = run.skill_collections.get(cid)
				if c_v is Array and (c_v as Array).has(outcome.id):
					(c_v as Array).remove_at((c_v as Array).find(outcome.id))
					var l_v: Variant = run.active_loadouts.get(cid)
					if l_v is Array and (l_v as Array).has(outcome.id):
						(l_v as Array).remove_at((l_v as Array).find(outcome.id))
					break
		&"add_relic":
			if outcome.id != &"":
				run.relics.append(outcome.id)
		&"add_curse":
			# ADR-0029: events curse the FIRST member (the one who "touched it"),
			# mirroring add_card's attribution.
			if outcome.id != &"" and not run.party.is_empty():
				run.curses_of(run.party[0]).append(outcome.id)
		&"remove_curse":
			_remove_curse(run, outcome.id)
		&"add_consumable":
			if outcome.id != &"":
				run.consumables.append(outcome.id)
		&"gain_gold":
			if outcome.amount > 0:
				run.currency += outcome.amount
		&"lose_gold":
			if outcome.amount > 0:
				run.currency = maxi(0, run.currency - outcome.amount)
		_:
			pass  # `nothing` and any unknown kind: no effect.


## Remove ONE copy of curse `curse_id` from the first member (party order) who
## carries it; an empty id removes the first curse found at all (ADR-0029).
func _remove_curse(run: RunState, curse_id: StringName) -> void:
	for cid in run.party:
		var curses: Array[StringName] = run.curses_of(cid)
		if curses.is_empty():
			continue
		if curse_id == &"":
			curses.remove_at(0)
			return
		var idx: int = curses.find(curse_id)
		if idx != -1:
			curses.remove_at(idx)
			return


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
