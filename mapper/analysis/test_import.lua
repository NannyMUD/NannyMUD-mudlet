-- mapimport: another map is read by loading it for a moment and loading this one back, then
-- merged by onRoom's rules. Two maps built through onRoom overlap on room 3 and disagree there.
-- Run: luajit analysis/test_import.lua      (from the client dir)
dofile("analysis/engine_load.lua")

-- map user data kept per map, and saveMap/loadMap as files of the fake map
local function deep(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = deep(v) end return o end
local function mud() local m = harness_map() ; m.mud = m.mud or {} ; return m.mud end
getMapUserData = function(k) return mud()[k] or "" end
setMapUserData = function(k, v) mud()[k] = v end
getAllMapUserData = function() return deep(mud()) end
local FILES = {}
saveMap = function(p) if p then FILES[p] = deep(harness_map()) end return true end
loadMap = function(p) if not FILES[p] then return false end harness_set_map(deep(FILES[p])) return true end
getMudletHomeDir = function() return "/profiles/B" end

local fail, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    fail = fail + 1
    print(string.format("FAIL %-60s got %s want %s", what, tostring(got), tostring(want)))
  end
end

local function fresh()
  reset_map() ; elro.cs_reset()
  elro.smap, elro.merge, elro.declWait, elro.outerPick, elro.hints_loaded = nil, nil, nil, nil, nil
  elro.current = nil
end
local function walk(id, from, dir, exits, terr) elro.onRoom(id, from, dir, "hall " .. id, "town", exits, terr or "") end
elro.autoflush = false

-- map A: 1 -e- 2 -e- 3 -n- 4, a recorded "climb rope" from 4 to 1, a note, a mark, an avoid
fresh()
walk(1, 0, "none", "east")
walk(2, 1, "east", "east,west")
walk(3, 2, "east", "west,north")
walk(4, 3, "north", "south,east")
walk(8, 4, "east", "west", "forest")
elro.record_edge(4, 1, { "climb rope" })
elro.current = 2 ; elro.cmd_note("goblin, 3 gold")
elro.current = 3 ; elro.cmd_mark("well")
lockRoom(3, true)
setMapUserData("elro.merge", "harbour\ttown")
saveMap("A")

-- map B: 3 -e- 5, and 3's north walked to 6 (A says 4); "well" names 5 here; a note on 3
fresh()
walk(3, 0, "none", "west,north,east")
walk(5, 3, "east", "west")
walk(6, 3, "north", "south")
walk(9, 8, "north", "south")   -- room 8 known here only as where a move came from
elro.current = 5 ; elro.cmd_mark("well")
elro.current = 3 ; elro.cmd_note("a well here")
elro.current = 5

local snap, err = elro.import_read("missing")
eq(snap, nil, "a map that cannot be loaded: nothing read")
eq(roomExists(5) and not roomExists(1), true, "...and this map is still the one loaded")

snap = elro.import_read("A")
eq(snap ~= nil, true, "map A read")
eq(roomExists(5) and not roomExists(1), true, "this map is loaded back after reading")
eq(snap and snap.rooms[4] ~= nil, true, "the snapshot holds A's rooms")

local n = elro.import_merge(snap, true)
eq(roomExists(1), false, "a dry run changes nothing")
eq(n.rooms, 3, "dry run: rooms 1, 2 and 4 are new (8 is a placeholder here)")
eq(n.exits, 7, "dry run: 1e, 2e, 2w, 4s, 4e, 8w, and 3w where this map has only a stub")
eq(n.kept, 1, "dry run: 3's north stays this map's")
eq(n.specials, 1, "dry run: the climb")
eq(n.marks, 0, "dry run: 'well' is taken here")
eq(n.markClash, 1, "...and reported")
eq(n.notes, 1, "dry run: the goblin note")
eq(n.avoid, 1, "dry run: room 3 avoided")
eq(#n.mergeList == 1 and n.mergeList[1][1] == "harbour" and n.mergeList[1][2] == "town", true,
   "dry run: the area merge it would bring, by name")

local said = {}
local realCecho = cecho
cecho = function(s) said[#said + 1] = s end
elro.import_confirm(snap, "A")
cecho = realCecho
local undoPath = elro._importUndo and elro._importUndo.path
eq(undoPath ~= nil and undoPath:find("before%-import") ~= nil, true, "confirm saved a backup of its own name")
eq(table.concat(said):find("mapimport undo", 1, true) ~= nil, true, "...and says how to undo")
eq(getRoomExits(1).east, 2, "new room 1 with its exit")
eq(getRoomExits(2).west, 1, "new room 2's assumed reverse")
eq(getRoomUserData(2, "assumed_west"), "1", "...still marked assumed")
eq(getRoomExits(3).west, 2, "3's west filled in from A, over the stub")
eq(getRoomUserData(3, "assumed_west"), "1", "...as assumed, as A had it")
eq(getRoomExits(3).north, 6, "3's observed north stays this map's")
eq(getRoomUserData(3, "mut_north"), "", "...and two maps disagreeing is not a maze mutation")
eq(elro.merge.harbour, "town", "the other map's area merge, for an area this map had none for")
eq(getRoomExits(3).east, 5, "this map's own exit untouched")
eq(elro.smap["4:1"], "climb rope", "the recorded special exit")
eq(getRoomUserData(2, "note"), "goblin, 3 gold", "the note came along")
eq(getRoomUserData(3, "note"), "a well here", "this map's own note kept")
eq(elro.mark_find("well"), 5, "a mark name already used here stays where it was")
eq(roomLocked(3), true, "the avoid flag came along")
eq(getRoomName(4), "hall 4", "new rooms keep their names")
eq(getRoomName(8), "hall 8", "a room known here only as a placeholder takes the other map's name")
eq(getRoomUserData(8, "terr"), "forest", "...and its terrain")
eq(getRoomUserData(8, "xcomp") ~= "", true, "...and its advertised exits")

local again = elro.import_merge(snap, true)
eq(again.rooms + again.exits + again.notes + again.specials + again.avoid, 0, "importing the same map again adds nothing")

-- a plain save in the same second must not reach the backup undo loads
saveMap(getMudletHomeDir() .. "/map/" .. os.date("%Y-%m-%d#%H-%M-%S") .. "map.dat")
elro.import_undo()
eq(roomExists(1) or roomExists(2) or roomExists(4), false, "undo: the imported rooms are gone")
eq(getRoomExits(3).east == 5 and getRoomExits(3).north == 6, true, "undo: this map's exits as they were")
eq(getRoomUserData(3, "note"), "a well here", "undo: this map's note as it was")
eq(roomLocked(3), false, "undo: the imported avoid flag is gone")
eq(elro.smap == nil or elro.smap["4:1"] == nil, true, "undo: the caches were dropped with the map")
eq(elro._importUndo, nil, "undo is used up")
said = {}
cecho = function(s) said[#said + 1] = s end
elro.import_undo()
cecho = realCecho
eq(table.concat(said):find("nothing to undo", 1, true) ~= nil, true, "a second undo says there is nothing to undo")

print(string.format("test_import: %d check(s), %d failure(s)", checks, fail))
os.exit(fail > 0 and 1 or 0)
