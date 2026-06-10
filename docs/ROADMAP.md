# Roadmap to 1.0 — from "systems complete" to shipped

*2026-06-10. Grounded in the ADR set (0001–0026, all implemented), the Asana
backlog, HANDOFF state (316 GUT green), and ADR-0008's release decision: Steam
(Windows/macOS/Linux + Steam Deck first-class) with an itch.io web demo as the
wishlist funnel.*

**Where we are:** every designed system is built and tested — 18-act descent,
solo origin → Act-2 recruit → Act-3 class pick → trees → Ascension, derived
decks from skill loadouts, per-character energy, stat_mult card ladder, shops/
treasure/gold, relics, meta-progression, StS-style UI with CC0 art and SFX, a
seeded balance harness, and 316 passing tests. What stands between this and a
shippable game is not systems: it is **content volume, balance depth,
presentation polish, and release engineering** — plus one non-negotiable:
**the game needs a name.**

---

## M1 — Systems complete ✅ (done 2026-06-10)

Everything in ADR-0001…0026. Exit criteria met: full flow plays headless and
in-editor; suite green; docs/Asana synced.

## M2 — The Tuned Descent (balance is the product)

*Goal: a skilled player's run dies for fair, legible reasons at every depth,
and the meta loop makes the next run feel different. This is the longest-lever
milestone — StS-likes live or die here.*

- Harness draft-emulation (deep-act reads currently kit-only lower bounds),
  then re-read A2–A18; fix the boss pinch (bands option B / growth knobs).
- Per-tier boss roster (5+ new bosses — everything is the Iron Warden today)
  and elite identity per tier.
- `meta_cash_out_acts` + XP curve re-derived for depth 18; retire
  `promotion_level`.
- Recruit pool meta-gating (ADR-0024 × 0018) so the meta loop feeds variety.
- Tune the five power injections (class pick, 3 tree beats, Ascension) against
  the tier walls with the harness; lockstep guard already in place.
- Docs debt: ADRs for the three 2026-06-10 owner decisions + block-economy
  resolution + C4/C5 cleanups.
- **Exit criteria:** harness shows the Goldilocks ordering at every tier;
  a full 18-act win is achievable but rare (<5% for autoplay policies at
  baseline); owner can articulate *why* each death happened.

## M3 — Content Depth (build diversity)

*Goal: 50 runs feel different. Current pool: ~60 distinct skills (121 card
files incl. upgrades/Ults), 6 relics, ~8 events, 19 enemies, 1 boss.*

| Category | Now | 1.0 target |
|---|---|---|
| Draftable skills | ~60 | **120–150** (every class line gets B/C breadth; race-flavored basics) |
| Relics | 6 | **30–40** (incl. derivation modifiers: "+1 copy of a chosen skill", reveal relics) |
| Events | ~8 | **25–30** (risk/reward, race- and class-conditional branches) |
| Enemies | 19 | **35–45** (per-tier uniques with mechanics, not just scaled variants) |
| Bosses | 1 | **6+** (one per tier minimum) |
| Statuses/keywords | 7 | +3–5 (burn? bleed? the injected-curse layer) |

- The **injected card layer** (curses/wounds/consumables — ADR-0026's open
  question): re-opens shop removal as a service and gives events teeth.
- Per-node tree `unlock_cards` so archetype/spec picks grant signature skills,
  not just stats.
- Loadout editor live-preview + editing at progression beats.
- **Exit criteria:** 3 classes × 2 archetypes feel mechanically distinct in
  blind playtests; no "autopick" flags from testers (the mage/AoE test).

## M4 — Presentation & Feel

*Goal: it reads as a finished game in a 30-second clip.*

- Combat feel: attack/hit tweens, damage numbers, death fades, screen shake,
  card hover/zoom + drag-to-play, energy orb, draw/discard pile viewers.
- Music wiring (tracks staged) + per-tier combat variants; audio bus + sliders.
- Real card art direction decision: keep CC0 icon style (cheap, coherent) vs
  commissioned art (cost, schedule) — owner call, affects budget.
- Title screen, settings (resolution/audio/keybinds), pause, run-stats screen.
- **Controller support end-to-end** (ADR-0008: Steam Deck first-class; input
  actions exist, UI focus-navigation does not) + readable at 1280×800.
- Onboarding: a guided first fight + tooltips (statuses, keywords, intents).
- Accessibility floor: font scaling, colorblind-safe statuses, reduced motion.
- **Exit criteria:** a stranger finishes Act 1 with zero verbal instruction;
  full run playable on a Deck-sized screen with controller only.

## M5 — Replayability & Meta Shine

- Unlock cadence: races → recruit candidates → skills/relics drip across the
  first ~10 runs (the ADR-0018 exit-package loop, now fed by real content).
- Post-win difficulty ladder (StS "Ascension levels" — ours needs a different
  name since Ascension is taken; "Depths"?), seeded runs, daily run.
- Run history + death recap (telemetry already captures everything needed).
- Achievements (local now, Steam later).
- **Exit criteria:** testers voluntarily start run #11.

## M6 — Release Engineering & Launch

- **Name the game.** Store page, capsule art, trailer, screenshots, tags.
- itch.io **web demo** (Acts 1–3) as the wishlist funnel (ADR-0008); export
  pipeline (Windows/macOS/Linux/HTML5) in CI with the GUT gate.
- Playtest waves: friends (M3) → closed itch (M4) → public demo (M5) →
  Steam Next Fest if timing allows; telemetry-driven balance patches between.
- Save versioning/migration policy for post-launch patches; settings persist.
- Steamworks (deferred per ADR-0008): wishlists on, achievements, cloud saves,
  Deck verification pass. Steam Direct $100.
- Localization decision (EN-only at 1.0 is defensible; string table anyway).
- QA: soak runs, resolution matrix, input matrix, fresh-machine installs.
- **Exit criteria:** release-candidate build plays 18 acts on all targets;
  store page live ≥3 months before launch for wishlists.

---

## Sequencing & rough effort

M2 → M3 overlap heavily (balance needs content; content needs balance reads) —
treat them as one alternating loop with the harness as referee. M4 starts once
M2's numbers stop moving weekly. At the current owner+agent cadence:

| Milestone | Calendar guess |
|---|---|
| M2 Tuned Descent | 2–4 weeks of sessions |
| M3 Content Depth | 4–8 weeks (largest authoring volume; harness-checked) |
| M4 Presentation | 3–6 weeks (art-direction call is the swing factor) |
| M5 Meta Shine | 1–2 weeks |
| M6 Release Eng | 2–4 weeks + the fixed ≥3-month store-page lead time |

**Realistic 1.0 window: ~4–6 months**, dominated by content authoring, the
art decision, and the deliberately long Steam wishlist runway. A public itch
demo is reachable in **4–6 weeks** (end of M2 + thin M4 slice) and is the
single best forcing function for everything after it.

## Top risks

1. **Balance at depth** — 18 acts is 3× the genre norm; if Acts 7–18 feel like
   stat-check repetition, the back half needs mechanical novelty per tier
   (tier-gate modifiers were deferred in ADR-0019 — likely needed at M3).
2. **Losing must be fun** — the design says runs are near-unwinnable; the meta
   drip (M5) carries that or the game feels punitive. Validate early in
   playtest wave 1.
3. **Art identity** — CC0 mosaic is coherent enough for a demo, but the Steam
   capsule/trailer needs a distinct look; decide by end of M3.
4. **The name** — blocks the store page, which anchors the whole M6 timeline.
