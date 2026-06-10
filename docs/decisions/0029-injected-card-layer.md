# ADR-0029: Injected non-skill card layer — curses & consumables

**Status:** Accepted — *decision made by agent, owner to ratify.* Resolves the **"Injected non-skill card layer"** open question of [ADR-0026](0026-derived-decks-from-skill-loadouts.md) (including its sub-question: do injected cards count toward the 20-card minimum?). Implements the "earned floor reduction" note of the same ADR.
**Date:** 2026-06-10
**Deciders:** Claude (build partner, on delegated authority); Michael (owner) to ratify
**Relates to:** [ADR-0026](0026-derived-decks-from-skill-loadouts.md) (derived decks, the open question this answers), [ADR-0023](0023-sts-style-map-run-structure.md) (shops/treasure — where removal and items are sold), [ADR-0006](0006-draw-as-cooldown-model.md) (draw economy the floor protects), [ADR-0003](0003-data-driven-content-architecture.md) (all knobs in data).

## Context

ADR-0026 made every card a projection of a skill — clean but monochrome: nothing external can touch the deck, so enemies/events have no way to *pollute* it, shops have nothing deck-shaped to sell, and the StS deck-management pressure (and its removal economy) is absent. The ADR explicitly deferred a candidate fix: a card layer injected into the derived deck *after* derivation, outside the loadout — curses forced in by the world, consumable item cards found/bought — plus an earned path (relics) back toward smaller decks. The open sub-question: do injected cards count toward the 20-card auto-fill floor (junk displaces fill) or sit on top (deck swells)?

## Decision

Two injected card kinds, with **opposite floor semantics**, plus a relic-gated floor reduction:

### 1. Curses COUNT toward the floor (displacement below it, swell above it)

A curse is a card forced into a member's deck by enemies (`inflict_curse` intents) or events (`add_curse` outcomes). It is stored **per member** (`RunState.member_curses`) — infliction targets the member who was hit, and removal is targeted too — and rides *that member's* derived deck every fight until removed.

- **Below the floor** (derived deck < 20): each curse **displaces one Strike/Defend auto-fill card** — the deck stays at the floor, junk replaces basics, and the Strike/Defend alternation is preserved for the remaining fill.
- **At/above the floor:** curses add on top — the deck swells past the cap, StS-style.
- **Why:** stable draw economy (a curse never shrinks nor pads your cycle below the floor), legible cost (the junk visibly *replaces your basics*), and **removal restores a basic** — which is exactly what makes curse removal a service worth paying for.
- Curses are **dead draws by default**: keyword `unplayable` (cost shown as "—"; `CardPlay` rejects them before anything is spent; the hand UI renders them dim and disabled) unless the curse itself says otherwise. Active downsides ride a `on_draw_damage` field (when drawn, the drawing unit takes N damage — Hex Mark, Vertigo).
- **Removal returns ONLY for curses** (the [ADR-0023] "no card removal" stance refined, as foreshadowed there): the shop sells a "Remove a curse" service (`shop_price_curse_removal`, act-scaled like every price); the `remove_curse` event outcome exists for event-flavored cleansing. Loadout deactivation remains the free knob for *skills*.
- In combat, an inflicted curse lands in the target's **discard pile immediately** (it joins this fight's cycle) and persists onto the member after the fight (`finish_combat` harvests `battle.inflicted_curses`).

### 2. Consumables inject ON TOP (never count toward the floor)

A consumable is a run-level **party inventory** item (`RunState.consumables`) — bought at shops (1–2 on the shelf per stock, `shop_price_consumable`), rolled by treasure nodes, or granted by events (`add_consumable`). At deck assembly the whole inventory injects **on top of the floor** into the **first member's** deck (consumables are neutral; first-member attribution mirrors party-level relic crediting).

- Consumables are **playable cards with `exhaust`**; costs 0–1; **flat effects** (`stat_mult: 0` on damage/block — they're items, not techniques).
- Playing one **CONSUMES it from the inventory** (`battle.consumed_items` → removed by `finish_combat`); an **unplayed** consumable persists to future combats.
- On top — never toward the floor — so items never crowd out the draw economy's basics and stockpiling items can't substitute for skills.

### 3. Earned floor reduction (the ADR-0026 note, now real)

A relic effect **`floor_reduction`** (trigger `passive`, consumed at deck *derivation*, not in combat): the run's total reduction lowers the auto-fill floor, clamped at **`derived_deck_floor_min` (12)**. One rare relic ships as proof — **Travel Light** (−4) — and the relic expansion pass will add more. This is the gated path back to the small-deck reliability archetype.

### Schema conventions

- `CardData.card_kind: "skill" | "curse" | "consumable"` (default `skill`) is the single discriminator; rarity stays untouched. Anything that is not a `skill` is **excluded from draft/shop/treasure reward pools** (`CardReward.eligible_pool`, alongside `signature` and `_plus` exclusions) — curses can never be drafted, items are bought/found, never drafted.
- `unplayable` joins `exhaust`/`return` as a recognized keyword (it was already reserved in data-schemas §3).
- New effect types: `inflict_curse` (`params.card_id`, validated to name a real curse), `cleanse` (`params.statuses`), `gain_gold` (banked on the battle, credited post-fight).
- New event outcome kinds: `add_curse` / `remove_curse` (empty id = first curse found) / `add_consumable`, validated like `add_card`.
- Knobs on BattleConfig: `derived_deck_floor_min` (12), `shop_price_consumable` (40), `shop_price_curse_removal` (75).

## Options considered

| Option | Verdict |
|---|---|
| **Curses count toward the floor (displace fill below, swell above)** | **Chosen** — stable draw economy, legible cost, removal restores a basic (gives the removal service real value). |
| Curses always on top (pure swell) | Rejected — below the floor a curse would *dilute padding with more padding*; early curses would be nearly free, and removal correspondingly worthless early. |
| Curses shrink effective skill density (replace skill copies) | Rejected — punishes the loadout the player curated; the floor basics are the right sacrificial layer. |
| Consumables count toward the floor | Rejected — stockpiled items would displace basics and act as free deck-thinning, competing with the relic-gated floor reduction. |
| Party-level curse pool (not per-member) | Rejected — infliction comes from targeted enemy intents; per-member lists keep removal targeted and the blame legible. |
| Per-member consumable inventories | Rejected — items are party gear (StS potions); one inventory, injected into the first member's deck, is the simplest v1 (revisit if the second member never sees items in play). |

## Consequences

- **RunState** gains `member_curses` (per member) + `consumables` (party), both in the save round-trip; `curses_of()` accessor.
- **`SkillLoadout.derive_deck(loadout, db, curses, consumables, floor_reduction)`** — skills → curses → fill to `effective_floor` → consumables; old callers unaffected (defaults).
- **Combat → run seam:** `BattleState.inflicted_curses` / `consumed_items` / `gold_found` are harvested by `RunController.finish_combat` (the battle layer stays run-agnostic, like `charm_executes`).
- **Shop** (ADR-0023) gains consumable stock + the curse-removal service; **treasure** can roll a consumable.
- **Content:** 8 curses (wound, doubt, fatigue, burden, cowardice, debt + active Hex Mark, Vertigo), 10 consumables (healing_draught, fire_bomb, smoke_vial, antidote, whetstone_oil, barrier_scroll, energy_philter, throwing_knife, lucky_coin, second_wind), relic Travel Light; hexer + coven_witch gained `inflict_curse` intents; evt_cursed_shrine now actually curses; evt_peddlers_cache demonstrates `add_consumable`/`remove_curse`.
- **Risk:** curse swell above the floor is unbounded in principle (repeated elite hexers); monitor — a cap or escalating-removal pricing is the prepared fallback. The first-member consumable attribution is provisional until items get a holder/targeting UI.

## Open questions (deferred)

- Derivation **modifiers** from ADR-0026's list ("+1 copy of a chosen skill", "Uncommons count as Common") — still future relic work.
- Whether shop curse removal should be once-per-shop (StS) instead of repeatable-while-gold-lasts (current).
- Curse variety beyond dead-draw + on-draw damage (e.g. "while in hand" auras) once a cheap hook exists.
