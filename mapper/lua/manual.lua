-- mapmanual: map a maze the game does not map, from what each room shows: its first line and its
-- exit list. Every step walked is kept, and the map is worked out from all of them, so two rooms
-- that look alike are told apart by where their exits lead. Exits are taken never to change.

elro.manual = elro.manual or {}
local M = elro.manual
M.data = M.data or {}                       -- area name -> its walk (see `load`)
M.q = M.q or {}
M.res = M.res or {}

elro.MANUAL_BASE, elro.MANUAL_MAX = 880000, 889999

local WORDS = {
  -- a whole line that means the move went nowhere
  wall = { ["You cannot go that way."] = true, ["You walk into a wall."] = true },
  exits = "obvious exit",                   -- the line that lists a room's exits
  -- lines that can come before a room and are never its name: sound codes, the status line
  noise = { "^!!", "^%*%*" },
}

local function noise(s)
  for _, p in ipairs(WORDS.noise) do if s:find(p) then return true end end
  return false
end
-- a way seen to lead the same place this many times is a fact: a different result is a change
local SURE = 3
local WALL = 0                              -- an edge target: the move went nowhere

local function say(s) cecho("\n<cyan>[elro]: " .. s .. "<reset>\n") end
local function echo(s) cecho("\n<grey>[manual] " .. s .. "<reset>\n") end
-- 'mapmanual trace': what each move, room and prompt was taken as; raw text, so no cecho
local function tr(fmt, ...)
  if not M.trace then return end
  local ok, s = pcall(string.format, fmt, ...)
  if type(cecho) == "function" then cecho("\n<dark_orange>[trace]<reset> ") end
  if type(_G.echo) == "function" then _G.echo((ok and s or fmt) .. "\n") end
end
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- ---- reading a room ----

local function exit_list(s)
  local out = {}
  s = s:gsub("%.%s*$", ""):gsub("%s+and%s+", ", ")
  for w in s:gmatch("[^,]+") do
    w = trim(w):lower()
    if w ~= "" then out[#out + 1] = w end
  end
  table.sort(out)
  return out
end

-- the room's key: its first line and its exits, in a fixed order
function M.key(name, exits) return name .. "\t" .. table.concat(exit_list(exits), ",") end
local function key_name(k) return k:match("^(.-)\t") or k end
local function key_exits(k)
  local out = {}
  for w in (k:match("\t(.*)$") or ""):gmatch("[^,]+") do out[#out + 1] = w end
  return out
end

-- ---- the walk, kept as map user data ----
-- D.nodes[g] is the g-th room seen: k = key index, d = the way walked on to node g+1,
-- w = ways that went nowhere, s = a fresh start (not reached from g-1), id = its map room.

local function areas()
  if M.areas then return M.areas end
  M.areas = {}
  local ok, s = pcall(getMapUserData, "elro.manual")
  if ok and type(s) == "string" then
    for name in s:gmatch("[^\n]+") do M.areas[#M.areas + 1] = name end
  end
  return M.areas
end

local function save_areas()
  pcall(setMapUserData, "elro.manual", table.concat(areas(), "\n"))
end

-- Drop the seen rooms in `gone` from the walk: the step into each and out of each goes too.
local function drop(D, gone)
  local keep, map = {}, {}
  for g, n in ipairs(D.nodes) do
    if gone[g] then
      local p = keep[#keep]
      if p and not n.s and map[g - 1] then p.d = nil end
      local nx = D.nodes[g + 1]
      if nx then nx.s = true end
    else
      keep[#keep + 1] = n ; map[g] = #keep
    end
  end
  D.nodes = keep
  if M.last and D == M.data[M.learn or ""] then M.last = map[M.last] end
  -- a pair declared the same follows its sightings, and goes with them
  local same = {}
  for _, p in ipairs(D.same or {}) do
    if map[p[1]] and map[p[2]] then same[#same + 1] = { map[p[1]], map[p[2]] } end
  end
  D.same = same
  -- so do the gates
  for _, list in ipairs({ "gin", "gout" }) do
    local keep = {}
    for _, gt in ipairs(D[list] or {}) do
      if map[gt.node] then gt.node = map[gt.node] ; keep[#keep + 1] = gt end
    end
    D[list] = keep
  end
  D.S = nil
end

local function load(area)
  local D = M.data[area]
  -- a walk loaded before an update may lack what the new code keeps
  if D then D.same, D.gin, D.gout = D.same or {}, D.gin or {}, D.gout or {} return D end
  D = { area = area, keys = {}, kidx = {}, nodes = {}, same = {}, gin = {}, gout = {} }
  local ok, s = pcall(getMapUserData, "elro.manual:" .. area)
  if ok and type(s) == "string" then
    for line in s:gmatch("[^\n]+") do
      local k = line:match("^K\t(.*)$")
      local sa, sb = line:match("^S\t(%d+)\t(%d+)$")
      local ia, id_, ib = line:match("^I\t(%d+)\t([^\t]+)\t(%d+)$")
      local oa, od, ob = line:match("^O\t(%d+)\t([^\t]+)\t(%d+)$")
      if k then
        D.keys[#D.keys + 1] = k ; D.kidx[k] = #D.keys
      elseif sa then
        D.same[#D.same + 1] = { tonumber(sa), tonumber(sb) }
      elseif ia then
        D.gin[#D.gin + 1] = { from = tonumber(ia), d = id_, node = tonumber(ib) }
      elseif oa then
        D.gout[#D.gout + 1] = { node = tonumber(oa), d = od, to = tonumber(ob) }
      else
        local ki, d, w, id, st = line:match("^N\t(%d+)\t(%S+)\t(%S+)\t(%S+)\t(%S+)$")
        if ki then
          local n = { k = tonumber(ki) }
          if d ~= "-" then n.d = d end
          if w ~= "-" then n.w = {} ; for x in w:gmatch("[^,]+") do n.w[x] = true end end
          if id ~= "-" then n.id = tonumber(id) end
          if st == "s" then n.s = true end
          D.nodes[#D.nodes + 1] = n
        end
      end
    end
  end
  -- a noise line read as a room's first line hides the real one
  local bad = {}
  for g, n in ipairs(D.nodes) do
    if noise(D.keys[n.k] or "") then bad[g] = true end
  end
  if next(bad) then drop(D, bad) end
  M.data[area] = D
  return D
end

local function save(D)
  local L = {}
  for _, k in ipairs(D.keys) do L[#L + 1] = "K\t" .. k end
  for _, n in ipairs(D.nodes) do
    local w = {}
    for x in pairs(n.w or {}) do w[#w + 1] = x end
    table.sort(w)
    L[#L + 1] = string.format("N\t%d\t%s\t%s\t%s\t%s", n.k, n.d or "-",
      #w > 0 and table.concat(w, ",") or "-", n.id and tostring(n.id) or "-", n.s and "s" or "-")
  end
  for _, p in ipairs(D.same or {}) do L[#L + 1] = "S\t" .. p[1] .. "\t" .. p[2] end
  for _, gt in ipairs(D.gin or {}) do L[#L + 1] = "I\t" .. gt.from .. "\t" .. gt.d .. "\t" .. gt.node end
  for _, gt in ipairs(D.gout or {}) do L[#L + 1] = "O\t" .. gt.node .. "\t" .. gt.d .. "\t" .. gt.to end
  pcall(setMapUserData, "elro.manual:" .. D.area, table.concat(L, "\n"))
end

-- ---- working out the map ----
-- Each room seen joins a room found so far with its key that it can be the same as: every way
-- walked from both agrees, as far as the walk followed them, and the walk does not place them
-- apart. The maze is taken to be a grid: a compass, up/down or prefixed step (meta-north) is a
-- fixed move, so a walked path with a net move between two sightings proves them two rooms.
-- Of the rooms a sighting can join, the one whose ways agree most is taken. A room that can
-- join none is a room of its own. A pair the player declared the same (`mapmanual same`) joins
-- regardless of the grid: an exit between them breaks it.

local AXIS = { north = { "y", 1 }, south = { "y", -1 }, east = { "x", 1 }, west = { "x", -1 },
               up = { "z", 1 }, down = { "z", -1 } }
local DIAG = { northeast = { "north", "east" }, northwest = { "north", "west" },
               southeast = { "south", "east" }, southwest = { "south", "west" } }

-- the move a step makes, as { axis = steps }, or nil for a way with no direction (enter)
function M.delta(d)
  local pre, base = d:match("^(.-%-)(%a+)$")
  if not base then pre, base = "", d end
  local v = {}
  for _, b in ipairs(DIAG[base] or { base }) do
    local a = AXIS[b]
    if not a then return nil end
    v[pre .. a[1]] = (v[pre .. a[1]] or 0) + a[2]
  end
  return v
end

local function vadd(a, b, sign)
  local v = {}
  for k, n in pairs(a) do v[k] = n end
  for k, n in pairs(b) do v[k] = (v[k] or 0) + sign * n end
  return v
end
local function vzero(a) for _, n in pairs(a) do if n ~= 0 then return false end end return true end

function M.solve(D)
  local N = #D.nodes
  local par, key, E = {}, {}, {}
  local gpar, goff = {}, {}                  -- the grid: each sighting's place, relative to a root
  -- a step through an exit its room does not list was paired with the wrong command
  local listed = {}
  for i, k in ipairs(D.keys) do
    listed[i] = {}
    for _, x in ipairs(key_exits(k)) do listed[i][x] = true end
  end
  for g = 1, N do
    local n = D.nodes[g]
    par[g], key[g] = g, n.k
    gpar[g], goff[g] = g, {}
    local e = {}
    for x in pairs(n.w or {}) do if not listed[n.k][x] then e[x] = WALL end end
    if n.d and listed[n.k][n.d] and D.nodes[g + 1] and not D.nodes[g + 1].s then e[n.d] = g + 1 end
    E[g] = e
  end
  -- a way out to a mapped room: a fixed target, its room id negated (rooms seen are 1..N)
  for _, gt in ipairs(D.gout or {}) do
    if E[gt.node] and listed[key[gt.node]][gt.d] then E[gt.node][gt.d] = -gt.to end
  end
  local function find(x) while par[x] ~= x do x = par[x] end return x end
  local log = {}
  local function set(t, k, v) log[#log + 1] = { t, k, t[k] } ; t[k] = v end
  local function undo(mark)
    for i = #log, mark + 1, -1 do local u = log[i] ; u[1][u[2]] = u[3] ; log[i] = nil end
    return false
  end
  -- a sighting's grid root and its place relative to it
  local function gfind(x)
    local off = {}
    while gpar[x] ~= x do off = vadd(off, goff[x], 1) ; x = gpar[x] end
    return x, off
  end
  -- place b at a's place moved by v; false when the grid already says otherwise
  local function gunion(a, b, v)
    local ra, oa = gfind(a)
    local rb, ob = gfind(b)
    local want = vadd(oa, v, 1)
    if ra == rb then return vzero(vadd(want, ob, -1)) end
    set(gpar, rb, ra) ; set(goff, rb, vadd(want, ob, -1))
    return true
  end
  -- the walk itself: each step a fixed move, so one walk never contradicts itself. A step into
  -- a room with no way back (a dive, a fall) is no move: such exits bend.
  for g = 1, N do
    local d = D.nodes[g].d or ""
    local t = E[g] and E[g][d]
    local v = t and t > 0 and listed[key[t]][M.reverse(d) or ""] and M.delta(d)
    if v then gunion(g, t, v) end
  end
  local function place(o)
    local p = {}
    for ax, n in pairs(o) do if n ~= 0 then p[#p + 1] = ax .. "=" .. n end end
    table.sort(p)
    return table.concat(p, ",")
  end
  -- Two pieces of grid about to be joined with x and y at one place: one place is one room, so
  -- look-alikes both have at another place are one room too. Returns those pairs. A place
  -- where they look different is passed over: a misread line or a bent way can cause it.
  local function overlap(x, y)
    local rx, ox = gfind(x)
    local ry, oy = gfind(y)
    local shift = vadd(ox, oy, -1)
    local at, pairs_ = {}, {}
    for g = 1, N do
      local r, o = gfind(g)
      if r == rx then
        local p = place(o)
        at[p] = at[p] or g
      end
    end
    for g = 1, N do
      local r, o = gfind(g)
      if r == ry then
        local a = at[place(vadd(o, shift, 1))]
        if a and find(a) ~= find(g) and key[a] == key[g] then pairs_[#pairs_ + 1] = { a, g } end
      end
    end
    return pairs_
  end
  -- Join a and b and everything that forces. Returns whether it holds, how many ways agreed,
  -- and how many of those are anchors: a wall or a mapped room both lead to, or another place
  -- where two pieces of grid joined here overlap. The log keeps the change until the caller
  -- commits or undoes it from `mark`. `free`: the player said so, the grid is not asked.
  local function merge(a, b, free)
    local mark, score, anchor = #log, 0, 0
    local work = { a, b }
    while #work > 0 do
      local y = table.remove(work) ; local x = table.remove(work)
      x, y = find(x), find(y)
      if x ~= y then
        if key[x] ~= key[y] then return undo(mark), 0, 0 end
        if not free then
          if gfind(x) ~= gfind(y) then
            for _, p in ipairs(overlap(x, y)) do
              if not (find(p[1]) == x and find(p[2]) == y) then
                work[#work + 1] = p[1] ; work[#work + 1] = p[2] ; anchor = anchor + 1
              end
            end
          end
          if not gunion(x, y, {}) then return undo(mark), 0, 0 end
        end
        if y < x then x, y = y, x end
        set(par, y, x)
        for d, t in pairs(E[y]) do
          local s = E[x][d]
          if s == nil then set(E[x], d, t)
          elseif s <= 0 or t <= 0 then                -- a wall or a mapped room: must be the same
            if s ~= t then return undo(mark), 0, 0 end
            score, anchor = score + 1, anchor + 1
          else work[#work + 1] = s ; work[#work + 1] = t ; score = score + 1 end
        end
      end
    end
    return true, score, anchor
  end
  local function commit() for i = #log, 1, -1 do log[i] = nil end end
  -- the sightings the player declared one room, as groups
  local spar = {}
  local function sroot(x) while spar[x] and spar[x] ~= x do x = spar[x] end return x end
  for _, p in ipairs(D.same or {}) do
    local a, b = sroot(p[1]), sroot(p[2])
    if a ~= b then spar[b] = a end
  end
  local reds, byKey = {}, {}
  for g = 1, N do
    if find(g) == g then
      -- every room it could be, tried and undone; the best agreeing one, the earliest of equals.
      -- A look-alike in another piece of grid (a fresh start) is placed by nothing: it joins
      -- only on an anchor. A room only one room looks like joins on its looks.
      local best, bestAnchor, bestScore
      local cands = byKey[key[g]] or {}
      local looks = {}                            -- rooms declared one ('same') count once
      for _, r in ipairs(cands) do looks[sroot(r)] = true end
      local alike = 0
      for _ in pairs(looks) do alike = alike + 1 end
      for _, r in ipairs(cands) do
        local apart = gfind(r) ~= gfind(g)
        local mark = #log
        local ok, sc, an = merge(r, g)
        if ok then
          undo(mark)
          if not (apart and alike > 1 and an == 0)
             and (not best or an > bestAnchor or (an == bestAnchor and sc > bestScore)) then
            best, bestAnchor, bestScore = r, an, sc
          end
        end
      end
      if best then
        merge(best, g) ; commit()
      else
        reds[#reds + 1] = g
        byKey[key[g]] = byKey[key[g]] or {}
        table.insert(byKey[key[g]], g)
      end
    end
  end
  -- rooms entered from one mapped room by one way are one room
  local entered = {}
  for _, gt in ipairs(D.gin or {}) do
    if gt.node <= N then
      local k = gt.from .. "\t" .. gt.d
      if entered[k] then
        if find(entered[k]) ~= find(gt.node) and merge(entered[k], gt.node) then commit() end
      else
        entered[k] = gt.node
      end
    end
  end
  -- pairs the player declared one room: joined past the grid, or refused when their ways differ
  local refused = {}
  for _, p in ipairs(D.same or {}) do
    if p[1] <= N and p[2] <= N and find(p[1]) ~= find(p[2]) then
      if merge(p[1], p[2], true) then commit() else refused[#refused + 1] = p end
    end
  end
  local keep = {}
  for _, r in ipairs(reds) do if find(r) == r then keep[#keep + 1] = r end end
  reds = keep
  for k, list in pairs(byKey) do
    local keep = {}
    for _, r in ipairs(list) do if find(r) == r then keep[#keep + 1] = r end end
    byKey[k] = keep
  end
  -- a class's way: WALL, a mapped room (negated), or the class it leads to
  local function way(r, d)
    local t = E[r][d]
    if t == nil or t <= 0 then return t end
    return find(t)
  end
  -- two-way: a walked way back is assumed where the room lists it and nothing is known there.
  -- Assumed ways never merge or split rooms; two walks that claim one way back cancel it.
  local A = {}
  if M.twoway_on() then
    local claim = {}
    for _, r in ipairs(reds) do
      for d, t in pairs(E[r]) do
        local rv = t > 0 and M.reverse(d)
        local c = rv and find(t)
        if c and listed[key[c]][rv] and E[c][rv] == nil then
          local k = c .. "\t" .. rv
          if claim[k] == nil then claim[k] = r elseif claim[k] ~= r then claim[k] = false end
        end
      end
    end
    for k, r in pairs(claim) do
      if r then
        local c, rv = k:match("^(%d+)\t(.+)$")
        c = tonumber(c)
        A[c] = A[c] or {}
        A[c][rv] = r
      end
    end
  end
  -- a way walked, or assumed
  local function way2(r, d)
    local t = way(r, d)
    if t ~= nil then return t end
    return A[r] and A[r][d]
  end
  return { reds = reds, find = find, E = E, A = A, way = way, way2 = way2, byKey = byKey,
           refused = refused, place = function(g) return gfind(g) end }
end

-- the way back: the opposite compass word, and the same for a prefixed one (meta-north)
function M.reverse(d)
  if elro.reverse[d] then return elro.reverse[d] end
  local pre, base = d:match("^(.-%-)(%a+)$")
  if pre and elro.reverse[base] then return pre .. elro.reverse[base] end
  return nil
end

function M.twoway_on()
  if M.twoway == nil then
    local ok, s = pcall(getMapUserData, "elro.manual.twoway")
    M.twoway = ok and s == "on"
  end
  return M.twoway
end

-- how often the walk tried way `d` from class `c`
local function support(D, S, c, d)
  local n = 0
  for g, node in ipairs(D.nodes) do
    if S.find(g) == c and (node.d == d or (node.w and node.w[d])) then n = n + 1 end
  end
  return n
end

-- ---- the map ----

local function free_near(x, y, z, taken)
  if not taken[x .. "," .. y .. "," .. z] then return x, y end
  for r = 1, 50 do
    for dx = -r, r do
      for dy = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r and not taken[(x + dx) .. "," .. (y + dy) .. "," .. z] then
          return x + dx, y + dy
        end
      end
    end
  end
  return x, y
end

local function new_id(used)
  for id = elro.MANUAL_BASE, elro.MANUAL_MAX do
    if not used[id] and not roomExists(id) then return id end
  end
  return nil
end

-- Each class keeps the map room of its earliest seen room that had one; a class with none gets
-- a new one. A room no class keeps is deleted.
local function assign(D, S)
  local members = {}
  for g in ipairs(D.nodes) do
    local r = S.find(g)
    members[r] = members[r] or {}
    table.insert(members[r], g)
  end
  local idOf, used = {}, {}
  for _, r in ipairs(S.reds) do
    for _, g in ipairs(members[r]) do
      local id = D.nodes[g].id
      if id and not used[id] and roomExists(id) then idOf[r] = id ; used[id] = true ; break end
    end
  end
  for _, r in ipairs(S.reds) do
    if not idOf[r] then
      local id = new_id(used)
      if not id then return nil end
      idOf[r] = id ; used[id] = true
    end
  end
  for g, n in ipairs(D.nodes) do n.id = (S.find(g) == g) and idOf[g] or nil end
  S.id = idOf
  S.members = members
  return idOf
end

local function is_ours(id, area)
  return roomExists(id) and getRoomUserData(id, "manual") == area
end

-- Rooms, exits and command records to match the classes. Returns whether the graph changed.
local function sync(D, S)
  local aid = elro.areaId(D.area)
  local front = elro.frontier_room and elro.frontier_room()
  if elro.smap == nil then elro.load_smap() end
  local changed, smapChanged = false, false
  local taken = {}
  for _, id in pairs(getAreaRooms(aid) or {}) do
    local x, y, z = getRoomCoordinates(id)
    taken[x .. "," .. y .. "," .. z] = true
  end
  local keep = {}
  for _, r in ipairs(S.reds) do keep[S.id[r]] = true end
  -- new rooms first, each beside the room it was first walked to from
  for _, r in ipairs(S.reds) do
    local id = S.id[r]
    if not roomExists(id) then
      local x, y, z = 0, 0, 0
      for _, g in ipairs(S.members[r]) do
        local p = D.nodes[g - 1]
        local del = p and not D.nodes[g].s and p.d and elro.delta[p.d]
        local pid = del and S.id[S.find(g - 1)]
        if pid and roomExists(pid) then
          local px, py, pz = getRoomCoordinates(pid)
          x, y, z = px + del[1], py + del[2], pz + del[3]
          break
        end
      end
      x, y = free_near(x, y, z, taken)
      taken[x .. "," .. y .. "," .. z] = true
      addRoom(id)
      setRoomArea(id, aid)
      setRoomCoordinates(id, x, y, z)
      setRoomName(id, key_name(D.keys[D.nodes[r].k]))
      setRoomUserData(id, "manual", D.area)
      setRoomUserData(id, "sarea", D.area)
      setRoomUserData(id, "adopt", D.area)
      setRoomUserData(id, "via", elro.VIA_NONE)
      elro.cs_lists_dirty() ; elro.cs_dirty(id, aid)
      changed = true
    end
  end
  -- exits
  for _, r in ipairs(S.reds) do
    local id = S.id[r]
    local want, wantS = {}, {}
    local ways = {}
    for d in pairs(S.E[r]) do ways[d] = true end
    for d in pairs(S.A[r] or {}) do ways[d] = true end
    for d in pairs(ways) do
      local t = S.way2(r, d)
      local to = t and (t > 0 and S.id[t] or t < 0 and roomExists(-t) and -t) or nil
      if to then
        if elro.dirNum[d] then want[d] = to else wantS[d] = to end
      end
    end
    local named = {}
    for _, d in ipairs(key_exits(D.keys[D.nodes[r].k])) do
      if front and elro.dirNum[d] and S.way2(r, d) == nil then want[d] = front end
      if not elro.dirNum[d] then named[#named + 1] = d end
    end
    -- the room's own non-compass exits, where the glyph looks for them
    local xspec = table.concat(named, ",")
    if getRoomUserData(id, "xspec") ~= xspec then setRoomUserData(id, "xspec", xspec) end
    for name, to in pairs(getRoomExits(id) or {}) do
      local d = elro.norm(name)
      if want[d] ~= to then
        setExit(id, -1, d)
        if to ~= front and want[d] ~= front then changed = true end
      end
    end
    local have = getRoomExits(id) or {}
    for d, to in pairs(want) do
      if have[d] ~= to then
        setExit(id, to, d)
        if to ~= front then changed = true end
      end
    end
    for _, e in ipairs(elro.special_list(id)) do
      if wantS[e.cmd] ~= e.to then pcall(removeSpecialExit, id, e.cmd) ; changed = true end
    end
    for k in pairs(elro.smap) do
      local a, b = k:match("^(%d+):(%d+)$")
      if tonumber(a) == id and wantS[elro.smap[k]] ~= tonumber(b) then elro.smap[k] = nil ; smapChanged = true end
    end
    for cmd, to in pairs(wantS) do
      if elro.smap[id .. ":" .. to] ~= cmd then
        elro.smap[id .. ":" .. to] = cmd ; smapChanged = true
        pcall(addSpecialExit, id, to, cmd)
        changed = true
      end
    end
    elro.cs_dirty(id, aid)
  end
  -- the way in from a mapped room, into a slot that is empty, unexplored, off the map or ours
  for _, gt in ipairs(D.gin or {}) do
    local id, from = S.id[S.find(gt.node)], gt.from
    if id and roomExists(from) and not is_ours(from, D.area) then
      if elro.dirNum[gt.d] then
        local cur = (getRoomExits(from) or {})[gt.d]
        if cur ~= id and not (cur == nil or cur == front or cur == elro.OFF_ROOM or is_ours(cur, D.area)) then
          tr("way in from %d by %s not written: the map has it leading to %s", from, gt.d, tostring(cur))
        end
        if cur ~= id and (cur == nil or cur == front or cur == elro.OFF_ROOM or is_ours(cur, D.area)) then
          tr("way in: %d %s now leads to %d", from, gt.d, id)
          setExit(from, id, gt.d)
          if elro.stub_apply then elro.stub_apply(from) end
          elro.cs_dirty(from, getRoomArea(from))
          changed = true
        end
      else
        local had
        for k, cmd in pairs(elro.smap) do
          local a, b = k:match("^(%d+):(%d+)$")
          if tonumber(a) == from and cmd == gt.d then
            if tonumber(b) == id then had = true
            elseif is_ours(tonumber(b), D.area) then
              pcall(removeSpecialExit, from, cmd) ; elro.smap[k] = nil ; smapChanged = true
            else had = true end                     -- a real special exit of the map's own wins
          end
        end
        if not had then
          elro.smap[from .. ":" .. id] = gt.d ; smapChanged = true
          pcall(addSpecialExit, from, id, gt.d)
          elro.cs_dirty(from, getRoomArea(from))
          changed = true
        end
      end
    end
  end
  -- rooms no class keeps
  for _, id in pairs(getAreaRooms(aid) or {}) do
    if not keep[id] and is_ours(id, D.area) then
      for k in pairs(elro.smap) do
        local a, b = k:match("^(%d+):(%d+)$")
        if tonumber(a) == id or tonumber(b) == id then elro.smap[k] = nil ; smapChanged = true end
      end
      local cl = type(getCustomLines) == "function" and getCustomLines(id)
      if type(cl) == "table" then for dir in pairs(cl) do pcall(removeCustomLine, id, dir) end end
      deleteRoom(id)
      elro.cs_lists_dirty()
      changed = true
    end
  end
  if smapChanged then elro.smap_index_dirty() ; elro.save_smap() end
  for _, r in ipairs(S.reds) do elro.glyph_room(S.id[r]) end
  if changed then elro.dirty[aid] = true end
  return changed
end

-- Work the map out again and bring the map rooms in line. Returns the solution.
local function rebuild(D)
  local S = M.solve(D)
  if not assign(D, S) then say("no room numbers left for this area; 'mapmanual wipe' one.") return nil end
  save(D)
  local changed = sync(D, S)
  D.S = S
  if changed and elro.flush_dirty then elro.flush_dirty() end
  if type(updateMap) == "function" then updateMap() end
  return S
end

local function solution(D)
  if not D.S then
    D.S = M.solve(D)
    assign(D, D.S)
  end
  return D.S
end

-- ---- where you are ----

local function show(id)
  M.view = id
  elro.recenter()
end

-- the room the view follows while off the map, or nil
function M.view_room()
  local id = M.view
  if id and elro.offmap and roomExists(id) then return id end
  return nil
end

-- the maze being learned, kept in the map so a restart or an update does not end it
local function set_learn(name)
  M.learn = name
  if type(setMapUserData) == "function" then pcall(setMapUserData, "elro.manual.learn", name or "") end
end

local function lost()
  M.last, M.belief, M.here = nil, nil, nil
  if M.view then M.view = nil ; elro.recenter(true) end
end

-- every class in every maze with this key
local function seed(k)
  local out = {}
  for _, area in ipairs(areas()) do
    local D = load(area)
    local ki = D.kidx[k]
    if ki then
      local S = solution(D)
      for _, r in ipairs(S.byKey[ki] or {}) do out[#out + 1] = { D = D, r = r } end
    end
  end
  return out
end

-- where a way leads, in words: nowhere, a mapped room (negated), or a room of the walk
local function led(S, t)
  if t == WALL then return "nowhere" end
  return "to room " .. tostring(t < 0 and -t or S.id[t])
end

-- the rooms known to be entered from mapped room `from` by `d`, with key k
local function gated(from, d, k)
  local out = {}
  for _, area in ipairs(areas()) do
    local D = load(area)
    local S, seen = solution(D), {}
    for _, gt in ipairs(D.gin or {}) do
      local r = gt.node <= #D.nodes and S.find(gt.node)
      if r and gt.from == from and gt.d == d and not seen[r] and D.keys[D.nodes[r].k] == k then
        seen[r] = true ; out[#out + 1] = { D = D, r = r }
      end
    end
  end
  return out
end

-- learning off: narrow down where you can be. `from`: the mapped room the move left.
local function locate(k, d, from)
  local B = {}
  if from then
    B = gated(from, d, k)
  elseif M.belief and d then
    for _, b in ipairs(M.belief) do
      local S = solution(b.D)
      local t = S.way2(b.r, d)
      if t and t > 0 and b.D.keys[b.D.nodes[t].k] == k then B[#B + 1] = { D = b.D, r = t } end
    end
  elseif M.belief then
    for _, b in ipairs(M.belief) do
      if b.D.keys[b.D.nodes[b.r].k] == k then B[#B + 1] = b end
    end
  end
  -- speak only when you were surely in a maze: outside one, its look-alikes and gaps are no news
  local sure = M.belief and #M.belief == 1 and M.belief[1].D.area
  if #B == 0 then B = seed(k) end
  if #B == 0 and sure and not M.hinted then
    M.hinted = true
    echo(string.format("a room '%s' does not know. Learning is off, so it is not added:"
      .. " 'mapmanual on' learns it.", sure))
  end
  M.belief = #B > 0 and B or nil
  if #B == 1 then
    M.hinted = nil
    show(solution(B[1].D).id[B[1].r])
  else
    if M.view then M.view = nil ; elro.recenter(true) end
    if #B > 1 and sure then echo(string.format("one of %d rooms that look alike; walk on to tell which", #B)) end
  end
end

-- learning on: one more room seen, reached by `d` from the last (nil: a fresh start), or by
-- `d` from mapped room `from`
local function learn(k, d, from)
  local D = load(M.learn)
  local S = solution(D)
  if from then M.last = nil end
  -- a look at the room you are in adds nothing
  if not d and M.last and D.keys[D.nodes[M.last].k] == k then
    show(S.id[S.find(M.last)])
    return
  end
  local before = #S.reds
  if M.last and d then
    local c = S.find(M.last)
    local t = S.way(c, d)
    local was = t and t > 0 and D.keys[D.nodes[t].k]
    if t and was ~= k and support(D, S, c, d) >= SURE then
      -- more likely a misread line than a changed maze: skip the step, keep learning
      echo(string.format("%s from room %d led %s every time before; this step is not kept."
        .. " If the area did change: 'mapmanual forget %d'.", d, S.id[c], led(S, t), S.id[c]))
      lost()
      return
    end
  end
  local ki = D.kidx[k]
  local newKey = not ki
  if newKey then
    D.keys[#D.keys + 1] = k ; ki = #D.keys ; D.kidx[k] = ki
    if M.names then for _, x in ipairs(key_exits(k)) do M.names[x] = true end end
  end
  local n = { k = ki }
  if M.last and d then D.nodes[M.last].d = d else n.s = true end
  D.nodes[#D.nodes + 1] = n
  local g = #D.nodes
  if from and d then D.gin[#D.gin + 1] = { from = from, d = d, node = g } end
  S = rebuild(D)
  if not S then return end
  M.last = g
  M.belief = { { D = D, r = S.find(g) } }
  local id = S.id[S.find(g)]
  if #S.reds > before + 1 or (#S.reds > before and not newKey) then
    echo(string.format("two rooms that look alike were told apart: %d room(s) now", #S.reds))
  elseif #S.reds > before then
    echo(string.format("new room %d: %s", id, key_name(k)))
  end
  show(id)
end

local function wall(d)
  if M.learn and M.last then
    local D = load(M.learn)
    local S = solution(D)
    local c = S.find(M.last)
    local t = S.way(c, d)
    if t and t ~= WALL then
      if support(D, S, c, d) >= SURE then
        echo(string.format("%s from room %d led %s every time before; this wall is not kept.",
          d, S.id[c], led(S, t)))
        return
      end
    end
    local n = D.nodes[M.last]
    if not (n.w and n.w[d]) then
      n.w = n.w or {} ; n.w[d] = true
      local S2 = rebuild(D)
      if S2 then M.belief = { { D = D, r = S2.find(M.last) } } ; show(S2.id[S2.find(M.last)]) end
    end
  end
end

-- ---- hooks ----
-- A room answers the oldest move still waiting, at its exit line; a wall line answers it too.
-- Prompts only end a block: a follower's "arrives" brings a prompt of its own, so counting
-- prompts pairs every later room with the wrong command. Results are acted on at the prompt,
-- when whether the player is off the map is known.

local LOOK = { look = true, l = true }
-- a move typed this long after the one before it means the one before got its answer
local GAP_MS = 400

-- every exit name any known maze room has
local function exit_names()
  if M.names then return M.names end
  M.names = {}
  for _, area in ipairs(areas()) do
    for _, k in ipairs(load(area).keys) do
      for _, x in ipairs(key_exits(k)) do M.names[x] = true end
    end
  end
  return M.names
end

function M.sent(text)
  local now = elro.now_ms()
  while M.q[1] and now - M.q[1].at > elro.sentAgeMs do table.remove(M.q, 1) end
  local c = trim((text or ""):lower())
  local d = elro.norm(c)
  if not elro.dirNum[d] then
    d = (exit_names()[c] or (M.here and M.here[c])) and c or nil
  end
  if d or LOOK[c] then
    local alone = not M.q[1]
    -- what arrived before this was typed is not its answer: a room's name is read from here on
    if alone then M.blk = {} end
    -- a lone move from a mapped room: it surely left that room (one typed ahead may not have)
    local from = alone and d and not elro.offmap and elro.current or nil
    M.q[#M.q + 1] = { at = now, d = d, alone = alone, from = from }
    tr("sent '%s': way %s, alone %s, from mapped room %s (off the map: %s)", c, tostring(d),
       tostring(alone), tostring(from), tostring(elro.offmap))
  end
end

-- the move this result answers: a head that was answered by a prompt before the next was typed
-- got no room, and a move the last room did not list cannot have made one
local function take()
  local q = M.q
  while q[2] and q[1].prompted and q[2].at - q[1].at > GAP_MS do table.remove(q, 1) end
  return table.remove(q, 1)
end

function M.line(l)
  -- only the answer to a move or look of ours: chatter between commands is never a room. A
  -- room shown unasked (a flee, a summons, a trap) moved us: we no longer know where we are.
  if not M.q[1] then
    local s = (l or ""):lower()
    if (M.last or M.belief) and (s:find("<short>", 1, true) or s:find(WORDS.exits, 1, true)) then
      M.unasked = true
    end
    return
  end
  -- xml mode tags the name (<short>) and the exits; stripped, a line reads as in plain mode.
  -- The tag reader may have cut the line first: it tells us the name it cut (M.shortText).
  local short = (l or ""):find("<short>", 1, true) ~= nil
  l = (l or ""):gsub("</?[%a_]+[^<>]*>", ""):gsub("^>%s*", "")
  if not short and M.shortText and M.shortText ~= "" and trim(l):sub(1, #M.shortText) == M.shortText then
    short = true
  end
  M.shortText = nil
  if noise(l) then return end
  M.blk = M.blk or {}
  local B = M.blk
  local function done()
    if B.name then
      M.res[#M.res + 1] = { k = M.key(B.name, B.ex), ex = exit_list(B.ex), t = take() }
      local t = M.res[#M.res].t
      tr("room '%s', exits '%s', answers %s", B.name, B.ex or "", t and tostring(t.d) or "no move")
    else
      tr("exit line '%s' but no room name read (xml expected: %s)", B.ex or "", tostring(M.xml))
    end
    -- a room without <short> means xml mode is off again
    if not B.short then M.xml = nil end
    M.blk = { after = true }
  end
  if B.exOpen then
    B.ex = B.ex .. " " .. trim(l)
    if B.ex:find("%.%s*$") then B.exOpen = nil ; done() end
    return
  end
  if not l:match("%S") then return end
  local s = trim(l)
  if WORDS.wall[s] then
    local t = take()
    if t and t.d then M.res[#M.res + 1] = { wall = t.d } end
    return
  end
  if short then
    B.name, B.short, M.xml = s, true, true
  elseif not B.name and not B.after and not M.xml then
    B.name = s
  end
  if s:lower():find(WORDS.exits, 1, true) then
    local _, j = s:find(":", 1, true)
    B.ex = j and trim(s:sub(j + 1)) or ""
    if j and not B.ex:find("%.%s*$") then B.exOpen = true else done() end
  end
end

-- Learning, and a lone move from the last learned room showed a mapped room: that way leads
-- there. Only one room shown and no other move waiting, so the two surely belong together.
local function gate_out(res)
  local r = res[1]
  if #res ~= 1 or M.q[1] or not r.k or not r.t or not r.t.alone or r.t.from or not r.t.d then
    tr("no way out kept: %d room(s) shown, move waiting %s, lone move %s", #res, tostring(M.q[1] ~= nil),
       tostring(r and r.t and r.t.alone))
    return
  end
  local d, to = r.t.d, elro.current
  if not (M.here and M.here[d]) or not to or not roomExists(to) then
    tr("no way out kept: '%s' listed %s, mapped room %s", d, tostring(M.here and M.here[d]), tostring(to))
    return
  end
  tr("way out: %s leads to mapped room %d", d, to)
  local D = load(M.learn)
  local n = D.nodes[M.last]
  if not n then return end
  for _, gt in ipairs(D.gout) do if gt.node == M.last and gt.d == d and gt.to == to then return end end
  n.d = d
  D.gout[#D.gout + 1] = { node = M.last, d = d, to = to }
  rebuild(D)
end

function M.prompt()
  -- lost at the prompt, not on the line: lost() may move the view, which waits for a whole room
  if M.unasked then M.unasked = nil ; lost() end
  for _, t in ipairs(M.q) do t.prompted = true end
  if not (M.blk and M.blk.exOpen) then M.blk = {} end
  local res = M.res
  M.res = {}
  if #res > 0 or M.q[1] then
    tr("prompt: %d room(s) read, off the map %s, learning %s, last seen %s, current %s", #res,
       tostring(elro.offmap), tostring(M.learn), tostring(M.last), tostring(elro.current))
  end
  if not elro.offmap and M.learn and M.last then gate_out(res) end
  if not elro.offmap and (M.last or M.belief) then lost() end
  for _, r in ipairs(res) do
    if not elro.offmap then
      if M.last or M.belief then lost() end
    elseif r.k then
      local d = r.t and r.t.d
      -- in from a mapped room: the step is a way in; otherwise a way the last room lists
      local from = r.t and r.t.from
      if not from and d and not (M.here and M.here[d]) then d = nil end
      M.here = {}
      for _, x in ipairs(r.ex) do M.here[x] = true end
      if M.learn then learn(r.k, d, from) else locate(r.k, d, from) end
    elseif r.wall then
      wall(r.wall)
    end
  end
end

local function kill_hooks()
  for _, h in ipairs({ "lineT", "promptT" }) do
    if M[h] then pcall(killTrigger, M[h]) ; M[h] = nil end
  end
  if M.sendH then pcall(killAnonymousEventHandler, M.sendH) ; M.sendH = nil end
  if NannyXml and NannyXml.listen then NannyXml.listen("manual", nil) end
end

local function hooks()
  kill_hooks()
  M.q, M.res, M.blk = {}, {}, {}
  if NannyXml and NannyXml.listen then
    NannyXml.listen("manual", function(class, text) if class == "short" then M.shortText = trim(text) end end)
  end
  M.lineT = tempRegexTrigger("^", function() M.line(line) end)
  M.promptT = tempPromptTrigger(function() M.prompt() end)
  M.sendH = registerAnonymousEventHandler("sysDataSendRequest", function(_, text) M.sent(text) end)
end

-- ---- the command ----

local function status()
  local list = areas()
  say(M.learn and ("learning the area '" .. M.learn .. "'.") or "not learning; known areas are only located.")
  if #list == 0 then cecho("  No area learned yet: 'mapmanual on <name>' inside one.\n") return end
  if M.twoway_on() then cecho("  Two-way is on: a way walked is taken to lead back.\n") end
  for _, area in ipairs(list) do
    local D = load(area)
    local S = solution(D)
    local here = M.belief and #M.belief == 1 and M.belief[1].D == D and M.belief[1].r
    local open, rows = 0, {}
    for _, r in ipairs(S.reds) do
      local ways = {}
      for _, d in ipairs(key_exits(D.keys[D.nodes[r].k])) do
        if S.way2(r, d) == nil then ways[#ways + 1] = d end
      end
      if #ways > 0 then
        open = open + #ways
        local row = string.format("<yellow>  %d<reset>  %s  <green>untried: %s<reset>%s\n",
          S.id[r], key_name(D.keys[D.nodes[r].k]), table.concat(ways, ", "), r == here and "  (here)" or "")
        if r == here then table.insert(rows, 1, row) else rows[#rows + 1] = row end
      end
    end
    cecho(string.format("  <white>%s<reset>: %d room(s), %d step(s) walked, %d named exit(s) untried.\n",
      area, #S.reds, #D.nodes, open))
    local CAP = 40
    for i = 1, math.min(#rows, CAP) do cecho(rows[i]) end
    if #rows > CAP then cecho(string.format("  and %d more room(s), blue on the map.\n", #rows - CAP)) end
  end
  if M.belief and #M.belief == 1 then
    cecho(string.format("  You are in room %d.\n", solution(M.belief[1].D).id[M.belief[1].r]))
  elseif M.belief then
    cecho(string.format("  You are in one of %d rooms that look alike.\n", #M.belief))
  end
end

local function wipe(area)
  local D = load(area)
  local aid = elro.cs_areas()[area]
  if elro.smap == nil then elro.load_smap() end
  local n = 0
  for _, id in pairs(aid and getAreaRooms(aid) or {}) do
    if is_ours(id, area) then
      for k in pairs(elro.smap) do
        local a, b = k:match("^(%d+):(%d+)$")
        if tonumber(a) == id or tonumber(b) == id then elro.smap[k] = nil end
      end
      deleteRoom(id) ; n = n + 1
    end
  end
  elro.smap_index_dirty() ; elro.save_smap()
  pcall(setMapUserData, "elro.manual:" .. area, "")
  M.data[area], M.names = nil, nil
  for i, a in ipairs(areas()) do if a == area then table.remove(M.areas, i) ; break end end
  save_areas()
  -- the map area only when nothing else is in it: the game's own rooms may share its name
  if aid and n > 0 and type(deleteArea) == "function" and not next(getAreaRooms(aid) or {}) then
    pcall(deleteArea, aid)
  end
  elro.cs_reset() ; elro.cs_areas_dirty()
  if M.learn == area then set_learn(nil) end
  if D then lost() end
  if type(updateMap) == "function" then updateMap() end
  return n
end

-- mapmanual [on <name> | off | wipe <name> [confirm]]
function elro.cmd_manual(arg)
  arg = trim(arg or "")
  local name = arg:match("^on%s+(.+)$")
  if arg == "on" or name then
    if type(tempPromptTrigger) ~= "function" then say("this Mudlet cannot see prompts; mapmanual needs them.") return end
    if not name and not M.lastArea then
      local ok, s = pcall(getMapUserData, "elro.manual.last")
      if ok and type(s) == "string" and s ~= "" then M.lastArea = s end
    end
    name = name or M.learn or M.lastArea
    if not name then say("name the area: 'mapmanual on <name>'. Its rooms go in a map area of that name.") return end
    local known = false
    for _, a in ipairs(areas()) do if a == name then known = true end end
    -- a new name the game's map already has: its layout would place our rooms among its own
    local aid = not known and elro.cs_areas()[name]
    if aid then
      for _, id in pairs(getAreaRooms(aid) or {}) do
        if not is_ours(id, name) then
          say(string.format("'%s' is an area of the game's map. Give the learned part a name of its own,"
            .. " such as '%s vc': the ways in and out join the two.", name, name))
          return
        end
      end
    end
    if not known then table.insert(M.areas, name) ; save_areas() end
    load(name)
    set_learn(name)
    M.lastArea = name
    pcall(setMapUserData, "elro.manual.last", name)
    if type(saveMap) == "function" then pcall(saveMap) end
    M.last = nil
    hooks()
    say("learning the area '" .. name .. "'. Every room you walk into is kept; 'mapmanual off' stops"
      .. " learning but still shows where you are. (Experimental.)")
  elseif arg:match("^trace") then
    local v = arg:match("^trace%s+(%a+)$")
    M.trace = (v == "on") or (v == nil and not M.trace)
    say(M.trace and "tracing: each move, room and prompt is shown as it is taken. 'mapmanual trace off' stops."
        or "tracing off.")
  elseif arg == "off" then
    set_learn(nil)
    M.last = nil
    if type(saveMap) == "function" then pcall(saveMap) end
    say("learning off. Known rooms are still found as you walk.")
  elseif arg:match("^twoway") then
    local v = arg:match("^twoway%s+(%a+)$")
    if v == "on" then M.twoway = true elseif v == "off" then M.twoway = false
    elseif v then say("'mapmanual twoway on' or 'mapmanual twoway off'.") return
    else M.twoway = not M.twoway_on() end
    pcall(setMapUserData, "elro.manual.twoway", M.twoway and "on" or "off")
    for _, area in ipairs(areas()) do
      local D = load(area)
      D.S = nil
      rebuild(D)
    end
    say(M.twoway and "two-way on: a way walked is taken to lead back, where the room lists the way back"
        .. " and it has not been walked." or "two-way off: every way has to be walked to be known.")
  elseif arg:match("^forget") then
    local id = tonumber(arg:match("^forget%s+(%d+)$"))
    local area = id and roomExists(id) and getRoomUserData(id, "manual")
    if not area or area == "" then say("'mapmanual forget <room number>', a room of a learned area.") return end
    local D = load(area)
    local S = solution(D)
    local gone, n = {}, 0
    for g in ipairs(D.nodes) do
      if S.id[S.find(g)] == id then gone[g] = true ; n = n + 1 end
    end
    local before = #S.reds
    drop(D, gone)
    M.belief = nil
    local S2 = rebuild(D)
    if S2 then
      say(string.format("room %d forgotten: %d sighting(s) dropped; '%s' has %d room(s), was %d.",
        id, n, area, #S2.reds, before))
    end
  elseif arg:match("^same") then
    -- two rooms the grid kept apart that the player knows are one: an exit between them warps
    local a, b = arg:match("^same%s+(%d+)%s+(%d+)$")
    a, b = tonumber(a), tonumber(b)
    local area = a and roomExists(a) and getRoomUserData(a, "manual")
    if not area or area == "" or not b or not roomExists(b) or getRoomUserData(b, "manual") ~= area then
      say("'mapmanual same <room> <room>', two rooms of the same learned area.") return
    end
    local D = load(area)
    local S = solution(D)
    local ra, rb
    for _, r in ipairs(S.reds) do
      if S.id[r] == a then ra = r end
      if S.id[r] == b then rb = r end
    end
    if not ra or not rb or ra == rb then say("those are one room already.") return end
    D.same[#D.same + 1] = { ra, rb }
    local before = #S.reds
    local S2 = rebuild(D)
    if not S2 then return end
    for _, p in ipairs(S2.refused) do
      if p[1] == ra and p[2] == rb then
        table.remove(D.same)
        rebuild(D)
        say(string.format("rooms %d and %d cannot be one: a way walked from both leads to different places.", a, b))
        return
      end
    end
    say(string.format("rooms %d and %d are one room now; '%s' has %d room(s), was %d. An exit between them"
      .. " breaks the grid.", a, b, area, #S2.reds, before))
  elseif arg:match("^dump") then
    local area = trim(arg:match("^dump%s*(.*)$") or "")
    if area == "" then area = M.learn or M.lastArea end
    if not area then say("'mapmanual dump <name>'.") return end
    local ok, s = pcall(getMapUserData, "elro.manual:" .. area)
    if not ok or type(s) ~= "string" or s == "" then say("no walk kept for '" .. area .. "'.") return end
    local path = getMudletHomeDir() .. "/mapmanual_" .. area:gsub("[^%w]", "_") .. ".txt"
    local f = io.open(path, "wb")
    if not f then say("could not write " .. path) return end
    f:write(s) ; f:close()
    say("the walk of '" .. area .. "' is in " .. path)
  elseif arg:match("^wipe") then
    local area, sure = arg:match("^wipe%s+(.-)%s+confirm$")
    area = area or arg:match("^wipe%s+(.+)$")
    sure = arg:match("%s+confirm$") ~= nil
    if not area or area == "" then say("'mapmanual wipe <name>' and then the same with 'confirm'.") return end
    local known = false
    for _, a in ipairs(areas()) do if a == area then known = true end end
    if not known then say("no learned area called '" .. area .. "'.") return end
    if not sure then say("this deletes every room of '" .. area .. "' and what was walked there. Add 'confirm'.") return end
    say(string.format("'%s' wiped: %d room(s) deleted.", area, wipe(area)))
  else
    status()
  end
end

-- a known maze is located from the first start on; the map loads a moment after the scripts
-- once the map is loaded: hooks for known mazes, and learning taken up where it was
function M.boot()
  M.areas = nil
  local ok, s = pcall(getMapUserData, "elro.manual.learn")
  M.learn = nil
  if ok and type(s) == "string" and s ~= "" then
    for _, a in ipairs(areas()) do if a == s then M.learn = s end end
  end
  -- always afresh: hooks kept from before an update would miss what the new code listens to
  if #areas() > 0 and type(tempPromptTrigger) == "function" then hooks() end
end

if type(tempTimer) == "function" then tempTimer(2, function() M.boot() end) end
