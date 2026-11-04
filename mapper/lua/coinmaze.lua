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

local WALL = "You cannot go that way."

-- A blocked maze names no exits, so the ways to try are the four compass points plus any other
-- direction that has moved someone here.
local function seed_dirs() return { north = true, east = true, south = true, west = true } end
C.dirs = C.dirs or seed_dirs()

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

-- A stub on every direction not yet tried. Rewritten each turn: a direction walked for the first
-- time adds a stub on every room, and the mapper's whole-map stub passes may have cleared them.
local function refresh_stubs()
  if type(setExitStub) ~= "function" then return end
  for n in pairs(C.used) do
    local id = coin_id(n)
    if roomExists(id) then
      local now = elro.stub_set(id)
      for d in pairs(C.dirs) do
        local dn = elro.dirNum[d]
        if tried(n, d) then
          if now[dn] then pcall(setExitStub, id, dn, false) end
        elseif not now[dn] then
          pcall(setExitStub, id, dn, true)
        end
      end
    end
  end
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
  local now = elro.now_ms()
  while C.q[1] and now - C.q[1].at > elro.sentAgeMs do table.remove(C.q, 1) end
  local t = { at = now, dir = move_dir(text), cur = elro.current, off = elro.offmap }
  if C.looking then t.look, t.dir, C.looking = true, nil, nil end
  C.q[#C.q + 1] = t
end

function elro.coins_line(l)
  local t = C.q[1]
  if not t or not (t.dir or t.look) then return end
  l = (l or ""):gsub("^>%s*", "")
  if not t.first and l:match("%S") then t.first = l end
  if t.look then return end
  if l == C.name then t.name = true end
  if l == WALL then t.wall = true end
  local n = tonumber(l:match("^(%d+) gold coins?%.$"))
  if n and not t.coins then t.coins = n end
end

local function maze_echo(s) cecho("\n<grey>[maze] " .. s .. "<reset>\n") end

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

function elro.coins_prompt()
  local t = table.remove(C.q, 1)
  if not t or not (t.dir or t.look) then return end
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
    elseif C.at and t.first then
      unlink(C.at, t.dir)
      if C.walls[C.at] then C.walls[C.at][t.dir] = nil end
      C.other[C.at] = C.other[C.at] or {}
      C.other[C.at][t.dir] = t.first
      maze_echo(string.format("%s from %d showed '%s': not numbered, position unknown until the next room",
                t.dir, C.at, t.first))
      C.at = nil
      C.dirs[t.dir] = true
      refresh_stubs()
    end
    return
  end
  C.dirs[t.dir] = true
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
    send("drop " .. n, false)
    C.used[n] = true ; C.at = n
    msg = string.format("new room %d, dropped %d", n, n)
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
  end
  draw_room(C.at, prev, t.dir)
  maze_echo(msg)
end

local function kill_hooks()
  if C.lineT and type(killTrigger) == "function" then pcall(killTrigger, C.lineT) end
  if C.promptT and type(killTrigger) == "function" then pcall(killTrigger, C.promptT) end
  if C.sendH and type(killAnonymousEventHandler) == "function" then pcall(killAnonymousEventHandler, C.sendH) end
  C.lineT, C.promptT, C.sendH = nil, nil, nil
end

function elro.coins_off()
  kill_hooks()
  C.on, C.q, C.looking = false, {}, nil
  release_view()
end

local function coins_on(name)
  kill_hooks()
  C.on, C.q, C.at = true, {}, nil
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
    local dirs = {}
    for d in pairs(C.dirs) do dirs[#dirs + 1] = d end
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
  if C.at then cecho(string.format("  You are in room %d.\n", C.at)) end
end

-- mapcoins [on [room name] | off | reset]
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
    C.walls, C.was, C.other, C.dirs = {}, {}, {}, seed_dirs()
    release_view()
    elro.coins_clear()
    say("coin maze forgotten and wiped from the map: numbering starts at 1 again.")
  else
    list()
  end
end

-- a fresh Lua state is a profile start: the last session's coin rooms go once the map is loaded
if fresh and type(tempTimer) == "function" then tempTimer(2, function() elro.coins_clear() end) end
