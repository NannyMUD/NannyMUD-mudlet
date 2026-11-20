-- What changed, release by release: 'maphelp news' shows it, and tools/changelog.lua writes
-- CHANGELOG.md from it. An item is { what changed, the help that tells more }. The top entry
-- is "next" until a release gives it a number and a date.

elro = elro or {}
elro.CHANGES = {
  { version = "0.10.0", date = "2026-11-20", items = {
    { "mapmanual (experimental) maps an area the game sends no map for, from what its rooms show, taking it to be a grid except where an exit has no way back (a dive, a fall), and joins it to the game's map where you walk in and out while learning, so speedwalks go through; mapmanual same joins two rooms a warp makes look apart.", "maphelp mapmanual" },
    { "mapmobs notes the monsters each room shows in the game's xml mode, and tells wanderers from rare spawns; players' pets are left out by themselves, 'mapmobs ignore' takes a '*' for any text and 'mapmobs ignore here' a whole room where players gather.", "maphelp mapmobs" },
    { "mapmobs seen off keeps a clicked room's monsters out of its notes line, for when you want only your own notes there.", "maphelp mapmobs" },
    { "mapnotes looks in one area with 'in <area>', and at monsters or your own notes alone with 'mobs' or 'notes'.", "maphelp mapnotes" },
    { "Clicking a room names the areas its exits lead to; mapflags puts that name at each blue arrow.", "maphelp mapflags" },
    { "A room's letter turns light blue while it has an unwalked up, down or named exit.", "maphelp mapglyphs" },
    { "maplevels and mapstitch now hold between logins.", "maphelp maplevels" },
  } },
  { version = "0.9.1", date = "2026-11-12", items = {
    { "A room on another level no longer gets the yellow mark of a room sitting on an edge.", "maplegend" },
  } },
  { version = "0.9.0", date = "2026-11-12", items = {
    { "maphelp is one lookup: an exact command shows it in full, any other word searches.", "maphelp" },
    { "mapvert stack puts each floor on its own level for Mudlet's 3D map.", "maphelp mapvert" },
    { "Stitching and the rings of other levels are off by default.", "maphelp maplevels" },
    { "A spell gate is no longer recorded as an exit.", "maphelp auto" },
    { "mapcoins (experimental) tells a maze's identical rooms apart by dropped coins.", "maphelp mapcoins" },
  } },
  { version = "0.8.5", date = "2026-10-30", items = {
    { "Room notes: mapnote, mapnotes, found by mapsearch, shown for a clicked room.", "maphelp mapnote" },
    { "mapimport joins another profile's map into this one, with mapimport undo.", "maphelp mapimport" },
  } },
  { version = "0.8.4", date = "2026-10-27", items = {
    { "A room can hold several marks.", "maphelp mapmark" },
  } },
  { version = "0.8.3", date = "2026-10-16", items = {
    { "Two layout guards no longer let a move through that crosses a loop or bends edges.", nil },
  } },
  { version = "0.8.2", date = "2026-10-16", items = {
    { "A named mark saves the map at once.", "maphelp mapmark" },
  } },
  { version = "0.8.0", date = "2026-10-09", items = {
    { "maprecordroute and maprecordundo record a way through ground that cannot be mapped.", "maphelp maprecordroute" },
  } },
  { version = "0.7.1", date = "2026-10-06", items = {
    { "The docked map follows you again when two characters map in the same Mudlet.", "maphelp mapwin" },
  } },
  { version = "0.7.0", date = "2026-10-05", items = {
    { "The mapper and NannyBasics share one repository, one version and one update command.", "maphelp mapupdate" },
  } },
  { version = "0.6.0", date = "2026-10-05", items = {
    { "The map docks in a panel on the right, shared with NannyBasics' panes.", "maphelp mapwin" },
  } },
  { version = "0.5.0", date = "2026-10-04", items = {
    { "The map is drawn from the game's GMCP room data, with exits the game declares.", "maphelp setup" },
    { "A speedwalk shows one prompt, not one per step.", "maphelp mapprompts" },
  } },
}
return elro.CHANGES
