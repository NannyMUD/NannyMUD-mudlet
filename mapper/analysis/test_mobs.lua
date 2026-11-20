-- monsters seen per room: <monster> lines of a room listing, kept at the prompt for the room
-- you are in; mapnotes finds them beside the notes, 'mobs' and 'notes' filter one or the other.
-- Run: luajit analysis/test_mobs.lua      (from the client dir)
dofile("analysis/engine_load.lua")
local B, X = elro.mobs, NannyXml

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
for id = 1, 2 do addRoom(id) ; setRoomArea(id, aid) ; setRoomCoordinates(id, id, 0, 0) ; setRoomName(id, "room " .. id) end
elro.cs_reset()
local echoed, said = {}, {}
echo = function(s) echoed[#echoed + 1] = s end
cecho = function(s) said[#said + 1] = s end

-- what xml.lua hands its listeners as a room is listed
local function listing(id, names)
  elro.current, elro.offmap = id, false
  X.listeners.mobs("short", "Room " .. id)
  for _, n in ipairs(names) do X.listeners.mobs("monster", n) end
  B.prompt()
end

B.state = nil
listing(1, { "A very large boar.", "An orc.", "An orc." })
local t = B.list(1)
eq(#t, 2, "two names, the second orc counted once per listing")
eq(t[1][1], "A very large boar", "...full stop off")
listing(1, { "An orc." })
eq(B.list(1)[1][1] == "An orc" and B.list(1)[1][2] == 2, true, "seen again: counted, most seen first")

-- a monster outside a listing (an arrival) is not kept
elro.current = 2
X.listeners.mobs("monster", "A wolf.")
B.prompt()
eq(#B.list(2), 0, "a monster line with no room listing: not kept")

-- off: nothing new is noted
elro.cmd_mobs("off")
listing(2, { "A wolf." })
eq(#B.list(2), 0, "mapmobs off: nothing noted")
elro.cmd_mobs("on")
listing(2, { "A wolf." })
eq(#B.list(2), 1, "on again: noted")

-- mapnotes: both, or one kind
elro.current = 1
elro.cmd_note("orc chief hides here")
echoed = {}
elro.cmd_notes("orc")
eq(#echoed, 2, "mapnotes orc: the note and the monster")
echoed = {}
elro.cmd_notes("mobs orc")
eq(#echoed == 1 and echoed[1], "An orc 2/2\n", "mapnotes mobs orc: the monster only, seen in 2 of 2 listings")
echoed = {}
elro.cmd_notes("notes orc")
eq(#echoed == 1 and echoed[1], "orc chief hides here\n", "mapnotes notes orc: the note only")
echoed = {}
elro.cmd_notes("in town mobs wolf")
eq(#echoed == 1 and echoed[1], "A wolf 1/1\n", "in <area> and mobs together")
echoed = {}
elro.cmd_notes("notes")
eq(#echoed, 1, "'notes' alone: every note, no monsters")

-- resident, rare spawn, wanderer: rooms 3 and 4, ten listings each
for id = 3, 4 do addRoom(id) ; setRoomArea(id, aid) ; setRoomCoordinates(id, id, 1, 0) end
elro.cs_reset()
for i = 1, 10 do
  local in3 = { "A guard" }
  if i == 5 then in3[#in3 + 1] = "A ghost" end                  -- once in ten, only here
  if i == 2 then in3[#in3 + 1] = "A goblin" end                 -- once here...
  listing(3, in3)
  listing(4, i == 7 and { "A goblin" } or {})                   -- ...and once there
end
local kinds = {}
for _, r in ipairs(B.rows(3, true)) do kinds[r[1]] = r[4] end
eq(kinds["A guard"], "resident", "in every listing: a resident")
eq(kinds["A ghost"], "rare", "seldom, and nowhere else in the area: a rare spawn")
eq(kinds["A goblin"], "wanders", "seldom, and elsewhere in the area too: a wanderer")
local shown = {}
for _, r in ipairs(B.rows(3)) do shown[r[1]] = true end
eq(shown["A goblin"] == nil and shown["A ghost"] and shown["A guard"], true, "wanderers hidden unless 'all'")
echoed = {}
elro.cmd_notes("mobs all goblin")
eq(#echoed, 2, "mapnotes mobs all goblin: both rooms it wandered through")
eq(echoed[1]:find("1/10 wanders", 1, true) ~= nil, true, "...marked as wandering")

-- a follower is in every room you are: ignored, and taken out where it was noted
listing(3, { "Rex" }) ; listing(4, { "Rex" })
elro.cmd_mobs("ignore Rex")
local any = false
for id = 3, 4 do for _, m in ipairs(B.list(id)) do if m[1] == "Rex" then any = true end end end
eq(any, false, "mapmobs ignore: out of every room")
listing(3, { "Rex" })
eq(B.list(3)[1][1] ~= "Rex" and #B.list(3) == 3, true, "...and never noted again")

-- a player seen in a room is known: a monster named after them is their pet, never noted, and
-- one noted before they were seen is no longer shown
listing(3, { "Bram's wolf, Greyfang" })
eq(#B.rows(3, true) > 0 and B.rows(3, true)[1][1] ~= nil, true, "before the owner is seen: noted")
X.listeners.mobs("player", "Bram the Necromancer (good)")
local shown = false
for _, r in ipairs(B.rows(3, true)) do if r[1]:find("Bram", 1, true) then shown = true end end
eq(shown, false, "once Bram is seen as a player, his pets are not shown")
listing(3, { "Bram's undead attendant" })
local noted = false
for _, m in ipairs(B.list(3)) do if m[1] == "Bram's undead attendant" then noted = true end end
eq(noted, false, "...and not noted")
eq(B.is_pet("Tom's cat"), false, "a name with an owner nobody saw as a player is a monster")

-- the clicked room's "Seen:" line off, kept with the map; the notes' line is another
local off, ud = {}, {}
local realGet, realSet = getMapUserData, setMapUserData
getMapUserData = function(k) return ud[k] or "" end
setMapUserData = function(k, v) ud[k] = v end
disableMapInfo = function(k) off[k] = true end
enableMapInfo = function(k) off[k] = nil end
elro.cmd_mobs("seen off")
eq(off["Monsters seen"], true, "seen off: the monsters' line is hidden")
eq(getMapUserData("elro.mobs.seen"), "off", "...and that is kept")
elro.cmd_mobs("seen on")
eq(off["Monsters seen"], nil, "seen on: shown again")
getMapUserData, setMapUserData = realGet, realSet

-- a room where players gather: nothing noted there
elro.current, elro.offmap = 4, false
elro.cmd_mobs("ignore here")
eq(#B.list(4), 0, "ignore here: the room's monsters are gone")
listing(4, { "A goblin." })
eq(#B.list(4), 0, "...and none are noted")
elro.current = 4
elro.cmd_mobs("unignore here")
listing(4, { "A goblin." })
eq(#B.list(4), 1, "unignore here: noted again")

-- a player's pet carries its owner's name first: '*' stands for any text
listing(3, { "Rook's clay golem", "Gerda's clay golem", "Rook's homunculus", "A clay golem" })
elro.cmd_mobs("ignore *'s clay golem")
local left = {}
for _, m in ipairs(B.list(3)) do left[m[1]] = true end
eq(left["Rook's clay golem"] == nil and left["Gerda's clay golem"] == nil, true, "'*'s clay golem': every owner's")
eq(left["A clay golem"] and left["Rook's homunculus"], true, "...the wild golem and other pets stay")
elro.cmd_mobs("ignore rook's *")
listing(3, { "Rook's ouroboros (sleeping)" })
left = {}
for _, m in ipairs(B.list(3)) do left[m[1]] = true end
eq(left["Rook's homunculus"] == nil and left["Rook's ouroboros (sleeping)"] == nil, true,
   "'rook's *': all of one owner's pets, odd characters and all")

-- turning it on asks for the game's xml mode: the mapper alone only says so, 'anyway' asks
local sent = {}
send = function(s) sent[#sent + 1] = s end
NannyXml.state, NannyBasics = nil, nil
elro.cmd_mobs("on")
eq(#sent, 0, "mapper alone: xml mode is not switched without asking")
elro.cmd_mobs("on anyway")
eq(sent[1], "toggle xml on", "'mapmobs on anyway' asks the game")
NannyXml.answer("xml mode turned on.")
NannyBasics = { colours = {} }
elro.cmd_mobs("on")
eq(#sent, 1, "already on: nothing more is sent")
NannyBasics = nil

elro.cmd_mobs("clear #1")
eq(#B.list(1), 0, "mapmobs clear #id forgets a room's monsters")
eq(elro.note_lines(1)[1], "orc chief hides here", "...and keeps its notes")

print(string.format("test_mobs: %d check(s), %d failure(s)", checks, fail))
os.exit(fail > 0 and 1 or 0)
