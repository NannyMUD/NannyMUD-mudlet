-- A spell gate is no exit: "enter gate" out of a room where the game showed a gate is a jump.
-- Run: luajit analysis/test_gate.lua      (from the client dir)
dofile("analysis/engine_load.lua")

local fail, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    fail = fail + 1
    print(string.format("FAIL %-56s got %s want %s", what, tostring(got), tostring(want)))
  end
end

local said = {}
cecho = function(s) said[#said + 1] = s end
elro.flush_dirty = function() end
elro.flush = function() end
elro.bg_busy = function() return false end

reset_map()
elro.cs_reset()
elro.smap = {}
elro.rec = nil

local function arrive(id, from, cmd)
  elro.onRoom(id, from, cmd, "room " .. id, "town", "north,south", "")
end
local function special(a, b) return elro.smap[a .. ":" .. b] ~= nil end

arrive(1, 0, "none")
eq(elro.current, 1, "(start in room 1)")

elro.gate_seen()
said = {}
arrive(2, 1, "enter gate")
eq(special(1, 2), false, "through a gate seen here: no exit recorded")
eq(getRoomUserData(2, "via"), elro.VIA_NONE, "...and the room is placed as after a login")
eq(table.concat(said):find("spell gate", 1, true) ~= nil, true, "...and it says so")

arrive(1, 2, "enter gate")
eq(special(2, 1), true, "no gate seen on this visit: 'enter gate' is an exit like any other")

elro.gate_seen()
arrive(3, 1, "north")
eq(getRoomExits(1).north, 3, "a compass move from a gate room is still an exit")
arrive(1, 3, "south")
arrive(4, 1, "enter gate")
eq(special(1, 4), true, "...and the gate mark went with that move")

elro.current = 1
elro.gate_seen()
arrive(5, 1, "enter hut")
eq(special(1, 5), true, "only 'enter gate' is blocked, not other commands")

elro.current = 1
elro.gate_seen()
arrive(6, 1, "enter perfect gateway")
eq(special(1, 6), false, "'enter <kind> gateway' is a gate too")

-- kept by hand: an armed maprecordmove, or an edge already recorded
elro.current = 1
elro.gate_seen()
local finished
local real_finish = elro.rec_finish
elro.rec = { from = 1 }
elro.rec_finish = function(id) finished = id ; elro.rec = nil end
arrive(7, 1, "enter gate")
elro.rec_finish = real_finish
eq(finished, 7, "an armed maprecordmove still records the gate")

elro.smap["1:8"] = "enter gate"
elro.current = 1
elro.gate_seen()
said = {}
arrive(8, 1, "enter gate")
eq(table.concat(said):find("spell gate", 1, true), nil, "a gate edge recorded by hand is walked as usual")
eq(getRoomUserData(8, "via") ~= elro.VIA_NONE, true, "...from the room it left")

eq(elro.is_gate_cmd("Enter  Gate"), true, "case and spacing do not matter")
eq(elro.is_gate_cmd("enter gatehouse"), false, "a gatehouse is not a gate")
eq(elro.is_gate_cmd("gate"), false, "nor is a bare word")

print(string.format("test_gate: %d check(s), %d failure(s)", checks, fail))
os.exit(fail == 0 and 0 or 1)
