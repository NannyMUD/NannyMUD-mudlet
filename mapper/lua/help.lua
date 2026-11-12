-- maphelp: every command, topic and the lookup. tools/help_md.lua writes the README's command
-- reference from the same tables, and the gate checks the two agree.
-- A row is { command, one-line summary, full text, also = { other words it answers to } }.

local H = {}

H.sections = {
  { title = "Getting started", rows = {
    { "maphelp [command or word]", "this list; a command's full text, or every help entry with that word",
      "Bare, the everyday commands. 'maphelp advanced' lists the rest: shaping the map by hand, mazes, diagnostics and tuning. 'maphelp <command>' gives that command's full text; any other word lists every command and page that mentions it. The pages: 'maphelp setup' (the settings we recommend), 'maphelp mouse' (what clicking does), 'maphelp auto' (what happens by itself), 'maphelp 3d' (Mudlet's 3D map) and 'maphelp share' (moving your map)." },
    { "maplegend", "what the colours, dots, letters and lines mean",
      "What the colours, dots, letters and lines on the map mean, and how to read a room." },
    { "mapwin [dock [width]|embed|left|right|lock|unlock|reset]", "open, close or move the map window",
      "Bare, open or close Mudlet's own map window (the same as its Map button). 'mapwin dock' puts the map in a panel on the right, shared with NannyBasics' panes; again closes it, 'mapwin dock <width>' sets its width. 'mapwin embed' is a small window over a top corner of the text instead; there 'left' and 'right' pick the corner, 'lock' removes the frame, 'unlock' brings it back and 'reset' restores the first size. Mudlet can show the map in only one of these per session: to change over, close the one you have, restart Mudlet, then open the other." },
    { "mapupdate", "install the newest release",
      "Replace this package with the newest release, NannyBasics too if you have it. Shortly after Mudlet starts you are told when one is out. It downloads first, so a failed download changes nothing; your map lives in the profile and is untouched." },
    { "mapprompts [on|off]", "show one prompt for a burst of commands",
      "When one action sends several commands at once (a speedwalk, an alias, a key), show only the last prompt. On by default." },
  } },
  { title = "Getting about", rows = {
    { "mapgoto <id|area>", "walk to a room id, or the nearest room of an area",
      "Speedwalk to a room id, or to the nearest room of a named area (part of the name is enough). Double-clicking a room on the map walks there too, as does 'Walk here' in its right-click menu. Recorded exits ('crawl hole') are walked with their own command." },
    { "mapnear [terrain]", "walk to the nearest room of a terrain",
      "Walk to the nearest room of a terrain: heal, shop, port and so on. Bare, the names you can search for." },
    { "mapmark [name]", "name the room you are in; typing the name walks there",
      "Remember the room you are in under a name: from then on typing that name walks there ('mapmark bank', later 'bank'). Bare, it marks 'here', and 'mapreturn' walks back: mark, go and sell, return. 'mapmarks' lists the marks, 'mapunmark <name>' forgets one and gives the word back. Marks are kept in the map.",
      also = { "mapmarks", "mapreturn", "mapunmark" } },
    { "mapavoid [id,...|sel]", "keep speedwalks out of a room",
      "Keep speedwalks out of a room (bare, the one you are in): a death trap, an aggressive monster. The same as 'Lock' in the map's right-click menu. 'mapavoids' lists them.",
      also = { "mapavoids" } },
    { "mapunavoid [id,...|sel]", "let speedwalks use a room again",
      "Let speedwalks use an avoided room again. 'mapavoids' lists them." },
    { "mapsearch <text>", "find rooms by name, area or notes",
      "Find rooms whose name, area's name or notes contain the text, in any case. It lists them with the ids 'mapgoto' takes." },
  } },
  { title = "Notes", rows = {
    { "mapnote [text]", "write a note on the room you are in",
      "Add a line of your own to the room you are in ('mapnote orc guard, 2 swords'); a room holds as many as you like. Bare, list its notes. 'mapnote del <n>' and 'mapnote clear' remove them; '#<id>' first means another room. Right-click a room on the map for 'Add note' and 'Notes'; clicking a room shows its notes in the map's corner. Notes are kept in the map." },
    { "mapnotes [text]", "every room with notes, by area",
      "Every room with notes, area by area, or only those whose notes contain the text ('mapnotes rabbit')." },
  } },
  { title = "Pictures and other maps", rows = {
    { "mapexport [area] [a4] [plain]", "write a map as a picture to print or share",
      "Write one map as a picture: an SVG any browser opens and a wiki can show. White, pale terrain tints, every room numbered, and a list of the rooms with where each way off the map leads. Bare, the map you are on. 'a4' fits it on one sheet to print; 'plain' leaves the tints out. A picture, not a copy of your map: 'maphelp share' says how to copy that." },
    { "mapview [fit|plain|reset|zoom <px>]", "a second window drawing the map like mapexport",
      "A prototype: the map you are on drawn in the style of mapexport, in a second window. A red ring marks you; click a room to walk there; the wheel zooms, 'fit' shows the whole map. Mudlet's map stays where it is." },
    { "mapimport [profile] [confirm|undo]", "join another profile's map into this one",
      "Join another profile's map into this one: rooms, exits, recorded exits, marks, notes and avoided rooms it has that this one lacks. Bare, list your other profiles that have a saved map; with a name, what it would add; 'confirm' does it. Where the two disagree, this one is kept. Your map is saved first, and 'mapimport undo' puts it back (this session only; anything explored since is lost). If the other map draws an area into another one, the import says so by name; 'mapunmerge' reverses it. Close the other profile first, so its latest exploring is in its saved map." },
  } },
  { title = "Mazes", rows = {
    { "mapcoins [on|off|reset|relearn|twoway|back|go [n]|layout]", "tell a maze's identical rooms apart by dropped coins",
      "For a maze whose rooms all look alike. Switch it on inside the maze ('on <room name>' if it cannot read the name): after each move into a room with no gold it drops a number of coins no other room has, so every room is known by its coins, and draws the rooms on a map of their own as you walk. Lines leave each room in the direction you walked, coloured by direction, with an arrow where they led; a short line marks a way not yet tried. Bare, the rooms numbered so far: where each way leads, which come back to the same room, which did not move you, which showed something else, and which are untested. 'go' walks to the nearest room with an untested way, 'go <n>' to room n, a step at a time; typing anything stops it. 'twoway' takes every way walked to lead back the way you came, for a maze that keeps to that. 'layout' has the mapper's engine tidy the coin map once. 'relearn' forgets every way but keeps the room numbers, since the coins are still lying there. 'reset' wipes it all and starts again at 1; 'off' stops dropping. In a cave of forward, right, back and left it keeps track of your facing and reads what each room says lies around you; 'back stay' is for a cave where back steps away without turning you, 'back turn' changes it again. Kept for this session only." },
  } },
  { title = "Fixing the map", rows = {
    { "mapwipe [area] [confirm]", "delete the whole map, or one area",
      "Delete the whole map, or every room the game put in one area. Without 'confirm' it only says what it would delete." },
    { "mapdelroom <id>|sel", "delete a room and its exits",
      "Delete a room and every exit to or from it, then redraw; 'sel' is every room selected on the map (also in its right-click menu as 'Delete rooms'). Use this rather than Mudlet's own delete: it clears the room's records and drawn lines too." },
    { "mapdeledge <from> <to>", "delete the exits from one room to another",
      "Delete every exit from one room to another, compass and special." },
    { "maprecordmove [command]", "record an exit you type as a command",
      "Record a special or multi-step exit ('maprecordmove enter gate'); bare, it captures the next one you walk. A recorded exit is kept like any other and speedwalks use it." },
    { "maprecordroute a,b,c", "record a known way through a blocked maze",
      "Record the known way through rooms the map does not show (a blocked maze) as one exit, one way." },
    { "maprecordundo", "take back the exit just recorded",
      "Take back the exit just recorded, and restore the one it replaced." },
    { "mapmerge <area>", "draw an area on the map you are standing on",
      "Merge that area into the one you are standing in, so both are drawn as one map." },
    { "mapunmerge <area>", "undo a merge",
      "Undo a merge, yours or one the game suggested. 'mapmerges' lists both.",
      also = { "mapmerges" } },
    { "maphints [on|off [area]]", "follow the game's suggestions to draw areas together",
      "The game may suggest drawing an area on another's map (a town built by several wizards). Follow the suggestions or not, for all areas or one; bare, list them." },
  } },
  { title = "Appearance", rows = {
    { "mapterrain [on|off]", "colour rooms by terrain",
      "Colour rooms by terrain; 'maplegend' says which colour is what." },
    { "mapglyphs [on|off]", "a letter on rooms with a typed exit",
      "A letter on rooms with an exit you type instead of a direction." },
    { "mapstubs [on|off|edges|classic|halo N]", "how unexplored exits are drawn",
      "What the map draws for unexplored exits. Mudlet redraws every stub of its own every frame, so a big part-explored area is slow. 'edges' draws each unexplored exit as a short line instead, which is far cheaper; 'classic' is Mudlet's stubs with a halo, showing only the stubs within N cells of you once an area has a lot. Nothing is lost either way." },
    { "mapvert [on|stack|off]", "how floors joined by up and down are placed",
      "'on' docks each floor beside the one it connects to, so every floor shows at once; a floor with no room beside its stair goes on its own level over it instead, and so does anything beyond it. 'stack' puts each floor on its own level, directly over or under its stair: right for Mudlet's 3D map, where up and down then stand upright instead of running across the map; in the 2D map you see one level at a time. 'off' places every floor on its own. Remembered." },
    { "mapstitch [on|off]", "neighbouring areas around the one shown in 3D",
      "Mudlet's 3D map (5.1) can draw the areas next to the one you are in around its edges. Off unless you turn it on: this mapper lays each area out on its own, so neighbours drawn together can overlap. Bare, says which it is. Kept in the map, so your choice holds." },
    { "maplevels [on|off]", "show the levels above and below as rings in 2D",
      "Mudlet can draw the rooms one level up and one level down as rings on the 2D map. Off unless you turn it on: with stacked floors the rings cover the level you are on. On, make them faint in Preferences: open the colour for the upper or lower level and set its alpha channel to about 50. Bare, says which it is. Kept in the map, so your choice holds." },
    { "mapareamin <n>", "how small an area folds into the world map",
      "The smallest cluster of rooms that keeps an area of its own instead of folding into the world map. Remembered." },
  } },
}

H.advanced = {
  { title = "Shaping the map by hand", rows = {
    { "mapcur <id|area>", "set the room you are in by hand",
      "Set the current room by hand: an id, or any room of a named area." },
    { "mapfold <dir>", "fold the branch through an exit into a submap",
      "Fold the branch through that exit into a submap." },
    { "mapunfold <dir>", "undo a fold",
      "Undo a fold. 'mapfolds' lists them.", also = { "mapfolds" } },
    { "mapsteal <id,...>", "move rooms into the area you are in",
      "Steal rooms into the area you are standing in, in one relayout." },
    { "mapunsteal <id,...>", "give stolen rooms back",
      "Return stolen rooms to their own area. 'mapsteals' lists them.", also = { "mapsteals" } },
    { "mapouter [clear] [id,...]", "rooms to draw on the outside",
      "Mark rooms as on the outer face, drawn outermost; bare, list them, 'clear' unmarks." },
  } },
  { title = "Mazes and shifting exits", rows = {
    { "mapmaze [auto [area|.]|sel]", "fold a maze into a submap",
      "Fold untruthful clusters into a submap: bare, the current room's; 'auto' the whole map, 'auto <area>' one area. 'sel' marks every room selected on the map as maze and folds once, for mirror mazes, which change nothing and so are invisible to 'auto'." },
    { "mapunmaze [all|id,...]", "release a maze submap",
      "Release the current room's whole maze submap; with room ids (or 'here') release only those, leaving the rest folded; 'all' releases every submap and clears the maze override. 'mapmazes' lists them.",
      also = { "mapmazes" } },
    { "mapmazelive [area|.|clear]", "what the last solve did with a maze's doors",
      "What the last solve did with this area's maze doors: which are drawn as spokes, which fell back to a stub, and whether the area was vetoed; 'clear' lifts vetoes." },
    { "mapmazefit [area|.]", "could each maze be one layout vertex",
      "Report whether each maze could be one layout vertex: its doors, their directions, and where that vertex would sit. Changes nothing." },
    { "mapexitlock [dir]", "stop the game re-pointing an exit",
      "Lock the current room's compass exits, or one, so the game's data cannot re-point them." },
    { "mapexitunlock [dir]", "unlock exits", "Clear exit locks on the current room; bare, all of them." },
    { "mapmutreset [id|area|all]", "wipe exit change counters",
      "Wipe the counts of exits that changed; bare, the current room's." },
  } },
  { title = "Appearance, in detail", rows = {
    { "mapterrain list|here|halo", "terrain counts, this room's terrain, the halo",
      "'list': how many rooms of each terrain the map holds. 'here': what the game sent for this room and what it became, which tells 'not sent' from 'not coloured'. 'halo <radius> [rim alpha] [centre alpha]' tunes the secondary ring; bare, the current values. Bare 'mapterrain' repaints from stored data." },
    { "mapglyphs list|auto on|off", "which rooms carry letters and why",
      "'list': which rooms are glyphed, their exit names and where each came from. 'auto on|off': count guessed special exits as evidence, or only advertised and recorded ones." },
    { "mapvert [area|all]", "up and down census",
      "Up and down census, and what the last pack honoured and drew." },
  } },
  { title = "Diagnostics", rows = {
    { "mapprofile [on|off|ms]", "time each phase of a move",
      "Time the phases of each move (graph, terrain, guess, relayout, view) and print those over <ms>; for finding what a slow move is doing." },
    { "mapecho [on|off]", "report when a relayout finishes",
      "Report when a relayout finishes: time, frames, the solver's profile. Off by default, and then no relayout prints anything." },
    { "mapoff [id]", "what is recorded about exits leaving the map",
      "What is recorded for a room about exits that leave the map: the record, the stubs, the lines." },
    { "mapstrict [on|off]", "draw only exits the game confirms",
      "Draw an exit only when the game reports the command you sent, and ignore a known room reported under another area. For a guild that rewrites what you see; following a party leader then draws no exits. Off by default." },
    { "mapaudit [all]", "exits the trusted exits contradict",
      "Exits whose geometry the exits walked both ways contradict: usually mistyped links." },
    { "mapedges [id]", "a room's exits in and out", "Outgoing and incoming exits for a room; bare, the current one." },
    { "mapmut [id]", "a room's exit change counts", "Per-exit change counters and lock state; bare, the current room." },
    { "mapcrossings", "every crossing and why it is allowed",
      "Every crossing as exit by exit, and what licensed it: cost, a proven wire, or nothing." },
    { "mapcaps", "why branches were capped", "Why each branch was capped during a render." },
    { "mapdump [sel|all]", "dump rooms, coordinates and exits",
      "Dump this area's rooms, coordinates and exits; 'sel' the rooms selected on the map, 'all' every room's area and coordinates." },
  } },
  { title = "Replay", rows = {
    { "mapsteps", "list the placement steps",
      "List room placement steps (set 'lua elro.stepDebug=true' before 'maprelayout this')." },
    { "mapstep [back|id|step n|off|reset]", "step through a placement",
      "Bare, advance one step; 'back' one step back; an id stops just before that room is placed." },
    { "maptop [n]", "slowest placement steps",
      "The slowest placement steps of the last relayout (set 'lua elro.stepTime=true' first)." },
    { "maplever [name ...]", "force levers to the front",
      "Force named levers to the front of every ranking; bare, list them, 'off' clears." },
  } },
  { title = "Tuning, timing and state", rows = {
    { "maprelayout [all|this]", "redraw maps now",
      "Redraw the maps that changed; 'all' every map, 'this' the one you are looking at, changed or not. It happens by itself; this is for after a setting change." },
    { "mapauto on|off|idle N", "when maps redraw by themselves",
      "Automatic relayout: at once when the drawing is visibly wrong, otherwise N seconds after you stop (on, 3 seconds by default)." },
    { "mapknobs [reset]", "settings overridden this session",
      "Every knob and probe overridden this session; 'reset' clears them. They survive mapreload, so a knob left set looks exactly like a code change that did nothing: run this before trusting any measurement." },
    { "mapbg [on|off|cancel|slice N|gc N|hook N]", "background relayout",
      "Background relayout, which does not freeze the client: state, on or off, abort, or the per-frame budget in ms. 'gc N' collects between frames; 'hook N' reports the source lines that blew the frame budget." },
    { "mapwd <secs|off>", "stop a runaway relayout",
      "Watchdog: abort a runaway relayout and say where it was, instead of freezing Mudlet (60 seconds by default)." },
    { "mapcs [reset]", "snapshot of Mudlet's room state",
      "Snapshot stats; 'reset' forces a full re-read of Mudlet's room state." },
    { "mapdebug on|off", "layout step tracing", "Switch layout step tracing on or off." },
    { "mapreload", "reload the code from disk",
      "Re-read lua/modules.lua and every module from disk, with no reinstall; also drops the room-state snapshot ('mapcs reset' does that alone)." },
    { "mapsrc [path]", "where the code is loaded from",
      "Show or set the directory the modules are loaded from. Remembered." },
  } },
}

-- A page is a title and paragraphs; "Head|text" is a paragraph under a heading.
H.pages = {
  mouse = { title = "On the map, with the mouse", paras = {
    "Double-click a room|Walks there by the shortest way, using recorded exits where they are needed.",
    "Click a room|Shows its notes in the map's corner.",
    "Right-click a room|Besides Mudlet's own entries: 'Walk here', 'Add note', 'Notes' and 'Delete rooms' (every selected room, cleanly; see 'mapdelroom'). Mudlet's 'Lock' keeps speedwalks out, the same as 'mapavoid'.",
    "The docked panel|Drag the bar at its inner edge to make it wider or narrower; the size is remembered. The X on the map's strip closes it; right-click any strip or bar to show it again, hide or show panes, or reset the layout. With NannyBasics, drag a pane by its title strip to move it, and the bars between panes to resize them.",
    "In mapview|Click a room to walk there; the wheel zooms.",
  } },
  auto = { title = "What happens by itself", paras = {
    "As you walk|Each move places the room and, when the drawing is visibly wrong or a few seconds after you stop, the area is laid out again in the background without freezing the client ('mapauto').",
    "Small areas|An area of only a few rooms is drawn on the world map instead of a tab of its own ('mapareamin').",
    "The dark|In a dark room the map shows you off the map; its exit stays unexplored, since it maps like any other once you bring a light.",
    "Gates|A magician's gate is not an exit: 'enter gate' maps the room you come out in without linking it to the room you left. A gate that always stands in the same spot can be recorded with 'maprecordmove enter gate'.",
    "The game's suggestions|The game may suggest drawing a town built by several wizards as one map; this is followed unless you say otherwise ('maphints').",
    "Prompts|A speedwalk or alias that sends several commands shows one prompt, not one per command ('mapprompts').",
    "Updates|Shortly after Mudlet starts you are told when a newer release is out ('mapupdate').",
    "Maze coins|The coin maze's own map is wiped at the next start ('mapcoins').",
  } },
  setup = { title = "Recommended setup", paras = {
    "What this mapper sets for you, and what to set yourself. Every choice below can be changed back.",
    "In the game|'toggle gmcp' and 'toggle gmcp room' switch the map data on; both are remembered at your next login.",
    "The map window|'mapwin dock' puts the map in a panel on the right, shared with NannyBasics' panes. Mudlet's own Map button works too.",
    "Floors in 2D|'mapvert on' (the default) docks each floor beside the one it connects to, so you see every floor at once. A floor with no room beside its stair goes on its own level over it.",
    "Other levels in 2D|Hidden by default, so a stacked floor never covers the level you are on. 'maplevels on' shows them as rings; then set the alpha channel of the upper and lower level colours in Preferences to about 50, so they stay faint.",
    "Prompts|'mapprompts' is on by default: a speedwalk shows one prompt, not one per step.",
    "The 3D map|Mudlet 5.1's 3D map is an experiment you switch on yourself. With it, type 'mapvert stack' so floors stand on their own levels. Neighbouring areas stay off ('mapstitch'). 'maphelp 3d' has the rest.",
  } },
  ["3d"] = { title = "The 3D map", paras = {
    "Mudlet 5.1 has a new 3D map, still an experiment, so it is off until you switch it on. It draws the same map as the 2D one, in one of seven styles; 'diorama' looks like a model town on a board.",
    "Switching it on|lua setConfig(\"experiment.3dmap.modernmapper\", true) or Settings, Advanced, Experiments, tick 'Modern 3D mapper'.",
    "Picking a style|Preferences, Mapper; or for example: lua setConfig(\"mapStyle\", \"diorama\")",
    "Floors|Type 'mapvert stack' while you use the 3D map: each floor goes on its own level over its stairs, so up and down stand upright instead of running across the map. 'mapvert on' puts back the flat layout, which gives the better overview in 2D.",
    "Other levels in 2D|The rooms one level up and down are hidden unless you type 'maplevels on'. Then they show as rings; to make them faint, open the colour for the upper or lower level in Preferences and set its alpha channel to about 50 (255 is solid).",
    "Neighbouring areas|Mudlet can draw the areas next to yours around its edges. This mapper keeps that off, because areas laid out one by one overlap when drawn together; 'mapstitch on' if you want it anyway.",
    "Clicking|Double-click a room to walk there and right-click for the same menu as on the 2D map.",
  } },
  share = { title = "Moving your map", paras = {
    "'mapexport' makes a picture to print. It does not copy your map. The map itself lives in your Mudlet profile, and Mudlet moves it:",
    "To another profile of yours|Settings, the Mapper tab, 'Copy map to other profile(s)': pick the profiles and press Copy.",
    "To a file|Settings, the Mapper tab, 'Save map...'. A backup, or something to hand to another player.",
    "From a file|Settings, the Mapper tab, 'Load map...'. This REPLACES the map in that profile; the two are not merged. Save your own first if you may want it back.",
    "Joining two maps|'mapimport <profile>' adds what another profile's map has and this one lacks, and keeps this one's where they disagree. Bare 'mapimport' lists the profiles.",
    "After a map is loaded or copied into a profile that is open, close and reopen that profile so the mapper reads the new map from the start.",
    "The file carries everything: rooms, exits, the special exits you recorded, terrain, merges, folds, your marks and room notes, and the rooms speedwalks keep out of. Only the map window's size and corner belong to the profile. The receiving profile needs this package too, and 'toggle gmcp' and 'toggle gmcp room' in the game to keep mapping.",
    "A map shows where you have been. Handing one over hands over that exploring.",
  } },
}
H.page_order = { "setup", "mouse", "auto", "3d", "share" }

-- the command word of a row, and every word it answers to
local function words(row)
  local w = { row[1]:match("^(%S+)") }
  for _, a in ipairs(row.also or {}) do w[#w + 1] = a end
  return w
end
H.words = words

-- every row, with the list it belongs to
function H.all_rows()
  local out = {}
  for _, list in ipairs({ H.sections, H.advanced }) do
    for _, s in ipairs(list) do
      for _, r in ipairs(s.rows) do out[#out + 1] = r end
    end
  end
  return out
end

-- What 'maphelp <arg>' shows: { kind = "rows"|"detail"|"page"|"none", ... }
function H.lookup(arg)
  arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if arg == "" then return { kind = "list", sections = H.sections } end
  if arg:match("^adv") then return { kind = "list", sections = H.advanced, advanced = true } end
  for name, p in pairs(H.pages) do
    if arg == name or (#arg >= 4 and name:sub(1, #arg) == arg) then return { kind = "page", page = p } end
  end
  local exact = {}
  for _, r in ipairs(H.all_rows()) do
    for _, w in ipairs(words(r)) do if w == arg then exact[#exact + 1] = r ; break end end
  end
  if #exact > 0 then return { kind = "detail", rows = exact } end
  local rows, pages = {}, {}
  for _, r in ipairs(H.all_rows()) do
    local text = (r[1] .. " " .. r[2] .. " " .. (r[3] or "") .. " " .. table.concat(r.also or {}, " ")):lower()
    if text:find(arg, 1, true) then rows[#rows + 1] = r end
  end
  for _, name in ipairs(H.page_order) do
    local p = H.pages[name]
    if (p.title .. " " .. table.concat(p.paras, " ")):lower():find(arg, 1, true) then pages[#pages + 1] = name end
  end
  if #rows == 0 and #pages == 0 then return { kind = "none", word = arg } end
  return { kind = "found", rows = rows, pages = pages, word = arg }
end

elro.HELP = H

-- ---- in the client ----

function elro.map_help(arg)
  local width = elro.help_width()
  local col = width >= 90 and 30 or 22
  local function wrap(text, w) return elro.wrap_text(text, w) end
  -- a row as command and summary, wrapped with a hanging indent
  local function short_row(cmd, text)
    local own = #cmd + 2 >= col
    if own then cecho("<yellow>  " .. cmd .. "<reset>\n") end
    for i, l in ipairs(wrap(text, width - col - 1)) do
      if i == 1 and not own then
        cecho(string.format("<yellow>  %s<reset>%s%s\n", cmd, string.rep(" ", col - 2 - #cmd), l))
      else
        cecho(string.rep(" ", col) .. l .. "\n")
      end
    end
  end
  local function para(text, indent)
    for _, l in ipairs(wrap(text, width - #indent)) do cecho(indent .. l .. "\n") end
  end
  local r = H.lookup(arg)
  local head = "\n<cyan>ElrohirMapper " .. tostring(elro.VERSION) .. "<reset>: "
  if r.kind == "list" then
    cecho(head .. (r.advanced and "advanced commands" or "everyday commands") .. "\n")
    if not r.advanced then
      -- two help systems, and a new player cannot tell which is which
      for _, l in ipairs(wrap("These commands belong to this Mudlet package and are never sent to the game. "
          .. "The game's own side is 'toggle gmcp' and 'toggle gmcp room', which switch the map data on.", width - 3)) do
        cecho("<cyan>  " .. l .. "<reset>\n")
      end
    end
    for _, s in ipairs(r.sections) do
      cecho("\n<cyan>" .. s.title:upper() .. "<reset>\n")
      for _, row in ipairs(s.rows) do short_row(row[1], row[2]) end
    end
    cecho("\n")
    if not r.advanced then
      local n = #H.all_rows()
      for _, s in ipairs(H.sections) do n = n - #s.rows end
      short_row("maphelp advanced", string.format("%d more: shaping the map by hand, mazes, diagnostics, tuning", n))
    end
    short_row("maphelp <command>", "that command in full")
    short_row("maphelp <word>", "every entry that mentions the word")
    short_row("maphelp setup", "the settings we recommend, for 2D and 3D")
    short_row("maphelp mouse|auto|3d|share", "clicking, what happens by itself, the 3D map, moving your map")
  elseif r.kind == "detail" then
    for _, row in ipairs(r.rows) do
      cecho("\n<yellow>  " .. row[1] .. "<reset>\n")
      para(row[3] or row[2], "    ")
    end
  elseif r.kind == "page" then
    cecho(head .. r.page.title .. "\n\n")
    for _, p in ipairs(r.page.paras) do
      local h, body = p:match("^(.-)|(.+)$")
      if h then cecho("<yellow>  " .. h:upper() .. "<reset>\n") ; para(body, "    ") else para(p, "  ") end
      cecho("\n")
    end
  elseif r.kind == "found" then
    cecho(string.format("\n<cyan>[elro]: help that mentions '%s':<reset>\n", r.word))
    for _, row in ipairs(r.rows) do short_row(row[1], row[2]) end
    for _, name in ipairs(r.pages) do short_row("maphelp " .. name, H.pages[name].title) end
  else
    cecho(string.format("\n<yellow>[elro]: nothing in the help mentions '%s'. 'maphelp' lists the commands.<reset>\n", r.word))
  end
  cecho("\n")
end
