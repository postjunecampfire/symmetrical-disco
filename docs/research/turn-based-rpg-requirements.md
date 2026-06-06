# Building a Modern Turn-Based RPG: A Programming-Perspective Requirements Guide

*A conceptual deep-dive comparing two classic archetypes — the tactical grid SRPG (e.g. **Fire Emblem: The Sacred Stones**) and the menu-driven ATB JRPG (e.g. **Final Fantasy VII**, original PS1 version). The focus is on how these systems are structured in code, what subsystems they demand, and how to choose a language and engine. It is meant to teach the shape of the problem, not to prescribe a single stack.*

---

## 1. Two archetypes, one family

Both games are "turn-based RPGs," but the resemblance is mostly thematic. From an engineering standpoint they are two genuinely different machines that happen to share a stats-and-narrative skin.

| Dimension | Tactical SRPG (Sacred Stones) | ATB JRPG (FF7) |
|---|---|---|
| Core play space | A **2D grid** of tiles | A series of **discrete screens** (world map, field, battle) |
| "Turn" meaning | Whole-army phases: player phase → enemy phase | Per-actor turns gated by a filling **ATB gauge** |
| Time model | Fully discrete; nothing happens until input | **Soft real-time**: gauges fill on a clock even while you wait |
| Spatial logic | Pathfinding, range, terrain, facing, zones of control | Mostly positional flavor; targeting is by selection, not movement |
| Defining algorithms | Grid pathfinding, threat ranges, tactical AI | Gauge scheduling, a battle "timeline," scripted enemy behavior |
| Content volume | Many maps, many units, growth tables | Large world, fields, cutscenes, materia/ability matrix, minigames |
| Hardest part to get right | AI and combat math balance | Content pipeline, state/scene management, set-piece scripting |

The single most important conceptual difference: **the SRPG is a discrete simulation on a graph, while the ATB JRPG is a soft real-time scheduler wrapped in a content-delivery engine.** Almost every downstream requirement flows from that distinction.

---

## 2. The architectural bedrock (shared by both)

Before the genre-specific parts, every game of this kind needs the same foundation.

### 2.1 The game loop

At the bottom is a loop that runs every frame: process input, update game state by some delta-time, render. Modern engines (Godot, Unity, Unreal) hand you this loop and a fixed-timestep variant for free, which is one of the strongest arguments for not writing an engine from scratch. The interesting design question is not *having* a loop but *what updates inside it*. In a pure SRPG the world is static between inputs, so most of the loop idles or animates; in an ATB game the loop is continuously advancing every combatant's gauge.

### 2.2 Finite state machines, everywhere

The dominant pattern in both genres is the **finite state machine (FSM)**, and usually a stack of them. A tactical RPG's battle flow is naturally modeled as a state machine controlling turn-based gameplay — states like *Player Turn → Select Unit → Move → Choose Action → Target → Resolve → Enemy Turn*. The same applies at the macro level (Title → Overworld → Battle → Dialogue → Menu → Game Over).

A practical refinement is the **pushdown automaton** (a stack of states): opening a menu *pushes* a menu state on top of the battle state rather than replacing it, so closing the menu *pops* back exactly where you were. This cleanly handles nested UI, pause, and "are you sure?" confirmations without tangled boolean flags.

### 2.3 Data-driven design and the data/logic split

The professional default is to **separate game data from game logic**. Stats, growth rates, item definitions, spell costs, enemy tables, and dialogue live in data files (JSON/YAML, Unity ScriptableObjects, Godot Resources, or a small embedded database), while code reads that data and applies rules. This is what lets a designer rebalance the whole game by editing tables instead of recompiling, and it is the difference between a toy and a maintainable project.

A useful rule of thumb on the storage choice: text formats like JSON are ideal for tuning, version control, and tooling because they diff cleanly and any tool can read them; engine-native asset formats (ScriptableObjects, Godot `Resource`s) load faster and integrate with the editor but lock you into that ecosystem. Many shipping projects use a **hybrid**: author and balance in spreadsheets/JSON, then bake into the engine-native format for runtime.

### 2.4 ECS vs OOP — and why "hybrid" usually wins

You will hear two camps:

- **Object-oriented (OOP):** a `Unit` class with stats, methods, and inheritance. Intuitive, fast to start, perfectly adequate for the entity counts these games have (dozens, not millions). For a Fire Emblem or FF7-scale game, OOP is entirely viable.
- **Entity-Component-System (ECS):** entities are IDs, data lives in components, and systems operate over components. It shines for cache efficiency and huge entity counts, and it makes "this unit can now fly / is poisoned / is a boss" a matter of adding/removing components rather than editing a class hierarchy.

For these two specific genres, the entity counts are small, so ECS's performance argument barely applies. Its *composition* argument, however, is genuinely useful for modeling status effects, equipment modifiers, and ability tags without inheritance spaghetti. The common, pragmatic answer is a **hybrid**: lightweight composition for unit state and effects, OOP/scene objects for UI and high-level flow. Don't adopt full ECS for the performance — adopt component composition for the flexibility, if at all.

### 2.5 Cross-cutting subsystems both games need

Regardless of genre you will build or integrate:

- **Save/load (serialization):** snapshot the entire game state to disk and restore it. This silently constrains your whole architecture — if state is scattered across the engine in hard-to-serialize objects, saving becomes painful. Design for it early.
- **Event/messaging bus:** a publish-subscribe system so combat, UI, audio, and quest logic can react to events ("unit died," "HP changed," "item acquired") without tight coupling.
- **Audio manager:** music with smooth transitions between map/battle/victory, plus sound effects.
- **Localization:** never hard-code displayed strings; route all text through a string table keyed by ID.
- **Input abstraction:** map physical inputs to logical actions (Confirm, Cancel, Cursor) so you can support keyboard, gamepad, and remapping.
- **RNG service:** a *seedable* random number generator, centralized — critical for balance testing, reproducible bugs, and deterministic replays/netcode if you ever add them.

---

## 3. Requirements specific to the tactical SRPG (Sacred Stones style)

This is fundamentally **a turn-based simulation over a graph of tiles**. The grid is the spine of everything.

### 3.1 Grid and map representation
- A 2D tile grid as the core data structure (a 2D array or a graph of tile nodes).
- Per-tile data: terrain type, movement cost, defense/avoidance bonus, occupant, elevation/impassability.
- A clean mapping between **grid coordinates** and **screen/world coordinates** (and back, for cursor selection).

### 3.2 Movement, pathfinding, and range
- **Reachable-tile computation:** given a unit's movement points and per-terrain costs, flood-fill (Dijkstra / breadth-first with weights) to find all tiles it can reach. This is the blue "move range" overlay.
- **Pathfinding** (A\* or Dijkstra) to draw and execute the actual route, respecting terrain cost and blocking units.
- **Attack/threat range:** movement range expanded by weapon/spell range; the union over all enemies is the "danger zone" overlay players rely on.
- **Movement preview** and cursor-driven path drawing as the player hovers.

### 3.3 Turn structure
- Phase-based turns: **player phase** (move all your units in any order) then **enemy phase**, then neutral/other phases — driven by the battle FSM.
- Per-unit "has moved / has acted" flags, with the turn ending when all units are spent or the player chooses to end it.

### 3.4 Combat resolution
- A deterministic-but-random damage model: hit chance, crit chance, damage = f(attack, defense, weapon, terrain), often with the genre's **weapon-triangle**-style advantages and follow-up (double) attacks based on speed.
- Combat **forecast UI** (predicted damage/hit/crit before you commit) — players expect to see the math.
- Permadeath bookkeeping if you emulate classic Fire Emblem (a dead unit is gone for the campaign), which ripples into save design and narrative branching.

### 3.5 Tactical AI
- This is the genre's hardest engineering problem. Per-enemy behavior is usually a **utility/scoring AI** or behavior tree: for each enemy, enumerate possible (move + action) pairs, score each by expected damage, kill potential, self-preservation, objective, and aggression profile, then pick the best.
- Different archetypes (aggressive, defensive/"stay until approached," boss, healer, thief targeting the exit) are largely **data-driven flags** on top of one scoring engine.

### 3.6 Map/objective and progression layer
- Objective types: rout, seize a tile, survive N turns, protect an NPC, escape — implemented as win/lose condition checks evaluated each turn.
- Between-battle systems: unit roster, experience/leveling with **growth-rate tables**, class promotion, weapon/item inventory, supports/affinity, shop/preparations.
- A **map/level data format** so designers can author maps and place units, triggers, and reinforcements without touching code.

> **Reference points:** open frameworks like the Godot 4 Tactical RPG template and GDQuest's tactical-movement series implement exactly this stack — grid, reachable-tiles flood fill, pathfinding, and a battle state machine — and are worth reading as concrete blueprints.

---

## 4. Requirements specific to the ATB JRPG (FF7 style)

This is **a soft real-time battle scheduler bolted onto a large content/scene engine**. Two very different halves: the exploration/presentation layer and the battle layer.

### 4.1 The ATB battle engine
The Active Time Battle system was designed by Hiroyuki Ito (debuting in Final Fantasy IV); FF7 was the first to use it with a three-member party. The core requirements:

- **Per-combatant ATB gauge** that fills over time at a rate derived from the actor's Speed/Dexterity stat. When a gauge reaches full, that actor "gets a turn" and may act.
- A **scheduler/timeline** advancing all gauges (party *and* enemies) each frame. Enemy gauges are typically hidden; player gauges are shown.
- **ATB modes** — Active (clock never stops), Wait (clock pauses while you navigate Item/Magic/Summon sub-menus), and a Recommended blend (pauses only during animations). This is a real requirement, not a cosmetic toggle: it changes when `update()` advances gauges and forces you to cleanly separate "menu open" from "world ticking."
- **Action queue and resolution:** chosen actions (Attack, Magic, Item, Summon, Limit) enqueue, play their animation, apply effects, then reset the actor's gauge. Some actions have cast time or post-use cooldown.
- **Targeting system**, status effects (poison, sleep, haste/slow that directly scale gauge speed), elemental affinities, and the damage formula.
- **Limit/special meters** filling on damage taken, orthogonal to the ATB gauge.

The architectural lesson: because gauges advance on a clock, the ATB battle is the one place where the game loop is doing continuous work, and **menu state must not block the simulation unless the chosen ATB mode says so.** Get the "what advances time and what doesn't" boundary right and the rest is data.

### 4.2 The exploration / presentation layer
FF7's bulk is not the battle engine; it's everything around it.

- **Scene/screen state management:** world map, pre-rendered/field screens, battle, menu, cutscene — a top-level FSM with clean transitions (and the famous "encounter swirl" hand-off into battle).
- **Field interaction:** an avatar moving through scenes, collision, triggers, NPCs, chests, doors/warps between maps.
- **Encounter system:** random or zone-based encounters with encounter tables per area, then a transition that snapshots field state, runs the battle, and returns.
- **Dialogue and cutscene/event scripting:** a scripting layer or data format to sequence camera, movement, text, and flags. At FF7's scale this is effectively a small **in-house scripting engine** — one of the largest hidden costs in the project.
- **Menu system:** deep, nested menus for party, equipment, the **Materia** matrix (a slot/linking system that itself is a small rules engine), shops, and status.
- **Minigames/set-pieces:** bespoke mechanics that each behave like their own tiny game — a notorious schedule risk.

### 4.3 Progression layer
- Party of characters with stats, levels, and an **ability/customization matrix** (FF7's Materia: equippable orbs that grant magic/skills and combine when linked). Modeling this cleanly is a data-modeling exercise in modifiers and slot rules.
- Equipment (weapon/armor/accessory) applying stat modifiers and Materia slots.
- Items, gil/currency, shops, and a quest/story-flag system gating progression.

---

## 5. Where the two diverge most (and what that means for you)

- **Spatial complexity** lives almost entirely in the SRPG. If you build the tactical game, budget heavily for grid math, pathfinding, range overlays, and AI. If you build the ATB game, you can largely skip pathfinding but you owe a real-time scheduler and far more content/scripting infrastructure.
- **Where the project's risk concentrates:** for the SRPG it's **AI quality and combat balance**; for the ATB JRPG it's the **content pipeline and scene/event scripting** (the actual battle math is comparatively contained). Plan staffing and schedule around those, not around the parts that look hard but are well-trodden.
- **Determinism:** the SRPG is naturally deterministic between inputs, which makes testing, replays, and even networked play tractable. The ATB game's clock-driven gauges make timing-dependent bugs more likely and reproducibility harder — another reason to centralize and seed RNG and to keep the time-advance logic in one place.

---

## 6. Language and engine selection

There is no single right answer, but the tradeoffs are well-understood.

### 6.1 Don't write the engine (probably)
Writing a custom engine in C++ with SDL/SFML, or in Rust (Bevy is an ECS-first engine), or in C# with MonoGame, is a legitimate and educational path — and historically how FF7 and Fire Emblem were actually built (custom engines in C/C++/assembly). But for a learning project today, an existing engine gives you the game loop, rendering, audio, input, asset pipeline, and a tile/scene editor for free, which is a large fraction of the non-gameplay work.

### 6.2 The mainstream engine options

- **Godot (GDScript and/or C#):** Purpose-built, first-class 2D workflow — node-based scenes, dedicated 2D physics, strong tilemap tools — which maps almost perfectly onto both a tile-grid SRPG and a screen-based JRPG. GDScript is Python-like with little boilerplate and a gentle learning curve; C# is supported and now nearly on par. Free and open-source with no royalties. The main cost is a smaller asset/library ecosystem than Unity. For 2D RPGs this is frequently the recommended default.
- **Unity (C#):** Mature, huge asset store, excellent 2D tooling, **ScriptableObjects** that fit data-driven RPG design beautifully, and the broadest learning resources. C# is a strong, productive language for this domain. The caveat is licensing/business-model uncertainty to weigh against the ecosystem.
- **Unreal (C++ / Blueprints):** Powerful, but its 2D support is comparatively weak and it's heavier than needed for these genres; generally not the best fit for a 2D RPG.
- **Code-first frameworks (MonoGame/C#, LibGDX/Java/Kotlin, Bevy/Rust, SDL or SFML/C++):** More control and a better learning experience for fundamentals, at the cost of building editors and pipeline yourself. Good if the *point* is to learn architecture rather than ship content fast.

### 6.3 A reasonable default for a learning project
For most people building either of these today: **Godot with GDScript** (or C# if you prefer static typing) for the fastest path from idea to playable, with all game *content* expressed as data resources so logic and balance stay decoupled. Choose **Unity/C#** if you specifically want industry-standard C# and the largest tutorial base; choose a **code-first framework** if learning the underlying systems *is* the goal.

---

## 7. Tooling and content pipeline (the part beginners underestimate)

For both genres, but especially the ATB JRPG, the **editor and data tooling are as much of the project as the runtime.**

- **Map/level editor:** author tile maps, terrain, unit/enemy placement, triggers, reinforcements. (Tiled, or the engine's built-in tilemap editor.)
- **Data tables:** spreadsheets or JSON for stats, growth rates, items, enemies, spells, encounter tables — with a defined import/bake step.
- **Dialogue/event editor:** even a simple node or script format; this is the SRPG's lighter need and the JRPG's heavy one.
- **Asset pipeline:** sprite/animation import, atlas packing, audio import, naming conventions.
- **Debug tooling:** battle simulators, an AI step-through, an RNG seed override, god-mode and skip-to-state shortcuts. These pay for themselves many times over.
- **Version control** (Git, with LFS for binary assets) from day one.

---

## 8. A pragmatic build order

A sane sequence that front-loads the genre's hard, defining systems and defers content:

1. **Foundations:** project skeleton, top-level scene/state machine, input abstraction, a placeholder render of the play space.
2. **The defining core loop:** for the SRPG — grid, cursor, reachable-tiles, pathfinding, one unit moving and attacking; for the JRPG — one ATB battle with gauges filling, a menu, and damage resolution.
3. **Data-driven everything:** move stats/items/enemies into data files; prove a designer can change balance without recompiling.
4. **Combat depth:** full damage model, status effects, the genre's signature systems (weapon triangle / Materia), win-lose conditions.
5. **AI** (SRPG) or **enemy scripts + scheduler edge cases** (JRPG).
6. **Progression & meta:** leveling, roster/party, inventory, shops, save/load.
7. **Content & presentation:** maps/scenes, dialogue, audio, UI polish, localization hooks.
8. **Tooling and balance pass:** editors, debug tools, and the long tail of tuning.

The throughline: **build the one system that defines the genre first** — the grid simulation for the tactical game, the real-time gauge scheduler for the ATB game — because every other requirement either feeds it or hangs off it.

---

## Sources

- [Godot Tactical RPG template — DeepWiki](https://deepwiki.com/ramaureirac/godot-tactical-rpg)
- [GDQuest — Tactical RPG Movement series](https://www.gdquest.com/tutorial/godot/2d/tactical-rpg-movement/)
- [The Liquid Fire — Tactics RPG State Machine](https://theliquidfire.com/2015/06/01/tactics-rpg-state-machine/)
- [tactical-rpg — GitHub Topics](https://github.com/topics/tactical-rpg)
- [Final Fantasy VII battle system — Final Fantasy Wiki](https://finalfantasy.fandom.com/wiki/Final_Fantasy_VII_battle_system)
- [Active Time Battle — Final Fantasy Wiki](https://finalfantasy.fandom.com/wiki/Active_Time_Battle)
- [FF7 ATB Combat System — Samurai Gamers](https://samurai-gamers.com/final-fantasy-7-ffvii/atb-combat-system/)
- [Separate Game Data and Logic with ScriptableObjects — Unity](https://unity.com/how-to/separate-game-data-logic-scriptable-objects)
- [JSON vs ScriptableObjects in Unity — Kerem Sirin (Medium)](https://medium.com/@krmsrn/json-vs-scriptableobjects-in-unity-a-technical-comparison-ae3d2efd59a9)
- [ECS vs OOP in Large-Scale Games — Daydreamsoft](https://www.daydreamsoft.com/blog/ecs-vs-oop-in-large-scale-games-choosing-the-right-architecture-for-performance-and-scalability)
- [A Data-Driven Game Object System (GDC 2002, Scott Bilas) — PDF](https://www.gamedevs.org/uploads/data-driven-game-object-system.pdf)
- [Unity vs Unreal vs Godot: Choosing Your Engine in 2025 — Wayline](https://www.wayline.io/blog/unity-unreal-godot-engine-comparison-2025)
- [Godot vs Unity — GameFromScratch](https://gamefromscratch.com/godot-vs-unity-which-to-choose-in-2025/)
