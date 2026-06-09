# Playtest review — 2026-06-08 (screenshots)

*Owner (Michael) playtested the current build and flagged design reconsiderations + asked
for a screenshot review. This is the synthesis: each finding has the observation, the root
cause in code/ADRs, a recommendation, and where it's tracked. Pairs with the new
[ADR-0023](../decisions/0023-sts-style-map-run-structure.md) (map/run-structure) and the
[Act 1–3 balance proposal](../systems/act-1-3-balance-proposal.md).*

## Owner's explicit reconsiderations

### 1. Flip the map — start at the bottom, climb up
**Now:** `map_view.gd` renders rows top→down (party header on top, row 0 first, boss last at the
visual bottom). **Want:** StS orientation — player starts at the **bottom**, progresses **up** the
page; boss at the top. **Root:** pure presentation — the `MapGraph` is a row-indexed DAG; only the
view's row iteration order needs reversing (render row N at the top, row 0 at the bottom, player
marker climbing). No model change. → ADR-0023, tracked.

### 2. Fog of war — don't show the next encounter type
**Now:** every node shows its type label ("Combat", "Rest", "Event", "Elite") from the start
(screenshot 1). **Want:** node types **hidden/Unknown** until revealed; **revealing** becomes a
mechanic — a relic and/or a **class-progression boon** (ties to
[ADR-0022](../decisions/0022-class-progression-trees-ascension.md)). **Root:** `map_view` reads
`node.node_type` and always labels it; needs a per-node `revealed` flag + a default "Unknown" glyph,
plus reveal hooks (relic effect, class boon, maybe adjacency "you can see one step ahead"). The
reference map (screenshot 2) shows the target: an **Unknown `?`** node type in the legend alongside
Merchant/Treasure/Rest/Enemy/Elite. → ADR-0023, tracked. *Design note:* a baseline of "see the next
row only" keeps early navigation legible; relics/boons extend sight further or reveal types.

### 3. Shops + StS-style node variety
**Now:** only five node kinds exist in code — `combat / elite / rest / event / boss`
(`map_generator.gd`). **No shop, no merchant, no treasure.** Default weights are **combat 6 vs
elite/rest/event 2 each** (`map_gen_config.gd`) → ~60% combat, which is exactly the wall of "Combat"
in screenshot 1. **Want:** add **Shop/Merchant** (buy cards + relics) and **Treasure** nodes, and
reweight for StS-like variety. **Root:** new node kinds (`&"shop"`, `&"treasure"`) + their handlers
(a shop screen with a card/relic buy list + a currency; treasure = a reward grant), plus
generation weights and placement rules (e.g. shop/treasure rarer, often pre-boss). Introducing a
**currency** is a real new system (earned from combat/events; spent at shops). → ADR-0023 +
new Asana tasks.

## Issues found in the screenshots

### 4. Character creation is the OLD model (pre-ADR-0021) — highest-impact gap
**Observation (screenshot 3):** "Create Your Party — Pick 2 (distinct) classes and a race for
each," classes chosen up front, races shown as small modifiers (+1 all / +DEX+INT / +STR+CON).
**This directly contradicts [ADR-0021](../decisions/0021-deferred-class-race-origin.md):** creation
should pick **race only**, **one race for the whole pair** (no mix-and-match), starting as a
classless "normal person"; **class is chosen at the end of Act 3**; races are **full base stat
templates**, not modifiers. The build still runs `character_creation.gd`, whose own header says
"(ADR-0015/0016): pick 2 distinct classes and a race for each." **Root:** the ADR-0021 rework was
decided but never implemented — there's already an Asana task ("Code: character creation rework —
race-only, one race for the pair"). This is why "character creation" feels absent/thin: you're
seeing the pre-pivot screen. **Recommendation:** prioritize the creation rework + the race-as-base-
template data split; it gates the whole deferred-class arc (ADR-0021/0022) and the Act 1–3 balance
feel. Tracked (existing task) — raising priority.

### 5. "Fairly easy to win"
**Observation (screenshot 4):** VICTORY, 9 nodes cleared, party only **Lv 2**, HP unchanged
(36/24). **Root — known and expected:** (a) the **EnemyScaler is uncalibrated** (the
[Act 1–3 proposal](../systems/act-1-3-balance-proposal.md) — `baseline`/`exponent` keys aren't even
in `battle_config.json`, and the scaler isn't wired into encounter assembly yet), so enemies sit
near base strength with no act ramp; (b) HANDOFF §5 already documents that **greed is barely punished
and a turtle is unbeatable** — the attrition thesis isn't biting; (c) it's a **single act**, so there's
no 18-act depth or escalating walls. **Recommendation:** this is the balance pass we scoped — land the
scaler calibration + wiring, then the attrition levers. Expect easy wins until then; not a new bug.

### 6. Leveling / power growth feels slow and invisible
**Observation:** one act = **+1 level**; HP stayed 36/24 across the level-up (screenshot 4 shows
3 unspent points). **Root:** `xp_per_combat 10`, `xp_curve_base 30`, `step 20` → ~3 combats per early
level; and stat points are **player-allocated**, so HP only moves if you spend on CON (the screenshots
show points unspent or spent elsewhere). Echoes the earlier "progression too slow" note that drove the
ADR-0022 cadence change. **Recommendation:** revisit the XP curve for the 18-act length, and make
level-ups feel impactful (clear "+HP/+stat" feedback when allocating). Minor; bundle into the balance
pass. Data knobs only.

### 7. Node-type monotony
Covered by #3 — the combat-6 weighting makes runs a Combat corridor. Reweighting + the new
shop/treasure kinds fix this together.

## Combat presentation (new ask) — layout + enemy targeting

**Observation (StS reference, screenshot 6):** desired combat is **horizontal** — party on the
**left**, enemies on the **right**, **hand centered at the bottom**, energy orb bottom-left, End Turn
bottom-right, draw/discard piles in the corners; each enemy shows an **HP bar + an intent icon**
(what it will do + the number).

### 8. Combat layout
**Now:** `battle_view` is the code-driven, asset-free view (ADR-0013 positionless). **Want:** the
StS spatial frame above. **Root:** presentation only — positionless combat (ADR-0013) means there's
no grid, but a **fixed left/right framing** (allies vs enemies) is a *visual* convention, not a
return to tactical positioning. → recommend a layout pass on `battle_view` (or a real combat scene).

### 9. Telegraphing WHO each enemy will attack — *the model already knows*
**Key point:** `enemy_ai.gd` already computes a **`Telegraph`** per enemy each turn — the chosen
intent **and the resolved primary target** (offensive intents currently pick the **lowest-HP**
player). The asset-free view just **doesn't render it**. So this is a display task, not new logic.

**Recommended way to indicate targeting** (with only 2 allies, legibility is easy):

1. **Intent icon above each enemy** (StS-standard): an icon for the intent kind (attack / block /
   buff / debuff) and, for attacks, the **damage number** it will deal. This already maps to the
   `Telegraph.intent`.
2. **An explicit target link** — a thin **arrow or line from the attacking enemy to the specific
   ally** it will hit, and/or a **reticle / colored outline on the targeted ally's portrait**.
   Brighten the link when you hover that enemy. With a left(allies)/right(enemies) frame, a short
   directed line reads instantly.
3. **Per-ally "incoming damage" pip** — a small red number on each ally summing the damage aimed at
   them this turn. **This is the highest-value addition mechanically:** the core balance lever is the
   **block economy** (HANDOFF §5), and block decisions are only as good as the player's visibility
   into incoming damage. Showing "you're about to take 7" on an ally makes "do I block?" a real,
   legible choice — which the attrition thesis depends on.

**Recommendation:** ship all three together (icon + value, target link/reticle, per-ally incoming
total). They reinforce each other and turn the already-computed telegraph into a readable threat the
player can plan blocks against. Optionally, a future enemy/relic could **hide** intents (fog applied
to combat) as a difficulty/identity lever — symmetric with the map fog-of-war idea.

## Suggested priority order

1. **Character-creation rework to ADR-0021** (#4) — unblocks the deferred-class arc; the build is
   currently pre-pivot.
2. **Combat targeting telegraph** (#9) — cheap (model exists), and it makes the block economy legible,
   which everything balance-related leans on.
3. **Map StS-ification** (#1–3, ADR-0023) — flip + fog + shop/treasure + reweight.
4. **Balance pass** (#5–6) — scaler calibration/wiring + XP curve, measured on the harness.
5. **Combat layout pass** (#8) — left/right framing; can ride along with #9.
