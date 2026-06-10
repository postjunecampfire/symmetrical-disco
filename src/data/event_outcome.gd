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
##   add_curse     — inflict curse card `id` on the FIRST party member (ADR-0029).
##   remove_curse  — remove one copy of curse `id` from whichever member carries
##                   it; an empty id removes the first curse found (party order).
##   add_consumable— append consumable card `id` to the party inventory (ADR-0029).
##   gain_gold     — add `amount` to the run's currency (M3 event economy).
##   lose_gold     — subtract `amount` from the run's currency, floored at 0.
##                   Pair with a `min_gold` choice condition when the cost is a
##                   real price (the floor is a safety net, not a discount).
##   nothing       — no effect (a "walk away" choice).

## The full outcome vocabulary. The loader validates `kind` against this set and
## EventResolver dispatches on it; keeping it here puts the contract on the data.
const KINDS: Array[StringName] = [
	&"heal", &"damage_party", &"add_card", &"remove_card", &"add_relic",
	&"add_curse", &"remove_curse", &"add_consumable", &"gain_gold",
	&"lose_gold", &"nothing",
]

@export var kind: StringName = &"nothing"
## Magnitude for heal / damage_party. Ignored by id-based and `nothing` kinds.
@export var amount: int = 0
## Target id for add_card / remove_card / add_relic. Ignored by amount kinds.
@export var id: StringName = &""
