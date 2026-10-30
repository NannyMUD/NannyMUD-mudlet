-- mapnote / mapnotes: lines of text on a room, kept in its user data; a ';' stays in a note,
-- the profile's separator ends it; the map menu and the info overlay reach the same notes.
-- Run: luajit analysis/test_notes.lua      (from the client dir)

-- Mudlet's map menu, info overlay and command line, faked before the engine registers with them
local mapEvents, handlers, infos, cmdline = {}, {}, {}, nil
addMapEvent = function(id, ev, parent, label) mapEvents[label] = ev end
registerAnonymousEventHandler = function(ev, fn) handlers[ev] = fn ; return ev end
killAnonymousEventHandler = function() end
registerMapInfo = function(label, fn) infos[label] = fn end
enableMapInfo = function() end
printCmdLine = function(s) cmdline = s end

dofile("analysis/engine_load.lua")
local selected
getMapSelection = function() return { rooms = selected } end   -- after the harness's own

local fail, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    fail = fail + 1
    print(string.format("FAIL %-56s got %s want %s", what, tostring(got), tostring(want)))
  end
end

reset_map()
local aid = addAreaName("town")
for id = 1, 3 do
  addRoom(id) ; setRoomArea(id, aid) ; setRoomCoordinates(id, id, 0, 0) ; setRoomName(id, "room " .. id)
end
elro.cs_reset()

local said, echoed = {}, {}
cecho = function(s) said[#said + 1] = s end
echo = function(s) echoed[#echoed + 1] = s end
local expanded
expandAlias = function(s) expanded = s end

elro.current = nil
elro.cmd_note("orc")
eq(said[#said]:find("current room unknown", 1, true) ~= nil, true, "no current room: refused")

elro.current = 1
elro.cmd_note("orc guard, 2 swords")
elro.cmd_note("  a <red> key; under the mat  ")
eq(getRoomUserData(1, "note"), "orc guard, 2 swords\na <red> key; under the mat",
   "two notes, trimmed; a lone ';' stays in the note")
echoed = {}
elro.cmd_note("")
eq(echoed[2], "a <red> key; under the mat\n", "bare mapnote lists them through echo, '<red>' kept as text")

getCommandSeparator = function() return ";;" end
elro.cmd_note("dragon;;look")
eq(elro.note_lines(1)[3], "dragon", "the profile's separator ends the note")
eq(expanded, "look", "...and the rest is run as typed")
getCommandSeparator = nil

elro.cmd_note("del 1")
eq(getRoomUserData(1, "note"), "a <red> key; under the mat\ndragon", "del 1 removes the first")
elro.cmd_note("del 9")
eq(said[#said]:find("has no note 9", 1, true) ~= nil, true, "del of a missing line says so")
elro.cmd_note("#3 statue of a cat")
eq(getRoomUserData(3, "note"), "statue of a cat", "#id notes another room")
elro.cmd_note("2 swords on the floor")
eq(elro.note_lines(1)[3], "2 swords on the floor", "a note starting with a number is a note")
elro.cmd_note("#99 nothing")
eq(said[#said]:find("no room 99", 1, true) ~= nil, true, "#id of an unknown room: refused")

echoed = {}
elro.cmd_notes("CAT")
eq(#echoed, 1, "mapnotes <text> lists matching lines only, any case")
eq(echoed[1], "statue of a cat\n", "...the line itself")
echoed = {}
elro.cmd_notes()
eq(#echoed, 4, "bare mapnotes lists every note")

echoed = {}
elro.search_rooms("statue")
eq(echoed[1], "statue of a cat\n", "mapsearch finds a room by its notes")

-- the map: right-click entries and the info overlay
eq(mapEvents["Add note (mapper)"] ~= nil and mapEvents["Notes (mapper)"] ~= nil, true, "both menu entries registered")
selected = { 3 }
handlers[mapEvents["Add note (mapper)"]]()
eq(cmdline, "mapnote #3 ", "Add note puts 'mapnote #3 ' on the command line")
echoed = {}
handlers[mapEvents["Notes (mapper)"]]()
eq(echoed[1], "statue of a cat\n", "Notes lists the selected room's notes")
local info = infos["Notes"]
eq(info ~= nil, true, "a Notes line in the map's info overlay")
eq((info(3)), "Notes: statue of a cat", "...naming the clicked room's notes")
eq((info(2)), "", "...and nothing for a room without notes")

elro.cmd_note("#3 clear")
eq(getRoomUserData(3, "note"), "", "clear empties the room")

print(string.format("test_notes: %d check(s), %d failure(s)", checks, fail))
os.exit(fail > 0 and 1 or 0)
