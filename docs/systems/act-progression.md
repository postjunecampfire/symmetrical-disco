# Act Progression — 18-Act Dungeon Wireframe & Power Curve

**Status:** Draft (v1 of the 18-act curve)
**Owners:** Michael; Claude
**Depends on:** [ADR-0019](../decisions/0019-eighteen-act-dungeon-progression.md) (18-act decision), [ADR-0012](../decisions/0012-run-structure-and-map.md) (per-act map model), [ADR-0011](../decisions/0011-death-downed-and-hp-attrition.md) (HP attrition), [ADR-0015](../decisions/0015-classes-races-leveling.md) (leveling), [ADR-0018](../decisions/0018-meta-progression-exit-package.md) (meta-progression). Extends [run-structure.md](run-structure.md).

> This is the **structural wireframe** for the dungeon: how the 18 acts are shaped and how difficulty scales between them. Per [ADR-0019](../decisions/0019-eighteen-act-dungeon-progression.md), this fixes **structure and curve, not rosters** — which specific enemies appear in each act is authored separately against the level bands below. Every number here is a tunable default destined for `/data` ([ADR-0003](../decisions/0003-data-driven-content-architecture.md)); code reads it, code does not hardcode it.

---

## 1. Shape of the descent

The dungeon is **18 acts**, played top-to-bottom as one continuous descent. Each act is a single [ADR-0012](../decisions/0012-run-structure-and-map.md) branching map (rows of combat/elite/rest/event nodes) that terminates in **one boss**. Beating the boss descends to the next act on the carried-over RunState (party, HP, deck, relics, levels). A TPK ends the run; meta-progression ([ADR-0018](../decisions/0018-meta-progression-exit-package.md)) carries gains forward.

The 18 acts group into **6 tiers of 3 acts**. The design cadence:

- **Every act** is a step up from the one before (gentle within a tier).
- **Every 3rd act crossing** — entering Act 4, 7, 10, 13, 16 — is a **tier gate**: a deliberate, noticeable jump in enemy level *and* structure.
- **The tier capstone** — Act 3, 6, 9, 12, 15, 18 — is the hardest boss of its tier and the wall most runs die against.

```
TIER 1        TIER 2        TIER 3        TIER 4        TIER 5        TIER 6
A1 A2 A3  ›gate›  A4 A5 A6  ›gate›  A7 A8 A9  ›gate›  A10 A11 A12  ›gate›  A13 A14 A15  ›gate›  A16 A17 A18
          ▲                ▲                ▲                 ▲ (A12=250)         ▲                    ▲ (A18=1300, end)
        capstone bosses get progressively, brutally harder →
```

---

## 2. The power curve (boss level by act)

**Boss level** is the single scalar that anchors an act's difficulty; enemy stats derive from it (§4). The owner's fixed calibration point: **the Act 12 boss is level 250.** Everything else is calibrated against that anchor so preceding and following acts sit on a coherent curve.

Capstone-to-capstone the curve scales **~2.3–2.4× per tier**; **tier-gate jumps (+41–56%) clearly exceed within-tier steps (+22–32%)**, which is what makes every third act *feel* like a wall.

| Act | Tier | Boss level | Δ vs prev | Cadence |
|----:|:----:|----------:|----------:|---------|
| 1 | 1 | **5** | — | start |
| 2 | 1 | **11** | +120% | within-tier |
| 3 | 1 | **18** | +64% | capstone |
| 4 | 2 | **28** | +56% | ► tier gate |
| 5 | 2 | **36** | +29% | within-tier |
| 6 | 2 | **44** | +22% | capstone |
| 7 | 3 | **62** | +41% | ► tier gate |
| 8 | 3 | **82** | +32% | within-tier |
| 9 | 3 | **105** | +28% | capstone |
| 10 | 4 | **150** | +43% | ► tier gate |
| 11 | 4 | **198** | +32% | within-tier |
| 12 | 4 | **250** | +26% | capstone · **★ anchor** |
| 13 | 5 | **360** | +44% | ► tier gate |
| 14 | 5 | **465** | +29% | within-tier |
| 15 | 5 | **580** | +25% | capstone |
| 16 | 6 | **820** | +41% | ► tier gate |
| 17 | 6 | **1050** | +28% | within-tier |
| 18 | 6 | **1300** | +24% | capstone · **final** |

Tier capstone ratios: A3→A6 2.44×, A6→A9 2.39×, A9→A12 2.38×, A12→A15 2.32×, A15→A18 2.24× (a gently decelerating geometric climb — steep enough that A16–A18 is an end-game wall, not a grind).

### Why this makes a single run "almost impossible"
Player power per act comes from a **bounded** budget: ~3 stat points/level ([ADR-0015](../decisions/0015-classes-races-leveling.md)), a handful of drafted cards, and a few relics/boons. That budget grows roughly **linearly** with acts cleared, while boss level grows **geometrically across tiers**. The gap compounds at every gate — so the deck/level a run can realistically assemble keeps pace for a tier or two, then falls behind. Reaching the deep acts (and certainly A18) is meant to require accumulated **meta-progression** ([ADR-0018](../decisions/0018-meta-progression-exit-package.md)) across many runs, not a single heroic attempt.

---

## 3. Per-act structure (the wireframe)

Each act is generated from a per-act `MapGenConfig` ([run-structure.md §4](run-structure.md)). Structure escalates with depth on three axes — **length** (more rows), **density of hard nodes** (more elites, heavier late-row combat weighting), and **scarcity of relief** (rest stays roughly fixed while everything around it scales, so attrition bites harder deep down). A `rest_before_boss` guarantee holds for **every** act.

| Act | Tier | Rows | Width | Combats* | Elites | Rests | Events | Late-row bias** |
|----:|:----:|:----:|:-----:|:--------:|:------:|:-----:|:------:|:---------------:|
| 1 | 1 | 7 | 2–3 | ~4 | 1 | 2 | 2 | low |
| 2 | 1 | 8 | 2–3 | ~5 | 1 | 2 | 2 | low |
| 3 | 1 | 8 | 2–3 | ~5 | 1 | 2 | 2 | low |
| 4 | 2 | 9 | 2–3 | ~5 | 1 | 2 | 2 | low–med |
| 5 | 2 | 9 | 2–3 | ~6 | 2 | 2 | 2 | med |
| 6 | 2 | 10 | 2–3 | ~6 | 2 | 2 | 1 | med |
| 7 | 3 | 10 | 2–4 | ~6 | 2 | 2 | 2 | med |
| 8 | 3 | 11 | 2–4 | ~7 | 2 | 2 | 1 | med |
| 9 | 3 | 11 | 3–4 | ~7 | 3 | 2 | 1 | med–high |
| 10 | 4 | 12 | 3–4 | ~7 | 3 | 2 | 1 | high |
| 11 | 4 | 12 | 3–4 | ~8 | 3 | 2 | 1 | high |
| 12 | 4 | 13 | 3–4 | ~8 | 3 | 2 | 1 | high |
| 13 | 5 | 13 | 3–5 | ~8 | 3 | 2 | 1 | high |
| 14 | 5 | 14 | 3–5 | ~9 | 4 | 2 | 1 | high |
| 15 | 5 | 14 | 3–5 | ~9 | 4 | 1 | 1 | very high |
| 16 | 6 | 15 | 3–5 | ~9 | 4 | 1 | 1 | very high |
| 17 | 6 | 15 | 3–5 | ~10 | 4 | 1 | 1 | very high |
| 18 | 6 | 16 | 3–5 | ~10 | 5 | 1 | 1 | very high |

\* *Combats* is the approximate number of standard combat nodes on a typical path; actual count varies with the branch the player chooses.
\*\* *Late-row bias* is how strongly node-type weighting tilts toward combat/elite in the last third of the act's rows (the run-structure `type_weights` shift by row band). Higher bias = fewer safe detours before the boss.

Node behaviors (combat / elite / rest / event / boss) are **unchanged** from [run-structure.md §5](run-structure.md). Only the per-act *config* changes.

---

## 4. Enemy level bands (handoff to roster authoring)

Within an act, enemies sit in a band keyed to the boss level. These bands are the **contract** for whoever authors rosters later; this doc does not pick monsters.

- **Trash / standard combat** ≈ `round(0.45 × boss_level)`, rising across the act's rows toward the boss.
- **Elite** ≈ `round(0.80 × boss_level)`.
- **Boss** = `boss_level` (the table in §2).

| Act | Trash | Elite | Boss |    | Act | Trash | Elite | Boss |
|----:|------:|------:|-----:|----|----:|------:|------:|-----:|
| 1 | 2 | 4 | 5 |  | 10 | 68 | 120 | 150 |
| 2 | 5 | 9 | 11 |  | 11 | 89 | 158 | 198 |
| 3 | 8 | 14 | 18 |  | 12 | 112 | 200 | **250** |
| 4 | 13 | 22 | 28 |  | 13 | 162 | 288 | 360 |
| 5 | 16 | 29 | 36 |  | 14 | 209 | 372 | 465 |
| 6 | 20 | 35 | 44 |  | 15 | 261 | 464 | 580 |
| 7 | 28 | 50 | 62 |  | 16 | 369 | 656 | 820 |
| 8 | 37 | 66 | 82 |  | 17 | 472 | 840 | 1050 |
| 9 | 47 | 84 | 105 |  | 18 | 585 | 1040 | 1300 |

> **Level → enemy stats** (the function that turns a level into HP/damage) is intentionally **deferred to balancing** ([ADR-0019](../decisions/0019-eighteen-act-dungeon-progression.md) open question). The current single-act enemies (`/data/enemies`) are authored as flat stat blocks (`max_hp`, intent `amount`); the multi-act scaler will multiply those base blocks by a level-derived factor. Whether that factor is linear or mildly exponential is a tuning decision, not a structural one.

---

## 4b. Tier mechanical identities (the ADR-0019 deferred tier modifiers)

Stat scaling alone makes Acts 7–18 a stat-check treadmill, so each tier also has a
**mechanical identity**: the enemy kits in its `tier_pools` lean on a distinct set of
mechanics, escalating from "learn the basics" to "multi-enemy synergy". Every enemy
still follows the Attack·Debuff·Defend kit convention (enemy_design_review.xlsx);
the identity is *which* debuff/defend tools the tier's roster carries. Each tier
also has its **own boss kit** — the Iron Warden is the Tier-1 boss only.

| Tier | Acts | Identity | Signature mechanics | New roster | Boss (kit) |
|:----:|:----:|----------|---------------------|------------|------------|
| 1 | 1–3 | **Tutorial** | plain attack/debuff/block kits | tunnel_rat, burrow_beetle | **Iron Warden** — block/crush/hex/stun sequence, passive ramp |
| 2 | 4–6 | **Debuff escalation** | curse infliction (`inflict_curse`), frail/weak stacking, first **burn** | ember_wisp, cinder_acolyte, dread_imp, grave_chanter | **The Hollow Matron** — curse-weaver: stacks doubt/burden + burn; post-fight curse-removal sink |
| 3 | 7–9 | **Attrition** | bleed/poison stacking, ally **heals**, block-piercing attacks (`pierce_damage`) | leech_swarm, rot_priest, plague_bearer, wall_breaker | **The Carrion King** — DoT layering + self-heal + pierce; punishes turtling |
| 4 | 10–12 | **Action economy** | mid-fight **summons**, hand disruption (wound curses), stun | bone_servant, gravecaller, mind_leech, chain_warden | **The Broodmother** — broodling waves (1 per 3 turns, max 4 — killable by single-target play) |
| 5 | 13–15 | **Punish patterns** | **thorns** (retaliate), **enrage** (strength per debuff taken), mark | bramble_fiend, pit_champion, huntmaster, blood_zealot | **The Duelist** — thorns stance → enrage → mark → burst; a solo duel |
| 6 | 16–18 | **Legion** | ally strength buffs, ally block (shield-bearers), AoE dread, combo casters | legion_bannerman, legion_shieldbearer, legion_blade, void_herald | **The Legion King** — buffs minions, shield walls, raises the fallen ONCE |

Supporting engine vocabulary added for this pass: effect kinds `pierce_damage`
(block-ignoring intent damage) and `revive_allies` (once-per-battle resurrection,
latched per caster); statuses `thorns` (attacker takes stacks on hit) and `enrage`
(holder gains Strength per debuff landed on it). **Energy drain was considered and
skipped**: the enemy phase resolves after the player has spent, and pools refill at
the next turn start, so a drain needs a player-side "reduced refill" hook — too
invasive for this pass.

Enemies are authored at the `enemy_scale_baseline_level` (8) stat band like the
original roster; the EnemyScaler provides all depth scaling, and the scaler treats
`pierce_damage` / `heal` / `revive_allies` amounts as magnitudes (scaled) while
status stacks stay control (unscaled).

---

## 5. Data contract — `ActProgression`

The 18-act curve is authored content. Proposed shape (mirrors `MapGenConfig`; lives in `/data/acts/`):

```gdscript
class_name ActConfig extends Resource
@export var act: int = 1                 # 1..18
@export var tier: int = 1                 # 1..6  ( (act-1)/3 + 1 )
@export var boss_level: int = 5           # §2 anchor curve
@export var trash_level: int = 2          # §4 band floor
@export var elite_level: int = 4          # §4
@export var map: MapGenConfig             # rows/width/weights/guarantees per §3
@export var boss_payload: StringName = &""   # optional fixed boss encounter id

class_name ActProgression extends Resource
@export var acts: Array[ActConfig] = []   # length 18, ordered
```

**Invariants** (tests must check): exactly 18 acts, contiguous `act` 1..18; `tier == (act-1)/3 + 1`; `boss_level` strictly increasing; **`acts[11].boss_level == 250`** (the anchor); every tier-gate Δ (acts 4,7,10,13,16) is a larger %-step than the within-tier steps inside the tier it enters; every act's map has `rest_before_boss == true`.

---

## 6. How the run advances acts

`RunController` ([run-structure.md §1](run-structure.md)) gains an **act index** on the RunState. On a boss win: instead of "run complete (v1 victory)", it loads the next `ActConfig`, regenerates the map from that act's `MapGenConfig`, carries HP/deck/relics/levels forward, applies the post-combat heal, and places the party at the new map's start. After Act 18's boss → **run complete (true victory)**. TPK at any act → run ends.

This is additive to ADR-0012's flow — the per-act map generation and combat assembly are unchanged; only the "what happens after the boss" branch and the source of the map config change.

---

## 7. Scope & deferred

**In scope (this doc):** the 18-act shape, the boss-level curve anchored at A12=250, per-act structure escalation, enemy level bands, the `ActProgression` data contract, and the act-advance flow.

**Deferred:** the level→enemy-stat function (balancing); re-tuning `meta_cash_out_acts` for depth 18; intra-act intra-row level ramping curve (currently "rises toward the boss", exact shape TBD); enemy-side energy drain (needs a player-side refill hook, see §4b).

**Done since v1:** act rosters via `tier_pools` (M3); tier-gate *mechanical* modifiers — per-tier enemy mechanics + per-tier bosses (§4b, M3).
