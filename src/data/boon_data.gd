class_name BoonData
extends Resource
## A cross-run "exit-package" boon (P3·08, ADR-0018): a mostly-horizontal perk the
## player banks at a meta cash-out and that applies to every FUTURE run's start.
##
## kinds (MetaProgress applies them in RunController-agnostic code):
##   relic  — start each run with relic `target`.
##   card   — add card `target` to each run's starting deck.
##   stat   — every party member starts with +`amount` in stat `target`
##            (str/dex/con/int; con also raises max HP via the usual derivation).
##   unlock — record an unlock (e.g. a class/race option). No combat effect yet;
##            consumed by the creation screen when locked content exists.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var kind: StringName = &"relic"
## relic id / card id / stat key / unlock id, per `kind`.
@export var target: StringName = &""
@export var amount: int = 0
