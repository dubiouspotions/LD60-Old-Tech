# Siege Engineers

A Ludum Dare 60 game ("Old Tech") made in Godot 4.7.

When the king's army starts to march, it refuses to stop for anything. Once it sets off, the column walks east straight off ravines, into water and spikes, and onto bridges that aren't finished. Only a wall over 1 m or a gap lower than 2 m stops it, or an archer it reaches: soldiers stop to cut him down, then march on. A brick tower in the way is besieged: the front soldier hacks at it until, after a good while, the whole tower comes down, archer and all.

You are the Royal Siege Engineers. Dig, chop, throw sandbags and bridge a way through before the archers' towers thin the ranks.

## How to play

Start a **New Game** from the main menu. Pick a tool from the toolbar (or press 1–5), then click the world to show your engineers where. You can only order what you have the supplies for.

| Tool | Key | What it does |
| --- | --- | --- |
| Dig/Chop | 1 | Marks soft earth (+1 earth), trees (the trunk gives logs, leaves give rope), rock (+1 stone, slow) and gold ore (+1 gold) for the engineers to dig. Click a mark again to clear it. Mark any part of a tree and it is cut at the base; dig the ground out from under a tree and it falls with the same yield. Marking a built bridge piece has an engineer take it apart (a rope comes back at once). |
| Bridge | 2 | Drag from point to point to plan a bridge deck soldiers walk on. A picker above the button chooses the material: **Log** (push and pull, up to 5 m, 1 log per started metre) or **Stone** (heavy and much stronger, up to 3 m, 1 stone per started metre). |
| Support | 3 | Plans a log that holds the structure up but is not walked on. Up to 5 m, 1 log per started 2 m. |
| Rope | 4 | Plans a rope. Only pulls, up to 12 m, 1 rope per started metre. |
| Sandbag | 5 | Costs 10 earth. An engineer walks within throwing range and lobs a sandbag there; it lands as a solid block. A bag that hits anything on the way bursts harmlessly. Click the order again to take it back. |

### Building

- Bridge, Support and Rope place a dashed blueprint, and the supplies are spent when you place it. Cancelling a plan nobody has started gives all of it back; taking apart a built piece gives back one less (at least one).
- Build tools work two ways. **Drag** from point to point for one piece, or **click** the start and then the end. Hold **Shift** to chain: each click places the next piece from the end of the last. Let go of Shift, right-click or press **Esc** to stop. A click that can't be built (too long, through the ground, not enough supplies) leaves the piece where it was.
- Ends snap to a 0.5 m grid, to existing joints, and to any point along a bridge or support (which is split there with a hinge). An end touching ground is bolted down. A plan may start anywhere, even in mid-air, but it can only be built once it connects to ground or finished work.
- While you plan, idle engineers walk over and wait beside it. **Build** above a plan hands it to them, **×** cancels it; **Enter** hands over every plan. They build member by member, climbing along what is already up, all working together when there is only one job. Finished parts are held on scaffolding, and each structure comes off it once it's done and no engineer is on it. Then your design holds or it doesn't.
- The column waits at the foot of a structure under construction and crosses once it stands on its own. It doesn't wait for a plan nobody has started: a soldier walking onto that falls.
- Joints are hinges, so build triangles or hang the deck from ropes. Each soldier weighs 80 kg, decks flex under them (the longer, the more), and members glow red as they near breaking.

### The march

- The march is one long road: each level joins the last. At the start of each level the column makes camp and sleeps through the night while your engineers keep working, until the king loses patience (30 s by default). Press **M** or **March now** to break camp early. Archers hold their fire while the column sleeps.
- Soldiers who reach a level's exit flag wait for the rest of the column. Once every living soldier is there, the next camp brings reinforcements and supplies.
- **Stone** comes from digging rock and from towers your soldiers raze. **Gold** comes from gold ore, your starting supplies and camp supply drops.
- From the second camp on, the **Camp Shoppe** sells soldiers (2 gold, or press **R**) and engineers (5 gold). You start with a single engineer.
- A soldier stuck in front of a wall or a ceiling too low to pass loses heart: after 8 s it deserts and climbs back the way the army came. Besieging a tower or fighting an archer doesn't count. The status bar counts down.
- Engineers die in spikes and water, and can be crushed. The level is lost when the last soldier or the last engineer dies. You then retry from the last camp with the army and supplies you had when you got there.

### Controls

| Key | Action |
| --- | --- |
| 1–5 | Pick a tool |
| Left click / drag | Use the tool |
| Shift | Chain build pieces |
| Enter | Build every plan |
| Space | Pause. You can plan and build while paused. |
| F | Toggle 2× speed |
| C | Follow the column (panning by hand turns it off) |
| M | March now |
| R | Buy a soldier at camp |
| Backspace | Restart the level from its checkpoint |
| Esc | Put down the piece in hand, or open the pause menu |
| WASD / arrows, right or middle drag, mouse wheel | Move the view |

The pause menu (Esc or **Menu**) offers Resume, Restart from Checkpoint, Restart (the whole campaign), Settings and Quit to Main Menu. **Settings** holds the music and sound volumes and full screen; they are remembered between sessions.

## Running

1. Install [Git LFS](https://git-lfs.com) and run `git lfs install` before cloning; images, audio and fonts are stored with it.
2. Open `Godot/project.godot` in Godot 4.7.2 and press F5 to start at the main menu. F6 on a level scene plays that level on its own.
3. Run the tests (GUT) with `godot --headless -s res://addons/gut/gut_cmdln.gd` from the `Godot/` folder, or use the GUT panel in the editor.

## Making content

Levels, tiles, tools, bridge materials, army and crew rules, sounds and music are all scenes and resources you edit in the editor, with no code. See [Godot/DESIGNERS.md](Godot/DESIGNERS.md). Coding agents should read [AGENTS.md](AGENTS.md).

| Folder | Contents |
| --- | --- |
| `Godot/levels/` | Level scenes. All inherit `level_base.tscn`. |
| `Godot/data/` | Campaign, terrain types, tools, bridge materials, army, crew and archer rules, sound effects |
| `Godot/objects/` | Soldier, engineer, archer, arrow, sandbag, falling blocks, camp, flags, signs, birds, effects |
| `Godot/world/` | Terrain (TileMapLayer + TileSet), tall grass, bridge simulation, background |
| `Godot/game/` | World, game flow, army, engineer crew, camera, tool input, day and night |
| `Godot/ui/` | HUD, pause and settings menus |
| `Godot/menu/` | Main menu and its bridge-collapse backdrop |
| `Godot/post/` | Night colour grade |
| `Godot/core/` | Resource types and autoloads (GameState, Audio, Settings, Effects) |
| `Godot/audio/` | Music and sound files |
| `Godot/dev/` | Tools for levels, tiles, grass, data and placeholder audio. Not exported. |
| `Godot/test/` | GUT tests |

## Builds

Pushing to `main` or `deploy` runs the GitHub Actions workflow. It exports Web, Windows, macOS and Linux builds with Godot 4.7.2. The `deploy` branch, or a manual run, also uploads them to itch.io; this needs the `ITCHIO_*` secrets set. Build failures are reported to Discord via `DISCORD_WEBHOOK_URL`.

## Credits

- Made for Ludum Dare 60 by the LD60-Old-Tech team.
- Fonts in `Godot/ui/fonts/`:
  - Alagard by Hewett Tsoi, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
  - Medodica by [Roberto Mocci](https://patreon.com/rmocci), SIL Open Font License.
  - [Chivo](https://github.com/Omnibus-Type/Chivo), SIL Open Font License.
- Tests use [GUT](https://github.com/bitwes/Gut) (MIT).
- Some sound effects are generated placeholders (`Godot/dev/synth_placeholder_audio.py`).
