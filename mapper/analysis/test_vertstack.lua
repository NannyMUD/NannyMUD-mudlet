-- Stacked floors (elro.vertStack, `mapvert stack`): each floor on its own level, its stair
-- room directly over the room it leads from, sliding aside only for a floor on the same level.
--   luajit analysis/test_vertstack.lua

dofile("analysis/engine_load.lua")

local fail, ntest = 0, 0
local function eq(got, want, what)
  ntest = ntest + 1
  if got ~= want then
    fail = fail + 1
    print(string.format("  FAIL: %s -- got %s want %s", what, tostring(got), tostring(want)))
  end
end

local AID
local function room(id) addRoom(id) ; setRoomArea(id, AID) end
local function link(a, b, d) setExit(a, b, d) ; setExit(b, a, elro.reverse[d]) end
local function stair(a, b) setExit(a, b, "up") ; setExit(b, a, "down") end

-- components in local coordinates, as compose_spqr_adj hands them over
local function scene(specs)
  local comps, lcs, adj, compOf = {}, {}, {}, {}
  for ci, s in ipairs(specs) do
    comps[ci] = s.rooms ; lcs[ci] = {}
    for _, r in ipairs(s.rooms) do
      compOf[r] = ci ; lcs[ci][r] = { s.at[r][1], s.at[r][2] } ; adj[r] = {}
    end
  end
  for r in pairs(compOf) do
    for dn, dest in pairs(getRoomExits(r) or {}) do
      local d = elro.norm(dn)
      local de = elro.delta[d]
      if de and (de[1] ~= 0 or de[2] ~= 0) and compOf[dest] then adj[r][d] = dest end
    end
  end
  return comps, lcs, adj, compOf
end

local function at(G, r) return G.coord[r][1], G.coord[r][2], elro._vertZ[r] end

-- one stair: the upper floor one level up, its stair room straight over the other end
do
  reset_map() ; AID = addAreaName("one")
  room(1) ; room(2) ; link(1, 2, "east")
  room(10) ; room(11) ; link(10, 11, "east")
  stair(2, 10)
  elro.cs_reset()
  local comps, lcs, adj, compOf = scene({
    { rooms = { 1, 2 }, at = { [1] = { 0, 0 }, [2] = { 1, 0 } } },
    { rooms = { 10, 11 }, at = { [10] = { 0, 0 }, [11] = { 1, 0 } } },
  })
  local groups = elro.vert_stack(comps, lcs, adj, compOf)
  eq(#groups, 1, "one stair: one group")
  local G = groups[1]
  local x2, y2, z2 = at(G, 2)
  local x10, y10, z10 = at(G, 10)
  eq(z2, 0, "the lower floor on level 0")
  eq(z10, 1, "the upper floor one level up")
  eq(x10 == x2 and y10 == y2, true, "the stair room stands straight over the room below")
  eq(elro._vertStats.honoured, 1, "the stair counts as straight up")
end

-- down is the mirror: a cellar one level below
do
  reset_map() ; AID = addAreaName("cellar")
  room(1) ; room(2) ; link(1, 2, "north")
  room(20) ; room(21) ; link(20, 21, "west")
  stair(20, 1)                                  -- 1 down-> 20
  elro.cs_reset()
  local comps, lcs, adj, compOf = scene({
    { rooms = { 1, 2 }, at = { [1] = { 0, 0 }, [2] = { 0, 1 } } },
    { rooms = { 20, 21 }, at = { [20] = { 0, 0 }, [21] = { -1, 0 } } },
  })
  local G = elro.vert_stack(comps, lcs, adj, compOf)[1]
  local x1, y1 = at(G, 1)
  local x20, y20, z20 = at(G, 20)
  eq(z20, -1, "a cellar one level down")
  eq(x20 == x1 and y20 == y1, true, "...straight under its stair")
end

-- two upper floors from one hall, both wanting the same spot: the second slides aside
do
  reset_map() ; AID = addAreaName("two")
  room(1) ; room(2) ; room(3) ; link(1, 2, "east") ; link(2, 3, "east")
  room(10) ; room(11) ; link(10, 11, "east")
  room(20) ; room(21) ; link(20, 21, "east")
  stair(1, 10) ; stair(2, 20)
  elro.cs_reset()
  local comps, lcs, adj, compOf = scene({
    { rooms = { 1, 2, 3 }, at = { [1] = { 0, 0 }, [2] = { 1, 0 }, [3] = { 2, 0 } } },
    { rooms = { 10, 11 }, at = { [10] = { 0, 0 }, [11] = { 1, 0 } } },
    { rooms = { 20, 21 }, at = { [20] = { 0, 0 }, [21] = { 1, 0 } } },
  })
  local G = elro.vert_stack(comps, lcs, adj, compOf)[1]
  local seen, clash = {}, false
  for _, r in ipairs({ 10, 11, 20, 21 }) do
    local x, y, z = at(G, r)
    eq(z, 1, "both upper floors on level 1: " .. r)
    local k = x .. ":" .. y
    if seen[k] then clash = true end
    seen[k] = true
  end
  eq(clash, false, "no two rooms share a cell on one level")
  eq(elro._vertStats.honoured, 1, "one stair straight up")
  eq(elro._vertStats.declined, 1, "the other floor slid aside")
  local x1, y1 = at(G, 1)
  local x10, y10 = at(G, 10)
  eq(x10 == x1 and y10 == y1, true, "the first floor took its spot")
end

-- floors on different levels may share a cell: a three-storey tower
do
  reset_map() ; AID = addAreaName("tower")
  room(1) ; room(2) ; link(1, 2, "north")
  room(10) ; room(11) ; link(10, 11, "north")
  room(20) ; room(21) ; link(20, 21, "north")
  stair(1, 10) ; stair(10, 20)
  elro.cs_reset()
  local comps, lcs, adj, compOf = scene({
    { rooms = { 1, 2 }, at = { [1] = { 0, 0 }, [2] = { 0, 1 } } },
    { rooms = { 10, 11 }, at = { [10] = { 0, 0 }, [11] = { 0, 1 } } },
    { rooms = { 20, 21 }, at = { [20] = { 0, 0 }, [21] = { 0, 1 } } },
  })
  local G = elro.vert_stack(comps, lcs, adj, compOf)[1]
  local x1, y1, z1 = at(G, 1)
  local x20, y20, z20 = at(G, 20)
  eq(z20 - z1, 2, "the top floor two levels up")
  eq(x20 == x1 and y20 == y1, true, "the whole tower stands on one spot")
  eq(elro._vertStats.honoured, 2, "both stairs straight up")
end

-- no stairs: every floor alone on level 0
do
  reset_map() ; AID = addAreaName("flat")
  room(1) ; room(2) ; link(1, 2, "east")
  room(5)
  elro.cs_reset()
  local comps, lcs, adj, compOf = scene({
    { rooms = { 1, 2 }, at = { [1] = { 0, 0 }, [2] = { 1, 0 } } },
    { rooms = { 5 }, at = { [5] = { 0, 0 } } },
  })
  local groups = elro.vert_stack(comps, lcs, adj, compOf)
  eq(#groups, 2, "no stair: a group per floor")
  eq(elro._vertZ[1] == 0 and elro._vertZ[5] == 0, true, "all on level 0")
end

-- the cell index tells levels apart
do
  reset_map() ; AID = addAreaName("cells")
  room(1) ; room(2)
  setRoomCoordinates(1, 3, 4, 0) ; setRoomCoordinates(2, 3, 4, 1)
  elro.cs_reset() ; elro.cell_drop()
  eq(elro.cell_at(AID, 3, 4, 0), 1, "level 0 at (3,4)")
  eq(elro.cell_at(AID, 3, 4, 1), 2, "level 1 at (3,4) is another room")
  eq(elro.cell_at(AID, 3, 4), 1, "no level means level 0")
end

-- the flat pack (mapvert on) with a stair it cannot dock: the floor goes one level up over
-- its stair instead of off on its own (vertDeclineStack, on by default)
do
  reset_map() ; AID = addAreaName("slab")
  local wall, pos, byxy, id = {}, {}, {}, 100
  for x = -4, 4 do
    for y = -4, 4 do
      id = id + 1 ; room(id) ; wall[#wall + 1] = id ; pos[id] = { x, y } ; byxy[x .. ":" .. y] = id
    end
  end
  for _, r in ipairs(wall) do
    local p = pos[r]
    local e, n = byxy[(p[1] + 1) .. ":" .. p[2]], byxy[p[1] .. ":" .. (p[2] + 1)]
    if e then link(r, e, "east") end
    if n then link(r, n, "north") end
  end
  local mid = byxy["0:0"]
  room(9001) ; room(9002) ; link(9001, 9002, "east")
  stair(mid, 9001)
  elro.cs_reset()
  local comps, lcs, adj, compOf = scene({
    { rooms = wall, at = pos },
    { rooms = { 9001, 9002 }, at = { [9001] = { 0, 0 }, [9002] = { 1, 0 } } },
  })
  elro.vertDeclineStack = nil
  local groups = elro.vert_assemble(comps, lcs, adj, compOf)
  eq(#groups, 1, "declined, but kept with its stair: one group")
  eq(elro._vertStats.stacked, 1, "stacked instead of declined")
  local G = groups[1]
  local mx, my, mz = at(G, mid)
  local fx, fy, fz = at(G, 9001)
  eq(mz, 0, "the slab on level 0")
  eq(fz, 1, "the floor one level up")
  eq(fx == mx and fy == my, true, "...straight over its stair")
  -- and with the fallback off, as before: its own group on level 0
  elro.vertDeclineStack = false
  groups = elro.vert_assemble(comps, lcs, adj, compOf)
  eq(#groups == 2 and elro._vertZ[9001] == 0, true, "fallback off: its own group, level 0")
  elro.vertDeclineStack = nil
end

-- stitching: off unless chosen, and a choice is kept
do
  local cfg, ud = { mapStitchAreas = true }, {}
  setConfig = function(k, v) cfg[k] = v end
  getConfig = function(k) return cfg[k] end
  getMapUserData = function(k) return ud[k] or "" end
  setMapUserData = function(k, v) ud[k] = v end
  saveMap = function() end
  local real_cecho = cecho
  cecho = function() end
  elro.mudlet_prefs_boot()
  eq(cfg.mapStitchAreas, false, "stitching off by default")
  elro.cmd_stitch("on")
  eq(cfg.mapStitchAreas == true and ud["elro.stitch"] == "on", true, "'mapstitch on' turns it on and records it")
  elro.mudlet_prefs_boot()
  eq(cfg.mapStitchAreas, true, "a chosen 'on' survives the next start")
  elro.cmd_stitch("off")
  eq(cfg.mapStitchAreas == false and ud["elro.stitch"] == "off", true, "'mapstitch off'")
  -- the rings of the levels above and below: the same, through 'maplevels'
  eq(cfg.showUpperLowerLevels, false, "the other levels' rings off by default")
  elro.cmd_levels("on")
  eq(cfg.showUpperLowerLevels == true and ud["elro.levels"] == "on", true, "'maplevels on'")
  elro.mudlet_prefs_boot()
  eq(cfg.showUpperLowerLevels, true, "a chosen 'on' survives the next start")
  cecho = real_cecho
end

-- a room on another level under a stretched edge is not buried: no yellow mark
do
  reset_map() ; AID = addAreaName("buried")
  room(1) ; room(2) ; link(1, 2, "east")
  room(3) ; room(4)
  setRoomCoordinates(1, 0, 0, 0) ; setRoomCoordinates(2, 3, 0, 0)
  setRoomCoordinates(3, 1, 0, 1) ; setRoomCoordinates(4, 2, 0, 0)
  local coord = { [1] = { 0, 0 }, [2] = { 3, 0 }, [3] = { 1, 0 }, [4] = { 2, 0 } }
  elro.draw_residual(coord)
  eq(getRoomUserData(3, "occl") ~= "1", true, "a room one level up is not under the edge")
  eq(getRoomUserData(4, "occl"), "1", "a room on the edge's own level is")
end

print(string.format("test_vertstack: %d check(s), %d failure(s)", ntest, fail))
os.exit(fail == 0 and 0 or 1)
