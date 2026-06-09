# Class Progression — trees, capstones, Ascension

*Design spec for the three class progression lines. Authored 2026-06-08. Pairs with
[ADR-0022](../decisions/0022-class-progression-trees-ascension.md) (the decision),
[ADR-0021](../decisions/0021-deferred-class-race-origin.md) (deferred class / cadence),
[ADR-0020](../decisions/0020-card-scaling-ladder.md) (card scaling), and
[ADR-0019](../decisions/0019-eighteen-act-dungeon-progression.md) (the 18-act curve).
Visual companion: [`class-progression-matrix.html`](class-progression-matrix.html).*

## 1. Shape at a glance

Three lines — **Fighter** (STR), **Mage** (INT), **Rogue** (DEX). Before Act 3 you are the
race-only "normal person" ([ADR-0021](../decisions/0021-deferred-class-race-origin.md));
the flavor name for that pre-class state is **Journeyman / Acolyte / Pickpocket**.

The five progression beats land at the **end of Acts 3, 6, 9, 12, 15**, each feeding the
tier wall just after it ([ADR-0019](../decisions/0019-eighteen-act-dungeon-progression.md)).
The earlier design put the first *choice* at Act 9 (halfway) and felt slow; this moves the
branching up so a real fork lands at every beat through Act 12, and reserves Act 15 for a
universal power payoff.

| End of act | Beat | Choice? | Tree width | Then faces |
|---|---|---|---|---|
| **Act 3** | **Class** — pick Fighter / Mage / Rogue | pick 1 of 3 lines | 1 | Act 4 wall (tier 2) |
| **Act 6** | **Archetype** | **1 of 2** | 2 | Act 7 wall (tier 3) |
| **Act 9** | **Specialize** | **1 of 2** | 4 | Act 10 wall (tier 4) |
| **Act 12** | **Capstone** | **1 of 2** | 8 | Act 13 wall (tier 5) |
| **Act 15** | **Ascension** — *Ascended X* | no branch (universal) | 8 | Act 16 wall (tier 6) |

Within a line the choice tree is a binary tree **1 → 2 → 4 → 8** across Acts 3/6/9/12.
Act 15 is **not** a branch: whatever capstone you reached *ascends in place*.

## 2. Ascension (Act 15)

At the end of Act 15 your Act-12 capstone becomes **"Ascended &lt;Capstone&gt;"**. It is a flat
power step, identical in shape for every class:

1. **Card boost — flat bump to every card in your run deck.** Implemented as a `stat_mult`
   step on owned cards per [ADR-0020](../decisions/0020-card-scaling-ladder.md) (the same
   field that drives flat → hybrid → multiplier), so it compounds with the attack stat and
   the Act-12 capstone rather than bolting on a parallel system. Magnitude is a **data knob**
   (see §5).
2. **Ult — one signature card added to the deck.** Each of the 24 capstones has its own Ult
   (§4). The Ult is the line's "big button": high-impact, low-frequency. Whether it is a fixed
   card or also scales with the Ascension boost is an open question (§5).

The display title flexes per line so "Ascended X" reads naturally: **Ascended Warlord**
(Fighter), **Ascended Sage** (Mage), **Ascended Blade** (Rogue) — cosmetic; the mechanical
identity is the underlying capstone.

## 3. The trees

Notation: **Act 3 → Act 6 → Act 9 → Act 12 capstone** *(⚡ Ascension Ult)*.

### Fighter (STR) — raw physical power: block, burst, bodies in the way

```
Fighter
├─ Brigand  (aggression: raw offense)
│  ├─ Warrior   (sustained heavy hitter)
│  │  ├─ Warlord       — commander, party buffs        ⚡ Banner of War
│  │  └─ Reaver        — relentless multi-hit           ⚡ Endless Onslaught
│  └─ Berserker (glass-cannon crits)
│     ├─ Ravager       — escalating crit ferocity       ⚡ Bloodlust
│     └─ Bloodletter   — lifesteal + poison-on-hit       ⚡ Exsanguinate
└─ Knight   (defense: armor & block)
   ├─ Cavalier (mobile mounted fighter)
   │  ├─ Paladin       — balanced holy knight            ⚡ Aegis of Dawn
   │  └─ Great Knight  — heavy armored cavalry           ⚡ Cavalry Charge
   └─ General  (immovable wall)
      ├─ Marshal       — team aura, shared block         ⚡ Iron Wall
      └─ Sentinel      — unbreakable solo tank           ⚡ Last Bastion
```

### Mage (INT) — schools of magic: elements, the dead, forbidden curses

```
Mage
├─ Elementalist (raw forces of nature)
│  ├─ Pyromancer (fire & burn DoT)
│  │  ├─ Conflagrator  — spreading inferno / DoT king    ⚡ Firestorm
│  │  └─ Magmancer     — eruption burst nuke             ⚡ Eruption
│  └─ Cryomancer (ice & storm control)
│     ├─ Frostbinder   — freeze-lock hard control        ⚡ Absolute Zero
│     └─ Tempest Sage  — chain lightning multi-hit       ⚡ Thunderstorm
└─ Sorcerer     (forbidden dark arts)
   ├─ Necromancer (summons the undead)
   │  ├─ Lich          — immortal undead horde           ⚡ Army of the Dead
   │  └─ Soulreaver    — life-drain magic                ⚡ Soul Harvest
   └─ Warlock     (curses, blood, poison)
      ├─ Plaguebringer — poison/disease, ignores block   ⚡ Pandemic
      └─ Hexblade      — curse-amplified strikes         ⚡ Doom
```

### Rogue (DEX) — finesse: the clean kill, the dodge, the poisoned blade

```
Rogue
├─ Assassin (lethality: the kill)
│  ├─ Stalker (stealth first-strike burst)
│  │  ├─ Nightblade    — one-shot executioner            ⚡ Death Mark
│  │  └─ Reaper        — crit-chain escalation           ⚡ Thousand Cuts
│  └─ Duelist (finesse parry-riposte)
│     ├─ Bladedancer   — counter / riposte king          ⚡ Riposte Stance
│     └─ Phantom       — untouchable dodge-counter       ⚡ Vanish
└─ Thief    (cunning: trickery & toxins)
   ├─ Poisoner (stacking toxins / DoT)
   │  ├─ Venomancer    — block-ignoring poison stacks    ⚡ Toxic Bloom
   │  └─ Apothecary    — debuff bombs & utility          ⚡ Alchemical Bomb
   └─ Shadow   (evasion & mobility)
      ├─ Shade         — pure evasion / vanish           ⚡ Smoke & Mirrors
      └─ Windrunner    — multi-action mobility           ⚡ Flurry
```

## 4. Capstones & Ults (flat reference)

24 capstones, one Ult each. Roles intentionally lean on existing combat mechanics
(block = DEX, poison ignores block, Vulnerable/Frail, crits, summons — see
[`act-progression.md`](act-progression.md) and the enemy/status systems).

| Line | Archetype | Specialization | Capstone | Ult | Mechanical hook |
|---|---|---|---|---|---|
| Fighter | Brigand | Warrior | **Warlord** | Banner of War | party-wide Strength + block |
| Fighter | Brigand | Warrior | **Reaver** | Endless Onslaught | hit all enemies / extra attacks |
| Fighter | Brigand | Berserker | **Ravager** | Bloodlust | crit scales with kills |
| Fighter | Brigand | Berserker | **Bloodletter** | Exsanguinate | heavy lifesteal + poison all |
| Fighter | Knight | Cavalier | **Paladin** | Aegis of Dawn | party heal + block, smite |
| Fighter | Knight | Cavalier | **Great Knight** | Cavalry Charge | unblockable trample, hits all |
| Fighter | Knight | General | **Marshal** | Iron Wall | team gains big block, taunt |
| Fighter | Knight | General | **Sentinel** | Last Bastion | unkillable 1 turn, retaliate |
| Mage | Elementalist | Pyromancer | **Conflagrator** | Firestorm | burn all, spreads |
| Mage | Elementalist | Pyromancer | **Magmancer** | Eruption | massive single-target nuke |
| Mage | Elementalist | Cryomancer | **Frostbinder** | Absolute Zero | freeze / stun all |
| Mage | Elementalist | Cryomancer | **Tempest Sage** | Thunderstorm | chain lightning, bounces |
| Mage | Sorcerer | Necromancer | **Lich** | Army of the Dead | summon undead horde |
| Mage | Sorcerer | Necromancer | **Soulreaver** | Soul Harvest | drain all → heal/buff |
| Mage | Sorcerer | Warlock | **Plaguebringer** | Pandemic | max poison all, ignores block |
| Mage | Sorcerer | Warlock | **Hexblade** | Doom | mark: escalating curse damage |
| Rogue | Assassin | Stalker | **Nightblade** | Death Mark | execute below HP threshold |
| Rogue | Assassin | Stalker | **Reaper** | Thousand Cuts | multi-hit crit barrage |
| Rogue | Assassin | Duelist | **Bladedancer** | Riposte Stance | counter all attacks this turn |
| Rogue | Assassin | Duelist | **Phantom** | Vanish | untargetable + free crit |
| Rogue | Thief | Poisoner | **Venomancer** | Toxic Bloom | max poison all, ignores block |
| Rogue | Thief | Poisoner | **Apothecary** | Alchemical Bomb | AoE Vulnerable + Frail |
| Rogue | Thief | Shadow | **Shade** | Smoke & Mirrors | full evasion + reposition |
| Rogue | Thief | Shadow | **Windrunner** | Flurry | extra actions / free cards |

> Note: **Plaguebringer** (Mage) and **Venomancer** (Rogue) both terminate in poison that
> ignores block — deliberate. They are the two lines' answers to the turtle problem
> (see HANDOFF §5 / the poison-ignores-block decision); they should *feel* different
> (Plaguebringer = wide disease; Venomancer = stacked single-target toxin).

## 5. Data model & knobs

Carries forward the [ADR-0021](../decisions/0021-deferred-class-race-origin.md) split
(races = base templates, classes = overlays) and the
[ADR-0020](../decisions/0020-card-scaling-ladder.md) `stat_mult` ladder.

- **Progression as data.** Each line is a small tree keyed by act boundary. Candidate shape:
  a `progression/<line>.json` (or extend `classes/*.json`) where every node carries
  `{ id, name, tier_act, stat_bonus, unlock_card_ids, parent }`, and each Act-12 capstone
  also carries `{ ult_card_id, ascension_stat_mult }`. The existing promotion plumbing
  (`RunController.eligible_promotions / apply_promotion`, [ADR-0015](../decisions/0015-classes-races-leveling.md))
  is the natural host — generalize "pick 1 of 2" to walk this tree by act.
- **Ascension** is a sixth code path, not a branch: at the Act-15 boundary, apply
  `ascension_stat_mult` to every owned card and append `ult_card_id` to `run_deck`.
- **Ults** are ordinary card resources with a high cost / scarce draw shape (the line's
  "big button"); they live in `data/cards/` like any other card.

### Open knobs (owner's call / playtest)

- **Ascension card-boost magnitude** — the flat `stat_mult` step applied to all cards.
- **Ult scaling** — fixed card, or does it also take the Ascension boost / scale with attack stat?
- **Eligibility** — act/tier boundary vs an accrued level gate (revisit `promotion_level`,
  already flagged in [ADR-0021](../decisions/0021-deferred-class-race-origin.md)).
- **Stat bonuses per node** — the bump each archetype/specialize/capstone pick grants.
- **Re-pick / lock-in** — is a branch choice permanent for the run (assumed yes)?
- Whether **Act 6 (archetype)** should ever offer a no-choice "formalize" fallback (currently always a choice).
