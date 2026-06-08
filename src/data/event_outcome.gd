class_name EventOutcome
extends Resource
## One typed delta applied when an event choice is taken (run-structure.md §6,
## ADR-0012). Deliberately tiny: a `kind` plus optional `amount`/`id`. Broad event
## scripting is deferred — this is the minimal v1 vocabulary.
##
## kinds (EventResolver.KINDS):
##   heal          — restore `amount` HP to each living party member.
##   damage_party  — deal `amount` HP to each party member (may down them).
##   add_card      — append card `id` to the run deck.
##   remove_card   — remove one copy of card `id` from the run deck.
##   add_relic     — append relic `id` to the run's relics.
##   nothing       — no effect (a "walk away" choice).

## The full outcome vocabulary. The loader validates `kind` against this set and
## EventResolver dispatches on it; keeping it here puts the contract on the data.
const KINDS: Array[StringName] = [
	&"heal", &"damage_party", &"add_card", &"remove_card", &"add_relic", &"nothing",
]

@export var kind: StringName = &"nothing"
## Magnitude for heal / damage_party. Ignored by id-based and `nothing` kinds.
@export var amount: int = 0
## Target id for add_card / remove_card / add_relic. Ignored by amount kinds.
@export var id: StringName = &""
