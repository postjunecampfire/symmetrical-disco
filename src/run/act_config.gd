class_name ActConfig
extends Resource
## One act of the 18-act dungeon (ADR-0019, act-progression.md §5). Pure data
## shell — no logic here. Authored content lives in /data/acts; these fields
## mirror the documented contract so the curve is data-driven (ADR-0003,
## AGENTS.md: no balance magic numbers in code). The map generator and the
## enemy level->stat scaler READ these values; they do not hardcode them.

## Act number, 1..18.
@export var act: int = 1
## Tier 1..6 == (act - 1) / 3 + 1. Stored for convenience; validated on load.
@export var tier: int = 1
## Boss level — the power-curve anchor for this act (act-progression.md §2).
## The Act 12 boss is the fixed calibration point at level 250.
@export var boss_level: int = 5
## Standard/"trash" enemy level band for this act (act-progression.md §4).
@export var trash_level: int = 2
## Elite enemy level band for this act.
@export var elite_level: int = 4
## Per-act map shape (rows/width/weights/guarantees). See MapGenConfig.
@export var map: MapGenConfig
## Optional fixed boss encounter id; empty => chosen from a pool at resolve time.
@export var boss_payload: StringName = &""
