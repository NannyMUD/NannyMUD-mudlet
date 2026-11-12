# ElrohirMapper

Client-side automap for [NannyMUD](https://nannymud.lysator.liu.se/). A Mudlet package that
computes each area's layout in Lua from the game's map data, sent over GMCP or as one `!NMAP`
line per move.

The game sends one message per move — room id, where you came from, the command you typed, the
room's name, area, exits and terrain.
It does no rendering and stores no coordinates. Everything you see is solved on the client:
which rooms form an area, where each one goes, and which edges have to bend.

## Install

Two steps, and the first one alone does nothing.

**1. The Mudlet package.** Download `ElrohirMapper.mpackage` from
[Releases](https://github.com/NannyMUD/NannyMUD-mudlet/releases) and drag it onto the Mudlet
window.

Or, in one line — note this is long and your client will wrap it, so join it back together
before pasting:

```
lua installPackage("https://github.com/NannyMUD/NannyMUD-mudlet/releases/latest/download/ElrohirMapper.mpackage")
```

**Updating.** When a newer release is out, you are told so shortly after Mudlet starts.
Type `mapupdate`. It downloads the newest release and swaps it in, NannyBasics too if you have
it; if the download fails nothing is changed. Your map lives in the profile, not in the package, and is kept. By
hand: Mudlet refuses to install over a package
that is already there ("package ElrohirMapper is already installed"), so remove `ElrohirMapper`
under Toolbox → Package Manager first, then install the new one.

**The map window.** The map opens docked in a panel on the right of the window, with the room
you are in named in its title strip. Drag the bar at the panel's inner edge to make it wider or
narrower; the size is remembered. The X on its strip closes the map; right-click any strip or
bar, or type `mapwin dock`, to show it again. `mapwin dock` also closes the panel and gives the
space back to the text, and `mapwin dock <width>` sets its width. With
[NannyBasics](../basics) installed, its panes share the same
panel: drag a pane by its title strip to move it, and the bars between panes to resize them.

`mapwin embed` shows the map as a small window over the top right corner of the text instead,
and Mudlet's own **Map** button still works too. Mudlet may refuse to show the map in one of
these while another has been in use; `mapwin` says so when it happens. To change over, close
the one you have, restart Mudlet, then open the other.

Known issue, seen on Mudlet 5.0.1 with two sessions side by side in MultiView: after switching
to another program and back, the text of the session you are not in can go black. Nothing is
lost; click into that session and it redraws. It has only been seen after locking the map window
from its right-click menu; `mapwin lock` does the same job and has not caused it.

**2. Switch the map data on, in game.** The game sends it only to players who ask for it,
over GMCP, the channel Mudlet uses for game data beside the text:

```
toggle gmcp        GMCP itself
toggle gmcp room   the map data
```

Each toggle switches its setting and says whether it is now on; both are remembered when you
log in again. Mudlet has GMCP switched on by default.

GMCP is the way to use it. The game also tells the mapper which room each exit leads to, once
that room is known, so walking through an area once connects the rooms you have visited, not
only the steps you took between them.

A client without GMCP can get the same data as a line of text on every move instead, which
this package reads and hides. It carries no exit destinations, so it maps less:

```
toggle map on    the text line; with GMCP on as well, the game uses GMCP
toggle map off   stop it
```

Not every area is mapped: the administrators open them one at a time.

If you used an earlier version of this package, start a new map with `mapwipe confirm`
first. The game numbers its rooms differently now, and an old map would mix the two.

Then walk. Type `maphelp` for the everyday commands and `maplegend` for what the colours,
dots, letters and lines on the map mean. `maphelp advanced` has the rest: shaping the map by
hand, mazes, diagnostics and tuning.

## What you get

Rooms are placed on a real grid rather than strung out from where you happened to walk in.
The engine solves each area as a graph: it finds the cycles, keeps a corridor straight, holds
a 45° diagonal at 45° where it can, and when a loop cannot close truthfully it decides which
edge is least bad to bend rather than letting the map drift. Up and down exits dock as
separate floors. Areas too small to deserve a tab fold into the world map. It relayouts as you
explore, in the background, without freezing the client.

Around the map:

- **Getting about.** Double-click a room to walk there. `mapgoto`, `mapnear` and named marks
  (`mapmark bank`, then `bank`) walk you; `mapavoid` keeps speedwalks out of a death trap.
- **Notes.** `mapnote` writes on a room, `mapnotes` and `mapsearch` find them again.
- **Mazes.** `mapcoins` tells the identical rooms of a maze apart by the coins you drop, draws
  them on a map of their own, and walks you to the ways not yet tried.
- **Pictures and other maps.** `mapexport` writes a map as a picture to print or put on a
  wiki; `mapimport` joins another character's map into yours; `maphelp share` says how to copy
  or back up a map.
- **Fixing the map.** Delete rooms and exits, record exits you type as commands, and draw
  areas together.

Every command is listed below, and in Mudlet `maphelp <word>` searches the same text.


<!-- help:begin (written by tools/help_md.lua from lua/help.lua: edit there) -->
## Commands

In Mudlet, `maphelp` lists these, `maphelp <command>` shows one in full and `maphelp <word>` finds every entry that mentions the word.

### Getting started

- **`maphelp [command or word]`** Bare, the everyday commands. 'maphelp advanced' lists the rest: shaping the map by hand, mazes, diagnostics and tuning. 'maphelp <command>' gives that command's full text; any other word lists every command and page that mentions it. The pages: 'maphelp setup' (the settings we recommend), 'maphelp mouse' (what clicking does), 'maphelp auto' (what happens by itself), 'maphelp 3d' (Mudlet's 3D map) and 'maphelp share' (moving your map).
- **`maplegend`** What the colours, dots, letters and lines on the map mean, and how to read a room.
- **`mapwin [dock [width]|embed|left|right|lock|unlock|reset]`** Bare, open or close Mudlet's own map window (the same as its Map button). 'mapwin dock' puts the map in a panel on the right, shared with NannyBasics' panes; again closes it, 'mapwin dock <width>' sets its width. 'mapwin embed' is a small window over a top corner of the text instead; there 'left' and 'right' pick the corner, 'lock' removes the frame, 'unlock' brings it back and 'reset' restores the first size. Mudlet can show the map in only one of these per session: to change over, close the one you have, restart Mudlet, then open the other.
- **`mapupdate`** Replace this package with the newest release, NannyBasics too if you have it. Shortly after Mudlet starts you are told when one is out. It downloads first, so a failed download changes nothing; your map lives in the profile and is untouched.
- **`mapprompts [on|off]`** When one action sends several commands at once (a speedwalk, an alias, a key), show only the last prompt. On by default.

### Getting about

- **`mapgoto <id|area>`** Speedwalk to a room id, or to the nearest room of a named area (part of the name is enough). Double-clicking a room on the map walks there too, as does 'Walk here' in its right-click menu. Recorded exits ('crawl hole') are walked with their own command.
- **`mapnear [terrain]`** Walk to the nearest room of a terrain: heal, shop, port and so on. Bare, the names you can search for.
- **`mapmark [name]`** Remember the room you are in under a name: from then on typing that name walks there ('mapmark bank', later 'bank'). Bare, it marks 'here', and 'mapreturn' walks back: mark, go and sell, return. 'mapmarks' lists the marks, 'mapunmark <name>' forgets one and gives the word back. Marks are kept in the map.
- **`mapavoid [id,...|sel]`** Keep speedwalks out of a room (bare, the one you are in): a death trap, an aggressive monster. The same as 'Lock' in the map's right-click menu. 'mapavoids' lists them.
- **`mapunavoid [id,...|sel]`** Let speedwalks use an avoided room again. 'mapavoids' lists them.
- **`mapsearch <text>`** Find rooms whose name, area's name or notes contain the text, in any case. It lists them with the ids 'mapgoto' takes.

### Notes

- **`mapnote [text]`** Add a line of your own to the room you are in ('mapnote orc guard, 2 swords'); a room holds as many as you like. Bare, list its notes. 'mapnote del <n>' and 'mapnote clear' remove them; '#<id>' first means another room. Right-click a room on the map for 'Add note' and 'Notes'; clicking a room shows its notes in the map's corner. Notes are kept in the map.
- **`mapnotes [text]`** Every room with notes, area by area, or only those whose notes contain the text ('mapnotes rabbit').

### Pictures and other maps

- **`mapexport [area] [a4] [plain]`** Write one map as a picture: an SVG any browser opens and a wiki can show. White, pale terrain tints, every room numbered, and a list of the rooms with where each way off the map leads. Bare, the map you are on. 'a4' fits it on one sheet to print; 'plain' leaves the tints out. A picture, not a copy of your map: 'maphelp share' says how to copy that.
- **`mapview [fit|plain|reset|zoom <px>]`** A prototype: the map you are on drawn in the style of mapexport, in a second window. A red ring marks you; click a room to walk there; the wheel zooms, 'fit' shows the whole map. Mudlet's map stays where it is.
- **`mapimport [profile] [confirm|undo]`** Join another profile's map into this one: rooms, exits, recorded exits, marks, notes and avoided rooms it has that this one lacks. Bare, list your other profiles that have a saved map; with a name, what it would add; 'confirm' does it. Where the two disagree, this one is kept. Your map is saved first, and 'mapimport undo' puts it back (this session only; anything explored since is lost). If the other map draws an area into another one, the import says so by name; 'mapunmerge' reverses it. Close the other profile first, so its latest exploring is in its saved map.

### Mazes

- **`mapcoins [on|off|reset|relearn|twoway|back|go [n]|layout]`** For a maze whose rooms all look alike. Switch it on inside the maze ('on <room name>' if it cannot read the name): after each move into a room with no gold it drops a number of coins no other room has, so every room is known by its coins, and draws the rooms on a map of their own as you walk. Lines leave each room in the direction you walked, coloured by direction, with an arrow where they led; a short line marks a way not yet tried. Bare, the rooms numbered so far: where each way leads, which come back to the same room, which did not move you, which showed something else, and which are untested. 'go' walks to the nearest room with an untested way, 'go <n>' to room n, a step at a time; typing anything stops it. 'twoway' takes every way walked to lead back the way you came, for a maze that keeps to that. 'layout' has the mapper's engine tidy the coin map once. 'relearn' forgets every way but keeps the room numbers, since the coins are still lying there. 'reset' wipes it all and starts again at 1; 'off' stops dropping. In a cave of forward, right, back and left it keeps track of your facing and reads what each room says lies around you; 'back stay' is for a cave where back steps away without turning you, 'back turn' changes it again. Kept for this session only.

### Fixing the map

- **`mapwipe [area] [confirm]`** Delete the whole map, or every room the game put in one area. Without 'confirm' it only says what it would delete.
- **`mapdelroom <id>|sel`** Delete a room and every exit to or from it, then redraw; 'sel' is every room selected on the map (also in its right-click menu as 'Delete rooms'). Use this rather than Mudlet's own delete: it clears the room's records and drawn lines too.
- **`mapdeledge <from> <to>`** Delete every exit from one room to another, compass and special.
- **`maprecordmove [command]`** Record a special or multi-step exit ('maprecordmove enter gate'); bare, it captures the next one you walk. A recorded exit is kept like any other and speedwalks use it.
- **`maprecordroute a,b,c`** Record the known way through rooms the map does not show (a blocked maze) as one exit, one way.
- **`maprecordundo`** Take back the exit just recorded, and restore the one it replaced.
- **`mapmerge <area>`** Merge that area into the one you are standing in, so both are drawn as one map.
- **`mapunmerge <area>`** Undo a merge, yours or one the game suggested. 'mapmerges' lists both.
- **`maphints [on|off [area]]`** The game may suggest drawing an area on another's map (a town built by several wizards). Follow the suggestions or not, for all areas or one; bare, list them.

### Appearance

- **`mapterrain [on|off]`** Colour rooms by terrain; 'maplegend' says which colour is what.
- **`mapglyphs [on|off]`** A letter on rooms with an exit you type instead of a direction.
- **`mapstubs [on|off|edges|classic|halo N]`** What the map draws for unexplored exits. Mudlet redraws every stub of its own every frame, so a big part-explored area is slow. 'edges' draws each unexplored exit as a short line instead, which is far cheaper; 'classic' is Mudlet's stubs with a halo, showing only the stubs within N cells of you once an area has a lot. Nothing is lost either way.
- **`mapvert [on|stack|off]`** 'on' docks each floor beside the one it connects to, so every floor shows at once; a floor with no room beside its stair goes on its own level over it instead, and so does anything beyond it. 'stack' puts each floor on its own level, directly over or under its stair: right for Mudlet's 3D map, where up and down then stand upright instead of running across the map; in the 2D map you see one level at a time. 'off' places every floor on its own. Remembered.
- **`mapstitch [on|off]`** Mudlet's 3D map (5.1) can draw the areas next to the one you are in around its edges. Off unless you turn it on: this mapper lays each area out on its own, so neighbours drawn together can overlap. Bare, says which it is. Kept in the map, so your choice holds.
- **`maplevels [on|off]`** Mudlet can draw the rooms one level up and one level down as rings on the 2D map. Off unless you turn it on: with stacked floors the rings cover the level you are on. On, make them faint in Preferences: open the colour for the upper or lower level and set its alpha channel to about 50. Bare, says which it is. Kept in the map, so your choice holds.
- **`mapareamin <n>`** The smallest cluster of rooms that keeps an area of its own instead of folding into the world map. Remembered.

## Advanced commands

Shaping the map by hand, mazes, diagnostics and tuning; `maphelp advanced` in Mudlet.

### Shaping the map by hand

- **`mapcur <id|area>`** Set the current room by hand: an id, or any room of a named area.
- **`mapfold <dir>`** Fold the branch through that exit into a submap.
- **`mapunfold <dir>`** Undo a fold. 'mapfolds' lists them.
- **`mapsteal <id,...>`** Steal rooms into the area you are standing in, in one relayout.
- **`mapunsteal <id,...>`** Return stolen rooms to their own area. 'mapsteals' lists them.
- **`mapouter [clear] [id,...]`** Mark rooms as on the outer face, drawn outermost; bare, list them, 'clear' unmarks.

### Mazes and shifting exits

- **`mapmaze [auto [area|.]|sel]`** Fold untruthful clusters into a submap: bare, the current room's; 'auto' the whole map, 'auto <area>' one area. 'sel' marks every room selected on the map as maze and folds once, for mirror mazes, which change nothing and so are invisible to 'auto'.
- **`mapunmaze [all|id,...]`** Release the current room's whole maze submap; with room ids (or 'here') release only those, leaving the rest folded; 'all' releases every submap and clears the maze override. 'mapmazes' lists them.
- **`mapmazelive [area|.|clear]`** What the last solve did with this area's maze doors: which are drawn as spokes, which fell back to a stub, and whether the area was vetoed; 'clear' lifts vetoes.
- **`mapmazefit [area|.]`** Report whether each maze could be one layout vertex: its doors, their directions, and where that vertex would sit. Changes nothing.
- **`mapexitlock [dir]`** Lock the current room's compass exits, or one, so the game's data cannot re-point them.
- **`mapexitunlock [dir]`** Clear exit locks on the current room; bare, all of them.
- **`mapmutreset [id|area|all]`** Wipe the counts of exits that changed; bare, the current room's.

### Appearance, in detail

- **`mapterrain list|here|halo`** 'list': how many rooms of each terrain the map holds. 'here': what the game sent for this room and what it became, which tells 'not sent' from 'not coloured'. 'halo <radius> [rim alpha] [centre alpha]' tunes the secondary ring; bare, the current values. Bare 'mapterrain' repaints from stored data.
- **`mapglyphs list|auto on|off`** 'list': which rooms are glyphed, their exit names and where each came from. 'auto on|off': count guessed special exits as evidence, or only advertised and recorded ones.
- **`mapvert [area|all]`** Up and down census, and what the last pack honoured and drew.

### Diagnostics

- **`mapprofile [on|off|ms]`** Time the phases of each move (graph, terrain, guess, relayout, view) and print those over <ms>; for finding what a slow move is doing.
- **`mapecho [on|off]`** Report when a relayout finishes: time, frames, the solver's profile. Off by default, and then no relayout prints anything.
- **`mapoff [id]`** What is recorded for a room about exits that leave the map: the record, the stubs, the lines.
- **`mapstrict [on|off]`** Draw an exit only when the game reports the command you sent, and ignore a known room reported under another area. For a guild that rewrites what you see; following a party leader then draws no exits. Off by default.
- **`mapaudit [all]`** Exits whose geometry the exits walked both ways contradict: usually mistyped links.
- **`mapedges [id]`** Outgoing and incoming exits for a room; bare, the current one.
- **`mapmut [id]`** Per-exit change counters and lock state; bare, the current room.
- **`mapcrossings`** Every crossing as exit by exit, and what licensed it: cost, a proven wire, or nothing.
- **`mapcaps`** Why each branch was capped during a render.
- **`mapdump [sel|all]`** Dump this area's rooms, coordinates and exits; 'sel' the rooms selected on the map, 'all' every room's area and coordinates.

### Replay

- **`mapsteps`** List room placement steps (set 'lua elro.stepDebug=true' before 'maprelayout this').
- **`mapstep [back|id|step n|off|reset]`** Bare, advance one step; 'back' one step back; an id stops just before that room is placed.
- **`maptop [n]`** The slowest placement steps of the last relayout (set 'lua elro.stepTime=true' first).
- **`maplever [name ...]`** Force named levers to the front of every ranking; bare, list them, 'off' clears.

### Tuning, timing and state

- **`maprelayout [all|this]`** Redraw the maps that changed; 'all' every map, 'this' the one you are looking at, changed or not. It happens by itself; this is for after a setting change.
- **`mapauto on|off|idle N`** Automatic relayout: at once when the drawing is visibly wrong, otherwise N seconds after you stop (on, 3 seconds by default).
- **`mapknobs [reset]`** Every knob and probe overridden this session; 'reset' clears them. They survive mapreload, so a knob left set looks exactly like a code change that did nothing: run this before trusting any measurement.
- **`mapbg [on|off|cancel|slice N|gc N|hook N]`** Background relayout, which does not freeze the client: state, on or off, abort, or the per-frame budget in ms. 'gc N' collects between frames; 'hook N' reports the source lines that blew the frame budget.
- **`mapwd <secs|off>`** Watchdog: abort a runaway relayout and say where it was, instead of freezing Mudlet (60 seconds by default).
- **`mapcs [reset]`** Snapshot stats; 'reset' forces a full re-read of Mudlet's room state.
- **`mapdebug on|off`** Switch layout step tracing on or off.
- **`mapreload`** Re-read lua/modules.lua and every module from disk, with no reinstall; also drops the room-state snapshot ('mapcs reset' does that alone).
- **`mapsrc [path]`** Show or set the directory the modules are loaded from. Remembered.

## Recommended setup

What this mapper sets for you, and what to set yourself. Every choice below can be changed back.

- **In the game.** 'toggle gmcp' and 'toggle gmcp room' switch the map data on; both are remembered at your next login.
- **The map window.** 'mapwin dock' puts the map in a panel on the right, shared with NannyBasics' panes. Mudlet's own Map button works too.
- **Floors in 2D.** 'mapvert on' (the default) docks each floor beside the one it connects to, so you see every floor at once. A floor with no room beside its stair goes on its own level over it.
- **Other levels in 2D.** Hidden by default, so a stacked floor never covers the level you are on. 'maplevels on' shows them as rings; then set the alpha channel of the upper and lower level colours in Preferences to about 50, so they stay faint.
- **Prompts.** 'mapprompts' is on by default: a speedwalk shows one prompt, not one per step.
- **The 3D map.** Mudlet 5.1's 3D map is an experiment you switch on yourself. With it, type 'mapvert stack' so floors stand on their own levels. Neighbouring areas stay off ('mapstitch'). 'maphelp 3d' has the rest.

## On the map, with the mouse

- **Double-click a room.** Walks there by the shortest way, using recorded exits where they are needed.
- **Click a room.** Shows its notes in the map's corner.
- **Right-click a room.** Besides Mudlet's own entries: 'Walk here', 'Add note', 'Notes' and 'Delete rooms' (every selected room, cleanly; see 'mapdelroom'). Mudlet's 'Lock' keeps speedwalks out, the same as 'mapavoid'.
- **The docked panel.** Drag the bar at its inner edge to make it wider or narrower; the size is remembered. The X on the map's strip closes it; right-click any strip or bar to show it again, hide or show panes, or reset the layout. With NannyBasics, drag a pane by its title strip to move it, and the bars between panes to resize them.
- **In mapview.** Click a room to walk there; the wheel zooms.

## What happens by itself

- **As you walk.** Each move places the room and, when the drawing is visibly wrong or a few seconds after you stop, the area is laid out again in the background without freezing the client ('mapauto').
- **Small areas.** An area of only a few rooms is drawn on the world map instead of a tab of its own ('mapareamin').
- **The dark.** In a dark room the map shows you off the map; its exit stays unexplored, since it maps like any other once you bring a light.
- **Gates.** A magician's gate is not an exit: 'enter gate' maps the room you come out in without linking it to the room you left. A gate that always stands in the same spot can be recorded with 'maprecordmove enter gate'.
- **The game's suggestions.** The game may suggest drawing a town built by several wizards as one map; this is followed unless you say otherwise ('maphints').
- **Prompts.** A speedwalk or alias that sends several commands shows one prompt, not one per command ('mapprompts').
- **Updates.** Shortly after Mudlet starts you are told when a newer release is out ('mapupdate').
- **Maze coins.** The coin maze's own map is wiped at the next start ('mapcoins').

## The 3D map

Mudlet 5.1 has a new 3D map, still an experiment, so it is off until you switch it on. It draws the same map as the 2D one, in one of seven styles; 'diorama' looks like a model town on a board.

- **Switching it on.** lua setConfig("experiment.3dmap.modernmapper", true) or Settings, Advanced, Experiments, tick 'Modern 3D mapper'.
- **Picking a style.** Preferences, Mapper; or for example: lua setConfig("mapStyle", "diorama")
- **Floors.** Type 'mapvert stack' while you use the 3D map: each floor goes on its own level over its stairs, so up and down stand upright instead of running across the map. 'mapvert on' puts back the flat layout, which gives the better overview in 2D.
- **Other levels in 2D.** The rooms one level up and down are hidden unless you type 'maplevels on'. Then they show as rings; to make them faint, open the colour for the upper or lower level in Preferences and set its alpha channel to about 50 (255 is solid).
- **Neighbouring areas.** Mudlet can draw the areas next to yours around its edges. This mapper keeps that off, because areas laid out one by one overlap when drawn together; 'mapstitch on' if you want it anyway.
- **Clicking.** Double-click a room to walk there and right-click for the same menu as on the 2D map.

## Moving your map

'mapexport' makes a picture to print. It does not copy your map. The map itself lives in your Mudlet profile, and Mudlet moves it:

- **To another profile of yours.** Settings, the Mapper tab, 'Copy map to other profile(s)': pick the profiles and press Copy.
- **To a file.** Settings, the Mapper tab, 'Save map...'. A backup, or something to hand to another player.
- **From a file.** Settings, the Mapper tab, 'Load map...'. This REPLACES the map in that profile; the two are not merged. Save your own first if you may want it back.
- **Joining two maps.** 'mapimport <profile>' adds what another profile's map has and this one lacks, and keeps this one's where they disagree. Bare 'mapimport' lists the profiles.

After a map is loaded or copied into a profile that is open, close and reopen that profile so the mapper reads the new map from the start.

The file carries everything: rooms, exits, the special exits you recorded, terrain, merges, folds, your marks and room notes, and the rooms speedwalks keep out of. Only the map window's size and corner belong to the profile. The receiving profile needs this package too, and 'toggle gmcp' and 'toggle gmcp room' in the game to keep mapping.

A map shows where you have been. Handing one over hands over that exploring.

<!-- help:end -->

## Using it with another MUD

The GMCP handler and the `!NMAP` trigger are only adapters. The integration point is one
function:

```lua
elro.onRoom(id, fromId, dir, name, area, exits, terr)
```

| argument | |
|---|---|
| `id` | integer, stable and unique per room. The whole map is keyed on it |
| `fromId` | the room moved from, or `0` for none (login, teleport) |
| `dir` | the direction moved, e.g. `"east"`; `"none"` if there is no meaningful one |
| `name` | the room's short description |
| `area` | the server's own area name — drives which rooms share a tab |
| `exits` | comma-separated, e.g. `"east,west,up"` |
| `terr` | comma-separated terrain tokens, most specific first; may be `""` |

Call that on every move and the rest works. Nothing else in the client knows where the data
came from, so another protocol such as MSDP is a handler and a mapping of field names;
`elro.gmcp_room` in `lua/core.lua` is the GMCP one. `analysis/test_onroom.lua` drives it
exactly this way.

Two requirements on `id`: it must be stable across sessions, and it must never be **reused**
for a different room — the client treats a repeated id as the same place.

When the player is somewhere the map cannot show (the dark, a room the game keeps off the
map), call `elro.offgrid()`. On NannyMUD that is one trigger on the exact line
"A dark room."; another MUD changes only that trigger.

## Development

Lua lives in `lua/`, loaded in the order given by `lua/modules.lua`. `mapreload` re-reads them
without reinstalling the package, so an edit is one command away from being live.

```
sh tools/run-gate.sh full     # tests + the layout regression canary
sh tools/build-package.sh     # -> ElrohirMapper.mpackage (refuses if the gate is red)
```

The command reference above is written from `lua/help.lua` by `luajit tools/help_md.lua`; run it
after changing the help, and the gate fails until you do.

`DESIGN.md` is the architecture. The layout engine's own notes are in the header comments of
`lua/eqw.lua` and `lua/walk.lua`.

## License

MIT — see [LICENSE](LICENSE).
