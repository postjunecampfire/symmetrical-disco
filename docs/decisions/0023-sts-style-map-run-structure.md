# ADR-0023: StS-style map — bottom-up, fog-of-war, shop/treasure nodes

**Status:** Accepted (supersedes the map *presentation & node-set* of [ADR-0012](0012-run-structure-and-map.md); extends [ADR-0019](0019-eighteen-act-dungeon-progression.md), links [ADR-0022](0022-class-progression-trees-ascension.md))
**Date:** 2026-06-08
**Deciders:** Michael (owner); Claude (build partner)

## Context

[ADR-0012](0012-run-structure-and-map.md) adopted a *Slay-the-Spire*-style branching map with
card-draft rewards. The first playable (2026-06-08 playtest, `docs/progress/2026-06-08-playtest-review.md`)
exposed three gaps against the StS feel the owner wants:

1. The map renders **top→down** (start at the top, descend) — the owner wants the StS **bottom→up**
   climb (boss at the top).
2. **Every node's type is visible** from the start, so there is no exploration tension and no room
   for information to be a *reward*.
3. The node set is thin — `combat / elite / rest / event / boss` only, weighted ~60% combat — so
   runs read as a Combat corridor. There is **no shop** (buy cards/relics) and **no treasure**.

These are run-structure decisions, so they get their own ADR rather than rewriting ADR-0012.

## Decision

- **Orientation: bottom→up.** The player starts at the **bottom** row and climbs; the boss sits at the
  **top**. Model is unchanged (`MapGraph` stays a row-indexed DAG); the **view** renders row 0 at the
  bottom and the highest row at the top, with the player marker climbing.
- **Fog of war — node types are hidden until revealed.** Each node carries a `revealed` flag; an
  unrevealed node shows an **"Unknown" (`?`)** glyph instead of its type. **Baseline reveal: the next
  row only** (you can see one step ahead), keeping navigation legible. **Revealing further is a
  mechanic, not a default** — a **relic** and/or a **class-progression boon**
  ([ADR-0022](0022-class-progression-trees-ascension.md)) extends sight or reveals types ahead. This
  makes *information* a build axis (e.g. a "Cartographer" relic; a scout-leaning class capstone).
- **New node types: Shop/Merchant and Treasure.** Add `&"shop"` and `&"treasure"` node kinds.
  **Shop** spends a **currency** on cards and relics; **Treasure** grants a reward (relic / card /
  currency). This introduces a **run currency** earned from combat/events and spent at shops.
- **Node variety reweight.** Rebalance generation weights away from the combat-corridor and place
  shop/treasure as rarer, structured nodes (e.g. a shop reachable each act, treasure mid-act, a rest
  guaranteed before the boss — the `rest_before_boss` guarantee already exists). Weights stay data
  (`MapGenConfig`, per-act in `act_progression.json`).
- **Legend.** The run UI shows a legend (Unknown / Merchant / Treasure / Rest / Enemy / Elite),
  matching the reference.

## Refinement (2026-06-09): selective fog, not progressive reveal

Owner clarified the fog model from a reference map: **fog is selective, not universal.** Rather than
hiding every node and revealing row-by-row, **most nodes show their type from the start** (Enemy/Combat,
Elite, Rest, and later Shop/Treasure are all visible — "some Elites marked"), and **a subset of nodes are
flagged `hidden` and render as `?` (Unknown) until the player arrives** — "some encounters should be
blind." Implementation:

- Per-node **`hidden`** boolean (supersedes the `revealed`/next-row-baseline framing above). A hidden,
  not-yet-cleared node renders as `?`; on arrival/clear it shows its real type.
- The generator marks **all `event` nodes hidden** (events are the `?` surprises) plus a **deterministic
  ~⅓ of mid-run `combat` nodes** (so a `?` might be a fight or an event — committing blind is the
  tension). **Start row, boss, elites and rests stay visible.**
- Relic / class-boon **reveal** (above) still applies — it pre-reveals `hidden` nodes (sets `hidden=false`),
  making sight a build axis — but it is additive on top of this selective baseline, not the baseline itself.

This refinement is implemented first (the `hidden` flag + generator marking + `?` rendering); the
shop/treasure node types and currency remain separate follow-ups.

## Options considered

| Option | Verdict |
|--------|---------|
| **Bottom-up + fog-of-war + shop/treasure + reweight** | **Chosen** — matches the StS target the owner referenced; makes information and economy real build axes. |
| Keep top-down, just restyle | Rejected — owner specifically wants the bottom-up climb. |
| Full-map reveal, no fog | Rejected — removes exploration tension and the chance to make sight a reward (relic/class boon). |
| Hide everything (no next-row baseline) | Rejected — pure-blind navigation is frustrating; "see one row ahead" is the legible floor, extended by relics/boons. |
| No currency (treasure-only rewards) | Rejected — a shop needs a spend resource; currency also gives combat/events a tangible payout. |

## Consequences

- **Supersedes** the map presentation & node-set of [ADR-0012](0012-run-structure-and-map.md); the
  branching-DAG + card-draft-reward core carries forward.
- **New code:** view orientation flip; per-node `revealed` + reveal hooks (relic effect, class boon,
  next-row baseline); `shop`/`treasure` node kinds + handlers; a **shop screen** (buy list, prices);
  a **currency** on `RunState` (earn/spend); generation weighting + placement rules; legend UI; GUT
  tests for reveal logic, shop transactions, and generator placement.
- **New content:** purchasable card/relic pool + prices; treasure reward tables; reveal-granting
  relic(s); optionally a sight-leaning class boon (links [ADR-0022](0022-class-progression-trees-ascension.md)).
- **Pairs with [ADR-0019](0019-eighteen-act-dungeon-progression.md):** per-act `MapGenConfig` already
  carries type weights + `rest_before_boss`; shop/treasure weights slot in there per act.
- **Combat fog (symmetry, deferred):** the same "hide information" lever could later apply to enemy
  intents as a difficulty/identity option — noted, not decided here.

## Open questions (tunable / deferred)

- **Currency:** name, earn rates (per combat/elite/event), and price curve — playtest.
- **Reveal economy:** exactly how far the baseline sees, and what each relic/class boon grants
  (one row? whole act? types-only vs full?).
- **Shop contents:** card/relic pool, reroll?, remove-a-card service (StS has one)?
- **Placement rules:** guaranteed shop per act? treasure frequency? — tie to per-act `MapGenConfig`.
- Whether **Event ("Unknown `?`")** and the fog "Unknown" glyph should be the *same* node (StS folds
  them) or distinct.
