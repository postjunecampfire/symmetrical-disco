# Act 1–3 balance — EnemyScaler calibration + harness plan (proposal)

*Working proposal, 2026-06-08. Grounds the [ADR-0021](../decisions/0021-deferred-class-race-origin.md)
"Act 1 = a fragile normal person, ×1.0 by ~Act 3" target in concrete numbers against the
real scaler ([`src/run/enemy_scaler.gd`](../../src/run/enemy_scaler.gd)), the authored curve
([`data/acts/act_progression.json`](../../data/acts/act_progression.json)), and the current
enemy roster. Not a settled spec — the numbers are for the owner to confirm via the harness.*

## 0. The gap (why the scaler does nothing useful today)

`factor(level) = (level / baseline_level) ^ exponent`. **`battle_config.json` currently has
neither `enemy_scale_baseline_level` nor `enemy_scale_exponent`**, so they fall back to the
resource defaults `1` / `1.0` → `factor(level) = level`. An Act-1 trash enemy at level 2 is
scaled **×2**, an Act-3 boss at level 18 is **×18**. The scaler mechanism is built and tested;
it has just never been **calibrated**. This proposal is that calibration.

## 1. Recommendation (one line)

```jsonc
// data/battle_config.json — add these two keys
"enemy_scale_baseline_level": 8,
"enemy_scale_exponent": 1.0
```

**Baseline 8, linear (exponent 1.0).** This calibrates the *authored* enemy stat blocks (today's
roster in `data/enemies/`) to **level 8 = ×1.0**, which is exactly **Act 3's trash band**. Linear
keeps enemy damage growing in lockstep with player DEX→block growth — the balance invariant the
HANDOFF (§5 DIRECTION) asks to bake in.

## 2. Why baseline 8 — it hits both endpoints ADR-0021 named

ADR-0021 names two anchors: **Act 1 ≈ ×0.25** and **back to ×1.0 by ~Act 3**. With the authored
trash levels (A1=2, A2=5, A3=8) and a *single linear knob*, baseline 8 lands both exactly:

| Act | trash lvl | ×trash | elite lvl | ×elite | boss lvl | ×boss |
|----:|----------:|-------:|----------:|-------:|---------:|------:|
| **1** | 2 | **0.25** | 4 | 0.50 | 5 | 0.625 |
| **2** | 5 | **0.625** | 9 | 1.125 | 11 | 1.375 |
| **3** | 8 | **1.00** | 14 | 1.75 | 18 | 2.25 |

The **trash spine** — what most fights are made of — runs `0.25 → 0.625 → 1.00`, a clean linear
on-ramp from "quarter strength" to "today's strength" precisely across Acts 1–3.

## 3. What Act 1 actually feels like (concrete)

Scaling the real base blocks by ×0.25 (`scaled()` rounds; HP floors at 1, damage at 0):

| Enemy (base) | Act-1 dmg | Act-1 HP |
|---|---:|---:|
| Gremlin (dmg 3 / HP 11) | **1** | 3 |
| Skirmisher (dmg 4 / HP 14) | **1** | 4 |
| Grunt (dmg 4 / HP 20) | **1** | 5 |
| Footman (dmg 7 / HP 30) | **2** | 8 |

That reproduces the HANDOFF's own illustration ("footman 7 dmg → ~2 vs a ~8-HP character") and the
intended feel: a fragile newcomer who still **one-or-two-shots weak things** and dies to careless
play. By Act 3 (×1.0) the same enemies are back to full numbers against a party that has leveled
~8–12× and is one fight from its class pick.

## 4. Party side — the partner lever (sanity check, no change proposed yet)

Max HP = `CON × hp_per_con` (+ race CON × hp_per_con + allocated CON × hp_per_con), `hp_per_con = 2`.
With the ADR-0021 illustrative race base lines (CON 2–5) a pre-class character sits around **6–12 HP**.
Against Act-1 trash dealing **1–2**, that's ~4–8 hits of cushion while killing 3–8-HP trash in 1–2 —
fragile but winning. **No change to `hp_per_con` proposed**; it's the partner knob if Act 1 reads
too brutal in the harness (alternatively a small flat base-HP floor). The races in `data/races/`
are still the *old* small-modifier model — the race-as-base-template rework
([ADR-0021](../decisions/0021-deferred-class-race-origin.md)) must land for these CON lines to exist.

## 5. The one thing to watch — the Act-3 boss (×2.25)

Because the authored curve climbs its tier-1 boss levels fast toward the A12 = 250 anchor
(5 → 11 → 18), bosses ramp much steeper than trash inside tier 1: **×0.625 → ×1.375 → ×2.25**. The
**Act-3 boss is fought classless** (the class pick lands at the *end* of Act 3, after the boss), so a
×2.25 boss is the hardest pre-class fight in the game. Two ways to resolve, **owner's call after the
harness read**:

- **(A) Keep the curve, calibrate baseline only (recommended first).** Treat the Act-3 boss as the
  classless "graduation exam." The party arrives leveled (~24–36 allocated stat points) and the
  reward for clearing it is the class pick itself. Don't touch the validated
  [ADR-0019](../decisions/0019-eighteen-act-dungeon-progression.md) curve.
- **(B) Soften tier-1 boss/elite levels** in `act_progression.json` (e.g. A3 boss 18 → ~14) so the
  within-tier ramp is gentler. This touches the ADR-0019 invariants (strictly-increasing bosses;
  tier-gate steeper than within-tier) and the A4 tier-gate, so it needs the whole-curve view — defer
  unless the harness says the classless boss is unwinnable.

Calibrating the baseline (this proposal) is fully reversible and doesn't preclude (B).

## 6. Linear is the right shape (don't reach for an exponent here)

A convex exponent (>1.0) would let Act 1 be *even* softer without lowering the Act-3 ×1.0 — but it
**breaks the lockstep**: enemy damage would grow faster than the player's linear DEX→block, so a
high-DEX turtle re-negates everything at depth (the exact failure mode the HANDOFF DIRECTION warns
about). Linear at baseline 8 is the honest single knob that satisfies both ADR-0021 endpoints; keep
the gate *spikes* in the authored bands (where they already live), not in the factor shape.

## 7. To actually measure it — harness changes

`tools/attrition_sim.gd` today runs **one** representative act and **does not apply EnemyScaler**
(the EncounterAssembler→scaler wiring is still a pending task). To validate this curve:

1. **Wire the scaler into the cohort runner** — scale each encounter's enemies to a given act's
   bands via `EnemyScaler.apply_to(enemy, EnemyScaler.band_level(act, role))` (trash/elite/boss per
   enemy role), parameterized by act number.
2. **Run A1 / A2 / A3 configs** × the existing cohorts (greedy / defensive / turtle / dex-turtle),
   with a **classless, low-race-base party** (no class pick) — that's the actual Act 1–3 player.
   Read win % and final-HP gaps per act.
3. **Targets:** Act 1 ≈ forgiving (greedy survivable, deaths rare); Act 3 boss is the pinch (greedy
   punished, balanced play clears). Tune `baseline` (or option B) until the curve reads right.
4. **Add the GUT lockstep assertion** the HANDOFF asks for: across a sweep of levels, the
   enemy-damage : DEX-block ratio stays ~constant (linear lockstep) — guards future curve edits from
   silently re-opening the turtle.

## 8. Open decisions for the owner

- Confirm **baseline 8 / exponent 1.0** (or pick a different baseline if the trash feel should shift).
- **Act-3 boss:** option (A) keep-and-calibrate, or (B) soften the tier-1 boss curve?
- Is **`hp_per_con = 2`** enough cushion for a classless party, or add a small base-HP floor?
- Order of ops: this calibration **depends on** the race-as-base-template rework landing (for real
  CON lines) and is **best measured after** the scaler→encounter wiring. Sequence accordingly.

> Once Act 1–3 reads right, the progression `stat_bonus` / `ascension_stat_mult` values
> ([ADR-0022](../decisions/0022-class-progression-trees-ascension.md)) finally have a reference point
> — that's the dependency we agreed to hold for.
