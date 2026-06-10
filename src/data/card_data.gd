class_name CardData
extends Resource
## A playable action / card (data-schemas.md §3).

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var character_tag: StringName = &"neutral"
@export var energy_cost: int = 1
@export var keywords: Array[StringName] = []
@export var innate: bool = false
@export var rarity: StringName = &"common"
@export var target: TargetSpec
@export var effects: Array[Effect] = []
@export var art: Texture2D
@export var upgrade_of: StringName = &""
## Tree-signature skill (M3): granted only by a progression-node pick
## (`unlock_cards` on a data/progression node). Signature cards are EXCLUDED
## from the draft/shop pools (CardReward.eligible_pool), like _plus variants.
@export var signature: bool = false
## Injected-card layer discriminator (ADR-0029): `skill` (default — a loadout
## skill), `curse` (forced in by enemies/events; counts toward the derived-deck
## floor, displacing auto-fill basics), or `consumable` (run-level item; injected
## ON TOP of the floor, consumed from the inventory when played). Anything that
## is not a `skill` NEVER appears in draft/shop/treasure reward pools.
@export var card_kind: StringName = &"skill"
## Curse active downside (ADR-0029): damage the DRAWING unit takes when this
## card is drawn (0 = plain dead draw). Routed through deal_damage (blockable).
@export var on_draw_damage: int = 0
