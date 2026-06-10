class_name EventChoice
extends Resource
## One option the player can take at an event node (run-structure.md §6). A label
## plus the ordered list of typed outcomes applied when it is chosen.
##
## M3 extensions (docs/systems/events.md):
## - `condition`: an optional gate evaluated by EventResolver.is_choice_available.
##   Unmet choices are HIDDEN in the event UI (flavor-gating, the cheap option)
##   and rejected by apply_choice_index. Recognized keys (all optional, ANDed):
##     "race"      — some party member has this race id (ADR-0015 party_races).
##     "class"     — some member has this class id (ADR-0021 pt2 member_classes;
##                   pre-class members are "" and never match, so class branches
##                   degrade gracefully in Acts 1–2).
##     "min_gold"  — run.currency >= N.
##     "has_curse" — true: someone carries a curse; false: nobody does.
##     "has_relic" — run.relics contains this relic id.
## - `random_weights` + `random_groups`: an optional weighted gamble table. When
##   non-empty, EventResolver picks ONE group (RNG seeded run.seed ^ event id, so
##   the same node in the same run always rolls the same fate) and applies it
##   INSTEAD of `outcomes`. weights[i] pairs with random_groups[i], which is an
##   Array[EventOutcome].

@export var label: String = ""
@export var outcomes: Array[EventOutcome] = []
## Optional availability gate; empty = always available. JSON-shaped (String
## keys), see class doc for the vocabulary.
@export var condition: Dictionary = {}
## Weighted gamble table (parallel arrays). Empty = deterministic choice.
@export var random_weights: Array[int] = []
## Array of Array[EventOutcome]; random_groups[i] is picked with weight
## random_weights[i]. Untyped because nested typed arrays don't export.
var random_groups: Array = []


## True if this choice resolves through the weighted gamble table.
func is_gamble() -> bool:
	return not random_groups.is_empty()
