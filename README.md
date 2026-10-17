# Sappers' March

A Ludum Dare 60 game ("Old Tech") made in Godot 4.7.

The column marches east on its own. It halts at anything it can't cross: walls over 1 m, drops over 3 m, water and spikes. You are the engineers above the field. Dig, fill, bridge and blast a way through before the archers' towers thin the ranks.

## How to play

| Tool | Key | What it does |
| --- | --- | --- |
| Dig | 1 | Digs soft earth (+1 earth) and fells trees (trunk gives logs, leaves give rope). Mines cyan crystals (+1 powder). Digging a bridge member takes it back. |
| Fill | 2 | Drops a block of earth that falls until it lands. Costs 1 earth. |
| Log | 3 | Drag from point to point to plan a deck log. Takes push and pull, up to 5 m. Costs 1 log. |
| Support | 4 | Plans a log that holds the structure up but is not walked on. Up to 5 m. Costs 1 log. |
| Rope | 5 | Drag from point to point to plan a rope. Only pulls, up to 12 m. Costs 1 rope. |
| Charge | 6 | Blasts rock, brick, bridges and your own soldiers within 2.6 m. Costs 1 powder. |
| Pan | 7 | Drag to move the view. |

- Log, Support and Rope place a dashed blueprint, and supplies are spent when you place it. Digging a planned member refunds it.
- **Enter** or the **Build** button hands the plan to the engineers (orange). They build it member by member, starting from the ground or finished parts and climbing along what is already up. Finished parts are held on scaffolding, and the column can't cross them yet. When the last engineer is back on the ground the scaffolding comes down, and your design holds or it doesn't. The column waits at any deck or ramp still being built.
- Bridge ends snap to a 0.5 m grid and to existing joints. An end touching ground is bolted down.
- Joints are hinges, so build triangles or hang the deck from ropes. Members glow red as they near breaking, and each soldier adds 80 kg.
- Each level the column waits at the start until the king loses patience (30 s by default). Use the time to build ahead, and press **M** or **March** to set off early once you're ready.
- **Space** pauses. Plan and build while paused, then resume to load the bridge.
- **F** toggles 2× speed. **C** makes the camera follow the column again.
- Move the view with **WASD**/arrow keys, right or middle drag, or the mouse wheel.
- Reaching a level's exit flag brings reinforcements and supplies. If the column falls, you retry the level with the army and supplies you had when it began.

## Running

1. Open `Godot/project.godot` in Godot 4.7.2 and press F5.
2. Run the tests (GUT) with `godot --headless -s res://addons/gut/gut_cmdln.gd` from the `Godot/` folder, or use the GUT panel in the editor.

## Making content

Levels, tiles, tools, bridge materials, army rules, sounds and music are all scenes and resources you edit in the editor, with no code. See [Godot/DESIGNERS.md](Godot/DESIGNERS.md).

| Folder | Contents |
| --- | --- |
| `Godot/levels/` | Level scenes. All inherit `level_base.tscn`. |
| `Godot/data/` | Campaign, terrain types, tools, log/rope, army rules, sound effects |
| `Godot/objects/` | Soldier, archer, arrow, charge, falling block, flags, effects |
| `Godot/world/` | Terrain (TileMapLayer + TileSet), bridge simulation, background |
| `Godot/game/`, `Godot/ui/` | Game flow, camera, tool input, HUD |
| `Godot/core/` | Resource types and autoloads (GameState, Audio, Effects) |
| `Godot/dev/` | Generators for levels, tiles, data and placeholder audio. Not exported. |
| `Godot/test/` | GUT tests |

## Builds

Pushing to `main` or `deploy` runs the GitHub Actions workflow. It exports Web, Windows, macOS and Linux builds with Godot 4.7.2. The `deploy` branch, or a manual run, also uploads them to itch.io; this needs the `ITCHIO_*` secrets set. Build failures are reported to Discord via `DISCORD_WEBHOOK_URL`.

Binary assets (images, audio, fonts, models) are stored with Git LFS. Run `git lfs install` before cloning.

## Credits

- Port of the original Sappers' March web prototype.
- Fonts: [Big Shoulders Stencil](https://github.com/xotypeco/big_shoulders) and [Chivo](https://github.com/Omnibus-Type/Chivo), SIL Open Font License (`Godot/ui/fonts/`).
- Tests use [GUT](https://github.com/bitwes/Gut) (MIT).
- Tile art and audio are generated placeholders (see `Godot/dev/`).
