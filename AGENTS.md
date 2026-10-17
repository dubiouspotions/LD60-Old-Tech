# AGENTS.md

Guide for coding agents working in this repo. Player and designer docs: [README.md](README.md), [Godot/DESIGNERS.md](Godot/DESIGNERS.md).

## Project

- Sappers' March, a Godot **4.7.2** port of a web prototype. 2D, GL Compatibility renderer, GDScript only.
- The Godot project lives in `Godot/`. CI (`.github/workflows/godot.yml`) runs with `working-directory: Godot`, and the export preset names (`Web`, `Windows Desktop`, `MacOS`, `Linux`) must stay as they are.
- Local editor binary: `C:/Users/Voxar/Work/Godot/Godot_v4.7.2-stable_win64_console.exe` (called `$GD` below).

## Commands (run from `Godot/`)

```sh
$GD --headless --import                              # re-import after adding assets/scripts
$GD --headless -s res://addons/gut/gut_cmdln.gd      # all GUT tests (must stay green)
$GD res://dev/screenshot.tscn -- out=<png> seconds=5 level=1   # play and grab a frame
$GD --headless res://dev/generate_levels.tscn -- [count=N] [seed=S] [force]
$GD --headless res://dev/bootstrap_data.tscn         # recreate missing data/*.tres only
```

## Core rule: designers edit, code reads

Non-coders must be able to create and change levels, objects, sounds and music in the editor. Keep it that way:

- Tunables go in `@export`s on scenes or in Resource types (`core/*.gd`), never in constants buried in logic.
- New content goes in as a scene or a `.tres`. Example: a new material is a `TerrainType` plus tiles in `world/tileset.tres`, with no code.
- Sounds are `SoundEffect` resources played through `Audio.play(sfx, pos_px)`. Never hard-code a stream path.
- Text the player sees is an exported string where practical.
- If you add a designer-facing knob, also update `Godot/DESIGNERS.md`.

## Architecture

| Area | Files | Notes |
| --- | --- | --- |
| Data types | `core/supplies.gd`, `terrain_type.gd`, `bridge_material.gd`, `tool_definition.gd`, `army_rules.gd`, `campaign.gd`, `sound_effect.gd` | Resources, all `@tool`. |
| Autoloads | `GameState` (campaign progress, supplies, checkpoint, best level in `user://`), `Audio`, `Effects` (`core/effects.tscn`: debris, floating text, shake) | |
| Level | `levels/level.gd`, `level_base.tscn` | Every level inherits `level_base.tscn`. `Level.of(node)` finds the owning level. |
| Terrain | `world/terrain.gd` (TileMapLayer) | Behaviour comes from the "terrain" custom data (a `TerrainType`). It caches cells. `settle()` detaches falling tiles and collapses unsupported structures. |
| Bridge | `world/bridge.gd` | XPBD truss in SI units (m, kg, N). It only advances when `Level._physics_process` steps it. |
| Army | `game/army.gd`, `objects/soldier/` | Column logic ported from the original `updateUnits`. Soldier nodes only display state. |
| Flow | `game/game.gd`, `tool_controller.gd`, `camera_rig.gd`, `ui/hud.gd` | The HUD only displays state and emits signals; the Game connects them. |

**Units.** Simulation is in metres (1 tile = 1 m, y points down). Node positions are pixels. Convert with `Grid.to_px` / `Grid.to_m` / `Grid.cell_of` (`Grid.PX = 32`).

**Pausing.** `LevelHolder` is pausable. The Game, ToolController, Camera, Terrain (`settle`), Bridge drawing, Audio and Effects keep running while paused, so the player can build during a pause. Speed is `Engine.time_scale`.

## Gotchas found the hard way

- Scripts that reference autoloads (`GameState`, `Audio`, `Effects`) **fail to compile under `godot -s script.gd`**. Run such tools as a scene (see `dev/*.tscn`). Only pure-Resource scripts can run via `-s`.
- Godot has no script API that saves *inherited* scenes, so `dev/generate_levels.gd` writes the `.tscn` text itself (`instance=ExtResource(base)`, then overrides). Keep levels inherited so changes to `level_base.tscn` reach every level.
- The tile atlas goes through two passes: `build_tileset.gd -- art`, then `--import`, then `-- tileset`.
- Under typed GDScript, `var x := dict.key` fails to compile ("cannot infer type"). Write `var x: T = dict.key`.
- `Terrain.size` only grows. Digging the last tile of a column must not move the level edge.

## Conventions

- Typed GDScript with tabs and `##` doc comments on public members. `untyped_declaration` is set to warn.
- Match the comment density of the existing code. No duplicated logic: shared rules belong in the Resource or the system that owns them.
- Write a failing test first wherever applicable. Tests live in `test/unit/`; build small worlds with `test/helpers/world_fixture.gd` (ASCII maps). Never weaken a test to make it pass.
- `test/unit/test_levels.gd` checks every campaign level (flags on ground, archers supported, spawns valid). Keep it passing after any level edit.
- `dev/` and `test/` are excluded from exports.

## Git

- Binary assets go through Git LFS (`.gitattributes` at the repo root). If you add a new binary type, add it there before committing.
