# AGENTS.md

Guide for coding agents working in this repo. Player and designer docs: [README.md](README.md), [Godot/DESIGNERS.md](Godot/DESIGNERS.md).

## Project

- Siege Engineers, a Ludum Dare 60 game in Godot **4.7.2**. 2D, GL Compatibility renderer, GDScript only.
- The Godot project lives in `Godot/`. CI (`.github/workflows/godot.yml`) runs with `working-directory: Godot`, and the export preset names (`Web`, `Windows Desktop`, `MacOS`, `Linux`) must stay as they are.
- Local editor binary: `C:/Users/Voxar/Work/Godot/Godot_v4.7.2-stable_win64_console.exe` (called `$GD` below).

## Commands (run from `Godot/`)

```sh
$GD --headless --import                              # re-import after adding assets/scripts
$GD --headless -s res://addons/gut/gut_cmdln.gd      # all GUT tests (must stay green)
$GD res://dev/screenshot.tscn -- out=<png> seconds=5 level=1   # play and grab a frame
$GD --headless res://dev/generate_levels.tscn -- [count=N] [seed=S] [force]
$GD --headless res://dev/bootstrap_data.tscn         # recreate missing data/*.tres only
$GD --headless res://dev/build_tiles_v2.tscn -- art      # then --import, then: -- tileset (v2 tiles into tileset.tres)
$GD --headless res://dev/convert_levels_v2.tscn      # retile the campaign levels with the v2 rules
$GD --headless res://dev/scatter_grass.tscn            # regrow every level's tall grass by its Scatter and save
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
| Data types | `core/supplies.gd`, `terrain_type.gd`, `bridge_material.gd`, `tool_definition.gd`, `army_rules.gd`, `campaign.gd`, `sound_effect.gd`, `menu_act.gd`, `menu_piece.gd` | Resources, all `@tool`. |
| Autoloads | `GameState` (campaign progress, supplies, checkpoint, best level in `user://`), `Audio` (also the saved volumes), `Settings` (full screen, saved beside the volumes), `Effects` (`core/effects.tscn`: debris, floating text, shake) | |
| World | `game/world.gd`, `world.tscn` | One continuous world: Terrain, Bridge, Army, Crew, Objects, Flags. Levels are stitched on (`Terrain.stamp`), streamed in with `ResourceLoader.load_threaded_request`, unloaded behind (`Terrain.unload_before`, `min_x`), and rewound for retries. Owns the camp/night cycle (`army.hold`). `World.of(node)` finds it. |
| Level | `levels/level.gd`, `level_base.tscn` | Templates only, never in the tree while playing: Terrain, Objects, StartFlag, ExitFlag plus settings. Every level inherits `level_base.tscn`. `campaign.levels` holds their paths. |
| Terrain look | `core/terrain_look.gd`, `data/terrain_look.tres`, `world/tile_rules.gd`, `world/terrain_skin.gd` | v2 tiles (`world/tilemap-terrain.png`) are source 2 of `world/tileset.tres`, each tagged with its material (grass/dirt tiles have one alternative per dirt or rock type). `Terrain` re-picks the tile of every cell around a change with `TileRules`, keeping tiles that still fit, so painted variants survive. Change cells through `set_type` (or retile what you touched) so this happens. `TerrainSkin` draws only the rock overlay (half-cell dual grid), also in the editor. With the look off, the classic old tiles are used. |
| Tall grass | `world/tall_grass.gd`, `tall_grass.tscn`, `tall_grass_tileset.tres` | Each level's Grass layer is stamped into the World's `TallGrass` with the terrain (same offset and seam), drawn above the army. Patches are erased on `Terrain.cell_changed` when their ground goes. Frames are stepped by `tall_grass.gdshader` (per world column), not by tile animation; the atlas needs `use_texture_padding = false`. |
| Terrain | `world/terrain.gd` (TileMapLayer) | Behaviour comes from the "terrain" custom data (a `TerrainType`). It caches cells. `settle()` detaches falling tiles and collapses unsupported structures. |
| Bridge | `world/bridge.gd` | XPBD truss in SI units (m, kg, N). It only advances when `World._physics_process` steps it. |
| Army | `game/army.gd`, `objects/soldier/` | Column logic ported from the original `updateUnits`. Soldier nodes only display state. |
| Flow | `game/game.gd`, `tool_controller.gd`, `camera_rig.gd`, `ui/hud.gd`, `ui/pause_menu.gd` | The HUD only displays state and emits signals; the Game connects them. Escape (`pause_menu`) opens the pause menu, unless the ToolController consumes it to put down a plank in hand. |
| Main menu | `menu/boot.tscn` (the main scene: readies every sound behind a loading bar, see Audio below), then `menu/main_menu.tscn`, `menu/menu_show.gd`, `core/menu_act.gd`, `ui/settings_menu.gd` | The backdrop is a real World playing `menu/menu_level.tscn`: `MenuShow` swaps a one-level copy of the campaign into `GameState` while it is in the tree, orders each MenuAct's bridge, holds the column short of the bridge (`army.stop_x`) until it stands, and breaks the act's pieces under load. Levels run on their own (F6) still go straight to `game/main.tscn` (`Level.GAME_SCENE`). |

**Units.** Simulation is in metres (1 tile = 1 m, y points down). Node positions are pixels. Convert with `Grid.to_px` / `Grid.to_m` / `Grid.cell_of` (`Grid.PX = 32`).

**Night grade.** `post/night_grade.tscn` (CanvasLayer 1, between the world and the HUD on layer 5) reads the screen and blends it into a night LUT by `DayNight`, except near every visible `PointLight2D` (tracked through `node_added`, passed to the shader as up to 32 spots). The WorldEnvironment LUT (`low_17`) is the identity.

**Pausing.** `LevelHolder` (holding the World) is pausable. The Game, ToolController, Camera, Terrain (`settle`), Bridge drawing, Audio and Effects keep running while paused, so the player can build during a pause. Speed is `Engine.time_scale`.

## Gotchas found the hard way

- On the web (no threads) sounds play as WebAudio samples: the first play of a stream decodes all of it (about 1 s per music file) and every play copies the decoded buffer (100 to 300 ms for a music file). `menu/boot.tscn` readies them all up front, and music imports loop so a track is never restarted. Read the playback type with `ProjectSettings.get_setting_with_override`, since `get_setting` ignores the `.web` override. Level loads take only ~10 ms there; stitching a level costs ~50 ms.
- Saving a resource from a headless script (`ResourceSaver.save`) drops every `uid=`. `dev/build_tiles_v2.gd` puts them back from each referenced file's header or `.import`, so the file matches what the editor writes. Do the same in any new tool that saves data.

- Scripts that reference autoloads (`GameState`, `Audio`, `Effects`) **fail to compile under `godot -s script.gd`**. Run such tools as a scene (see `dev/*.tscn`). Only pure-Resource scripts can run via `-s`.
- Godot has no script API that saves *inherited* scenes, so `dev/generate_levels.gd` writes the `.tscn` text itself (`instance=ExtResource(base)`, then overrides). Keep levels inherited so changes to `level_base.tscn` reach every level.
- The tile atlas goes through two passes: `build_tileset.gd -- art`, then `--import`, then `-- tileset`.
- In 4.7.2 painting or `set_cell` does not emit `TileMapLayer.changed`; `_update_cells` is the hook, and cells set inside it are never drawn, so `Terrain` defers its re-pick (`_retile_painted_later`).
- Under typed GDScript, `var x := dict.key` fails to compile ("cannot infer type"). Write `var x: T = dict.key`.
- `Terrain.size` only grows while playing; digging the last tile of a column must not move the level edge. Only `stamp`/`clear_from` move the right edge and `unload_before` the left (`min_x`).
- A level's cells left of its StartFlag column are dropped when it is stitched onto another level; keep stitch seams flat (`test_levels` checks them).
- `level_01.tscn` once referenced `archer.tscn` by a UID the cache did not know, which logs an engine error on load. Prefer path-only `ext_resource` lines in hand-written scenes.

## Conventions

- Typed GDScript with tabs and `##` doc comments on public members. `untyped_declaration` is set to warn.
- Match the comment density of the existing code. No duplicated logic: shared rules belong in the Resource or the system that owns them.
- Write a failing test first wherever applicable. Tests live in `test/unit/`; build small worlds with `test/helpers/world_fixture.gd` (ASCII maps). Never weaken a test to make it pass.
- `test/unit/test_levels.gd` checks every campaign level (flags on ground, archers supported, spawns valid). Keep it passing after any level edit.
- `dev/` and `test/` are excluded from exports.

## Git

- Binary assets go through Git LFS (`.gitattributes` at the repo root). If you add a new binary type, add it there before committing.
