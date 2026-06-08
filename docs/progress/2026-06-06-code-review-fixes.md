# Code Review Follow-up — 2026-06-06

Two issues surfaced by a full source review were ticketed in Asana ("Unnamed Game"
project) and resolved. Both fixes are data + documentation only — no behavior code
changed, no test changes required.

## Issue 1 — Frost Nova over-promised AoE (Medium)

**Asana:** https://app.asana.com/1/1215299236116959/project/1215466153342748/task/1215469761656374

**Problem.** `data/cards/frost_nova.json` (in the Mage's starting deck) described
itself as hitting "all enemies in a 1-tile radius," but true AoE (`radius > 0`) is
deferred per `data-schemas.md` §11, and `BattleState._resolve_unit()` degrades a
tile target to the *single* occupant. The card hit one enemy, not the area shown.

**Fix (data-only).** Reworded the card to match the engine and aligned its
`TargetSpec` with single-target reality:
- description → "Deal 4 damage and apply 1 Weak to an enemy. Exhaust."
- `target.shape` `area` → `single`; removed `radius: 1`.

When real AoE lands, this card is a one-line revert to restore the radius.

## Issue 2 — `effect.target_override` parsed but never applied (Low / latent)

**Asana:** https://app.asana.com/1/1215299236116959/project/1215466153342748/task/1215470144602504

**Problem.** The loader parsed and stored `Effect.target_override` (schema §2.2
says it should retarget that effect), but `EffectResolver.resolve()` ignored it —
every effect used the card/intent's main target. No live bug (only `reposition`
used it, and its override equaled the card target), but a latent contract trap:
the next card relying on per-effect retargeting would silently misbehave.

**Decision.** Full support needs `TargetSpec`→target resolution, which the
resolver deliberately excludes ("targeting/selection is NOT here"). Rather than
expand scope, the field is explicitly marked **deferred** so the data contract
stops implying support, and the misleading inert override was removed from data.

**Fix.**
- `data/cards/reposition.json` — dropped the redundant `target_override` from its
  `move` effect (move uses the card's resolved target tile; behavior unchanged).
- `src/combat/effect_resolver.gd` — docstring now states `target_override` is
  deferred and not honored, and where a future handler would live.
- `src/data/content_database.gd` — comment at the parse site notes the field is
  preserved for forward-compat but currently inert.
- `docs/systems/data-schemas.md` §11 — added `target_override` to the deferred
  list, cross-referencing the §12 open question on multi-unit targeting.

## Verification

- All `data/**/*.json` parse; no `target_override` remains in `/data`.
- `reposition` effects = `[{move}, {draw 1}]`; `frost_nova` target = single.
- No GUT suite asserts the Frost Nova description or `reposition`'s effect shape
  (tests reference `frost_nova` only by id), so no test updates were needed.
- **Pending human gate:** Godot is not available in this environment, so the
  headless GUT run (`godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests
  -gexit`) still needs to be run locally to confirm a warning-clean, green suite,
  per AGENTS.md.
