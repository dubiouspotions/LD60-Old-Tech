# Sappers' March — designer guide

Everything below is done in the Godot editor (4.7). No code needed.

## Levels

| Task | How |
| --- | --- |
| New level | Scene → New Inherited Scene → `levels/level_base.tscn`. Save as `levels/level_NN.tscn`. |
| Paint ground | Select **Terrain**, open the TileMap panel, paint. Every tile's behaviour comes from its TerrainType (below). Left, right and below the painted area count as bedrock. Above is open sky. |
| Start / end | Move **StartFlag** (the column starts here) and **ExitFlag** (the level ends when the front soldier passes it). Put each flag's origin on the ground. |
| Enemies | Drag `objects/archer/archer.tscn` under **Objects**. Its origin is its feet, so put it on top of a solid tile. It dies when that tile is blasted. Tune range and reload in the Inspector. |
| Music, reinforcements, supply drop | Select the root node and use the Inspector. The supply drop and reinforcements are given on arrival, but not on the first level. |
| Order of levels | `data/campaign.tres` → **Levels**. Starting soldiers, starting supplies, tools and jingles are set there too. |

Checks: run the GUT panel (or `test/unit/test_levels.gd`). It flags levels with buried or floating flags, archers standing on nothing, and similar mistakes.

## Tiles and terrain types

- `data/terrain/*.tres` holds one TerrainType per material. It sets: solid, natural ground (anchors bridges and holds bricks), structure (collapses when nothing holds it up), falls (fill), hazard (water or spikes, with the death and "ahead" texts), dig action and yields, and debris colour.
- `world/tileset.tres` is the TileSet. Each tile's **terrain** custom data points to a TerrainType. To add a material: create a TerrainType, add tiles to the atlas, and set their **terrain** data.
- `world/tiles.png` is placeholder art. Replace it with your own; keep the layout or reassign the tiles in the TileSet editor.

## Objects and tuning

| What | Where |
| --- | --- |
| Soldier look and walk cycle | `objects/soldier/soldier.tscn` (polygons + AnimationPlayer "walk"/"idle") |
| March speed, step-up, fall damage, max army, messages | `data/army_rules.tres` |
| How long the column waits before the king orders the march | **March Delay** on each level's root node (default in `levels/level_base.tscn`) |
| March banner texts and sound, "king waits" status | **Game** node in `game/main.tscn` |
| Engineer crew: size, walk/climb/build speed, step-up, ground climb and drop limits, strike delay, sounds | `data/crew_rules.tres` |
| Engineer look | `objects/engineer/engineer.tscn` (inherits the soldier scene) |
| Log / support / rope strength, length, mass, cost, colours | `data/bridge/log.tres`, `support.tres`, `rope.tres`. **Walkable** decides if soldiers walk on it; **Draw Layer** puts it behind (lower) or over (higher) other members. |
| Tool rack: names, hints, keys, costs, hold-repeat | `data/tools/*.tres` (rack order is the Campaign's **Tools** list) |
| Charge fuse, radius, chain fuse, explosion | `objects/charge/charge.tscn` |
| Arrows | `objects/arrow/arrow.tscn` |
| Falling fill | `objects/falling_block/falling_block.tscn` |
| Debris, floating text, explosion flash | `objects/effects/` |
| Sky, sun, mountain ridges | `world/background/background.tscn` |
| HUD layout, texts, theme, fonts | `ui/hud.tscn`, `ui/theme.tres`, `ui/fonts/` |
| Bridge physics feel, build messages, blueprint / ordered / scaffold colours | **Bridge** node in `levels/level_base.tscn` |
| Build button text | **HUD** node in `ui/hud.tscn` (Commit Text) |

## Sound and music

- `data/sounds/*.tres` are SoundEffect resources. Each has a list of streams (one is picked at random each play), a volume, and a pitch spread. Point any sound slot in the Inspector at one.
- Music is set per level, on the level root's **Music**. Any stream loops.
- `audio/` holds synthesized placeholder WAVs. Drop in real files and re-point the resources.
- Buses: Master, Music, SFX (`audio/default_bus_layout.tres`).

## Dev scripts (`dev/`, not exported)

- `generate_levels.tscn`: regenerates starter levels with the original game's random generator. It skips existing files unless run with `-- force`.
- `build_tileset.gd`: redraws the placeholder atlas and rebuilds the TileSet.
- `bootstrap_data.tscn`: recreates any missing data resource.
- `synth_placeholder_audio.py`: rewrites the placeholder audio.
- `screenshot.tscn`: plays a few seconds and saves a PNG.

Tests: `godot --headless -s res://addons/gut/gut_cmdln.gd`
