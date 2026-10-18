# Sappers' March — designer guide

Everything below is done in the Godot editor (4.7). No code needed.

## Balancing: the ValueTweaks node

Open `game/main.tscn` and select **ValueTweaks**. Its Inspector lists the main balance values in one place:

| Section | Values |
| --- | --- |
| army | starting soldiers, soldier hit points, mutiny time (seconds blocked before a soldier deserts), recruit price |
| crew | number of engineers |
| enemies | archer hit points |
| supplies | starting supplies, checkpoint supplies |
| prices | what each tool costs (build tools: their material) |
| yields | what digging each tile gives, and what felling a tree gives |
| art | **Terrain V2**: draw the ground with the v2 tiles (on) or the old tiles (off) |

The node stores nothing itself. Each value is the real one in the file that owns it (`data/campaign.tres`,
`data/army_rules.tres`, `data/crew_rules.tres`, `data/archer_rules.tres`, `data/tools/*.tres`, `data/bridge/*.tres`,
`data/terrain/*.tres`). Changing it here changes and saves that file, and changing the file shows up here. There is no
undo for edits made here. Tools and terrain types with a cost or yield appear on their own; to list another terrain
type, add it to the node's **Terrain Types**.

## Levels

| Task | How |
| --- | --- |
| New level | Scene → New Inherited Scene → `levels/level_base.tscn`. Save as `levels/level_NN.tscn`. |
| Paint ground | Select **Terrain**, open the TileMap panel, paint. Every tile's behaviour comes from its TerrainType (below). Left, right and below the painted area count as bedrock. Above is open sky. |
| Start / end | Move **StartFlag** (the column camps here) and **ExitFlag** (the level ends when the front soldier passes it). Put each flag's origin on the ground. |
| How levels join | The game is one continuous march. Each level is attached so its **StartFlag** lands on the previous level's **ExitFlag**, moved up or down to match. Ground left of the StartFlag column is only used on the first level, so keep the area right of the ExitFlag a flat run at the same height as the next level's start. The next level loads in the background while the column is still on this one, and levels far behind are removed. |
| Enemies | Drag `objects/archer/archer.tscn` under **Objects** (the game only finds archers there, and the level checks flag one placed anywhere else). Its origin is its feet, so put it on top of a solid tile. It dies when that tile is dug or collapses, or when soldiers reach it and cut it down. Tune range and reload in the Inspector. Hit points are shared by all archers: **Hit Points** in `data/archer_rules.tres` (or ValueTweaks). |
| Music, reinforcements, supply drop | Select the root node and use the Inspector. The supply drop and reinforcements are given on arrival, but not on the first level. Leave **Supply Drop** empty to use the campaign's **Checkpoint Supplies**; set it only for a level that should drop something different. |
| Order of levels | `data/campaign.tres` → **Levels** (a list of level files). Starting soldiers, starting supplies, tools, jingles, the camp music and the dawn bugle are set there too. |

Checks: run the GUT panel (or `test/unit/test_levels.gd`). It flags levels with buried or floating flags, archers standing on nothing, seams the column can't walk over, and similar mistakes.

## Night camp

At the start of every level the column makes camp. **Dusk**: night falls while every soldier walks to their spot behind the camp flag (back or forward) and lies down. **Night**: the soldiers sleep and the engineers keep digging and building. **Morning**: when the player presses **March** (M) or the king loses patience, day breaks, everyone gets up and the camp is struck, then the column marches.

| What | Where |
| --- | --- |
| Length of the night | **March Delay** on the level's root node, counted from arrival (dusk included). 0 means no camp. |
| Length of dusk and morning | **Dusk Time** / **Morning Time** on `game/world.tscn` |
| Gap between sleepers, how long a soldier stands before lying down | **Camp Spacing** / **Settle Time** in `data/army_rules.tres` (the gap shrinks if the world ends close behind the camp) |
| Tents, fire, firelight, crackle | `objects/camp/camp.tscn` (its origin is the camp flag; the column sleeps to its left) |
| Sleeping soldier pose and the "z" | **Asleep** node and the "sleep" animation in `objects/soldier/soldier.tscn` |
| Night colours, fade time, cursor lantern strength | **DayNight** node in `game/main.tscn` (lantern light: **Lantern** node) |
| Camp music, dawn bugle | `data/campaign.tres` → Camp group |
| Recruit button text and where it floats | **Recruit Text** on the **HUD** node in `ui/hud.tscn`; the button floats at the **ButtonSpot** marker in `objects/camp/camp.tscn` |
| Price of a recruit, its sound and text | **Recruit Cost** / **Recruit Sound** / **Recruit Text** in `data/army_rules.tres` (the army limit is **Max Soldiers** there) |
| Where gold comes from | Gold ore tiles (`data/terrain/crystal.tres`), the campaign's **Start Supplies**, and each level's **Supply Drop** |
| Do archers shoot at night | **Rests At Night** on `objects/archer/archer.tscn` |
| How early the next level loads, how far behind levels are removed | **Stream Ahead** / **Unload Behind** on `game/world.tscn` |

## Tiles and terrain types

- `data/terrain/*.tres` holds one TerrainType per material. It sets: solid, natural ground (anchors bridges and holds bricks), structure (collapses when nothing holds it up), falls (fill), hazard (water or spikes, with the death and "ahead" texts), dig action and yields, and debris colour.
- `world/tileset.tres` is the TileSet. Each tile's **terrain** custom data points to a TerrainType. To add a material: create a TerrainType, add tiles to the atlas, and set their **terrain** data.
- `world/tiles.png` is placeholder art. Replace it with your own; keep the layout or reassign the tiles in the TileSet editor.

### The v2 terrain tiles

The ground is painted with the v2 tiles (`world/tiles_v2.png`): source 1 of `world/tileset.tres`, next to the old tiles
(source 0). Paint them like any tiles in the TileMap editor.

- **Every v2 tile carries its material.** Grass, wall and dirt tiles come in one alternative per material: soil, rock
  and bedrock. The alternative you paint sets what the ground *is*, for example a grassy tile that is really bedrock.
  Pick the alternative in the TileSet panel's alternative tiles (the number badge on the tile). Fillets (the grass
  curves in the air at the foot of a step) are air. Water and spikes are their own tiles.
- **Rock in the dirt is drawn for you.** Paint rock cells with the full rock tile. The rounded dirt-to-rock edges are
  an overlay on the half-cell grid, and it shows in the editor as you paint.
- **Retile** (select the level's **Terrain** node, then the button at the top of the Inspector) fixes every cell whose
  tile does not fit its neighbours and keeps every tile that does. Paint roughly with any tile of the right material,
  press Retile, then save. Variants you picked by hand stay as long as they still fit.
- **While playing,** the same rules re-pick the tiles around anything that changes the ground (digging, collapses,
  fill), so edges stay matched.
- **Other materials** (brick, trees, fill, gold ore) have no v2 art and use their old tiles.
- **The roles** are in `data/terrain_look.tres`: which atlas tiles are flat tops, corners, walls, inner corners, dirt,
  rock, fillets, water and spikes. A role with several tiles gives variety: a cell that needs a new tile picks one by
  its position. The `*_alt` roles (the square grass corners) are valid when painted but never picked. **Body** is the
  rock overlay: 16 tiles indexed by which of the four cells around a corner are rock (top-left 1, top-right 2,
  bottom-left 4, bottom-right 8). The two diagonal cases (6 and 9) have no art yet and fall back to full rock.
- **Switching off** (**Enabled** on the look, or **art › Terrain V2** on ValueTweaks) draws everything with the old
  tiles: the *Classic look* roles, with grass where soil meets the air. Levels need no repainting either way.
- Rock touching the air gets the grass edge like dirt, because the sheet has no bare-rock edge pieces.

**Changing the sheet.** Edit `world/tiles_v2.png` (the sky colour **Sky Key** is cut out for you), update the roles in
`data/terrain_look.tres` if tiles moved or were added, then from `Godot/`:

```sh
godot --headless res://dev/build_tiles_v2.tscn -- art       # tiles_v2_keyed.png: the sheet with the sky transparent
godot --headless --import
godot --headless res://dev/build_tiles_v2.tscn -- tileset   # rebuilds source 1 of the TileSet
godot --headless res://dev/convert_levels_v2.tscn           # optional: retile every campaign level
```

## Objects and tuning

| What | Where |
| --- | --- |
| Soldier look and walk cycle | `objects/soldier/soldier.tscn` (sprite + AnimationPlayer "walk"/"idle"/"sleep") |
| March speed, step-up, fall damage, how far ahead dangers are warned about, melee reach/speed/damage against archers, max army, messages (including the siege and "waiting for the column" status) | `data/army_rules.tres` |
| How long soldiers must attack a tower before it falls | **Raze Time** on the terrain type (`data/terrain/brick.tres`, 15 s of one soldier's attack; 0 means it can't be attacked) |
| How long the column camps before the king orders the march | **March Delay** on each level's root node (default in `levels/level_base.tscn`) |
| March and camp banner texts, march sound, camp status | **Game** node in `game/main.tscn` |
| How long a tile takes to dig | **Dig Time** on each terrain type in `data/terrain/` |
| Engineer crew: size, walk and climb speed, dig speed, dig reach, step-up, ground climb and drop limits, fall gravity, stranded time (then an engineer climbs any height back to the column), strike delay, sounds | `data/crew_rules.tres` (how fast each piece type is built: **Build Speed** on `data/bridge/*.tres`) |
| Engineer look | `objects/engineer/engineer.tscn` (its own placeholder until engineer art exists; keep the Body, Wounded and AnimationPlayer nodes the soldier script uses) |
| Bridge / support / rope strength, length, mass, cost, colours | `data/bridge/log.tres` (Bridge), `support.tres`, `rope.tres`. **Walkable** decides if soldiers walk on it; **Draw Layer** puts it behind (lower) or over (higher) other members. |
| Tool rack: names, hints, keys, costs, hold-repeat | `data/tools/*.tres` (rack order is the Campaign's **Tools** list). Each button shows its cost as supply swatches (build tools use their material's cost) and dims when it can't be afforded; the dim look is on `ui/tool_button.tscn` |
| Arrows | `objects/arrow/arrow.tscn` |
| Falling fill | `objects/falling_block/falling_block.tscn` |
| Debris, floating text | `objects/effects/` |
| Sky, sun, mountain ridges | `world/background/background.tscn` |
| HUD layout, texts, theme, fonts | `ui/hud.tscn`, `ui/theme.tres`, `ui/fonts/` |
| Bridge physics feel, build messages, blueprint / ordered / scaffold colours | **Bridge** node in `game/world.tscn` |
| Build buttons above plans: text, look, height | **Build Text** on the **HUD** node in `ui/hud.tscn`; the Build + cancel pair is `ui/plan_buttons.tscn`; **Plan Button Rise** on the **Game** node in `game/main.tscn` |

## Sound and music

- `data/sounds/*.tres` are SoundEffect resources. Each has a list of streams (one is picked at random each play), a volume, and a pitch spread. Point any sound slot in the Inspector at one.
- Music is set per level, on the level root's **Music**; it starts when the column breaks camp. The campaign's **Camp Music** plays during the night. Any stream loops.
- `audio/` holds synthesized placeholder WAVs. Drop in real files and re-point the resources.
- Buses: Master, Music, SFX (`audio/default_bus_layout.tres`). The bus volumes there are the full-volume mix; the player's **Sound** panel (Music and Sound sliders) scales them and remembers the setting in `user://settings.cfg`. Which buses the sliders drive: **Music Bus** / **Sound Bus** on the **HUD** node in `ui/hud.tscn`.

## Dev scripts (`dev/`, not exported)

- `generate_levels.tscn`: regenerates starter levels with the original game's random generator. It skips existing files unless run with `-- force`.
- `build_tileset.gd`: redraws the placeholder atlas and rebuilds the TileSet.
- `bootstrap_data.tscn`: recreates any missing data resource.
- `synth_placeholder_audio.py`: rewrites the placeholder audio.
- `screenshot.tscn`: plays a few seconds and saves a PNG (`march` skips the camp, `look=<x>` parks the camera).

Tests: `godot --headless -s res://addons/gut/gut_cmdln.gd`
