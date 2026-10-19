# Sappers' March — designer guide

Everything below is done in the Godot editor (4.7). No code needed.

## Balancing: the ValueTweaks node

Open `game/main.tscn` and select **ValueTweaks**. Its Inspector lists the main balance values in one place:

| Section | Values |
| --- | --- |
| army | starting soldiers, soldier hit points, mutiny time (seconds blocked before a soldier deserts), recruit price; crew: engineer hire price |
| crew | number of engineers |
| enemies | archer hit points |
| supplies | starting supplies, checkpoint supplies |
| prices | what each tool costs (build tools: their material) |
| yields | what digging each tile gives, and what felling a tree gives |
| art | **Terrain V2**: draw the ground with the v2 tiles (on) or the old tiles (off). **Light Dither**: how the night lights fade out (see *Night camp*): **Enabled** (off fades smoothly), **Pixel Size** (screen pixels per dither pixel; 4 matches the tiles and soldiers), **Steps** (brightness levels, 1 = pure on/off), **Pattern** (Bayer 2, 4 or 8: neat ordered grids, bigger is finer; Noise: scattered grain; Bands: no dither, hard rings), **Spread** (1 dithers all the way between levels, 0 gives hard bands), **World Space** (on: the pattern is fixed to the ground and lights move over it; off: each light carries its pattern along), **Animated** with **Frames Per Second** and **Frames** (the pattern shimmers, looping every Frames) |

The node stores nothing itself. Each value is the real one in the file that owns it (`data/campaign.tres`,
`data/army_rules.tres`, `data/crew_rules.tres`, `data/archer_rules.tres`, `data/tools/*.tres`, `data/bridge/*.tres`,
`data/terrain/*.tres`). Changing it here changes and saves that file, and changing the file shows up here. There is no
undo for edits made here. Tools and terrain types with a cost or yield appear on their own; to list another terrain
type, add it to the node's **Terrain Types**.

## Levels

| Task | How |
| --- | --- |
| New level | Scene → New Inherited Scene → `levels/level_base.tscn`. Save as `levels/level_NN.tscn`. |
| Play a level | Open it and press **Run Current Scene** (F6): the game starts at that level, marching at once (no intro card). A level not yet in the campaign is played on its own. |
| Paint ground | Select **Terrain**, open the TileMap panel, paint. Every tile's behaviour comes from its TerrainType (below). Left, right and below the painted area count as bedrock. Above is open sky. |
| Start / end | Move **StartFlag** (the column camps here) and **ExitFlag** (the level ends when the front soldier passes it). Put each flag's origin on the ground. |
| How levels join | The game is one continuous march. Each level is attached so its **StartFlag** lands on the previous level's **ExitFlag**, moved up or down to match. Ground left of the StartFlag column is only used on the first level, so keep the area right of the ExitFlag a flat run at the same height as the next level's start. The next level loads in the background while the column is still on this one, and levels far behind are removed. |
| Enemies | Drag `objects/archer/archer.tscn` under **Objects** (the game only finds archers there, and the level checks flag one placed anywhere else). Its origin is its feet, so put it on top of a solid tile. It dies when that tile is dug or collapses, or when soldiers reach it and cut it down. When its tower falls it rides it down, and dies only if the tower breaks up. It shoots at the nearest soldier in range that it has a clear shot at (no ground or log on the arrow's arc), and at the nearest in range only when it has a clear shot at nobody. A wall or log screen therefore makes it pick other targets rather than waste arrows. With no clear shot at anyone from where it stands, it first walks along its tower top, out to the edges, to the nearest spot that gives it one (**Walk Speed**), and fires anyway only if there is none. Tune range and reload in the Inspector. Hit points are shared by all archers: **Hit Points** in `data/archer_rules.tres` (or ValueTweaks). |
| Tutorial signs | Drag `objects/sign/sign.tscn` under **Objects**. Its origin is the bottom of the board: put it where the board should hang. Tick **Post** for a post that reaches down to the ground by itself (it follows the sign as you move it and the ground as it is painted or dug); off by default, the board hangs on its own. The level checks flag a board in the ground. Type the board's words in **Text**. The board fits its text: it wraps past **Max Width** and adds **Padding** (left/right, top/bottom); **Font** (alagard), **Font Size** and **Font Color** are on the sign too. A lamp lights it during the night camp. It is drawn in front of the ground and behind the characters and the tall grass (**Z Index** 1). See the three signs in `level_01.tscn`. |
| Music, reinforcements, supply drop | Select the root node and use the Inspector. The supply drop and reinforcements are given on arrival, but not on the first level. Leave **Supply Drop** empty to use the campaign's **Checkpoint Supplies**, and **Reinforcements** at -1 to use its **Checkpoint Reinforcements** (none); set them only for a level that should be different. Both campaign values are in `data/campaign.tres`. |
| Order of levels | `data/campaign.tres` → **Levels** (a list of level files). Starting soldiers, starting supplies, tools, jingles, the camp music and the dawn bugle are set there too. |

Checks: run the GUT panel (or `test/unit/test_levels.gd`). It flags levels with buried or floating flags, archers standing on nothing, signs with the board in the ground, seams the column can't walk over, and similar mistakes.

## Night camp

At the start of every level the column makes camp. **Dusk**: night falls while every soldier walks to their spot behind the camp flag (back or forward) and lies down. **Night**: the soldiers sleep and the engineers keep digging and building. **Morning**: when the player presses **March** (M) or the king loses patience, day breaks, everyone gets up and the camp is struck, then the column marches.

| What | Where |
| --- | --- |
| Length of the night | **March Delay** on the level's root node, counted from arrival (dusk included). 0 means no camp. |
| Length of dusk and morning | **Dusk Time** / **Morning Time** on `game/world.tscn` |
| Gap between sleepers, how long a soldier stands before lying down | **Camp Spacing** / **Settle Time** in `data/army_rules.tres` (the gap shrinks if the world ends close behind the camp) |
| Tents, fire, firelight, crackle | `objects/camp/camp.tscn` (its origin is the camp flag; the column sleeps to its left) |
| Sleeping soldier pose and the "z" | **Asleep** node and the "sleep" animation in `objects/soldier/soldier.tscn` |
| Night colours, fade time | **DayNight** node in `game/main.tscn` |
| Night lights: cursor lantern, engineers' lamps (strength: **Night Energy**), camp fire (its **Flicker** animation) | **Lantern** node in `game/main.tscn`, **Lamp** node in `objects/engineer/engineer.tscn`, **FireLight** in `objects/camp/camp.tscn`. They use the **Mix** blend mode, so where lights overlap the brighter one wins instead of the two adding up. With Mix, energy 1 in white light shows things at their day colour, so night energies sit above 1 and lights fade from daylight, not from 0. Give any new light the Mix blend mode too. Each light's texture is a **DitheredLightTexture**: it fades out in dither pixels instead of a smooth gradient. Set its reach with **Size** (pixels across; keep the light's **Texture Scale** at 1 so the pixels stay crisp) and its **Gradient** (colour and opacity from centre to edge). How it dithers is its **Dither**, `data/light_dither.tres`, shared by every light and the night grade and also on ValueTweaks (**art › Light Dither**). The lights are nudged onto the art pixel grid so the dither lines up with the tiles. Tick **Local To Scene** on the texture (under Resource) so every copy of the light has its own; lights must not share one. Use one for any new light too. |
| Pollen and seed fluff on the wind by day: how many around the view (**Max Count**, 0 turns it off), **Wind** (left to right), flutter height and pace, how far down the view, colour, share of fluffy seeds | **Pollen** node in `game/world.tscn` (under AmbientLayer). It fades out at night. |
| Leaves bursting from a felled tree: leaves per leaf cell, leaves shaken loose by each swing of the axe while felling (**Per Chop**, on the beat of the crew's work sound), most at once, outward **Poof** speed, gravity, air **Drag** (how slowly they settle), sideways **Sway**, colours, longest life. Each is gone when it touches the ground. | **Leaves** node in `game/world.tscn`. **Leaf Types** says which terrain cells shed leaves. |
| Fireflies at night, by a tree or a bush: drag `objects/fireflies/fireflies.tscn` into a level's **Objects** and set **Amount** (most out at once, 0 turns it off), **Radius** (how far they roam from the node, metres; shown as a circle in the editor, where they fly as if it were night), **Speed**, **Life** (seconds each one lives), **Spawn Interval** (seconds between new ones), **Wander** (how often they change direction), **Blink Rate**, **Dim** (how bright between flashes), colour and glow. Under **Plant**: **Needs Plant** (on by default) stops new ones coming out once the nearest tree or bush within **Plant Reach** is chopped down (**Plant Types** says what counts: trunk and leaves) | Each level places its own swarms (named Fireflies1, 2, ... under **Objects**). They keep out of solid ground, and in the game they are moved onto the **Fireflies** node in `game/world.tscn` (under AmbientLayer, drawn above the night grade so they keep their colour). Keep the node itself in the air: `test_levels` checks it. |
| Night colour grade: which LUT the night fades into, how much of each light's reach keeps the day colours (**Reach**), how hard the edge is (**Falloff**), the light energy that keeps them fully (**Full Light Energy**), and how the fade around lights is dithered (**Dither**, the same `data/light_dither.tres` as the lights) | **Grade** node in `post/night_grade.tscn`. Every visible light in the game counts (camp fire, engineers' lamps, cursor lantern, any light you add). LUTs live in `post/lut/` as 17-slice strips imported as 3D textures; `low_17.png` changes nothing. |
| Stars: how many, colour, how far down the sky, share of bigger cross stars, twinkle depth and speed, shooting-star interval, length, speed and trail, and how far they drift sideways with the camera (**Parallax**, as the sky's by default; they wrap round the screen) | **Stars** node in `world/background/background.tscn`. They fade in with the night and keep their own colour under the night tint. **Star Seed** picks a different sky. |
| The background hills and forest: parallax art tiled across the screen (**Texture**, **Texture Height** as a share of the screen, **Parallax** share of the camera's travel); without a texture a node draws a plain ridge line instead. The pixel sky behind them is the same kind of node, tiled sideways (so it covers any width of window) with a small parallax | **RidgeFar** (`world/background/paralax_back.png`), **RidgeNear** (`paralax_front.png`) and **BakgrPixel** (the sky, `bakgr_pixel.png`) in `world/background/background.tscn` |
| The sun crossing the sky: it rises at dawn as the column breaks camp, follows the leader's way from the start flag to the exit flag, sets at the exit flag (dusk) and stays down all night. Where it rises and sets across the screen (**Rise X**, **Set X**), the horizon and the top of its arc (**Horizon Y**, **Peak Y**); drag **Progress** to preview. How far down it sits at night: **Sun Below** on the **World** node. How dark it is follows the sun along the **Darkness By Sun** graph on the **DayNight** node in `game/main.tscn` (x: the sun's progress, -0.2 down before dawn, 0 dawn, 0.5 midday, 1 sunset, 1.2 down at night; y: 0 full day, 1 full night): it sets the night tints, stars, night grade, fireflies and pollen. The night lights still come on with the camp | **SunPixel2** in `world/background/background.tscn`; `game/world.tscn` |
| Camp music, dawn bugle | `data/campaign.tres` → Camp group |
| Where the status (night timer) and March Now sit | **StatusPanel** and **MarchPanel** (with **MarchButton** in it) in `ui/hud.tscn`, both anchored to the top centre and growing both ways as their text changes. March Now wears the NinePatchPanel / PanelButton look. |
| Panning with the mouse | While the middle or right button drags the view, the HUD takes no mouse at all (no hovering, so the drag stays smooth over its buttons) until the button is let go. |
| A nine-patch panel with words-only buttons on it (the Camp Shoppe's look), for any menu | Set a PanelContainer's **Theme Type Variation** to **NinePatchPanel** and its Buttons' to **PanelButton** (both in `ui/theme.tres`: Alagard 16, no button backgrounds, the hover colour). A PanelButton glows with the highlight frame (`ui/styles/ninepatch_highlight.tres`, `ui/elements/panel_highlight_ninepatch.png`, the same nine-patch settings) when hovered or toggled on: the Camp Shoppe, March Now and the tool buttons, whose row sits on a NinePatchPanel too. **PanelText** is the matching Label look (tool names). The panel style itself is `ui/styles/ninepatch_panel.tres` (`ui/elements/panel_ninepatch.png`, its texture margins, tiling and tint), usable directly as a StyleBox too. |
| Camp Shoppe: the button hanging under the camp that drops down a soldier and an engineer to buy. It fades in once the first tent is up | Whether a level has one: **Camp Shoppe** on the level root (off on level 1). How long it fades in: **Shop Fade Time**. Purchase texts (**Soldier Text**, **Engineer Text**; the price follows with the gold icon), and how far it keeps from where the view stops scrolling (**Shop Edge Margin**). It belongs to the camp, so it stays under it: the rest of the HUD is drawn in front of it (the **WorldButtons** layer is moved to the back of the HUD when the game starts) on the **HUD** node in `ui/hud.tscn`, which also holds the **ShopButton** and **ShopMenu** nodes; the button hangs **Tiles Below Tents** (1) below the bottom of the lowest tent, across from the **ButtonSpot** marker, both in `objects/camp/camp.tscn` |
| Arrows at the screen edge pointing at what is off screen: blue at the column's leader, red at the nearest engineer | **LeadMarker** and **CrewMarker** in `ui/hud.tscn` (colour, size, arrow characters) |
| Price of a recruit, its sound and text | **Recruit Cost** / **Recruit Sound** / **Recruit Text** in `data/army_rules.tres` (the army limit is **Max Soldiers** there) |
| Price of an engineer, its sound and text, and the crew limit | **Hire Cost** / **Hire Sound** / **Hire Text** / **Max Crew** in `data/crew_rules.tres` |
| Where stone comes from | Rock tiles (`data/terrain/rock.tres`, **Dig Yield**) and razed towers (`data/terrain/brick.tres`, **Bulk Yield**) |
| Where gold comes from | Gold ore tiles (`data/terrain/crystal.tres`), the campaign's **Start Supplies**, and each level's **Supply Drop** |
| Do archers shoot at night | **Rests At Night** on `objects/archer/archer.tscn` |
| The dashed circle around each archer showing its shooting range (off by default; only the look, the range itself is **Shoot Range**) | **Show Range** and **Range Color** in the **Look** group on `objects/archer/archer.tscn` |
| When levels load: the next level loads as the column reaches each checkpoint (the start, a restart, or a level's camp), so the short hitch of stitching it on falls at the camp, not during the march. While camping, panning the view within **Stream Ahead** of the end of the world loads one more; by day nothing loads unless the column reaches an exit flag before its level is in. How far behind levels are removed: **Unload Behind** | **Stream Ahead** / **Unload Behind** on `game/world.tscn` |

## Tiles and terrain types

- `data/terrain/*.tres` holds one TerrainType per material. It sets: solid, natural ground (holds bricks up; bridge joints bolt to any solid tile), structure (falls when nothing holds it up), falls (boxes, sandbags), refills (water: it comes back when a sandbag or box that landed in it is dug out or falls out), hazard (water or spikes, with the death and "ahead" texts), dig action and yields, and debris colour.
- `world/tileset.tres` is the TileSet. Each tile's **terrain** custom data points to a TerrainType. To add a material: create a TerrainType, add tiles to the atlas, and set their **terrain** data.
- `world/tiles.png` is placeholder art. Replace it with your own; keep the layout or reassign the tiles in the TileSet editor.

### The v2 terrain tiles

The ground is painted with the v2 tiles (`world/tilemap-terrain.png`): source 2 of `world/tileset.tres`, next to the
old tiles (source 0). Paint them like any tiles in the TileMap editor. Source 1 (`tiles_v2_keyed.png`) is the earlier
v2 sheet; nothing uses it any more.

- **Every v2 tile carries its material.** Grass, wall, ceiling and dirt tiles come in one alternative per material:
  soil, rock and bedrock. The alternative you paint sets what the ground *is*, for example a grassy tile that is really
  bedrock. Pick the alternative in the TileSet panel's alternative tiles (the number badge on the tile). Fillets (the
  grass curves in the air at the foot of a step) are air.
- **Tunnels get ceilings.** Ground with air below gets the ceiling tiles (grass hanging down), and the cells where a
  tunnel roof meets its wall get the bottom inner corners. Digging a tunnel in play picks them for you.
- **Rock in the dirt is drawn for you.** Paint rock cells with the full rock tile. The rounded dirt-to-rock edges are
  an overlay on the half-cell grid, and it shows in the editor as you paint.
- **Painting re-picks the tiles around it.** Paint roughly with any tile of the right material: the tiles around what
  you painted that no longer fit their neighbours are re-picked as you go, and the rock overlay follows. Variants you
  picked by hand stay as long as they still fit. **Retile** (select the level's **Terrain** node, then the button at
  the top of the Inspector) does the same for every cell at once, for example after the roles changed.
- **Decorations are kept.** An old tile with no material painted in the air (source 0) is never touched by Retile or
  by digging next to it.
- **While playing,** the same rules re-pick the tiles around anything that changes the ground (digging, collapses,
  boxes), so edges stay matched.
- **Water, spikes and other materials** (brick, trees, box, gold ore) have no art on the sheet and use their old
  tiles. Water picks the *Classic look* surface and deep tiles; water or spikes you paint by hand are kept.
- **The roles** are in `data/terrain_look.tres`: which atlas tiles are flat tops, corners, walls, inner corners
  (top and bottom), ceilings, dirt, rock and fillets. **Flat Tops Fillet** are the tops under a fillet, drawn so the
  slope's grass runs on into them without gaps (empty uses Flat Tops). A role with several tiles gives variety: a cell that needs a new
  tile picks one by its position, and solid rock varies over the **Rock** tiles. The `*_alt` roles (the square grass
  corners) are valid when painted but never picked. **Body** is the rock overlay: 16 tiles indexed by which of the four
  cells around a corner are rock (top-left 1, top-right 2, bottom-left 4, bottom-right 8). The two diagonal cases (6
  and 9) have no art yet and fall back to full rock. The grass tufts tile (0, 0) is not used yet.
- **Switching off** (**Enabled** on the look, or **art › Terrain V2** on ValueTweaks) draws everything with the old
  tiles: the *Classic look* roles, with grass where soil meets the air. Levels need no repainting either way.
- **Rock never gets grass.** Rock and bedrock touching the air (the surface, a tunnel dug into rock) use the **Rock
  edges** roles on the look: the same places as the grass roles, plus fillets for steps of rock. The sheet has no rock
  edge art yet, so they are empty: an empty edge role draws the Rock tiles (square edges) and an empty fillet draws
  nothing. Draw the art, list it there, and run `build_tiles_v2.tscn -- tileset` so each tile gets its rock and bedrock
  alternatives; no code changes.

### Tall grass

Each level has a **Grass** layer (under the level root, after ExitFlag) for patches of tall grass that sway and are
drawn in front of the soldiers, engineers and objects. It grows by itself in the editor: whenever you paint the
Terrain, open the level or change a setting, the grass is regrown in patches on open soil, clear of the flags and
objects. Moved a flag or an object? Press **Regrow Grass** on the level root.

- **The settings** are the **Scatter** on the Grass node, `data/grass_scatter.tres` for every level: what ground it
  grows on, metres between patches (least, most), cells per patch (least, most), metres kept clear of flags, objects
  and the level's ends, and a seed for other places. Each level gets its own pattern from its file name. For one
  level that should differ, give its Grass node its own Scatter (*Make Unique*).
- **To paint grass by hand,** clear the Scatter on that level's Grass node, then pick the grass tile in the TileMap
  panel and paint it in the air cells right on top of the ground.
- Painting the ground in one spot never moves the grass elsewhere: where patches go depends only on the seed.
- Grass on ground that is dug away, or in a cell that gets filled, disappears while playing, and in the editor
  as soon as you paint ground over it or erase the ground under it.
- `godot --headless res://dev/scatter_grass.tscn` regrows and saves the grass of every level at once (after
  changing the settings, so levels you have not opened match).
- `test_levels` checks that every grass cell is in the air with ground under it.
- **The animation** plays the frames of `world/grass_anim.png` (8 px each, left to right, drawn at 4x like the rest
  of the art) from `world/tall_grass_material.tres`. Each column of the world starts one frame later than the column
  to its left, so the sway rolls along like wind. Open the material to tune it, and it shows in the editor as well:
  **Frame Time** (seconds per frame) and **Delay Frames** (how far each column lags: 0 sways all in step, negative
  rolls right to left). To add a frame, just widen the sheet by 8 px. Keep **Use Texture Padding** off on the
  grass TileSet's atlas, because the frames are read straight from the sheet.
- **Birds** hide in the grass. When a soldier or engineer comes within **Flush Distance** of a patch (joined grass
  cells), the patch's birds burst out once, flying up and away from whoever came. Tune it on the **Birds** node in
  `game/world.tscn`: its **Settings** (`data/bird_settings.tres`) hold the **Chance** a patch hides birds (0.3: most
  patches are empty), how many (**Per Patch**), **Tree Birds** and **First Chop Birds**; the node has the **Colors** they
  come in. A level can hide more or fewer: give its root node its own **Birds** settings (empty uses the default). The
  node sends **Tree Birds** (1–2) off the top of every tree that comes down
  (chopped, or its ground gone), both ways, and **First Chop Birds** (0–1) at the first swing of the axe at a tree, and now and then by day one bird across the view (**Cross Interval** seconds apart,
  in the top **Cross Height** of the view; none during the night camp). The flight (speed, climb, lift, flap speed,
  life) is on `objects/bird/bird.tscn`; each bird starts its flap on a random frame.
- **Bird art** is `world/bird.png`: nine 32 px frames facing right, white on black. White is the bird and black is
  see-through; `objects/bird/bird_mask.gdshader` paints the white in the bird's colour, so one sheet makes every
  colour. Keep it black and white (greys give a see-through edge).
- How far in front it draws is the **Z Index** of `world/tall_grass.tscn` (4: above soldiers 2 and arrows 3).

**Changing the sheet.** Edit `world/tilemap-terrain.png` (keep the sky transparent), update the roles in
`data/terrain_look.tres` if tiles moved or were added, then from `Godot/`:

```sh
godot --headless --import
godot --headless res://dev/build_tiles_v2.tscn -- tileset   # rebuilds source 2 of the TileSet
godot --headless res://dev/convert_levels_v2.tscn           # optional: retile every campaign level
```

A sheet whose sky is a solid colour instead: set it as **Source Texture**, the colour as **Sky Key** and a new file as
**Texture**, and run `build_tiles_v2.tscn -- art` first to cut the sky out.

## Objects and tuning

| What | Where |
| --- | --- |
| Soldier look and walk cycle | `objects/soldier/soldier.tscn` (sprite + AnimationPlayer "walk"/"idle"/"sleep") |
| Mutiny clock: the pie over a soldier blocked by a wall, running down clockwise until it deserts (**Mutiny Time** in `data/army_rules.tres`). Each soldier has its own, gone as soon as it moves again. Drawn as square pixels the size of the soldier sprite's (**Pixel Size**), **Diameter** art pixels wide, jumping one of **Ticks** steps at a time. Below **Warn Left** of the time it blinks between **Warn Color** and **Warn Blink Color** | **MutinyClock** node in `objects/soldier/soldier.tscn` (place it by moving the node; colours, **Blink Rate**; **Left** previews it in the editor) |
| March speed, step-up, fall damage, how far ahead dangers are warned about, melee reach/speed/damage against archers, stone chips and sparks per blow on a tower (**Hit Chips**, **Hit Sparks**; chips take the tower stone's **Debris Colour**), max army, messages (including the siege and "waiting for the column" status) | `data/army_rules.tres` |
| How long soldiers must attack a tower before it falls | **Raze Time** on the terrain type (`data/terrain/brick.tres`, 15 s of one soldier's attack; 0 means it can't be attacked) |
| A tower or tree whose ground is dug away: it falls as one piece with everything on it (the archer, battlements and other tiles painted in the air on it, flags, torches, any object on top or inside), smashing boxes under it and, if any of its tiles has **Crushes** on (brick yes, trunk and leaves no, so a falling tree kills nobody), crushing the soldiers, engineers and archers under it, and stands where it lands, after breaking a layer of the ground under it for every metre it fell beyond **Crush Free Fall** (1 m) and sinking into the hole, again and again until a short drop (3 m: 2 layers, then 1, then it stops; bedrock holds). If it fell more than **Survives Fall** (towers 3 m; trees 1 m, so a 2 m drop fells a tree), or onto spikes, it breaks up instead (a tower collapses, a tree is felled) and what it carried goes with it | **Survives Fall** and **Crushes** on `data/terrain/brick.tres`, `trunk.tres`, `leaves.tres` (the lowest in a piece counts for Survives Fall); fall gravity, top speed, landing sound and shake, **Crush Free Fall** on `objects/falling_piece/falling_piece.tscn`; the crunch of a tower breaking up (razed or fallen) is **Collapse Sound** on `world/terrain.tscn` (`data/sounds/collapse.tres`) |
| How long the column camps before the king orders the march | **March Delay** on each level's root node (default in `levels/level_base.tscn`) |
| March and camp banner texts, march sound, camp status, the status bar once the game is over (**Lost Status**, **Crew Lost Status**, **Victory Status**) | **Game** node in `game/main.tscn` |
| Losing a level: how long the world goes on before the lost card (**Lost Delay**, 1.5 s), then the card: the screen fades to its overlay (**Card Fade Time**) and the card slides up from below (**Card Slide Time**), with **Lost Sound** | **Lost Sound** in `data/campaign.tres`; **Lost Delay** on the **Game** node in `game/main.tscn`; fade and slide times on the **HUD** (`ui/hud.tscn`) |
| How long a tile takes to dig | **Dig Time** on each terrain type in `data/terrain/` |
| Several materials on one tool button (Bridge: Log and Stone): list them in **Bridge Material** and **Other Materials** on the tool (`data/tools/*.tres`); each shows as a clickable **Icon** (set on the material, `data/bridge/*.tres`) on the button itself. Icon size: **Material Icon Size** in `ui/tool_button.tscn` |
| Taking back a built bridge piece with Dig/Chop: it is marked, and an engineer takes it apart at the piece's **Build Speed**; a material with **Dismantle Instantly** (rope) comes back at once. Either way it gives back one less of each supply it cost, but at least one. A plan never built gives back all it cost. A sandbag dug up gives back the Sandbag tool's **Cost** less one the same way (its own Dig Yield is not used) | `data/bridge/*.tres`; sandbag cost: **Cost** on `data/tools/2_sandbag.tres` |
| Wood from trees: every tree that comes down (chopped, knocked down by a bridge piece, broken up by a fall) drops its logs as pieces of wood (one per log); the engineer that chopped it picks them all up before taking other work, and idle engineers within **Help Radius** help (and pick up wood nobody chopped). Pick-up reach and time (0.25 s), the sound as each piece is picked up (**Pickup Sound**, `data/sounds/log_pickup.tres`; picking up plays no work sound), help radius, and how long an engineer tries to reach a piece before fetching it anyway (**Gather Give Up**) | `data/crew_rules.tres`. How the pieces fall and look: **Wood** node in `game/world.tscn`. The logs count once picked up. |
| Engineer crew: size, walk and climb speed, dig speed, dig reach, step-up, ground climb and drop limits, crushed text, death sound, fall gravity, stranded time (then an engineer climbs any height back to the column), stuck time (still no way back after that much more: the status line warns, **Stuck One Text** / **Stuck Many Text** on the root of `game/main.tscn`), strike delay, sounds | `data/crew_rules.tres` (how fast each piece type is built: **Build Speed** on `data/bridge/*.tres`) |
| Which job an engineer takes: the one nearest ahead of the column's leader first (jobs behind the leader after every job ahead), the shorter way between jobs about as urgent; on its way it switches to a more urgent free job that is nearer to it. It finds its way round to a job (back off a ledge, into a pit, under an overhang) by the walking limits above | Code (`game/crew.gd`, `game/crew_nav.gd`); no knobs |
| The column waits at the foot of a structure under construction (part of it on scaffolding, or a piece the crew has started) until it stands on its own, then crosses; a plan nobody has started is walked onto (and fallen off) as ever | The status text: **Construction Text** in `data/army_rules.tres` |
| Testing cheats (F2 while playing): **Instant Work** builds every ordered plan, digs every marked cell and picks up all wood at once; turning the cheats on also tops every supply up to **Cheat Supplies**. **F3** skips the level as if it was won: the column and crew arrive at the next camp with its reinforcements and supply drop (the last level wins the campaign) | `data/crew_rules.tres`, group **Cheats**; **Cheat Supplies** on the root of `game/main.tscn` |
| Engineer look | `objects/engineer/engineer.tscn` (its own placeholder until engineer art exists; keep the Body, Wounded and AnimationPlayer nodes the soldier script uses) |
| Engineer at work: on every blow you hear while it digs, chops, builds or takes apart a bridge piece (the work sound's beat, **Work Sound Interval** on `data/crew_rules.tres`, and the blow that finishes the job) it jolts **Work Shake Px** (1) towards the work for **Work Shake Time**, then stands still until the next blow | Root node of `objects/engineer/engineer.tscn` |
| Bridge / support / rope / stone strength, length, mass, cost (per started **Metres Per Cost**: 1 m, 2 m for support), colours | `data/bridge/log.tres` (Log), `support.tres`, `rope.tres`, `stone.tres`. **Walkable** decides if soldiers walk on it; **Draw Layer** puts it behind (lower) or over (higher) other members. **Flex** is how far the middle of a 5 m piece sinks with one soldier standing on it (it grows with the load and the length cubed; 0 is rigid; ropes never flex). **Solid To Bodies**: soldiers and archers collide with it (off for supports and ropes). **Solid Along**: its whole length collides (off for ropes). |
| Tool rack: names, hints, keys, costs, hold-repeat | `data/tools/*.tres` (rack order is the Campaign's **Tools** list). Each button shows its cost as supply swatches (build tools use their material's cost) and dims when it can't be afforded; the dim look is on `ui/tool_button.tscn` |
| Arrows | `objects/arrow/arrow.tscn` |
| Sandbag (the Sandbag tool, `data/tools/2_sandbag.tres`, 10 earth): the click orders it, and an engineer walks to a standing spot at most **Throw Reach** aside of it (any height, not under it), as near **Throw Distance** aside as it can without a long way round and with a clear arc, winds up (**Throw Windup**) and throws it in an arc (**Throw Speed**, **Throw Arc Per Metre**, **Throw Arc Least**); it then falls and lands as a sandbag tile (`data/terrain/sandbag.tres`, art `world/sandbag.png`). If it hits anything on the way (ground, a bridge piece, a soldier, archer or engineer), or falls on a soldier or archer, it breaks in a cloud of dust and hurts nobody. Clicking an order again takes it back with all its cost. A tool with **Thrown** off drops its block at the cursor instead | throw tuning in `data/crew_rules.tres`; the falling sandbag `objects/sandbag/sandbag.tscn` (**Harmless**: breaks on people instead of crushing them; **Smash Dust**, **Smash Sound**: how it breaks); on `objects/sandbag/thrown_bag.tscn`: **Spin** (turns a second, about its centre), **Hit Margin** |
| Debris, floating text | `objects/effects/` |
| How a tile shakes and blinks when a soldier strikes it or a bridge piece hits it (**Hit Time**, **Hit Shake** in pixels, **Hit Flash** colour, **Hit Flash Share**), and the ripple that runs from it through the rest of the tower and its battlements to show the whole tower will fall (**Ripple Lift** in pixels, **Ripple Speed**, **Ripple Time**) | **Hit effect** group on the **Terrain** node (`world/terrain.tscn`). Sparks look: `objects/effects/sparks.tscn`. |
| A razed tower's fall: the row struck (and anything below) is crushed at once; the rest drops a column at a time, left to right (**Collapse Stagger** seconds apart, on the **World** node in `game/world.tscn`), and each row breaks as it hits the ground. Its archer hangs a moment (**Topple Hang**), falls (**Topple Gravity**), lies flat and perfectly still (**Lie Time**), then blinks **Vanish Blinks** times (**Vanish Flash**) and vanishes in a puff (**Smoke Color**, **Smoke Puffs**). The column waits until it is all over, with **Collapse Text** as its status | Archer timings: **Topple** group on `objects/archer/archer.tscn`. Status text: `data/army_rules.tres`. How fast the rest falls: `objects/falling_piece/falling_piece.tscn`. |
| A tower breaking up (razed or collapsing): chunks and dust per cell (**Collapse Rubble**, **Collapse Rubble Speed**, **Collapse Dust**, how much paler the dust is than the stone: **Collapse Dust Pale**); its battlements and other decorations painted on it come down with it | **Collapse effect** group on the **Terrain** node. Particle looks: `objects/effects/rubble.tscn`, `objects/effects/dust.tscn`. Chunks take the stone's **Debris Colour**. |
| A splash where anything falls into water (a sandbag or box, a thrown sandbag, a soldier, an engineer, a bridge piece, a falling tower or tree): drops of the liquid's **Debris Colour** thrown up at its surface (**Splash Amount**, 0: none), only when it goes in at **Splash Speed** or faster (walking in does not splash), with **Splash Sound** | **Look** group on `data/terrain/water.tres` (any terrain type can splash). Particle look: `objects/effects/splash.tscn`; how much paler the drops are: **Splash Pale** on `core/effects.tscn` |
| Sky, sun, stars, mountain ridges | `world/background/background.tscn` |
| HUD layout, texts, theme, fonts | `ui/hud.tscn`, `ui/theme.tres`, `ui/fonts/`. The pixel fonts (Alagard, Medodica) fall back to Chivo for characters they lack (`·`, `×`, `≤`): set under **Fallbacks** in each font's Import dock. The web build has no system fonts, so keep text to characters some bundled font has (**Allow System Fallback** is off, so the desktop shows the same gaps the web would) |
| Arrows at the screen edge pointing at the column (blue) and the nearest engineer (red) when off screen: one sprite pointing right, tinted and flipped | **LeadMarker** and **CrewMarker** in `ui/hud.tscn` (**Texture**, **Modulate**); the placeholder art is `ui/elements/edge_arrow.png` |
| Bridge physics feel, build messages, blueprint / ordered colours | **Bridge** node in `game/world.tscn` |
| Scaffolding look | `world/scafolding.png`: four tiles in a 2x2 sheet (any tile size; each is drawn one cell big). Under every scaffolded joint a column of cells runs down to the ground, and each cell takes the tile its place has in that 2x2 arrangement, so towers side by side join up. A cell with no scaffolding to its right gets a closing post: the left edge of its tile, so keep the posts on the tiles' left edges. **Scaffold Texture**, **Scaffold Color** (tint) and **Scaffold Max Depth** are on the **Bridge** node (`world/bridge.tscn`). |
| Bridge pieces against soldiers and archers, and damage from fast pieces (**Harm Speed**, **Siege Per kJ**, **Crush Weight**): bodies stop slower pieces; faster ones crush them, and so does more than Crush Weight resting on them (pieces, what they carry, boxes and stacks of boxes) | **Bridge** node in `game/world.tscn`, group **Impact** |
| Spikes breaking what falls on them: **Breaks Falling** on a TerrainType (on for spikes). Boxes break when they reach it; a bridge piece breaks when a loose part of it (an end not bolted, or its length) reaches it. Pieces bolted down in a spike pit on purpose stay. | `data/terrain/spikes.tres` |
| What a hit on the ground does (any piece meeting it at 1 m/s or more; Harm Speed is only for crushing soldiers and archers): damage = impact energy (½·m·v², with any load) × the piece's **Ram**. A tower takes **Siege Per kJ** seconds of siege per kJ of damage; other ground breaks when the damage reaches its **Impact Strength** (0: never). A piece whose hit carried more energy than its own **Impact Strength** breaks if what it hit held (a log rammed into brick breaks; a stone beam does not) | group **Impact** on `data/bridge/*.tres` and `data/terrain/*.tres` |
| Dig marks and the siege bar on a tower block under attack: **Mark Color**, **Siege Color** (fill), **Siege Empty Color** (the empty part and the outline, dark so the bar shows against the brick), **Siege Bar Height** | **ToolController** node in `game/main.tscn` |
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
