-- Monsters seen per room: in xml mode a room's listing tags each monster <monster>, so the
-- names are kept in the room's user data beside the player's notes, with how often and when
-- last they were seen. Read by mapnotes and the map's info overlay. 'mapmobs off' stops it.

elro.mobs = elro.mobs or {}
local B = elro.mobs
local KEY = "mobs"
B.CAP = B.CAP or 30                          -- names kept per room, the least seen go first

function B.on()
  if B.state == nil then
    local ok, s = pcall(getMapUserData, "elro.mobs")
    B.state = not (ok and s == "off")
  end
  return B.state
end

-- a room's monsters as { name, count, last }, most seen first
function B.list(id)
  local t = {}
  local s = roomExists(id) and getRoomUserData(id, KEY) or ""
  for name, n, last in s:gmatch("([^\t\n]+)\t(%d+)\t(%d+)") do
    t[#t + 1] = { name, tonumber(n), tonumber(last) }
  end
  return t
end
elro.mob_list = B.list

local function store(id, t)
  table.sort(t, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
  while #t > B.CAP do table.remove(t) end
  local out = {}
  for _, m in ipairs(t) do out[#out + 1] = m[1] .. "\t" .. m[2] .. "\t" .. m[3] end
  setRoomUserData(id, KEY, table.concat(out, "\n"))
end

-- how many listings of the room were read while noting was on
function B.visits(id)
  return tonumber(roomExists(id) and getRoomUserData(id, "mobv") or "") or 0
end

-- names never noted: a follower or pet is in every room you are, and would look at home there
function B.ignored()
  if not B.ign then
    B.ign = {}
    local ok, s = pcall(getMapUserData, "elro.mobs.ignore")
    for n in (ok and s or ""):gmatch("[^\n]+") do B.ign[n:lower()] = true end
  end
  return B.ign
end

local function save_ignored()
  local t = {}
  for n in pairs(B.ignored()) do t[#t + 1] = n end
  table.sort(t)
  pcall(setMapUserData, "elro.mobs.ignore", table.concat(t, "\n"))
end

-- one listing of room `id` and the names in it: each counts once however many stand there
function B.record(id, names, now)
  if not id or not roomExists(id) then return end
  setRoomUserData(id, "mobv", tostring(B.visits(id) + 1))
  local t = B.list(id)
  local at = {}
  for i, m in ipairs(t) do at[m[1]] = i end
  local seen, ign, added = {}, B.ignored(), false
  for _, name in ipairs(names) do
    if not seen[name] and not ign[name:lower()] then
      seen[name] = true
      if at[name] then
        t[at[name]][2] = t[at[name]][2] + 1 ; t[at[name]][3] = now
      else
        t[#t + 1] = { name, 1, now } ; at[name] = #t ; added = true
      end
    end
  end
  if next(seen) then store(id, t) end
  if added then B.idx = nil end
end

-- per area, in how many rooms each name was seen; built when asked, dropped when one is added
local function area_index(aid)
  B.idx = B.idx or {}
  local x = B.idx[aid]
  if x then return x end
  x = {}
  for _, r in ipairs(elro.cs_area_rooms(aid)) do
    for _, m in ipairs(B.list(r)) do x[m[1]] = (x[m[1]] or 0) + 1 end
  end
  B.idx[aid] = x
  return x
end

-- Resident: seen in a third of the room's listings or more. Seen less: a rare spawn when the
-- name is in no other room of the area, else a wanderer. Too few listings to tell: new.
B.SHARE, B.MINVISITS = 1 / 3, 3
function B.kind(id, m)
  local v = B.visits(id)
  if v < B.MINVISITS or m[2] >= B.SHARE * v then return v < B.MINVISITS and "new" or "resident", v end
  if (area_index(getRoomArea(id))[m[1]] or 0) > 1 then return "wanders", v end
  return "rare", v
end

-- a room's monsters to show as { name, count, visits, kind }; wanderers only when `all`
function B.rows(id, all)
  local out = {}
  for _, m in ipairs(B.list(id)) do
    local k, v = B.kind(id, m)
    if all or k ~= "wanders" then out[#out + 1] = { m[1], m[2], v, k } end
  end
  return out
end
elro.mob_rows = B.rows

-- "A very large boar." as a name: trailing full stop and blanks off
function B.clean(text)
  return (text:gsub("^%s+", ""):gsub("[%s%.]+$", ""))
end

-- A room listing starts at its <short>; its <monster> lines wait for the prompt, when the
-- room the move led to is known.
B.pending, B.listing = B.pending or {}, B.listing or false
if elro.xml and elro.xml.listen then
  elro.xml.listen("mobs", function(class, text)
    if class == "short" then B.listing, B.pending = true, {}
    elseif class == "monster" and B.listing then
      local name = B.clean(text)
      if name ~= "" then B.pending[#B.pending + 1] = name end
    end
  end)
end

-- what noting costs, in seconds: total, worst and how many times (shown by bare mapmobs)
B.cost = B.cost or { n = 0, sum = 0, max = 0 }
function B.time(c, t0)
  local d = os.clock() - t0
  c.n, c.sum = c.n + 1, c.sum + d
  if d > c.max then c.max = d end
end

function B.prompt()
  if B.listing and B.on() and not elro.offmap and elro.current then
    local t0 = os.clock()
    B.record(elro.current, B.pending, os.time())
    B.time(B.cost, t0)
  end
  B.listing, B.pending = false, {}
end

if type(tempPromptTrigger) == "function" then
  if B.promptT then pcall(killTrigger, B.promptT) end
  B.promptT = tempPromptTrigger(function() B.prompt() end)
end

-- how a row reads: "An orc 9/10", "A ghost 1/12 rare"
function B.describe(r)
  local s = r[1] .. " " .. r[2] .. "/" .. math.max(r[3], r[2])
  if r[4] == "rare" or r[4] == "wanders" then s = s .. " " .. r[4] end
  return s
end

-- the map's info overlay: the clicked room's monsters, most seen first, wanderers left out
local INFO = "Monsters seen"
if type(registerMapInfo) == "function" then
  pcall(registerMapInfo, INFO, function(room)
    local t = room and B.rows(room) or {}
    if #t == 0 then return "" end
    local parts = {}
    for _, r in ipairs(t) do parts[#parts + 1] = B.describe(r) end
    local s = "Seen: " .. table.concat(parts, " \194\183 ")
    if #s > 240 then s = s:sub(1, 237) .. "..." end
    return s, false, false, 230, 140, 140
  end)
  if type(enableMapInfo) == "function" then pcall(enableMapInfo, INFO) end
end

-- mapmobs [on|off|clear [#id]|ignore [name]|unignore <name>]
function elro.cmd_mobs(arg)
  arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local function say(s) cecho("\n<green>[elro]: " .. s .. "\n<reset>") end
  local ign = arg:match("^ignore%s+(.+)$")
  if ign then
    ign = B.clean(ign):lower()
    B.ignored()[ign] = true
    save_ignored()
    -- out of every room it was noted in
    local n = 0
    for id in pairs(elro.cs_all_rooms()) do
      local t, keep = B.list(id), {}
      for _, m in ipairs(t) do if m[1]:lower() ~= ign then keep[#keep + 1] = m end end
      if #keep < #t then store(id, keep) ; n = n + 1 end
    end
    B.idx = nil
    if type(saveMap) == "function" then pcall(saveMap) end
    say(string.format("'%s' is never noted, and was taken out of %d room(s). 'mapmobs unignore %s' undoes it.", ign, n, ign))
    return
  end
  local uni = arg:match("^unignore%s+(.+)$")
  if uni then
    uni = B.clean(uni):lower()
    B.ignored()[uni] = nil
    save_ignored()
    say("'" .. uni .. "' is noted again from now on.")
    return
  end
  if arg == "ignore" then
    local t = {}
    for n in pairs(B.ignored()) do t[#t + 1] = n end
    table.sort(t)
    say(#t == 0 and "no names ignored. 'mapmobs ignore <name>' for a pet or follower."
        or ("never noted: " .. table.concat(t, ", ") .. "."))
    return
  end
  if arg == "on" or arg == "off" then
    B.state = arg == "on"
    pcall(setMapUserData, "elro.mobs", arg)
    if type(saveMap) == "function" then pcall(saveMap) end
    say(B.state and "monsters are noted per room again (in the game's xml mode)."
        or "monsters are no longer noted. Those already noted stay; 'mapmobs clear' empties a room.")
    return
  end
  local hid = arg:match("^clear%s+#?(%d+)$")
  if arg == "clear" or hid then
    local id = hid and tonumber(hid) or elro.current
    if not id or not roomExists(id) then say("no such room; 'mapmobs clear #<id>'.") return end
    setRoomUserData(id, KEY, "") ; setRoomUserData(id, "mobv", "")
    B.idx = nil
    if type(saveMap) == "function" then pcall(saveMap) end
    say(string.format("monsters seen in %d forgotten.", id))
    return
  end
  local rooms, names = 0, 0
  for id in pairs(elro.cs_all_rooms()) do
    local t = B.list(id)
    if #t > 0 then rooms, names = rooms + 1, names + #t end
  end
  say(string.format("monsters are %snoted per room: %d name(s) in %d room(s). Needs the game's"
    .. " xml mode ('toggle xml'). 'mapnotes mobs <name>' finds them.", B.on() and "" or "NOT ", names, rooms))
  local function ms(c, what)
    if c.n == 0 then return end
    cecho(string.format("<grey>  %s: %d time(s), %.3f ms on average, %.3f ms at worst<reset>\n",
      what, c.n, c.sum / c.n * 1000, c.max * 1000))
  end
  ms(B.cost, "noting a room listing")
  if elro.xml and elro.xml.cost then ms(elro.xml.cost, "reading a tagged line") end
end
