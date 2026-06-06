# Classic Turn-Based RPGs: Games, Languages & Infrastructure Survey

*A survey of games matching the pattern you described — turn-based combat, sometimes side-scrolling presentation, often handheld, a party of 3–4 with discrete battle states, and a larger navigable world map. For each, this documents the implementation language and the scaffolding/infrastructure that had to exist underneath. It's organized into three eras so we can talk through what's most realistic to build today.*

---

## How to read this

Every game in this family is really **three machines stitched together**: a *world/exploration* layer, a *battle* layer, and a *meta/progression* layer that persists between them. The "scaffolding" column below is the connective tissue — the systems that aren't gameplay but without which gameplay can't exist (state management, save serialization, data tables, scripting, asset pipeline). The pattern is remarkably consistent across forty years; only the *language and tooling* change.

---

## Era 1 — Original cartridge games (hand-built, close to the metal)

These shipped with **no engine**. Every subsystem listed was written by the team, usually in assembly, with data baked into the ROM.

### Final Fantasy (NES, 1987) — and the SNES/PS1 line
- **Language:** 6502 assembly on NES (the NES CPU is a 6502 variant); the SNES entries (FF IV–VI) are **65c816 assembly** with **SPC700 assembly** for the sound chip; FF VII (PS1) moved to C/C++ with assembly for performance-critical paths.
- **Scaffolding it had to build by hand:**
  - A **top-level state machine** switching world map ↔ town/field ↔ menu ↔ battle.
  - A **tile map renderer** and scrolling system driven by the console's hardware tile/sprite registers.
  - A **turn/ATB scheduler** (ATB arrives in FF IV) advancing per-actor gauges.
  - **Data tables in ROM** for monsters, spells, items, and the damage formula — the original data-driven design, just compiled in.
  - **Battery-backed SRAM save** routines (manual serialization of party/inventory/flags).
  - A **text/dialogue engine** with a compact script format (tile-indexed fonts, control codes).

### Fire Emblem: The Sacred Stones (GBA, 2004)
- **Language:** primarily **ARM/Thumb assembly with C** (the GBA toolchain supported C; Nintendo's RPG teams mixed both). Community work today happens through the **disassembly** plus C "hacking" frameworks.
- **Scaffolding:**
  - A **grid/tile map model** with terrain costs and a coordinate↔screen mapping.
  - **Pathfinding + reachable-tile flood fill** for movement and threat ranges.
  - A **battle FSM** for player-phase / enemy-phase turn flow.
  - **Utility-scoring enemy AI** parameterized by per-unit data flags.
  - **Event/trigger scripting** for map objectives, reinforcements, and dialogue.
  - **Growth-rate and class tables** in ROM; SRAM save with permadeath bookkeeping.

### Pokémon Red/Blue (Game Boy, 1996) → Emerald (GBA, 2004)
- **Language:** **Z80-style (Sharp LR35902) assembly** on Game Boy; the GBA generation (Ruby/Sapphire/Emerald) is **C with assembly**. This is unusually well-documented because of the **PRET decompilation projects** (`pokered`, `pokecrystal` in assembly; `pokeemerald`/`pokeruby` in hand-written C) that rebuild byte-identical ROMs from source.
- **Scaffolding (visible directly in the decomp):**
  - **Overworld engine:** tile-based movement, collision, warps, NPC scripts.
  - **Encounter system:** per-zone encounter tables + the transition into battle.
  - **Turn-based battle engine:** move/turn ordering by Speed, type-effectiveness matrix, status effects.
  - **A bytecode scripting VM** for events/dialogue (the games ship a tiny interpreter and the "story" is data for it).
  - **Save serialization** to cartridge SRAM with versioned sections and checksums.
  - **Data as tables:** species/base stats/moves/items are all structured data the code reads.

> **Why the decompilations matter for you:** `pokeemerald` is the single clearest real-world reference for how one of these games is actually structured — a complete, buildable C codebase showing the overworld engine, battle engine, scripting VM, and save system laid out as files you can read.

### Chrono Trigger (SNES, 1995)
- **Language:** **65c816 assembly** (game logic) + **SPC700 assembly** (audio). Notable for an exceptionally efficient custom **event-scripting system** that drives its cutscenes and the on-map (no separate battle screen) combat transitions.
- **Scaffolding:** tile/sprite renderer, party + ATB battle engine, a large **event script interpreter**, and a location/warp graph for the time-travel overworld.

### Shining Force (Genesis, 1992) — a side-scrolling-presentation tactical RPG
- **Language:** **Motorola 68000 assembly.**
- **Scaffolding:** grid tactical battles (like Fire Emblem) but with a more cinematic, side-view battle animation layer bolted onto the grid resolution — a good example of "grid logic underneath, side-scroller *presentation* on top," which matches part of your description.

**Era 1 takeaway:** the *design patterns* (state machine, data tables, scripting VM, save serialization, tile renderer) are already all present in 1990 — they were just hand-written in assembly. Modern engines give you these for free; that's the entire value proposition.

---

## Era 2 — Decompilations & disassemblies (the Rosetta Stone)

Not games to build, but the best **reference architecture** available, because they're real shipped games turned back into readable source.

| Project | Language | What it teaches |
|---|---|---|
| **pret/pokered**, **pokecrystal** | Z80 assembly (RGBDS assembler) | How a battle engine + overworld + script VM fit in 1MB |
| **pret/pokeemerald**, **pokeruby** | Hand-written **C** | A clean, buildable C codebase: file-by-file structure of overworld, battle, scripting, save |
| **rh-hideout/pokeemerald-expansion** | C | A *maintained toolkit* layered on the decomp — shows how people extend these today |
| **FF disassemblies (FF1 NES, FF6 SNES)** | 6502 / 65c816 assembly | Damage formulas, ATB timing, menu state as actual code |

**Why use these:** if your goal is to *understand* the genre at a deep level, reading `pokeemerald` teaches more than any tutorial — it's the genuine article with the data/logic separation, scripting VM, and save system all visible.

---

## Era 3 — Modern engines & frameworks (what you'd actually build on today)

This is the practical menu. Each row is a real path; the "scaffolding you get free" vs. "scaffolding you still build" distinction is the whole decision.

### Purpose-built genre engines (most scaffolding free)

**Lex Talionis** — *Fire Emblem–style SRPG engine*
- **Language:** **Python** (built on **Pygame**); Python 3.7+.
- **Free scaffolding:** grid, pathfinding, battle FSM, items/skills/abilities system, event scripting, a full **editor to build a game without writing code**.
- **You build:** content (maps, units, story); optional Python for custom mechanics.
- **Best when:** you specifically want a tactical/Fire Emblem game and want to start at the *content* layer.

**Pokémon Essentials** — *Pokémon-style monster-catching RPG*
- **Language:** **Ruby (RGSS)**, as a kit on top of **RPG Maker XP**.
- **Free scaffolding:** overworld, turn-based battle engine, type chart, encounter tables, menus, save — essentially the entire Pokémon stack.
- **You build:** maps, species/move data, story.
- **Best when:** the target is a creature-collector with party-of-N battles.

**Solarus** — *Zelda-like 2D action/RPG engine*
- **Language:** engine in **C++**, you script games in **Lua**; ships a quest editor.
- **Free scaffolding:** overworld, maps, entities, save, dialogue — tuned for action-RPG but adaptable.
- **Best when:** you want exploration-heavy 2D with a light scripting language.

### General 2D engines (some scaffolding free, you build the RPG systems)

**RPG Maker (MV / MZ / Unite)** — *the classic JRPG kit*
- **Language:** **JavaScript** (MV/MZ; older XP/VX use **Ruby/RGSS**).
- **Free scaffolding:** map editor, event system, default **turn-based battle engine**, menus, save/load, database of actors/items/skills, party-of-N out of the box.
- **You build:** mostly content and plugins; deep custom combat means plugin/JS work.
- **Best when:** you want a menu-driven JRPG fast and accept the genre conventions.

**Godot** — *free, open-source, 2D-first*
- **Language:** **GDScript** (Python-like) and/or **C#**.
- **Free scaffolding:** game loop, scene/node system (maps naturally onto your scene-state machine), tilemaps, 2D physics, input, audio, save via resource serialization, an editor.
- **You build:** the RPG systems themselves (battle FSM, grid/ATB, data tables) — but there are templates (Godot Tactical RPG, GDQuest series, Zenva micro-RPG courses) that scaffold these.
- **Best when:** you want full control with no royalties and a strong 2D workflow.

**Unity** — *industry standard*
- **Language:** **C#.**
- **Free scaffolding:** loop, 2D tooling, **ScriptableObjects** (an excellent fit for data-driven RPG stats/items), huge asset store, save via serialization.
- **You build:** the RPG systems; asset-store packages can jump-start combat.
- **Best when:** you want C#, the largest tutorial base, and broad platform reach. (Weigh licensing changes.)

**GameMaker** — *pixel/retro specialist*
- **Language:** **GML** (GameMaker Language) plus visual scripting.
- **Free scaffolding:** loop, rooms, sprites/animation, input; strong for 2D action and retro presentation.
- **You build:** RPG systems; less RPG-specific structure than RPG Maker.

### Code-first frameworks (least free scaffolding, most learning)

| Framework | Language | Notes |
|---|---|---|
| **MonoGame** | C# | Spiritual successor to XNA; you build everything above the draw/audio/input layer. Great for learning. |
| **LibGDX** | Java / Kotlin | Cross-platform 2D/3D framework; same "you build the engine" tradeoff. |
| **Bevy** | Rust | ECS-first engine; modern, fast, steeper learning curve. |
| **SDL2 / SFML** | C / C++ | Bare windowing/input/audio; closest to the Era-1 experience, maximum control. |
| **ImpactJS / HTML5 Canvas** | JavaScript | Proven for this genre — **CrossCode**, a large 2D action-RPG, shipped on a heavily modified ImpactJS engine. |

**Era 3 takeaway:** the choice is a slider between *content-first* (Lex Talionis, Pokémon Essentials, RPG Maker — story shipped fast, systems fixed) and *systems-first* (Godot, Unity, MonoGame, SDL — total control, you build the RPG layer). The further "down" the slider, the more you learn and the more you build.

---

## The infrastructure map (what's the same in every one of these)

No matter the era or language, the same scaffolding elements recur. This is the checklist any project in this family must satisfy:

1. **Top-level state/scene machine** — world ↔ field ↔ battle ↔ menu ↔ dialogue.
2. **Tile/map system** — grid or scene representation, collision, warps.
3. **World navigation** — overworld movement and an encounter/transition mechanism into battle.
4. **Battle engine** — turn ordering (phases, speed-sorted, or ATB gauges) + action resolution + targeting.
5. **Party & progression model** — 3–4 characters, stats, leveling, equipment/abilities.
6. **Data tables** — monsters, items, skills, growth rates, encounter tables (the data/logic split).
7. **Scripting/event system** — sequencing dialogue, cutscenes, triggers, story flags (the biggest hidden cost; in old games this was a custom bytecode VM).
8. **Save/load serialization** — snapshot and restore the whole game state.
9. **Asset pipeline** — sprites, tilesets, animation, audio import.
10. **Cross-cutting services** — input abstraction, audio manager, seedable RNG, localization/string tables.

The only thing that changes across the whole survey is **how much of this list the engine hands you vs. how much you write.**

---

## Setting up our discussion: the "what's most possible" axes

When we talk through this, these are the levers that determine feasibility. Worth thinking about where you sit on each before we dig in:

- **Genre target:** tactical/grid (Fire Emblem/Shining Force) vs. menu-JRPG (Final Fantasy/Chrono Trigger) vs. monster-collector (Pokémon). They share scaffolding but their *hard* system differs (AI+grid vs. ATB scheduler vs. battle/type engine).
- **Goal:** ship a playable game fast, or *learn how the machine works*? This sets the content-first ↔ systems-first slider.
- **Language comfort:** Python (Lex Talionis), JavaScript (RPG Maker MV/MZ, ImpactJS), Ruby (Essentials), C#/GDScript (Unity/Godot), C/C++/Rust (frameworks).
- **Presentation:** top-down tile world, side-scroll battle view, or both (Shining Force pattern).
- **Target platform:** desktop is easiest; "handheld" today realistically means itch.io/desktop, web (HTML5), or Steam Deck — actual cartridge/retro homebrew is a separate, harder track.
- **Scope honesty:** the content/scripting layer (item 7) and save system (item 8) sink more projects than the battle math does.

When you're ready, tell me where you land on **genre target** and **goal (ship vs. learn)** and I'll narrow this to the two or three most realistic paths and sketch what the first milestone looks like.

---

## Sources

- [pret/pokeemerald — decompilation of Pokémon Emerald (C)](https://github.com/pret/pokeemerald)
- [rh-hideout/pokeemerald-expansion (C ROM hack base)](https://github.com/rh-hideout/pokeemerald-expansion)
- [List of Pokémon disassembly projects — Glitch City Wiki](https://glitchcity.wiki/wiki/List_of_Pok%C3%A9mon_disassembly_projects)
- [Reversing Pokémon Red and Blue — Retro Reversing](https://www.retroreversing.com/pokemonredblue)
- [pret organization](https://pret.github.io/)
- [Chrono Trigger — Wikipedia](https://en.wikipedia.org/wiki/Chrono_Trigger)
- [What were SNES games programmed in? — GameDev.net](https://gamedev.net/forums/topic/343677-what-were-snes-games-programmed-in/)
- [FF1 Disassembly (NES, 6502 asm)](https://github.com/Entroper/FF1Disassembly)
- [everything8215/ff6 — Final Fantasy VI disassembly](https://github.com/everything8215/ff6)
- [Lex Talionis — Fire Emblem engine (Python/Pygame)](https://lex-talionis.net/)
- [Lex Talionis source — GitLab](https://gitlab.com/rainlash/lex-talionis)
- [Maruno17/pokemon-essentials (Ruby/RMXP)](https://github.com/Maruno17/pokemon-essentials)
- [Solarus — 2D ARPG engine (C++/Lua)](https://www.solarus-games.org/)
- [RPG Maker official](https://store.rpgmakerofficial.com/)
- [Godot Engine](https://godotengine.org/)
- [Build a Micro Turn-Based RPG with Godot 4 — Zenva](https://academy.zenva.com/product/build-a-turn-based-rpg-battle-system-with-godot-4/)
- [Best 2D Game Engines: Godot vs Unity vs GameMaker (2025)](https://generalistprogrammer.com/tutorials/best-2d-game-engines-godot-unity-gamemaker)
- [Architecture of CrossCode — Radical Fish Games](https://www.radicalfishgames.com/?p=277)
- [ImpactJS — HTML5/JavaScript game engine](https://impactjs.com/)
