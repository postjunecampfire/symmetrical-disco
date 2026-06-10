# DCC Adaptation — Carl & Donut as Brawler & Charmer

*Design spec for adapting the Dungeon Crawler Carl StS mod into the Unnamed Game.
Authored 2026-06-09. Pairs with [ADR-0028](../decisions/0028-dcc-carl-donut-class-lines.md)
(the decision) and [`dcc-integration-roadmap.md`](dcc-integration-roadmap.md) (the phases).
Source repo: `~/Claude/Crawl/Crawler` (CLAUDE.md, docs/planning/CARL_DESIGN.md v5,
DONUT_CHARM_DESIGN.md, DONUT_FAME_DESIGN.md, DONUT_MAGIC_MISSILE_REDESIGN.md).*

## 1. What the source material is

A total-conversion StS mod with two characters and five archetype pillars:

| Character | Pillars | Signature systems |
|---|---|---|
| **Carl** (Brawler/Demolitions, 65 cards) | BOMB (AOE with self-damage tax), BRAWLER (multi-hit STR, block→damage), SURVIVOR (sustain, thresholds, Exhaust payoffs) | Infusion (absorb bomb tax), Bomber Studio (double bomb damage), Counter, Smush (on-kill permanent scaling) |
| **Donut** (Charm/Dex/Fame, 53 cards) | SPELLCASTER (Charm stacking + Magic Missile tokens), EVASION (Dex/block), CELEBRITY (Fame) | Charm (per-enemy stacking debuff → threshold procs → execute at max HP), Enthrall (skip enemy attacks), Fame (per-act 0–50 counter → milestones → Sponsor Boxes), Magic Missile (0-cost unblockable tokens, Infinite Blades model) |

## 2. Adaptation principles

1. **Race + class decomposition, not presets** (owner's call, ADR-0028). Carl = Human + **Brawler** line; Donut = **Cat** race + **Charmer** line. Both books-classes appear as Act-12 capstones.
2. **Data first, engine second.** Phase 0 ships only what the six effect types (`damage`, `block`, `heal`, `apply_status`, `draw`, `gain_energy`) and current statuses express. Every mechanic that needs a new effect kind or hook is explicitly deferred and listed in §5 — never approximated in code-adjacent hacks.
3. **One target set per card** (no per-effect target override, ADR-0013): the engine cannot express "damage the enemy AND block yourself" on one card. Cards were re-cut around this constraint (e.g. Gut Check is deferred; bombs lost their self-damage tax and carry `exhaust` as the interim cost).
4. **Carry the playtest record.** The mod's balance lessons (§6) directly shaped the numbers.

## 3. The class lines

Both trees follow the existing 14-node binary shape (archetype @6 → specialization @9 → capstone @12, ult per capstone, `ascension_stat_mult: 0.5`). Data: `data/progression/brawler.json`, `data/progression/charmer.json`.

### Brawler (STR) — Carl: bombs, fists, refusing to die

```
Brawler
├─ Demolitionist (bombs)
│  ├─ Sapper      (traps/control)
│  │  ├─ Trapmaster            ⚡ Hidden Pit        — AOE damage + stun all
│  │  └─ Engineer              ⚡ Crafting Table    — draw 3 + 2 energy
│  └─ Anarchist   (big AOE)
│     ├─ Compensated Anarchist ⚡ Collateral Damage — huge scaling AOE
│     └─ Firebrand             ⚡ Inferno Payload   — AOE + Vulnerable setup
└─ Pugilist (fists/survival)
   ├─ Bruiser     (burst offense)
   │  ├─ Juggernaut            ⚡ Haymaker          — 6 dmg @ 3.0× STR
   │  └─ Prizefighter          ⚡ Combination       — 4 × 3 dmg multi-hit
   └─ Survivor    (sustain — CON-leaning stat bonuses)
      ├─ Unbreakable           ⚡ You Will Not Break Me — 18 Block + 3 STR
      └─ Royal Bodyguard       ⚡ Shield the Princess   — party 12 Block + 6 heal
```

### Charmer (INT) — Donut: charm, missiles, celebrity

```
Charmer
├─ Enchanter (charm/debuffs)
│  ├─ Beguiler (control)
│  │  ├─ Heartbreaker          ⚡ Coup de Grace     — 6 dmg @ 3.0× INT
│  │  └─ Puppeteer             ⚡ Mass Enthrall     — AOE stun + Weak
│  └─ Idol     (fame/party)
│     ├─ Superstar             ⚡ Standing Ovation  — party Block + Strength
│     └─ Former Child Actor    ⚡ Encore            — 3 energy + 3 cards
└─ Evoker (magic missiles)
   ├─ Spellslinger (missile quantity)
   │  ├─ Barrage Master        ⚡ Missile Storm     — 3×3 AOE multi-hit
   │  └─ Spellweaver           ⚡ Spell Weave       — draw 4 + 4 Block
   └─ Arcanist (big spells)
      ├─ Grand Incantatrix     ⚡ Grand Incantation Prime — AOE dmg + Vuln + Weak
      └─ Princess              ⚡ Royal Decree      — AOE Weak + Vuln + Stun
```

**Royal Bodyguard is the thesis of this adaptation:** Carl protecting Donut was pure flavor in solo StS; in a party-of-2 game `all_allies` Block/heal makes it a real archetype. Same for Idol's party buffs — Fame payoffs the mod could never express.

## 4. Shipped Phase-0 data (inert until the class pick is extended)

| File(s) | Contents |
|---|---|
| `data/characters/brawler.json` / `charmer.json` | Class overlays: Brawler STR+2/CON+1 `attack_stat: str`; Charmer INT+2/DEX+1 `attack_stat: int`. 4-card starting kits. |
| `data/races/cat.json` + `data/cards/pounce.json` | Cat: STR 1 / DEX 6 / CON 2 / INT 5 (14-point template, matches Elf/Orc). Pounce: 1c, 3 dmg + draw 1, neutral. |
| `data/cards/*` (47 new) | 12 Brawler cards + 8 ults + 4 upgrades; 11 Charmer cards + 8 ults + 4 upgrades. All within the six-effect registry. |
| `data/status/charm.json` | `intensity`, no decay. **Inert groundwork** — no card references it until Phase 2. |
| `data/relics/*` (4) | Fan Mail (combat_start 4 Block), Celebrity Endorsement (combat_start 2 STR), Heart-Covered Boxers (passive +8 max HP), Diamond Sponsor (turn_start +1 energy). First Sponsor-Box tier ports. |

Key card adaptations and what changed:

| Card | Source | Adaptation | Fidelity loss (deferred fix) |
|---|---|---|---|
| Cobbled Bomb | 8 AOE, take 3 | 1c AOE 4 @0.6, **Exhaust** | self-damage tax → Phase 2 `self_damage` |
| Cheap Shot | 0c, 4 dmg + 1 Vuln | identical (3 dmg) | — |
| Smoke Bomb / Firecracker | utility / safe AOE | identical | — |
| Xistera | 3×3 multi-hit STR | three `damage` effects @0.4 | per-hit scaling kept ✓ |
| Smush | on-Fatal permanent +2 | **not shipped** | Phase 4 on-fatal hook |
| Haymaker | dmg = current Block | ult version is a flat 3.0× nuke | Phase 4 block-read effect |
| Tripwire | Block + intent-conditional | **not shipped** | Phase 4 intent-read |
| Magic Missile | generated 0-cost unblockable token | 0c common, 3 dmg @0.5, Exhaust | tokens/unblockable → Phase 3 |
| Hex | Vuln + Charm | Vuln only (2 dmg rider) | Charm stacks → Phase 2 |
| Enthrall | skip next attack (intent override) | Stun 1 + Weak 2, Exhaust | re-arm aura → Phase 4 |
| Coup de Grace | dmg = target's Charm, removes it | ult: 6 dmg @3.0 | Charm cash-in → Phase 2 |
| Incantation / Grand Incantation | Charm auras | Weak/Vuln AOE skills | aura powers → Phase 3 |

## 5. Mechanic mapping — what needs engine work

| DCC mechanic | Target seam in this engine | Phase |
|---|---|---|
| **Charm** (stack → 10-threshold Vuln+Weak proc → execute at max HP) | status hook on `apply_status` + threshold check in `BattleContext`; execute = HP-loss bypassing block. New effect kind `charm_damage` (charm = unblocked damage). | 2 |
| **Bomb self-damage tax** (block absorbs, STR doesn't amplify) | `self_damage` effect kind (applies to caster regardless of card target) — also unlocks Gut Check-style dmg+block cards via the same "caster-side effect" notion. | 2 |
| **Fame** (per-act 0–50 counter, milestones, end-of-act Sponsor Box tiers) | `RunState` counter + act-boundary hook (`_resolve_act_end` chain); Sponsor Box = tiered relic reward at the boss chest, reuses the relic registry. Telemetry parallels the mod's `RunMetricsLogger` (this repo already has `telemetry_logger.gd` — same per-combat snapshot pattern). | 3 |
| **Magic Missile tokens** (Infinite Blades engine) | `add_card` effect kind (insert a generated card into hand/discard); SpellWeave/MissileBarrage become real. Mod lesson: keep scaling **linear and flat** (the compounding Claw-counter version was deleted for a reason). | 3 |
| **Unblockable** | damage flag param read by block decrement | 3 (watch closely) |
| **Counter / intent-reading / block-scaling / on-fatal scaling / Enthrall re-arm** | conditional-effect framework (`conditional` was already on the deferred registry list in data-schemas §2.3) | 4 |
| **Bomber Studio / Infusion / aura powers** | a Powers layer (persistent combat effects beyond statuses) — biggest single engine ask; decide vs. cutting after Phase 2/3 playtests | 4 |

## 6. Balance lessons imported from the mod's playtests

1. **Dead conditional cards need mechanic rework, not number buffs** — trap cards at <15% pick rate until the player got agency (Enthrall rework). Applied: no shipped card has a condition the player can't control.
2. **Uncapped self-scaling breaks** (Smush + Duplicator past +60 damage) — any Phase-4 scaling card gets a hard cap from day one.
3. **Permanent stats belong on rare/expensive cards, not Skills** (the Footwork/SteadyAim snowball). Applied: War Gauntlet is the only STR-gain card, rare, 2c, Exhaust.
4. **Block-centric is safer than damage-centric** for tuning; Carl's 25% win rate vs Donut's 50% came from sustain gaps. Applied: Survivor branch is CON-weighted, Trollskin Wrap ships in the pool.
5. **AOE ceilings compound with damage doublers** (Bomber Studio + Scorched Earth = 48 AOE). Applied: AOE cards use `stat_mult` 0.6–0.7 like Frost Nova, and the doubling power itself is deferred to Phase 4 pending the Powers-layer decision.

## 7. Open questions (owner's call)

- Class-pick pacing: five lines at Act 3 — show all five, or gate Brawler/Charmer behind a meta unlock (mirrors the mod's character-unlock feel)?
- Charm execute threshold: mod ended at **max HP** (changed from current HP, 2026-05-29, because converging from both ends executed bosses at half health). Same rule here, or tune for 2-member parties?
- Theme: adopt DCC dungeon flavor wholesale (AI announcer events, loot boxes) or keep these mechanics under the game's own skin? Phase 5 assumes the latter by default — names are changeable, ids are permanent.
