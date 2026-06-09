# Card scaling taxonomy — flat → hybrid → multiplier

*System spec for **ADR-0020** (accepted 2026-06-08). Defines how cards scale across a
run so the deck becomes the player's geometric answer to the geometric difficulty
curve (ADR-0019). Builds on ADR-0014 (stats), ADR-0016 (neutral cards are flat),
and the pure-DEX Defend direction (HANDOFF §5). The decision lives in
[ADR-0020](../decisions/0020-card-scaling-ladder.md); this file holds the detailed
taxonomy, example cards, crossover math, and pool weighting.*

## 1. Why scaling cards exist

Per-turn output is `a × (base + stat)` — plays/turn × (card base + the owner's
scaling stat). Enemy power is **geometric** across the 18 acts; flat cards + linear
leveling are **additive** and structurally fall behind. A card that *multiplies the
stat* turns a linearly-growing stat into geometrically-growing output — the only
same-shape answer to the curve. So the card pool itself is the power curve: you
descend by drafting bigger multipliers.

Two rules govern the whole system:

- **Symmetry.** Offense (the owner's `attack_stat`: str|dex|int) and defense (DEX →
  block) both get the full flat→hybrid→multiplier ladder, so the
  damage-vs-defense balance invariant (HANDOFF §5: DEX and damage scale in
  lockstep) holds at every magnitude. A multiplier that exists for attacks has a
  mirror that exists for block.
- **Crossover gating.** A multiplier card "Deal `m×S`" beats a flat "Deal `base+S`"
  only when **`S > base / (m − 1)`**. That breakpoint decides which act a card may
  appear in: a multiplier must not be draftable before the player could plausibly
  have the stat to justify it (see §4).

## 2. The three scaling classes

Each class exists in an **offense** form (scales `attack_stat`) and a **defense**
form (scales DEX → block). Magnitude shown for a tier-1 baseline; absolute numbers
are data and tune per tier.

### Class A — Flat (additive base)
The reliable floor. Base carries the value; the stat is a small auto-add (the
current `×1` behavior). Common rarity. Dominant in **Tiers 1–2 (acts 1–6)**, stays
as filler forever.

- Offense: `Deal 9.` → `9 + attack_stat`
- Defense: `Gain 8 Block.` → `8 + DEX`

### Class B — Hybrid (base + amplified stat)
Bridge cards that pay the stat **more than once** — partial multiplier. Reward
players who have started investing. Uncommon. Dominant in **Tiers 3–4 (acts 7–12)**.

- Offense: `Deal damage equal to your Strength + 4.` → `floor(attack_stat × 1.5) + 4`
- Defense: `Gain Block equal to your Dexterity + 3.` → `floor(DEX × 1.5) + 3`

### Class C — Multiplier (pure stat-scaling)
The geometric ceiling. Base is near zero; the stat is multiplied 2–4×. Rare, and
**always guardrailed** (Exhaust, X-cost, or single-turn — see §5). Dominant in
**Tiers 5–6 (acts 13–18)**, gated into late reward pools.

- Offense: `Deal 2× your Strength. Exhaust.` → `floor(attack_stat × 2)`
- Defense: `Gain Block equal to 2× your Dexterity. Exhaust.` → `floor(DEX × 2)`
- Status form (no new effect type needed): `Gain 3 Strength this combat.` —
  rents temporary stat, multiplies every later attack.

## 3. Effect schema — one new optional field

The whole ladder is expressible with a single backward-compatible addition:
`stat_mult` (float, default `1.0`) on the `damage` and `block` effects.

```
scaled damage = base + floor(attack_stat × stat_mult)
scaled block  = base + floor(DEX × stat_mult)
```

- `stat_mult` absent / `1.0` → today's behavior (every existing card unchanged;
  pure-DEX Defend stays `base 0, stat_mult 1.0` → `DEX`).
- Class B → `stat_mult 1.5–2.0`, small base.
- Class C → `stat_mult 2.5–4.0`, base `0–2`, plus a keyword guardrail.

It rides the existing scale flag (`card.innate or non-neutral`); neutral cards
ignore `stat_mult` and stay flat (ADR-0016). Implement as a first-class float on
`Effect` (type-checked) rather than in `params`. This is the one engine task that
unlocks the entire multiplicative tier.

## 4. Crossover breakpoints → which act unlocks what

`S* = base / (m − 1)` is the attack_stat at which a multiplier overtakes a flat
card. Below `S*` the multiplier is a trap; above it, a bomb. Gate each multiplier so
its crossover lands inside the tier where the player has that stat.

| Multiplier `m` | vs flat `base 10` | crossover `S*` | earliest sane tier |
|---|---|---|---|
| ×1.5 (hybrid) | 10 + S | S > 20 | Tier 2–3 |
| ×2 | 10 + S | S > 10 | Tier 3–4 |
| ×3 | 10 + S | S > 5 | Tier 4+ (rare, gated) |
| ×4 | 10 + S | S > 3.3 | Tier 5–6 (Exhaust only) |

Starting stats are low (Fighter STR 8, Mage INT 8) and leveling adds 3 pts/level, so
×2 cards cross over by mid-run and ×3+ almost immediately — which is exactly why the
big multipliers must be **rarity- and pool-gated**, not freely available early.

**Reward-pool weighting by tier** (drives the per-act draft pool the scaler/map work
will reference):

- Tiers 1–2: mostly A, a little B.
- Tiers 3–4: B-heavy, A filler, first gated C.
- Tiers 5–6: C-heavy, B support, A as cheap cycle fodder.

## 5. Guardrails — multipliers are where balance explodes

Multiplicative offense is the mirror of the turtle problem (unkillable defense ↔
runaway offense / the classic infinite). Non-negotiable rails on Class C:

- **Cap stacking** — limit how many `stat_mult` effects compound in one turn.
- **Exhaust the biggest** — ×3/×4 cards leave the deck after one use.
- **Cost-gate** — X-cost or 2–3 energy so a multiplier isn't also high-frequency.
- **Single-turn buffs** — "+100% attack_stat this turn" expires, not permanent.
- **Poison is the pressure valve** — it ignores block (`deal_unblockable`), so a
  runaway *defense* multiplier still bleeds; keep a poison applier in late pools.

## 6. Open questions for the owner

1. **Rogue double-dip — DEFERRED TO PLAYTEST (2026-06-08).** The Rogue's
   `attack_stat` IS dex, and block also scales DEX, so one stat feeds *both* its
   offense and defense multipliers. Decision: **leave the Rogue class as-is for
   now** and let playtesting size the problem before tuning. Notes for when we
   revisit: the fragility tax already exists (CON 12 → 24 HP vs the Fighter's
   34–38). Nerfing Rogue *attacks* is likely the wrong lever — it pushes the Rogue
   toward the dex-turtle line (weak offense + intact DEX block), the opposite of
   the glass-cannon fantasy; the asymmetry to watch is on the *defense* side. If it
   proves too strong, prefer **dampening/gating** Rogue access to Class-B/C
   *defense* multipliers (not a hard "never") and/or leaning the both-ways DEX
   build into the **Duelist** promotion as an earned identity. Measure it with the
   `dex-turtle` harness cohort once multi-act content runs.
2. **Ceiling height.** How high does Class C go — ×3 max (controlled) or ×4+ with
   heavy Exhaust (swingy, combo-y)?
3. **Hybrid as the default mid-tier**, or skip B and jump A→C at a hard tier line?
4. **Defense multiplier parity** — exact mirror of offense, or slightly behind so
   aggression keeps a small edge at depth (a deliberate, small asymmetry)?
