-- maprecordroute: the known way through rooms the map does not show, recorded as one edge
-- from where it started to the first mapped room it comes out in; and maprecordundo.
--   cd .../mapper && luajit analysis/test_route.lua
dofile("analysis/engine_load.lua")

local fails, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    fails = fails + 1
    print("FAIL " .. what .. "  got " .. tostring(got) .. " want " .. tostring(want))
  end
end

local SPECIAL = {}
function getSpecialExits(id) return SPECIAL[id] or {} end
function addSpecialExit(a, b, cmd) SPECIAL[a] = SPECIAL[a] or {} ; SPECIAL[a][cmd] = b end
function removeSpecialExit(id, cmd) if SPECIAL[id] then SPECIAL[id][cmd] = nil end end
local SENT = {}
function send(c) SENT[#SENT + 1] = c end
function tempTimer() return 1 end
function killTimer() end
cecho = function() end
elro.smap = {} ; elro.save_smap = function() end
elro.flush_dirty = function() return 0 end ; elro.flush = elro.flush_dirty

local function out(id, dir) elro.nmp_room({ id = id, from = 0, dir = dir, name = "Out " .. id,
  area = "maze", exits = "north,south" }) end

-- 1. the route is sent as given and recorded from where it started to where it came out
elro.onRoom(1, 0, "none", "Entrance", "maze", "north", "outdoors")
elro.route_start("n, e ,climb tree,s")
eq(table.concat(SENT, "|"), "n|e|climb tree|s", "the steps are sent as given, trimmed")
out(5, "s")
eq(elro.smap["1:5"], "n;;e;;climb tree;;s", "recorded as one edge 1 -> 5")
eq(elro.has_special(1, 5), true, "...and as a special exit Mudlet can route over")
eq(elro.smap["5:1"], nil, "one way only")
eq(elro.rec, nil, "the recorder is disarmed")

-- 2. maprecordundo takes it back
elro.rec_undo()
eq(elro.smap["1:5"], nil, "undo removes the edge")
eq(elro.has_special(1, 5), false, "...and the special exit")
elro.rec_undo()
eq(elro.smap["1:5"], nil, "a second undo has nothing to take back")

-- 3. undo puts back the recording it replaced
elro.smap["1:5"] = "old" ; addSpecialExit(1, 5, "old")
elro.current = 1
elro.route_start("n,e")
out(5, "e")
eq(elro.smap["1:5"], "n;;e", "a new route replaces the old recording")
elro.rec_undo()
eq(elro.smap["1:5"], "old", "undo puts the old recording back")
eq(SPECIAL[1] and SPECIAL[1]["old"], 5, "...and its special exit")
eq(SPECIAL[1] and SPECIAL[1]["n;;e"], nil, "...without the new one")

-- 4. fences: a first step into a mapped room, a way back to the start, too many steps
elro.current = 1 ; elro.smap = {}
elro.route_start("climb rope")
elro.nmp_room({ id = 2, from = 1, dir = "climb rope", name = "Mapped", area = "maze", exits = "down" })
eq(elro.rec, nil, "a first step into a mapped room abandons the route")
eq(elro.lastRec ~= nil and elro.lastRec.to == 2, false, "...and nothing is offered for undo")
elro.current = 1
elro.route_start("n,s")
out(1, "s")
eq(elro.rec, nil, "coming back to the start abandons the route")
eq(elro.smap["1:1"], nil, "...and records nothing")
elro.current = 1
SENT = {}
elro.route_start(string.rep("n,", elro.routeMax + 1))
eq(#SENT, 0, "a route longer than routeMax is refused before anything is sent")
eq(elro.rec, nil, "...and nothing is armed")

print(string.format("test_route: %d check(s), %d failure(s)", checks, fails))
os.exit(fails == 0 and 0 or 1)
