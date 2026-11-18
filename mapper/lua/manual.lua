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
  D.S = nil
end

local function load(area)
  local D = M.data[area]
  if D then return D end
  D = { area = area, keys = {}, kidx = {}, nodes = {} }
  local ok, s = pcall(getMapUserData, "elro.manual:" .. area)
  if ok and type(s) == "string" then
    for line in s:gmatch("[^\n]+") do
      local k = line:match("^K\t(.*)$")
      if k then
        D.keys[#D.keys + 1] = k ; D.kidx[k] = #D.keys
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
  pcall(setMapUserData, "elro.manual:" .. D.area, table.concat(L, "\n"))
end

-- ---- working out the map ----
-- Each room seen joins the first room found so far with its key that it can be the same as;
-- being the same means every way walked from both agrees, as far as the walk followed them.
-- A seen room that agrees with none becomes a room of its own.
function M.solve(D)
  local N = #D.nodes
  local par, key, E = {}, {}, {}
  -- a step through an exit its room does not list was paired with the wrong command
  local listed = {}
  for i, k in ipairs(D.keys) do
    listed[i] = {}
    for _, x in ipairs(key_exits(k)) do listed[i][x] = true end
  end
  for g = 1, N do
    local n = D.nodes[g]
    par[g], key[g] = g, n.k
    local e = {}
    for x in pairs(n.w or {}) do if not listed[n.k][x] then e[x] = WALL end end
    if n.d and listed[n.k][n.d] and D.nodes[g + 1] and not D.nodes[g + 1].s then e[n.d] = g + 1 end
    E[g] = e
  end
  local function find(x) while par[x] ~= x do x = par[x] end return x end
  local log = {}
  local function set(t, k, v) log[#log + 1] = { t, k, t[k] } ; t[k] = v end
  local function undo(mark)
    for i = #log, mark + 1, -1 do local u = log[i] ; u[1][u[2]] = u[3] ; log[i] = nil end
    return false
  end
  local function merge(a, b)
    local mark = #log
    local work = { a, b }
    while #work > 0 do
      local y = table.remove(work) ; local x = table.remove(work)
      x, y = find(x), find(y)
      if x ~= y then
        if key[x] ~= key[y] then return undo(mark) end
        if y < x then x, y = y, x end
        set(par, y, x)
        for d, t in pairs(E[y]) do
          local s = E[x][d]
          if s == nil then set(E[x], d, t)
          elseif s == WALL or t == WALL then
            if s ~= t then return undo(mark) end
          else work[#work + 1] = s ; work[#work + 1] = t end
        end
      end
    end
    for i = #log, mark + 1, -1 do log[i] = nil end
    return true
  end
  local reds, byKey = {}, {}
  for g = 1, N do
    if find(g) == g then
      local joined = false
      for _, r in ipairs(byKey[key[g]] or {}) do
        if merge(r, g) then joined = true ; break end
      end
      if not joined then
        reds[#reds + 1] = g
        byKey[key[g]] = byKey[key[g]] or {}
        table.insert(byKey[key[g]], g)
      end
    end
  end
  -- a class's way: WALL, or the class it leads to
  local function way(r, d)
    local t = E[r][d]
    if t == nil or t == WALL then return t end
    return find(t)
  end
  -- two-way: a walked way back is assumed where the room lists it and nothing is known there.
  -- Assumed ways never merge or split rooms; two walks that claim one way back cancel it.
  local A = {}
  if M.twoway_on() then
    local claim = {}
    for _, r in ipairs(reds) do
      for d, t in pairs(E[r]) do
        local rv = t ~= WALL and M.reverse(d)
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
  return { reds = reds, find = find, E = E, A = A, way = way, way2 = way2, byKey = byKey }
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
      if t and t ~= WALL then
        if elro.dirNum[d] then want[d] = S.id[t] else wantS[d] = S.id[t] end
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
  if not assign(D, S) then say("no room numbers left for this maze; 'mapmanual wipe' one.") return nil end
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

-- learning off: narrow down where you can be
local function locate(k, d)
  local B = {}
  if M.belief and d then
    for _, b in ipairs(M.belief) do
      local S = solution(b.D)
      local t = S.way2(b.r, d)
      if t and t ~= WALL and b.D.keys[b.D.nodes[t].k] == k then B[#B + 1] = { D = b.D, r = t } end
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

-- learning on: one more room seen, reached by `d` from the last (nil: a fresh start)
local function learn(k, d)
  local D = load(M.learn)
  local S = solution(D)
  -- a look at the room you are in adds nothing
  if not d and M.last and D.keys[D.nodes[M.last].k] == k then
    show(S.id[S.find(M.last)])
    return
  end
  local before = #S.reds
  if M.last and d then
    local c = S.find(M.last)
    local t = S.way(c, d)
    local was = (t == WALL) and "nowhere" or (t and D.keys[D.nodes[t].k])
    if t and was ~= k and support(D, S, c, d) >= SURE then
      -- more likely a misread line than a changed maze: skip the step, keep learning
      echo(string.format("%s from room %d led %s every time before; this step is not kept."
        .. " If the maze did change: 'mapmanual forget %d'.", d, S.id[c],
        t == WALL and "nowhere" or ("to room " .. S.id[t]), S.id[c]))
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
        echo(string.format("%s from room %d led to room %d every time before; this wall is not kept.",
          d, S.id[c], S.id[t]))
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
    -- what arrived before this was typed is not its answer: a room's name is read from here on
    if not M.q[1] then M.blk = {} end
    M.q[#M.q + 1] = { at = now, d = d }
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
  -- only the answer to a move or look of ours: chatter between commands is never a room
  if not M.q[1] then return end
  -- xml mode tags the name (<short>) and the exits; stripped, a line reads as in plain mode
  local short = (l or ""):find("<short>", 1, true) ~= nil
  l = (l or ""):gsub("</?[%a_]+[^<>]*>", ""):gsub("^>%s*", "")
  if noise(l) then return end
  M.blk = M.blk or {}
  local B = M.blk
  local function done()
    if B.name then
      M.res[#M.res + 1] = { k = M.key(B.name, B.ex), ex = exit_list(B.ex), t = take() }
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

function M.prompt()
  for _, t in ipairs(M.q) do t.prompted = true end
  if not (M.blk and M.blk.exOpen) then M.blk = {} end
  local res = M.res
  M.res = {}
  if not elro.offmap and (M.last or M.belief) then lost() end
  for _, r in ipairs(res) do
    if not elro.offmap then
      if M.last or M.belief then lost() end
    elseif r.k then
      local d = r.t and r.t.d
      if d and not (M.here and M.here[d]) then d = nil end
      M.here = {}
      for _, x in ipairs(r.ex) do M.here[x] = true end
      if M.learn then learn(r.k, d) else locate(r.k, d) end
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
end

local function hooks()
  kill_hooks()
  M.q, M.res, M.blk = {}, {}, {}
  M.lineT = tempRegexTrigger("^", function() M.line(line) end)
  M.promptT = tempPromptTrigger(function() M.prompt() end)
  M.sendH = registerAnonymousEventHandler("sysDataSendRequest", function(_, text) M.sent(text) end)
end

-- ---- the command ----

local function status()
  local list = areas()
  say(M.learn and ("learning the maze '" .. M.learn .. "'.") or "not learning; known mazes are only located.")
  if #list == 0 then cecho("  No maze learned yet: 'mapmanual on <name>' inside one.\n") return end
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
  if aid and n > 0 and type(deleteArea) == "function" then pcall(deleteArea, aid) end
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
    if not name then say("name the maze: 'mapmanual on <name>'. Its rooms go in an area of that name.") return end
    local known = false
    for _, a in ipairs(areas()) do if a == name then known = true end end
    if not known then table.insert(M.areas, name) ; save_areas() end
    load(name)
    set_learn(name)
    M.lastArea = name
    pcall(setMapUserData, "elro.manual.last", name)
    if type(saveMap) == "function" then pcall(saveMap) end
    M.last = nil
    if not M.sendH then hooks() end
    say("learning the maze '" .. name .. "'. Every room you walk into is kept; 'mapmanual off' stops"
      .. " learning but still shows where you are. (Experimental.)")
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
    if not area or area == "" then say("'mapmanual forget <room number>', a room of a learned maze.") return end
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
    if not known then say("no maze called '" .. area .. "'.") return end
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
  if #areas() > 0 and not M.sendH and type(tempPromptTrigger) == "function" then hooks() end
end

if type(tempTimer) == "function" then tempTimer(2, function() M.boot() end) end
