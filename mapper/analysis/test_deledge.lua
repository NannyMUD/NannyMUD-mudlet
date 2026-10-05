-- mapdeledge on a special exit: Mudlet removes one by its COMMAND, so a fake keyed
-- the same way catches a call that passes the destination id instead.
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

addRoom(31) ; addRoom(32) ; addRoom(1328)
setExit(32, 31, "down")
addSpecialExit(32, 1328, "syndicate")
elro.smap = {} ; elro.save_smap = function() end ; elro.flush_dirty = function() end

elro.delete_edge(32, 1328)
eq(elro.has_special(32, 1328), false, "the special exit is gone")
eq(getRoomExits(32).down, 31, "...and the compass exit is untouched")

print(string.format("test_deledge: %d check(s), %d failure(s)", checks, fails))
os.exit(fails == 0 and 0 or 1)
