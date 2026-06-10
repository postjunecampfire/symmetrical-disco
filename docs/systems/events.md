# Events (M3 — catalogue + schema)

Status: live as of M3 ("Events → 25–30"). 28 authored events in `data/events/*.json`.

Events are the run layer's risk/reward valve (run-structure.md §6, ADR-0012).
Each event node presents 2–4 choices that usually span **safe-small / risky-big /
walk-away**. Outcomes are typed deltas applied to the `RunState` by
`EventResolver` (`src/run/event_resolver.gd`); the loader
(`src/data/content_database.gd`) validates every referenced id at load time.

## Schema

```jsonc
{
  "id": "evt_example",
  "title": "Display Title",
  "body": "Flavor text. Must match the mechanical outcomes exactly.",
  "tiers": [1, 2],                 // OPTIONAL: dungeon tiers 1..6 (ADR-0019)
                                   // this event may be drawn in. Absent/empty
                                   // = global. Explicit node payloads bypass it.
  "choices": [
    {
      "label": "Button text",
      "condition": {               // OPTIONAL gate; keys are ANDed.
        "race": "orc",             //   some member has this race id
        "class": "mage",           //   some member has this class id ("" pre-Act-3 never matches)
        "min_gold": 20,            //   run.currency >= N
        "has_curse": true,         //   true: someone is cursed / false: nobody is
        "has_relic": "oracles_eye" //   run.relics contains this relic id
      },
      "outcomes": [ { "kind": "...", "amount": 0, "id": "..." } ],
      "random_outcomes": [         // OPTIONAL weighted gamble; replaces `outcomes`.
        { "weight": 2, "outcomes": [ ... ] },
        { "weight": 1, "outcomes": [ ... ] }
      ]
    }
  ]
}
```

**Outcome kinds** (`EventOutcome.KINDS`): `heal`, `damage_party`, `add_card`,
`remove_card`, `add_relic`, `add_curse`, `remove_curse`, `add_consumable`,
`gain_gold`, `lose_gold`, `nothing`.

**Rules enforced by the loader**

- Every `add_card`/`remove_card` id must be a card; `add_relic` a relic;
  `add_curse`/`remove_curse` a curse card; `add_consumable` a consumable card.
  Gamble groups are validated identically.
- Condition keys must be in the vocabulary; `race`/`class`/`has_relic` ids must
  resolve against their registries.
- Every event must keep **at least one unconditional choice** so no party
  composition can soft-lock an event node.
- `tiers` entries must be in 1..6.

**Determinism**: gamble rolls and the event drawn at an unfixed node both seed
from `run.seed ^ hash(salt)` (event id / node id), so a given run always rolls
the same fate — no save-scumming (same scheme as `evt_cursed_shrine`'s node
pick and `RunNavigator._seeded_pick`).

**Drawing + fog**: `RunNavigator.event_for` filters the pool to events whose
`tiers` admit the current act's tier (empty band = always eligible; an
over-restrictive band that empties the pool falls back to all events). Map fog
is unchanged: event nodes render as "?" until entered (map_generator), and
`map_view._show_event` hides choices whose `condition` is unmet.

## Catalogue (28)

| id | tier band | choices (safe / risky / gated / walk) | ops used |
|---|---|---|---|
| evt_wandering_medic | global | salve / bandages / wave on | heal, add_card, nothing |
| evt_cursed_shrine | global | seize power / offer bandage / step away | add_curse+add_relic, remove_card+heal, nothing |
| evt_peddlers_cache | global | take bottles / burn charm / leave | add_consumable×2, remove_curse+damage_party, nothing |
| evt_gamblers_den | global | wager 20g `min_gold` (gamble ±) / cheat `class:rogue` / pass | gamble(gain/lose_gold), gain_gold, nothing |
| evt_mysterious_door | global | force (gamble: relic vs dmg+curse) / pick `class:rogue` / leave | gamble(add_relic / damage_party+add_curse), gain_gold+add_consumable, nothing |
| evt_blood_altar | global | bleed 5 → relic / pay 25g → draught `min_gold` / back away | damage_party+add_relic, lose_gold+add_consumable, nothing |
| evt_gravekeepers_bargain | global | rob crypt (60g + curse) / tend graves (heal) / move on | gain_gold+add_curse, heal, nothing |
| evt_hexbreakers_hut | global | rite 40g `min_gold+has_curse` / blood rite `has_curse` / buy vial `min_gold` / leave | lose_gold+remove_curse, damage_party+remove_curse, lose_gold+add_consumable, nothing |
| evt_curse_eater | global | feed curse → 50g `has_curse` / bottle drool (+curse) / leave | remove_curse+gain_gold, add_consumable+add_curse, nothing |
| evt_orcish_war_shrine | global | warcry `race:orc` → skill / loot bowls (+curse) / pass | add_card, gain_gold+add_curse, nothing |
| evt_elven_waystone | global | sing `race:elf` → skill / trace runes (gamble) / walk | add_card, gamble(heal / damage_party), nothing |
| evt_founders_banner | global | raise banner `race:human` → skill / sell cloth / leave | add_card, gain_gold, nothing |
| evt_cats_paw_idol | global | knead paw `race:cat` → skill / rub for luck (gamble) / ignore | add_card, gamble(gain/lose_gold), nothing |
| evt_proving_ground | global | ring bell `class:fighter` / train (dmg → skill) / save strength | add_consumable+heal, damage_party+add_card, nothing |
| evt_silver_tongued_stranger | global | out-charm `class:charmer` / hear pitch (gamble) / walk | gain_gold, gamble(add_consumable / lose_gold), nothing |
| evt_collapsed_tunnel | 1–3 | dig (dmg → 40g) / slip through `class:rogue` / go around | damage_party+gain_gold, gain_gold, nothing |
| evt_abandoned_shop | 1–2 | ransack (gamble: gold vs curse) / pay 25g → stock `min_gold` / leave | gamble(gain_gold / add_curse), lose_gold+add_consumable×2, nothing |
| evt_dungeon_mushrooms | 1–2 | eat (gamble: heal vs dmg) / harvest → antidote / pass | gamble(heal / damage_party), add_consumable, nothing |
| evt_moonlit_pool | 1–3 | drink (heal 8) / dive (gamble: 45g vs dmg) / stay dry | heal, gamble(gain_gold / damage_party), nothing |
| evt_tollkeepers_bridge | 1–4 | pay 15g toll `min_gold` (+heal) / shove past (dmg → 20g) / detour | lose_gold+heal, damage_party+gain_gold, nothing |
| evt_arcane_residue | 2–6 | siphon `class:mage` / scoop bare-handed (dmg) / leave | heal+add_consumable, add_consumable+damage_party, nothing |
| evt_smugglers_drop | 2–4 | take cache (+debt curse) / forge entry `has_relic:merchants_ledger` / reseal | add_consumable×2+add_curse, gain_gold, nothing |
| evt_pit_fighters_purse | 2–5 | fight `class:brawler` (45g, dmg) / bet 15g `min_gold` (gamble) / watch | gain_gold+damage_party, gamble(gain/lose_gold), nothing |
| evt_starving_prisoner | 2–5 | buy keys 30g `min_gold` → relic / pick lock `class:rogue` → relic / move on | lose_gold+add_relic, add_relic, nothing |
| evt_whispering_idol | 3–6 | listen (relic + doubt curse) / smash (gamble: gold vs curse) / leave | add_relic+add_curse, gamble(gain_gold / add_curse), nothing |
| evt_rusted_vault | 4–6 | bribe 60g `min_gold` → relic / force (gamble: 90g vs dmg 5) / leave | lose_gold+add_relic, gamble(gain_gold / damage_party), nothing |
| evt_shrine_of_ash | 4–6 | walk coals (dmg 6 → relic) / pocket gold (+wound curse) / bow out | damage_party+add_relic, gain_gold+add_curse, nothing |
| evt_echoing_stairwell | 5–6 | descend dark (gamble: 70g+scroll vs dmg+curse) / torchlight 20g `min_gold` → 50g / climb up | gamble(gain_gold+add_consumable / damage_party+add_curse), lose_gold+gain_gold, nothing |

## Curse-layer integration (ADR-0029)

- **Curses inflicted on greedy picks**: cursed_shrine, gravekeepers_bargain,
  orcish_war_shrine, abandoned_shop, whispering_idol, shrine_of_ash,
  smugglers_drop, curse_eater (bottle), mysterious_door / echoing_stairwell
  (gamble downside).
- **Curse removal as the reward**: evt_hexbreakers_hut (gold OR blood),
  evt_peddlers_cache (burn the charm).
- **Curse traded for a payoff**: evt_curse_eater (remove_curse → +50 gold).

## Design dials

- Gold sizes track the economy knobs in `battle_config.json` (combat 12 / elite
  25 / boss 40; treasure 25–60): safe gains ~20–35, risky gains 45–90, costs
  15–60 scaling with tier band.
- `damage_party` stays in the 2–6 band (member pools are small, ADR-0021 pt1);
  6 is reserved for tier 4+.
- Race/class/relic branches are flavor-gated shortcuts or extras, never the
  only path to an event's reward class, and race-basic `add_card` grants go to
  the first member (ADR-0026) so they only use NEUTRAL-tagged cards.
