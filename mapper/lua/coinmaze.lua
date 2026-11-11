-- mapcoins: tell the rooms of a maze apart by the gold coins lying in them. Switched on by
-- hand inside the maze. After a move into a room of the maze's name with no coins, it drops
-- the lowest number of coins not yet used there; a room with coins is known by their number.
-- Each move between two numbered rooms is remembered and drawn in an area of its own, placed
-- here and never by the layout engine. Session only: the rooms are deleted at profile start.

local fresh = elro.coins == nil
elro.coins = elro.coins or { on = false, used = {}, edges = {} }
local C = elro.coins
C.walls = C.walls or {}                     -- room -> dir -> true: a move that showed no room
C.was = C.was or {}                         -- room -> dir -> what it did before it changed
C.other = C.other or {}                     -- room -> dir -> what it showed that was no maze room
C.q = C.q or {}
C.desc = C.desc or {}                       -- room -> dir -> what the room said lies that way

local WALL = "You cannot go that way."

-- A blocked maze names no exits, so the ways to try are the four compass points plus any other
-- direction that has taken someone from one room of the maze to another.
local function maze_dirs()
  local s = { north = true, east = true, south = true, west = true }
  -- up and down belong to the rooms that have them, never offered everywhere
  for _, ways in pairs(C.edges) do
    for d in pairs(ways) do if d ~= "up" and d ~= "down" then s[d] = true end end
  end
  return s
end

local function say(s) cecho("\n<cyan>[elro]: " .. s .. "<reset>\n") end

-- ---- drawing ----
local COIN = "coinmaze"

local function coin_id(n) return elro.COIN_BASE + n end

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

local function taken_cells(aid)
  local taken = {}
  for _, id in pairs(getAreaRooms(aid) or {}) do
    local x, y, z = getRoomCoordinates(id)
    taken[x .. "," .. y .. "," .. z] = true
  end
  return taken
end

local function tried(n, d)
  return (C.edges[n] and C.edges[n][d]) ~= nil or (C.walls[n] and C.walls[n][d]) ~= nil
    or (C.other[n] and C.other[n][d]) ~= nil
end

-- Each walked way is drawn leaving its room in its own direction, coloured by that direction,
-- with an arrow at the room it reaches: a maze's north rarely leads to the room drawn north.
local DIR_COL = {
  north = { 255, 220, 60 }, east = { 80, 200, 255 }, south = { 255, 110, 200 }, west = { 120, 230, 120 },
  northeast = { 255, 160, 60 }, southeast = { 170, 130, 255 }, southwest = { 60, 230, 200 },
  northwest = { 230, 230, 230 },
}
local TIP, NEAR, SIDE = 0.6, 0.45, 0.1
local PAIR_COL = { 200, 200, 200 }

local function seg_dist(ax, ay, bx, by, cx, cy)
  local dx, dy = bx - ax, by - ay
  local l2 = dx * dx + dy * dy
  local t = l2 > 0 and math.max(0, math.min(1, ((cx - ax) * dx + (cy - ay) * dy) / l2)) or 0
  local px, py = ax + dx * t - cx, ay + dy * t - cy
  return math.sqrt(px * px + py * py)
end

local function clear_run(ax, ay, bx, by, pos, a, b)
  for id, p in pairs(pos) do
    if id ~= a and id ~= b and seg_dist(ax, ay, bx, by, p[1], p[2]) < NEAR then return false end
  end
  return true
end

local function draw_lines()
  if type(addCustomLine) ~= "function" or type(getCustomLines) ~= "function" then return end
  local pos = {}
  for n in pairs(C.used) do
    local id = coin_id(n)
    if roomExists(id) then pos[id] = { getRoomCoordinates(id) } end
  end
  for id in pairs(pos) do
    local cl = getCustomLines(id)
    if type(cl) == "table" then for k in pairs(cl) do pcall(removeCustomLine, id, k) end end
  end
  -- a bend around a room in the way, on whichever side is clear
  local function bow(sx, sy, ex, ey, a, b, z)
    if clear_run(sx, sy, ex, ey, pos, a, b) then return nil end
    local vx, vy = ex - sx, ey - sy
    local len = math.sqrt(vx * vx + vy * vy)
    if len == 0 then return nil end
    vx, vy = vx / len, vy / len
    local mx, my = (sx + ex) / 2, (sy + ey) / 2
    for _, sg in ipairs({ 1, -1 }) do
      local px, py = mx + vy * 0.8 * sg, my - vx * 0.8 * sg
      if clear_run(sx, sy, px, py, pos, a, b) and clear_run(px, py, ex, ey, pos, a, b) then return { px, py, z } end
    end
    return nil
  end
  -- Two rooms joined both ways: one grey line, leaving each room in its own direction.
  local done = {}
  for n, ways in pairs(C.edges) do
    for d, m in pairs(ways) do
      if m ~= n and not done[n .. d] then
        local back = C.edges[m] or {}
        local e = back[elro.reverse[d]] == n and elro.reverse[d] or nil
        if not e then for d2, n2 in pairs(back) do if n2 == n and not done[m .. d2] then e = d2 ; break end end end
        local a, b = coin_id(n), coin_id(m)
        local da, db = elro.delta[d], e and elro.delta[e]
        if e and pos[a] and pos[b] and da and db and (da[1] ~= 0 or da[2] ~= 0) and (db[1] ~= 0 or db[2] ~= 0) then
          done[n .. d], done[m .. e] = true, true
          local pa, pb, z = pos[a], pos[b], pos[a][3]
          local sx, sy = pa[1] + da[1] * TIP, pa[2] + da[2] * TIP
          local tx, ty = pb[1] + db[1] * TIP, pb[2] + db[2] * TIP
          local pts = { { sx, sy, z } }
          local mid = bow(sx, sy, tx, ty, a, b, z)
          if mid then pts[#pts + 1] = mid end
          pts[#pts + 1] = { tx, ty, z }
          pts[#pts + 1] = { pb[1], pb[2], z }
          pcall(addCustomLine, a, pts, elro.shortDir(d), "solid line", PAIR_COL, false)
          -- the other end's slot gets nothing to draw, so Mudlet draws no line of its own there
          pcall(addCustomLine, b, { { pb[1], pb[2], z }, { pb[1], pb[2], z } }, elro.shortDir(e), "solid line", PAIR_COL, false)
        end
      end
    end
  end
  for n, ways in pairs(C.edges) do
    local a = coin_id(n)
    for d, m in pairs(ways) do
      local b, de = coin_id(m), elro.delta[d]
      local pa, pb = pos[a], pos[b]
      if not done[n .. d] and pa and pb and de and (de[1] ~= 0 or de[2] ~= 0) then
        local ax, ay, z = pa[1], pa[2], pa[3]
        local sx, sy = ax + de[1] * TIP, ay + de[2] * TIP
        local pts
        if a == b then
          -- back here: a small loop out and back on the right of the way out
          local rx, ry = de[2] * 0.3, -de[1] * 0.3
          pts = { { sx, sy, z }, { sx + rx, sy + ry, z }, { ax + de[1] * NEAR + rx, ay + de[2] * NEAR + ry, z } }
        else
          local bx, by = pb[1], pb[2]
          local vx, vy = bx - sx, by - sy
          local len = math.sqrt(vx * vx + vy * vy)
          if len > 0 then vx, vy = vx / len, vy / len end
          -- a hair to the right of travel, so the two ways of a pair do not lie on one line
          local ox, oy = vy * SIDE, -vx * SIDE
          local ex, ey = bx - vx * NEAR + ox, by - vy * NEAR + oy
          pts = { { sx, sy, z } }
          local mid = bow(sx, sy, ex, ey, a, b, z)
          if mid then pts[#pts + 1] = mid end
          pts[#pts + 1] = { ex, ey, z }
        end
        pcall(addCustomLine, a, pts, elro.shortDir(d), "solid line", DIR_COL[d] or { 200, 200, 200 }, true)
      end
    end
  end
  -- untested: the mapper's short frontier line, which stops before the neighbour's
  local f = elro.FRONTIER_LEN or 0.3
  for id, p in pairs(pos) do
    for dname, to in pairs(getRoomExits(id) or {}) do
      local d = elro.norm(dname)
      local de = elro.delta[d]
      if to == elro.FRONTIER_ROOM and de and (de[1] ~= 0 or de[2] ~= 0) then
        pcall(addCustomLine, id, { { p[1], p[2], p[3] }, { p[1] + de[1] * f, p[2] + de[2] * f, p[3] } },
              elro.shortDir(d), "solid line", elro.FRONTIER_COL, false)
      end
    end
  end
end

-- An exit to the frontier placeholder on every direction not yet tried, drawn as a short line by
-- draw_lines. Rewritten each turn: a direction walked for the first time is untested on every room.
local function refresh_stubs()
  local front = elro.frontier_room and elro.frontier_room()
  local dirs = maze_dirs()
  for n in pairs(C.used) do
    local id = coin_id(n)
    if roomExists(id) then
      local ex = getRoomExits(id) or {}
      local now = elro.stub_set(id)
      for d, dn in pairs(elro.dirNum) do
        -- Mudlet's own stubs, from maps made before this
        if now[dn] and type(setExitStub) == "function" then pcall(setExitStub, id, dn, false) end
        if tried(n, d) or not dirs[d] then
          if ex[d] == front then setExit(id, -1, d) ; elro.cs_dirty(id) end
        elseif front and not ex[d] then
          setExit(id, front, d) ; elro.cs_dirty(id)
        end
      end
    end
  end
  draw_lines()
  if type(updateMap) == "function" then updateMap() end
end

-- room n, made if new: one step from the room it was walked to from, or beside it when taken
local function draw_room(n, prev, dir)
  local id = coin_id(n)
  local aid = elro.areaId(elro.COIN_AREA)
  local pid = prev and coin_id(prev)
  if not roomExists(id) then
    local x, y, z = 0, 0, 0
    local d = dir and elro.delta[dir]
    if pid and roomExists(pid) and d then
      local px, py, pz = getRoomCoordinates(pid)
      x, y, z = px + d[1], py + d[2], pz + d[3]
    end
    x, y = free_near(x, y, z, taken_cells(aid))
    addRoom(id)
    setRoomArea(id, aid)
    setRoomCoordinates(id, x, y, z)
    setRoomName(id, string.format("%d coin%s", n, n == 1 and "" or "s"))
    setRoomUserData(id, COIN, "1")
    -- adopt pins the area to its own tab; VIA_NONE keeps a small one from folding
    setRoomUserData(id, "sarea", elro.COIN_AREA)
    setRoomUserData(id, "adopt", elro.COIN_AREA)
    setRoomUserData(id, "via", elro.VIA_NONE)
    elro.cs_lists_dirty() ; elro.cs_dirty(id, aid)
  end
  if pid and roomExists(pid) and dir and elro.dirNum[dir] then
    -- Mudlet will not hold a stub and an exit in one direction
    if type(setExitStub) == "function" then pcall(setExitStub, pid, elro.dirNum[dir], false) end
    setExit(pid, id, dir)
    elro.cs_dirty(pid)
  end
  refresh_stubs()
  C.view = id
  elro.recenter()
end

-- the view goes back to wherever the mapper says the player is
local function release_view()
  if C.view then C.view = nil ; elro.recenter(true) end
end

-- every coin maze room and its area; true when there was any
function elro.coins_clear()
  local n = 0
  for id in pairs(getRooms() or {}) do
    if id >= elro.COIN_BASE and id < elro.FRONTIER_ROOM and getRoomUserData(id, COIN) == "1" then
      deleteRoom(id) ; n = n + 1
    end
  end
  local aid = elro.cs_areas()[elro.COIN_AREA]
  if aid and type(deleteArea) == "function" then pcall(deleteArea, aid) end
  if n > 0 or aid then elro.cs_reset() ; elro.cs_areas_dirty() end
  if type(updateMap) == "function" then updateMap() end
  return n > 0
end

local function move_dir(cmd)
  local c = (cmd or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local d = elro.norm(c)
  return elro.dirNum[d] and d or nil
end

-- Caves that only know forward, right, back and left: the move is turned into a compass direction
-- from the facing the client keeps, which starts as north and becomes the way each move went.
local REL = { forward = 0, right = 1, back = 2, left = 3 }
local COMPASS = { "north", "east", "south", "west" }
local COMPASS_I = { north = 0, east = 1, south = 2, west = 3 }
local function turn_to(h, k) return COMPASS[(COMPASS_I[h or "north"] + k) % 4 + 1] end

-- the text after "to your right" and the like, up to the next one or the sentence's end
local function segment(text, label)
  local _, j = text:find(label, 1, true)
  if not j then return nil end
  local rest = text:sub(j + 1)
  local cut = #rest + 1
  for _, stop in ipairs({ ", to your", " and to your", "." }) do
    local k = rest:find(stop, 1, true)
    if k and k < cut then cut = k end
  end
  return rest:sub(1, cut - 1)
end

-- A room that says what is in front, right and left: a wall where it says so or says nothing,
-- a way to try where it names one. Behind is never told.
local SIDES = { { "in front of you", 0 }, { "to your right", 1 }, { "to your left", 3 } }
local function note_sides(n, text, h)
  text = (text or ""):lower()
  if not text:find("in front of you", 1, true) then return end
  for _, s in ipairs(SIDES) do
    local seg = segment(text, s[1])
    local d = turn_to(h, s[2])
    if seg and not seg:find("wall", 1, true) then
      if C.walls[n] then C.walls[n][d] = nil end
      C.desc[n] = C.desc[n] or {}
      C.desc[n][d] = seg
    elseif not (C.edges[n] and C.edges[n][d]) then
      C.walls[n] = C.walls[n] or {}
      C.walls[n][d] = true
    end
  end
end

-- A room seen before says the same words about each side, so its text tells which way you face.
-- Each facing scores +1 for a side worded as last time and -1 for one worded differently. Only
-- a facing the words contradict is replaced, by one that alone fits best: a corridor reads the
-- same from both ends, and behind is never told, so a mere better fit proves nothing.
local function facing_from_text(n, text)
  text = (text or ""):lower()
  if not C.desc[n] or not text:find("in front of you", 1, true) then return nil end
  local score = {}
  for i, h in ipairs(COMPASS) do
    local s = 0
    for _, side in ipairs(SIDES) do
      local seg = segment(text, side[1])
      local known = C.desc[n][turn_to(h, side[2])]
      local open = seg and not seg:find("wall", 1, true)
      if known then s = s + ((open and seg == known) and 1 or -1) end
    end
    score[h] = s
  end
  local best, tie = nil, false
  for _, h in ipairs(COMPASS) do
    if not best or score[h] > score[best] then best, tie = h, false
    elseif score[h] == score[best] then tie = true end
  end
  if tie or score[best] < 1 or (score[C.heading] or 0) >= 0 then return nil end
  return best
end

local function next_free()
  local n = 1
  while C.used[n] do n = n + 1 end
  return n
end

-- Every command sent while the mode is on, ours too, oldest first. Each gets one prompt, so the
-- head is the command the current output belongs to, however fast the player types. Age as in
-- elro.sent_push: a command that never got its prompt would shift every later one.
function elro.coins_sent(text)
  if not C.on then return end
  -- anything typed by hand ends a walk
  if C.walk and not C.ownSend then C.walk = nil ; cecho("\n<grey>[maze] walk stopped<reset>\n") end
  local now = elro.now_ms()
  while C.q[1] and now - C.q[1].at > elro.sentAgeMs do table.remove(C.q, 1) end
  local c = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local t = { at = now, dir = move_dir(text), rel = REL[c], cur = elro.current, off = elro.offmap }
  -- a cave of forward and back refuses compass words: not a move
  if C.relSeen and t.dir and COMPASS_I[t.dir] then t.dir = nil end
  t.turn = ({ ["turn right"] = 1, ["turn left"] = 3, ["turn around"] = 2 })[c]
  if C.looking then t.look, t.dir, t.rel, C.looking = true, nil, nil, nil end
  C.q[#C.q + 1] = t
end

function elro.coins_line(l)
  local t = C.q[1]
  if not t or not (t.dir or t.rel or t.look or t.turn) then return end
  l = (l or ""):gsub("^>%s*", "")
  if not t.first and l:match("%S") then t.first = l end
  if t.look then return end
  if t.name then t.text = (t.text or "") .. " " .. l end
  if l == C.name then t.name = true end
  -- a room with no such exit has no such verb, so some mazes answer "What?"
  if l == WALL or l == "What?" or l == "You walk into a wall." then t.wall = true end
  local n = tonumber(l:match("^(%d+) gold coins?%.$"))
  if n and not t.coins then t.coins = n end
end

local function maze_echo(s) cecho("\n<grey>[maze] " .. s .. "<reset>\n") end

-- What the room you are in has, by the words you move with: forward/right/back/left in a cave
-- that uses them, compass otherwise.
local REL_NAME = { [0] = "forward", "right", "back", "left" }
local function here_echo()
  local n = C.at
  if not n then return end
  local rel = C.relSeen and C.heading
  local function name(d)
    if rel and COMPASS_I[d] then return REL_NAME[(COMPASS_I[d] - COMPASS_I[rel]) % 4] end
    return d
  end
  local order = rel and { "forward", "right", "left", "back" }
    or { "north", "east", "south", "west", "northeast", "southeast", "southwest", "northwest", "up", "down" }
  local by = {}
  local set = maze_dirs()
  for d in pairs(C.edges[n] or {}) do set[d] = true end
  for d in pairs(set) do by[name(d)] = d end
  local open, ways, walls = {}, {}, {}
  for _, k in ipairs(order) do
    local d = by[k]
    if d then
      local to = C.edges[n] and C.edges[n][d]
      if to == n then ways[#ways + 1] = k .. " back here"
      elseif to then ways[#ways + 1] = k .. " to " .. to
      elseif C.walls[n] and C.walls[n][d] then walls[#walls + 1] = k
      elseif not (C.other[n] and C.other[n][d]) then open[#open + 1] = k end
    end
  end
  local parts = {}
  if #open > 0 then parts[#parts + 1] = "<green>untested: " .. table.concat(open, ", ") .. "<grey>" end
  if #ways > 0 then parts[#parts + 1] = table.concat(ways, ", ") end
  if #walls > 0 then parts[#parts + 1] = "wall: " .. table.concat(walls, ", ") end
  cecho(string.format("<grey>[maze] room %d%s: %s<reset>\n", n, rel and (", facing " .. rel) or "",
        #parts > 0 and table.concat(parts, "; ") or "nothing known"))
end

-- what this direction led to before, when that is not what it did now
local function note_change(n, d, old)
  C.was[n] = C.was[n] or {}
  C.was[n][d] = old
end

-- forget the walked way from n, if any, and its line on the map; returns where it led
local function unlink(n, d)
  local old = C.edges[n] and C.edges[n][d]
  if old then
    C.edges[n][d] = nil
    note_change(n, d, old)
    setExit(coin_id(n), -1, d)
    elro.cs_dirty(coin_id(n))
  end
  return old
end

-- ---- walking: one step at a time, each chosen from where you are now ----
local function own_send(cmd)
  C.ownSend = true
  send(cmd, false)
  C.ownSend = nil
end

local function has_untested(n)
  for d in pairs(maze_dirs()) do if not tried(n, d) then return true end end
  return false
end

-- the first way to take from `from` toward a room that `goal` accepts, by the fewest steps
local function first_step(from, goal)
  local seen, q, first = { [from] = true }, { from }, {}
  local i = 1
  while q[i] do
    local n = q[i] ; i = i + 1
    if n ~= from and goal(n) then return first[n], n end
    local ds = {}
    for d in pairs(C.edges[n] or {}) do ds[#ds + 1] = d end
    table.sort(ds)
    for _, d in ipairs(ds) do
      local m = C.edges[n][d]
      if not seen[m] then
        seen[m] = true
        first[m] = first[n] or d
        q[#q + 1] = m
      end
    end
  end
  return nil
end

local function walk_stop(why)
  C.walk = nil
  if why then maze_echo(why) end
end

local function walk_next()
  local w = C.walk
  if not w then return end
  if not C.at then return walk_stop("walk stopped: position unknown") end
  if w.target and C.at == w.target then return walk_stop("arrived in room " .. C.at) end
  if not w.target and has_untested(C.at) then return walk_stop("arrived: room " .. C.at .. " has untested ways") end
  w.steps = w.steps + 1
  if w.steps > 60 then return walk_stop("walk stopped after 60 steps") end
  local goal = w.target and function(n) return n == w.target end or has_untested
  local d, to = first_step(C.at, goal)
  if not d then return walk_stop("no known way from room " .. C.at .. (w.target and (" to room " .. w.target) or " to an untested way")) end
  local cmd = d
  if C.relSeen and COMPASS_I[d] then cmd = REL_NAME[(COMPASS_I[d] - COMPASS_I[C.heading or "north"]) % 4] end
  own_send(cmd)
end

local function prompt_once()
  local t = table.remove(C.q, 1)
  if not t or not (t.dir or t.rel or t.look or t.turn) then return end
  if t.turn then
    -- turned on the spot unless the game did not know the command
    if t.first and t.first ~= "What?" then
      C.heading = turn_to(C.heading, t.turn)
      if C.at then note_sides(C.at, t.text or t.first, C.heading) ; refresh_stubs() end
      C.relSeen = true
      maze_echo("facing " .. C.heading)
      here_echo()
    end
    return
  end
  if t.rel then t.dir = turn_to(C.heading, t.rel) ; C.relSeen = true end
  if t.look then
    if not t.first then say("could not read the room's name. Try 'mapcoins on <room name>'.") ; elro.coins_off() return end
    C.name = t.first
    say("coin maze ON for rooms called '" .. C.name .. "'. Walk; an empty room gets coins. 'mapcoins off' stops.")
    return
  end
  -- no room of the maze's name was shown: out of the maze if the game named a real room this
  -- turn; a wall only on the game's own words; anything else may be another room, so where the
  -- player is becomes unknown
  if not t.name then
    if elro.current ~= t.cur or (t.off and not elro.offmap) then
      C.at = nil
      release_view()
    elseif C.at and t.wall then
      local old = unlink(C.at, t.dir)
      if C.other[C.at] then C.other[C.at][t.dir] = nil end
      C.walls[C.at] = C.walls[C.at] or {}
      C.walls[C.at][t.dir] = true
      if old then
        maze_echo(string.format("%s from %d led to %d before; now it does not move you", t.dir, C.at, old))
      else
        maze_echo(string.format("%s from %d does not move you", t.dir, C.at))
      end
      refresh_stubs()
      here_echo()
    elseif C.at and t.first then
      unlink(C.at, t.dir)
      if C.walls[C.at] then C.walls[C.at][t.dir] = nil end
      C.other[C.at] = C.other[C.at] or {}
      C.other[C.at][t.dir] = t.first
      maze_echo(string.format("%s from %d showed '%s': not numbered, position unknown until the next room",
                t.dir, C.at, t.first))
      C.at, C.lostSaid = nil, true
      if t.rel then C.heading = t.dir end
      refresh_stubs()
    elseif not C.at and not C.lostSaid then
      C.lostSaid = true
      maze_echo("position unknown: moves are not on the map until you reach a room with coins"
                .. " (said once; 'mapcoins off' if you have left the maze)")
    end
    return
  end
  C.lostSaid = nil
  if t.rel then
    -- a passage described as curving turns you while you walk it
    local seg = C.at and C.desc[C.at] and C.desc[C.at][t.dir] or ""
    C.heading = turn_to(t.dir, seg:find("curving to the left", 1, true) and 3
                                or seg:find("curving to the right", 1, true) and 1 or 0)
  end
  local prev, msg = C.at, nil
  if t.coins then
    C.used[t.coins] = true ; C.at = t.coins
    msg = string.format("room %d", t.coins)
  elseif #C.q > 0 then
    -- coins sent now would land wherever the command in flight takes the player
    C.at = nil
    say("no coins here, but you had already sent another command, so none were dropped.")
    return
  else
    local n = next_free()
    own_send("drop " .. n)
    C.used[n] = true ; C.at = n
    msg = string.format("new room %d, dropped %d", n, n)
  end
  local fixed = C.relSeen and facing_from_text(C.at, t.text)
  if fixed and fixed ~= C.heading then
    msg = msg .. string.format(" (facing corrected from %s to %s by the room's own words)", C.heading or "north", fixed)
    C.heading = fixed
  end
  if prev then
    C.edges[prev] = C.edges[prev] or {}
    local old = C.edges[prev][t.dir]
    local blocked = C.walls[prev] and C.walls[prev][t.dir]
    if old and old ~= C.at then
      note_change(prev, t.dir, old)
      msg = msg .. string.format(" (%s from %d, which led to %d before)", t.dir, prev, old)
    elseif blocked then
      note_change(prev, t.dir, "no move")
      msg = msg .. string.format(" (%s from %d, which did not move you before)", t.dir, prev)
    else
      msg = msg .. string.format(" (%s from %d)", t.dir, prev)
    end
    C.edges[prev][t.dir] = C.at
    if C.walls[prev] then C.walls[prev][t.dir] = nil end
    if C.other[prev] then C.other[prev][t.dir] = nil end
  else
    msg = msg .. " (where you came from was not known, so this way is not on the map)"
  end
  -- two-way: the way back is behind you, unless something was seen there already
  local rev
  if C.twoway and prev and prev ~= C.at then
    rev = t.rel and elro.reverse[C.heading] or elro.reverse[t.dir]
    local here = C.at
    if rev and not (C.edges[here] and C.edges[here][rev]) and not (C.walls[here] and C.walls[here][rev])
       and not (C.other[here] and C.other[here][rev]) then
      C.edges[here] = C.edges[here] or {}
      C.edges[here][rev] = prev
    else
      rev = nil
    end
  end
  note_sides(C.at, t.text, C.heading)
  draw_room(C.at, prev, t.dir)
  if rev then
    setExit(coin_id(C.at), coin_id(prev), rev) ; elro.cs_dirty(coin_id(C.at))
    refresh_stubs()
  end
  maze_echo(msg)
  here_echo()
end

function elro.coins_prompt()
  local t = C.q[1]
  prompt_once()
  if C.walk and t and (t.dir or t.rel) then walk_next() end
end

local function kill_hooks()
  if C.lineT and type(killTrigger) == "function" then pcall(killTrigger, C.lineT) end
  if C.promptT and type(killTrigger) == "function" then pcall(killTrigger, C.promptT) end
  if C.sendH and type(killAnonymousEventHandler) == "function" then pcall(killAnonymousEventHandler, C.sendH) end
  C.lineT, C.promptT, C.sendH = nil, nil, nil
end

function elro.coins_off()
  kill_hooks()
  C.on, C.q, C.looking, C.walk = false, {}, nil, nil
  release_view()
end

local function coins_on(name)
  kill_hooks()
  C.on, C.q, C.at, C.lostSaid, C.heading, C.relSeen = true, {}, nil, nil, "north", nil
  C.lineT = tempRegexTrigger("^", function() elro.coins_line(line) end)
  C.promptT = tempPromptTrigger(function() elro.coins_prompt() end)
  C.sendH = registerAnonymousEventHandler("sysDataSendRequest", function(_, text) elro.coins_sent(text) end)
  if name then
    C.name = name
    say("coin maze ON for rooms called '" .. name .. "'. Walk; an empty room gets coins. 'mapcoins off' stops.")
  else
    -- the first line of a look is the room's name
    C.looking = true
    send("look", false)
  end
end

local LIST_ORDER = { north = 1, northeast = 2, east = 3, southeast = 4, south = 5,
                     southwest = 6, west = 7, northwest = 8, up = 9, down = 10 }

local function list()
  local ns = {}
  for n in pairs(C.used) do ns[#ns + 1] = n end
  table.sort(ns)
  local rows, open = {}, 0
  for _, n in ipairs(ns) do
    local ways, stays, none, untried, elsewhere = {}, {}, {}, {}, {}
    -- the maze's directions, plus any this room was tried in
    local set, dirs = maze_dirs(), {}
    for d in pairs(C.edges[n] or {}) do set[d] = true end
    for d in pairs(C.walls[n] or {}) do set[d] = true end
    for d in pairs(C.other[n] or {}) do set[d] = true end
    for d in pairs(set) do dirs[#dirs + 1] = d end
    table.sort(dirs, function(a, b) return LIST_ORDER[a] < LIST_ORDER[b] end)
    for _, d in ipairs(dirs) do
      local to = C.edges[n] and C.edges[n][d]
      if to == n then stays[#stays + 1] = d
      elseif to then ways[#ways + 1] = d .. " " .. to
      elseif C.walls[n] and C.walls[n][d] then none[#none + 1] = d
      elseif C.other[n] and C.other[n][d] then elsewhere[#elsewhere + 1] = d .. " '" .. C.other[n][d] .. "'"
      else untried[#untried + 1] = d ; open = open + 1 end
    end
    local parts = {}
    if #ways > 0 then parts[#parts + 1] = table.concat(ways, ", ") end
    if #elsewhere > 0 then parts[#parts + 1] = "<cyan>elsewhere: " .. table.concat(elsewhere, ", ") .. "<reset>" end
    if #stays > 0 then parts[#parts + 1] = "<grey>back here: " .. table.concat(stays, ", ") .. "<reset>" end
    if #none > 0 then parts[#parts + 1] = "<grey>no move: " .. table.concat(none, ", ") .. "<reset>" end
    if #untried > 0 then parts[#parts + 1] = "<green>untested: " .. table.concat(untried, ", ") .. "<reset>" end
    local changed = {}
    for _, d in ipairs(dirs) do
      local old = C.was[n] and C.was[n][d]
      if old then changed[#changed + 1] = d .. " was " .. old end
    end
    if #changed > 0 then parts[#parts + 1] = "<red>changed: " .. table.concat(changed, ", ") .. "<reset>" end
    rows[#rows + 1] = string.format("<yellow>  %3d<reset>  %s\n", n, table.concat(parts, "; "))
  end
  say(string.format("coin maze %s%s; %d room(s) numbered, %d direction(s) untested.", C.on and "ON" or "off",
      C.name and (", rooms called '" .. C.name .. "'") or "", #ns, open))
  for _, r in ipairs(rows) do cecho(r) end
  cecho("  Map lines leave a room the way you walked: <yellow>north<reset> <cyan>east<reset> <magenta>south<reset> <green>west<reset>; the arrow marks where it led."
        .. " A grey line joins two rooms both ways.\n")
  if C.twoway then cecho("  Two-way is on: a way walked is taken to lead back.\n") end
  if C.at then cecho(string.format("  You are in room %d, facing %s.\n", C.at, C.heading or "north")) end
end

-- mapcoins [on [room name] | off | reset | twoway [on|off]]
function elro.cmd_coins(arg)
  arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local name = arg:match("^on%s+(.+)$")
  if arg == "on" or name then
    if type(tempPromptTrigger) ~= "function" then say("this Mudlet cannot see prompts; mapcoins needs them.") return end
    coins_on(name)
  elseif arg == "off" then
    elro.coins_off()
    say("coin maze off. Its map stays until 'mapcoins reset' or the next start.")
  elseif arg == "reset" then
    C.used, C.edges, C.at = {}, {}, nil
    C.walls, C.was, C.other, C.desc = {}, {}, {}, {}
    release_view()
    elro.coins_clear()
    say("coin maze forgotten and wiped from the map: numbering starts at 1 again.")
  elseif arg:match("^go") then
    local n = tonumber(arg:match("^go%s+(%d+)$"))
    if not C.on then say("mapcoins is off.") return end
    if not C.at then say("where you are is not known: walk into a room with coins first.") return end
    if n and not C.used[n] then say("no room " .. n .. " is known.") return end
    C.walk = { target = n, steps = 0 }
    walk_next()
  elseif arg == "relearn" then
    -- the coins stay in the rooms, so keep the numbers and forget only what was learned
    for n in pairs(C.used) do
      local id = coin_id(n)
      if roomExists(id) then
        for d in pairs(elro.dirNum) do setExit(id, -1, d) end
        elro.cs_dirty(id)
      end
    end
    C.edges, C.walls, C.was, C.other, C.desc = {}, {}, {}, {}, {}
    refresh_stubs()
    say("ways forgotten, room numbers kept: walk and every room is learned again, nothing dropped twice.")
  elseif arg == "layout" then
    local aid = elro.cs_areas()[elro.COIN_AREA]
    if not aid then say("no coin maze on the map yet.") return end
    C.layoutOnce = true
    elro.dirty[aid] = true
    if elro.flush_dirty() ~= -1 then
      refresh_stubs()
      say("coin maze laid out by the mapper's engine.")
    else
      say("coin maze being laid out in the background; its lines come back on your next step.")
    end
  elseif arg:match("^twoway") then
    local v = arg:match("^twoway%s+(%a+)$")
    C.twoway = v == "on" or (v == nil and not C.twoway)
    say("two-way " .. (C.twoway and "ON: a way walked is taken to lead back the way you came."
        or "off: every way has to be walked to be known."))
  else
    list()
  end
end

-- Repair a running session from before compass words were ignored in a cave: such a word was
-- taken for a way out, and the way it had replaced is put back.
for n, ways in pairs(C.other) do
  for d, what in pairs(ways) do
    if type(what) == "string" and what:find("^In this cave, you can't determine directions") then
      ways[d] = nil
      local old = C.was[n] and C.was[n][d]
      if type(old) == "number" and not (C.edges[n] and C.edges[n][d]) then
        C.edges[n] = C.edges[n] or {}
        C.edges[n][d] = old
        C.was[n][d] = nil
        if roomExists(coin_id(n)) and roomExists(coin_id(old)) then setExit(coin_id(n), coin_id(old), d) end
      end
    end
  end
end

-- a fresh Lua state is a profile start: the last session's coin rooms go once the map is loaded
if fresh and type(tempTimer) == "function" then tempTimer(2, function() elro.coins_clear() end) end
