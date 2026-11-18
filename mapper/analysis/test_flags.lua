-- mapflags: the name of the area a blue stub leads to, as a map label marked as ours; a sweep
-- removes every marked label (also ones an earlier session left in the map) and nothing else.
-- Run: luajit analysis/test_flags.lua      (from the client dir)
dofile("analysis/engine_load.lua")

local labels, nextId, sizes = {}, 0, {}       -- [area][id] = text; [id] = { w, h }
-- this fake Mudlet draws a label 12/zoom high and 7/zoom wide a character, as a profile might
createMapLabel = function(aid, text, x, y, z, r, g, b, br, bg, bb, zoom)
  nextId = nextId + 1
  labels[aid] = labels[aid] or {}
  labels[aid][nextId] = text
  sizes[nextId] = { (#text - 6) * 7 / zoom, 12 / zoom }
  return nextId
end
getMapLabel = function(aid, id) local s = sizes[id] return s and { Width = s[1], Height = s[2] } end
deleteMapLabel = function(aid, id) if labels[aid] then labels[aid][id] = nil end end
getMapLabels = function(aid) local t = {} for k, v in pairs(labels[aid] or {}) do t[k] = v end return t end
cecho = function() end

local fail, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    fail = fail + 1
    print(string.format("FAIL %-56s got %s want %s", what, tostring(got), tostring(want)))
  end
end
local function count(aid, ours)
  local n = 0
  for _, t in pairs(labels[aid] or {}) do
    if (t:sub(1, #elro.flags.MARK) == elro.flags.MARK) == ours then n = n + 1 end
  end
  return n
end

reset_map()
local town, forest = addAreaName("town"), addAreaName("forest")
addRoom(1) ; setRoomArea(1, town) ; setRoomCoordinates(1, 0, 0, 0)
addRoom(2) ; setRoomArea(2, town) ; setRoomCoordinates(2, 1, 0, 0)
addRoom(4) ; setRoomArea(4, forest) ; setRoomCoordinates(4, 0, 0, 0)
setExit(1, 2, "east") ; setExit(1, 4, "north")
elro.cs_reset()
labels[town] = { [900] = "the player's own label" }

elro.draw_area_stubs({ [1] = true })
eq(count(town, true), 0, "off by default: no flags")

elro.cmd_flags("on")
eq(count(town, true), 1, "on: one flag, for the one exit out of the area")
local text
for _, t in pairs(labels[town]) do if t:find("forest", 1, true) then text = t end end
eq(text, elro.flags.MARK .. "forest", "...naming the area it leads to, behind the marker")
local h
for id, t in pairs(labels[town]) do if t == text then h = sizes[id][2] end end
eq(math.abs(h - elro.flags.height) <= 0.15 * elro.flags.height, true,
   "read back and redrawn at the target height, whatever this Mudlet makes of the zoom")
elro.draw_area_stubs({ [1] = true })
elro.draw_area_stubs({ [1] = true })
eq(count(town, true), 1, "drawn again: still one flag, never piled up")

-- a flag an earlier session left in the map file is found by its marker
labels[town][901] = elro.flags.MARK .. "old"
elro.flags.redraw_all()
eq(count(town, true), 1, "a restart's sweep removes leftovers, then draws again")
eq(labels[town][901], nil, "...the leftover itself is gone")

elro.cmd_flags("off")
eq(count(town, true), 0, "off: every flag is gone")
eq(count(town, false), 1, "...and the player's own label stays")

print(string.format("test_flags: %d check(s), %d failure(s)", checks, fail))
os.exit(fail > 0 and 1 or 0)
