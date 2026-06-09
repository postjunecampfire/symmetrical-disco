# Asset sourcing — concrete needs → free packs (license-safe for Godot)

*2026-06-09. Needs enumerated from real data (`data/cards`, `data/enemies`, `data/relics`,
`data/status`, map node kinds, 6 tiers). RPG Maker official/free materials are ruled out
(EULA Art. 2: engine-locked). Policy below.*

**License policy:** prefer **CC0** (no strings). **CC-BY** allowed — requires a credit line
(add `CREDITS.md` at repo root, list author + pack + URL). **Never:** CC-BY-SA / NC, or
engine-locked store assets (RPG Maker RTP/free packs).

| # | Need | Count today | Source (license) | Notes |
|---|------|------------|------------------|-------|
| 1 | Enemy battlers | 19 (`data/enemies/`) | **Dungeon Crawl Stone Soup tiles**, OpenGameArt (CC0, 6000+ tiles incl. monsters) | Direct analogs exist for nearly the whole roster: gnoll/orc fighters (skirmisher/footman/grunt), ogre, goblin/hobgoblin (gremlin/hobgoblin), oozes, witch/necromancer (coven witch/occultist/hexer), centaur-archer/human archer (archer/marksman/sharpshooter), armored knight (iron warden/blademaster/captain). 32×32 — upscale 2–4× nearest-neighbor for the battler panel. |
| 2 | Player characters | 3 races now; class skins later (24 capstones long-term) | DCSS **player avatars + equipment layers** (CC0) | Layered base + gear lets one race base show class progression (Act-3 pick, promotions) by swapping equipment layers — matches the "become who you play" arc cheaply. |
| 3 | Card frames + rarity tiers | 1 frame × 3 rarities (0026: common/uncommon/rare) | **Kenney Boardgame Pack + UI Pack** (CC0) | Card templates included; rarity = border tint (gray/blue/gold). Vector sources, no attribution needed. |
| 4 | Card/skill art | 24 cards now, grows with skill drafts + 24 Ults | **game-icons.net** (CC BY 3.0, ~4,180 icons) | Per-concept icons: sword (strike), shield (defend/bulwark), dart+drop (venom dart), fireball (firestorm), knife fan (fan of knives), etc. SVG, recolorable per class line. **Requires credit** → CREDITS.md. |
| 5 | Status icons | 7 (`data/status/`) | game-icons.net (CC BY 3.0) | block/strength/weak/vulnerable/frail/poison/stun all have direct matches. Same credit line as #4. |
| 6 | Relic icons | 6 now (`data/relics/`), grows | game-icons.net (CC BY 3.0) | Idol/totem/satchel/core motifs all present. |
| 7 | Map node glyphs + legend | 7 kinds (combat/elite/rest/event/boss/shop/treasure) + `?` unknown | **Kenney Game Icons** (CC0) first, game-icons.net for gaps | Crossed-swords, skull (elite/boss), campfire, chest, coin/scales (shop), `?` glyph all in Kenney = zero-attribution UI layer. |
| 8 | UI chrome | panels, buttons, HP/XP bars, energy orb, end-turn | **Kenney UI Pack (+ RPG expansion)** (CC0, 430+ pieces) | Replaces the asset-free gray boxes in `battle_view`/`map_view` wholesale; 5 color themes ≈ tier theming for free. |
| 9 | Combat / map backdrops | 6 (one per tier) is enough | OpenGameArt CC0 backgrounds (e.g. Screaming Brain Studios packs); fallback: gradient + DCSS wall/floor textures | Lowest priority — a tinted gradient per tier reads fine; don't block on art. |
| 10 | SFX | card draw/shuffle/play, hit, block, poison tick, win/lose, UI clicks | **Kenney audio packs** — Casino Audio (real card flip/shuffle/slide sounds), Impact Sounds, Interface Sounds, RPG Audio (CC0) | Casino pack is the sleeper hit: actual cardstock sounds for the deck loop. |
| 11 | Music | title, map, combat, elite/boss, rest | CC0 packs: **Fantasy Music Mega Pack** (Blacis, itch), **Fantasy Game Music Tracks** (kmontesdev, itch), OGA "CC0 Music" collections; alkakrab packs (no-attribution) | Need ~5 loopable tracks; all candidates loop. Pick per-tier combat variants later from the same packs. |
| 12 | Font | UI + card text | **Kenney fonts** (CC0) or any Google Fonts OFL face | OFL is fine for embedding/distribution. |

## Working notes

- **Pipeline:** put sources in `assets/<domain>/` mirroring `data/` ids (`assets/enemies/ogre.png` ↔ `data/enemies/ogre.json` — the schema already has `art`/`sprite` fields on CardData/CharacterData). Pixel art: import filter = nearest, no mipmaps.
- **Attribution:** single `CREDITS.md` — DCSS tile authors (CC0, credit optional but courteous), game-icons.net authors (CC-BY, **required**), music per-track.
- **What stays bespoke:** nothing must be. The only thing no pack provides is per-capstone Ult art identity (24, far away) — game-icons.net recolors cover v1.
- **RPG Maker store:** only relevant if buying — packs explicitly marked "engine of your choice" are legal in Godot; "Maker only"-labelled are not. No free materials qualify.

## Suggested first pass (1 session)

1. Download DCSS tileset + Kenney UI/Game Icons/Casino Audio + one music pack.
2. Map the 19 enemy ids to DCSS sprites (one dictionary or per-file `sprite` field — field exists).
3. Wire `battle_view` ally/enemy panels + hand card frames to textures; map_view glyphs.
4. SFX hooks: card play/draw/shuffle (deck calls are single seams), damage, end-of-combat.
5. CREDITS.md.
