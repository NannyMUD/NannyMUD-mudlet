-- The !NMP line parser: key=value pairs in any order, unknown keys ignored, the
-- off-map marker dispatched to onOff, everything else to onRoom.
dofile("analysis/engine_load.lua")

local fails, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    fails = fails + 1
    print("FAIL " .. what .. "  got " .. tostring(got) .. " want " .. tostring(want))
  end
end

local room, off
elro.onRoom = function(...) room = { ... } end
elro.onOff = function(...) off = { ... } end

-- the everyday line
room, off = nil, nil
elro.nmp_line("id=137|from=136|dir=west|name=a mountain side|area=world|exits=east,west,south|terr=mountain,outdoors")
eq(off, nil, "a room line is not the marker")
eq(room[1], 137, "id")
eq(room[2], 136, "from")
eq(room[3], "west", "dir")
eq(room[4], "a mountain side", "name")
eq(room[5], "world", "area")
eq(room[6], "east,west,south", "exits")
eq(room[7], "mountain,outdoors", "terr")
eq(room[8], nil, "no mha")
eq(room[9], nil, "no mh")

-- the hints, and a field the client does not know
room = nil
elro.nmp_line("id=5|from=4|dir=n|name=x|area=a|exits=|terr=|mha=town|mh=shop|later=whatever")
eq(room[8], "town", "mha")
eq(room[9], "shop", "mh")
eq(room[6], "", "an empty exits field is the empty string")
eq(room[1], 5, "...and an unknown key changes nothing")

-- any order
room = nil
elro.nmp_line("name=y|exits=up|id=9|area=b|from=0|dir=none")
eq(room[1], 9, "keys in any order: id")
eq(room[4], "y", "...name")
eq(room[2], 0, "...from")

-- a trailing line ending survives no field
room = nil
elro.nmp_line("id=3|from=2|dir=east|name=z|area=c|exits=west\r\n")
eq(room[6], "west", "a trailing CR LF is not part of the last value")

-- the markers
room, off = nil, nil
elro.nmp_line("id=0|from=136|dir=west")
eq(room, nil, "the off-map marker is not a room")
eq(off[1], 136, "...it carries from")
eq(off[2], "west", "...and dir")
off = nil
elro.nmp_line("id=0|from=0")
eq(off[1], 0, "the bare marker: from 0")
eq(off[2], nil, "...no dir")

-- rubbish
room, off = nil, nil
elro.nmp_line("garbage")
eq(room, nil, "no id: nothing")
eq(off, nil, "...at all")
elro.nmp_line(nil)
eq(room, nil, "nil: nothing")

-- a bare verb gets its arguments back from the command in flight
local clock = 1000
elro.now_ms = function() return clock end
local function turn(...) elro.sentQ = {} ; for _, c in ipairs({ ... }) do elro.sent_push(c) end end
local function dir(d) room = nil ; elro.nmp_line("id=7|from=6|dir=" .. d .. "|name=x|area=a|exits=") return room[3] end

turn("crawl se")
eq(dir("crawl"), "crawl se", "verb only: the typed arguments are added")
eq(dir("crawl se"), "crawl se", "verb + args from the server: unchanged")
turn("  Crawl   se ")
eq(dir("crawl"), "Crawl se", "the verb matches in any case, whitespace collapsed")
turn("n")
eq(dir("north"), "north", "an abbreviation the server expanded: unchanged")
turn("north")
eq(dir("north"), "north", "a bare command: unchanged")
turn("look")
eq(dir("crawl"), "crawl", "another verb in flight: unchanged")
turn()
eq(dir("crawl"), "crawl", "nothing in flight: unchanged")

turn("open door", "crawl se", "crawl nw")
elro.sent_pop()
eq(dir("crawl"), "crawl se", "each prompt moves to the next command")
elro.sent_pop()
eq(dir("crawl"), "crawl nw", "...and the next")

turn("crawl se")
clock = clock + elro.sentAgeMs + 1
eq(dir("crawl"), "crawl", "a stale head is not trusted")
elro.sent_push("enter")
eq(#elro.sentQ, 1, "a push drops what idled past the limit")
eq(elro.sentQ[1].cmd, "enter", "...and keeps the new command")

turn("climb tree")
off = nil
elro.nmp_line("id=0|from=6|dir=climb")
eq(off[2], "climb tree", "the off-map marker is amended too")

-- the admin's !NMAP server: -1 is off the map, for id and from alike
elro.sentQ = {}
elro.current = nil
room, off = nil, nil
elro.nmp_line("id=-1|from=12|dir=west|name=|area=|exits=|terr=")
eq(room, nil, "id=-1 is not a room")
eq(off[1], 12, "...it is the off-map marker, with from")
eq(off[2], "west", "...and dir")
off = nil
elro.nmp_line("id=-1|from=0|dir=none|name=|area=|exits=|terr=")
eq(off[1], 0, "id=-1 from a teleport: the bare marker")
room = nil
elro.nmp_line("id=40|from=-1|dir=none|name=x|area=a|exits=|terr=")
eq(room[1], 40, "from=-1 into a mapped room is a room line")
eq(room[2], 0, "...with from 0, a jump")

-- a from the client never put the player in is a jump
elro.current = 35
room = nil
elro.nmp_line("id=36|from=35|dir=crawl se|name=x|area=a|exits=|terr=")
eq(room[2], 35, "from = the current room: kept")
room = nil
elro.nmp_line("id=37|from=99|dir=north|name=x|area=a|exits=|terr=")
eq(room[2], 0, "from = a room never entered (the dark): a jump")
off = nil
elro.nmp_line("id=-1|from=99|dir=north|name=|area=|exits=|terr=")
eq(off[1], 0, "...the same for the off-map marker, so no exit is recorded")
elro.current = nil
room = nil
elro.nmp_line("id=38|from=36|dir=east|name=x|area=a|exits=|terr=")
eq(room[2], 36, "no current room yet (a fresh session): from is taken as sent")

-- offgrid: the map's own entry point, no exit recorded
off = nil
elro.offgrid()
eq(off[1], 0, "offgrid is the bare off-map marker")
eq(off[2], nil, "...with no dir")

-- strict mode: an exit only for the command in flight
elro.strict = true
elro.current = 50
elro.sentQ = {}
elro.sent_push("s")
room = nil
elro.nmp_line("id=51|from=50|dir=south|name=x|area=a|exits=|terr=")
eq(room[2], 50, "strict: typed 's', reported 'south': the exit is kept")
elro.sentQ = {}
elro.sent_push("south")
room = nil
elro.nmp_line("id=51|from=50|dir=southh|name=x|area=a|exits=|terr=")
eq(room[2], 0, "strict: a garbled dir is a jump")
elro.sentQ = {}
room = nil
elro.nmp_line("id=51|from=50|dir=north|name=x|area=a|exits=|terr=")
eq(room[2], 0, "strict: nothing in flight (a party follow) is a jump")
elro.sent_push("crawl se")
room = nil
elro.nmp_line("id=51|from=50|dir=crawl se|name=x|area=a|exits=|terr=")
eq(room[2], 50, "strict: a typed command that matches is kept")
-- strict mode: a known room under another area is a garbled line, dropped
reset_map()
addRoom(36) ; setRoomUserData(36, "sarea", "elrohir")
addRoom(37)
elro.current = 35
room, off = nil, nil
elro.nmp_line("id=36|from=0|dir=none|name=thhe forest|area=elrohhir|exits=|terr=")
eq(room, nil, "strict: known room, other area: the line is not used")
eq(off[1], 0, "...and the map goes off the grid")
room = nil
elro.nmp_line("id=36|from=0|dir=none|name=the forest|area=elrohir|exits=|terr=")
eq(room[1], 36, "strict: known room, same area: mapped")
room = nil
elro.nmp_line("id=37|from=0|dir=none|name=x|area=elrohir|exits=|terr=")
eq(room[1], 37, "strict: a known room with no stored area is not judged")
room = nil
elro.nmp_line("id=38|from=0|dir=none|name=x|area=anything|exits=|terr=")
eq(room[1], 38, "strict: a new room cannot be judged: mapped")
room = nil
elro.nmp_line("id=39|from=0|dir=none|name=x|area=|exits=|terr=")
eq(room[1], 39, "...an empty area on a new room too")

elro.strict = false
room = nil
elro.nmp_line("id=36|from=0|dir=none|name=x|area=elrohhir|exits=|terr=")
eq(room[1], 36, "strict off: the area is not judged")
elro.sentQ = {}
elro.current = 50
room = nil
elro.nmp_line("id=51|from=50|dir=north|name=x|area=a|exits=|terr=")
eq(room[2], 50, "strict off: nothing in flight still draws the exit")
elro.current = nil
reset_map()

-- the package: both tags, the dark line, and no handshake left
local function slurp(p) local f = io.open(p, "rb") ; local s = f:read("*a") ; f:close() ; return s end
local xml, core = slurp("map_helper.xml"), slurp("lua/core.lua")
eq(xml:find("^!NMA?P (.+)$", 1, true) ~= nil, true, "the trigger takes !NMP and !NMAP")
eq(xml:find("^A dark room\\.$", 1, true) ~= nil, true, "the NannyMUD dark trigger is there")
eq(xml:find("elro.offgrid()", 1, true) ~= nil, true, "...and calls offgrid")
eq(xml:find("mapack", 1, true), nil, "no mapack alias")
eq(core:find("nmp ack", 1, true), nil, "no handshake sent")
eq(("!NMAP id=1|from=0"):match("^!NMA?P (.+)$"), "id=1|from=0", "the tag pattern reads !NMAP")
eq(("!NMP id=1|from=0"):match("^!NMA?P (.+)$"), "id=1|from=0", "...and !NMP")

print(string.format("test_nmp: %d check(s), %d failure(s)", checks, fails))
os.exit(fails == 0 and 0 or 1)
