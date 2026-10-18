# Sappers' March

A Ludum Dare 60 game ("Old Tech") made in Godot 4.7.

The column marches east on its own, and orders are orders. Once it sets off it walks straight off ravines, into water and spikes, and onto bridges that aren't finished. Only a wall over 1 m or a gap lower than 2 m stops it, or an archer it reaches: soldiers stop to cut him down, then march on. A brick tower in the way is besieged: the front soldier hacks at it until, after a good while, the whole tower comes down, archer and all. You are the engineers above the field. Dig, fill and bridge a way through before the archers' towers thin the ranks.

## How to play

| Tool | Key | What it does |
| --- | --- | --- |
| Dig | 1 | Marks soft earth (+1 earth), trees (trunk gives logs, leaves give rope) and gold ore (+1 gold) for the engineers to dig. Click a mark again to clear it. Mark any part of a tree and it is cut at the base; dig the ground out from under a tree and it falls with the same yield. Digging a bridge member takes it back at once. |
| Fill | 2 | Drops a block of earth that falls until it lands. Costs 1 earth. |
| Bridge | 3 | Drag from point to point to plan a bridge deck (a log soldiers walk on). Takes push and pull, up to 5 m. Costs 1 log. |
| Support | 4 | Plans a log that holds the structure up but is not walked on. Up to 5 m. Costs 1 log. |
| Rope | 5 | Drag from point to point to plan a rope. Only pulls, up to 12 m. Costs 1 rope. |

- Bridge, Support and Rope place a dashed blueprint, and supplies are spent when you place it. Digging a planned member refunds it.
- While you plan, idle engineers (orange) walk over and wait beside it. **Build** above a plan hands that plan to them, **×** beside it cancels the plan and refunds it; **Enter** hands over every plan. They build it member by member, starting from the ground or finished parts and climbing along what is already up. With only one thing to build or dig, they all work on it together. Finished parts are held on scaffolding, and the column can already walk on them; pieces still being built can't be walked on. Each separate structure comes down off its scaffolding once it's finished and no engineer is on it, and your design holds or it doesn't. The column doesn't wait for it: a soldier walking onto an unfinished bridge falls.
- Bridge ends snap to a 0.5 m grid, to existing joints, and to any point along a bridge or support (which is split there into two pieces joined by a hinge). An end touching ground is bolted down. A plan may start anywhere, even in mid-air, but the engineers can only build it once it connects to ground or finished work.
- Joints are hinges, so build triangles or hang the deck from ropes. Members glow red as they near breaking, and each soldier adds 80 kg.
- The march is one long road: each level joins the last. At the start of every level the column makes camp and sleeps through the night while your engineers keep working, until the king loses patience (30 s by default). Use the night to build ahead, and press **M** or **March** to break camp early. Archers hold their fire while the column sleeps.
- **Gold** comes from gold ore, your starting supplies and each camp's supply drop. While the column camps, press **R** or **Recruit** to buy another soldier (5 gold); recruits join the camp.
- **Space** pauses. Plan and build while paused, then resume to load the bridge.
- **F** toggles 2× speed. **C** makes the camera follow the column again. **Sound** (bottom right) sets music and sound volume; it is remembered between sessions.
- Move the view with **WASD**/arrow keys, right or middle drag, or the mouse wheel.
- A soldier stuck in front of a wall or a ceiling too low to pass loses heart: after 8 s it deserts, turns round and climbs back the way the army came. Besieging a tower or fighting an archer doesn't count. The status bar counts down.
- Soldiers who reach a level's exit flag wait there for the rest of the column. Once every living soldier has arrived, it means camp, reinforcements and supplies. If the column falls, you retry from that camp with the army and supplies you had when you got there; work done since is undone.

## Running

1. Open `Godot/project.godot` in Godot 4.7.2 and press F5.
2. Run the tests (GUT) with `godot --headless -s res://addons/gut/gut_cmdln.gd` from the `Godot/` folder, or use the GUT panel in the editor.

## Making content

Levels, tiles, tools, bridge materials, army rules, sounds and music are all scenes and resources you edit in the editor, with no code. See [Godot/DESIGNERS.md](Godot/DESIGNERS.md).

| Folder | Contents |
| --- | --- |
| `Godot/levels/` | Level scenes. All inherit `level_base.tscn`. |
| `Godot/data/` | Campaign, terrain types, tools, log/rope, army rules, sound effects |
| `Godot/objects/` | Soldier, archer, arrow, falling block, camp, flags, effects |
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
