class_name PromotionData
extends Resource
## A class-promotion branch (P3·06, ADR-0015). At an act boundary, a character that
## has reached the promotion level may pick 1 of 2 branches for its class; the
## branch amplifies the identity it already has — a stat bump plus a signature card.
##
## Applying a promotion reuses existing machinery (no new combat wiring): the stat
## mods fold into RunState.allocated_stats (so they flow through the assembler /
## effective-HP / in-fight stats), and `signature_card` is appended to run_deck.

@export var id: StringName = &""
@export var display_name: String = ""
## The class (character id) this promotes FROM, e.g. &"fighter".
@export var from_class: StringName = &""
## Stat amplifiers granted on promotion.
@export var str_mod: int = 0
@export var dex_mod: int = 0
@export var con_mod: int = 0
@export var int_mod: int = 0
## A card id added to the run deck on promotion (the branch's signature).
@export var signature_card: StringName = &""
