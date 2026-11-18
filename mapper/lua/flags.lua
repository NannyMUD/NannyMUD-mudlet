-- Flags: the name of the area a blue cross-area stub leads to, as a small map label at the
-- stub's tip. Off unless 'mapflags on'. Mudlet saves labels with the map, so every flag's text
-- starts with an invisible marker: a sweep finds and deletes all of ours, and nothing else.

elro.flags = elro.flags or {}
local F = elro.flags
F.MARK = "\226\128\139\226\128\140"          -- zero-width space + zero-width non-joiner
F.at = F.at or {}                            -- [room][dir] = { area, label id, rect }
-- a label is a picture drawn at this font and stretched to the map: a big font shrunk stays
-- sharp, a small one enlarged blurs. The zoom (higher is smaller) is corrected by measure.
F.font = F.font or 24
F.zoom = F.zoom or 120
F.chars = F.chars or 12
F.height = F.height or 0.32                  -- a flag's height in map units (a room is 1 apart)
F.stats = F.stats or { tried = 0, made = 0, failed = 0, err = nil }
-- one character's size in map units: Mudlet's own label size does not follow font and zoom
-- alike in every profile, so each flag is read back (measure) and these follow what it says
local function cw() return F.cw or 0.12 end
local function ch() return F.ch or F.height end

-- label `lid`'s drawn width and height, from Mudlet, or nil
local function measure(aid, lid)
  if type(getMapLabel) ~= "function" then return nil end
  local ok, L = pcall(getMapLabel, aid, lid)
  local w = ok and type(L) == "table" and tonumber(L.Width or L.width)
  local h = ok and type(L) == "table" and tonumber(L.Height or L.height)
  if not w or not h or w <= 0 or h <= 0 then return nil end
  return w, h
end

function F.on()
  if F.state == nil then
    local ok, s = pcall(getMapUserData, "elro.flags")
    F.state = ok and s == "on"
  end
  return F.state
end

local function is_ours(text) return type(text) == "string" and text:sub(1, #F.MARK) == F.MARK end

local function delete(aid, lid)
  if type(deleteMapLabel) == "function" then pcall(deleteMapLabel, aid, lid) end
end

-- every flag in every area, including ones left in the map file by an earlier session
function F.sweep()
  F.at, F.cells = {}, {}
  if type(getMapLabels) ~= "function" or type(getAreaTable) ~= "function" then return 0 end
  local n = 0
  for _, aid in pairs(getAreaTable() or {}) do
    local ok, ls = pcall(getMapLabels, aid)
    if ok and type(ls) == "table" then
      for lid, text in pairs(ls) do
        if is_ours(text) then delete(aid, lid) ; n = n + 1 end
      end
    end
  end
  return n
end

-- the flags of these rooms, before they are drawn again
function F.clear(roomMap)
  F.cells = {}                               -- rooms may have moved: occupancy is read afresh
  for r in pairs(roomMap) do
    for _, L in pairs(F.at[r] or {}) do delete(L[1], L[2]) end
    F.at[r] = nil
  end
end

-- the cells of an area holding a room, read once per drawing
local function cells(aid)
  local c = F.cells[aid]
  if c then return c end
  c = {}
  for _, r in ipairs(elro.cs_area_rooms(aid)) do
    local x, y, z = getRoomCoordinates(r)
    if x then c[math.floor(x + 0.5) .. ":" .. math.floor(y + 0.5) .. ":" .. (z or 0)] = true end
  end
  F.cells[aid] = c
  return c
end

-- how much a label's rectangle (x0, y0 top-left; y grows up) covers: rooms count double,
-- other flags once
local function cover(aid, z, x0, y0, w, h)
  local c = cells(aid)
  local R = 0.35                             -- a room's drawn radius, about
  local n = 0
  for gx = math.floor(x0 - R + 0.5), math.floor(x0 + w + R + 0.5) do
    for gy = math.floor(y0 - h - R + 0.5), math.floor(y0 + R + 0.5) do
      if c[gx .. ":" .. gy .. ":" .. z]
         and gx + R > x0 and gx - R < x0 + w and gy + R > y0 - h and gy - R < y0 then
        n = n + 2
      end
    end
  end
  -- a margin: the drawn text runs a little past the size Mudlet reports
  local M = 0.1
  for _, byDir in pairs(F.at) do
    for _, L in pairs(byDir) do
      local q = L[3]
      if L[1] == aid and q[5] == z and q[1] - M < x0 + w and q[1] + q[3] + M > x0
         and q[2] - q[4] - M < y0 and q[2] + M > y0 - h then
        n = n + 1
      end
    end
  end
  return n
end

-- whether a flag with this name already stands within two cells of the tip
local function said_nearby(aid, z, name, hx, hy)
  for _, byDir in pairs(F.at) do
    for _, L in pairs(byDir) do
      local q = L[3]
      if L[1] == aid and q[5] == z and q[6] == name
         and math.abs(q[1] + q[3] / 2 - hx) <= 2 and math.abs(q[2] - q[4] / 2 - hy) <= 2 then
        return true
      end
    end
  end
  return false
end

-- where a flag may go, best first: past the tip along the stub, then beside the stub
local function spots(del, hx, hy, w, h, g)
  local dx, dy = del[1], del[2]
  local out = {}
  local function at(x, y) out[#out + 1] = { x, y } end
  local ax = dx > 0 and hx + g or dx < 0 and hx - w - g or hx - w / 2
  local ay = dy > 0 and hy + h + g or dy < 0 and hy - g or hy + h / 2
  at(ax, ay)
  if dy == 0 then
    at(ax, hy + h + g) ; at(ax, hy - g)                          -- above, below
  elseif dx == 0 then
    at(hx + g, ay) ; at(hx - w - g, ay)                          -- right, left
  else
    at(ax, hy + h / 2) ; at(hx - w / 2, ay)
  end
  -- the same again half a cell further out, for a crowded spot
  local n = #out
  for i = 1, n do out[#out + 1] = { out[i][1] + dx * 0.5, out[i][2] + dy * 0.5 } end
  return out
end

-- a flag for the stub of `room` going `d` (delta del) to `dest`; the stub tip is (hx, hy)
function F.add(room, d, del, dest, hx, hy, z)
  if not F.on() or type(createMapLabel) ~= "function" then return end
  F.stats.tried = F.stats.tried + 1
  local name = elro.areaName and elro.areaName(getRoomArea(dest))
  if not name or name == "" then F.stats.failed = F.stats.failed + 1 ; F.stats.err = "no area name" return end
  if #name > F.chars then name = name:sub(1, F.chars - 1) .. "." end
  local aid = getRoomArea(room)
  if said_nearby(aid, z, name, hx, hy) then F.stats.shared = (F.stats.shared or 0) + 1 return end
  local w, h, pick, ok, lid
  for try = 1, 3 do
    w, h = #name * cw(), ch()
    -- the spot covering least, the first of equals
    local best
    for _, s in ipairs(spots(del, hx, hy, w, h, 0.05)) do
      local n = cover(aid, z, s[1], s[2], w, h)
      if not best or n < best then best, pick = n, s end
      if n == 0 then break end
    end
    ok, lid = pcall(createMapLabel, aid, F.MARK .. name, pick[1], pick[2], z,
                    255, 255, 255, 40, 90, 170, F.zoom, F.font, true, false)
    if not ok or lid == nil or (tonumber(lid) or 0) < 0 then
      F.stats.failed = F.stats.failed + 1 ; F.stats.err = tostring(lid)
      return
    end
    -- the real size: a wrong height corrects the zoom, a wrong guess places it again
    local mw, mh = measure(aid, lid)
    if not mw then break end
    local scale = F.height / mh
    if math.abs(scale - 1) > 0.15 then F.zoom = math.max(10, math.min(400, F.zoom / scale)) end
    F.cw, F.ch = mw / #name * scale, mh * scale
    local good = math.abs(scale - 1) <= 0.15 and math.abs(mw - w) <= 0.15 * w + 0.05
                 and math.abs(mh - h) <= 0.15 * h + 0.05
    if good or try == 3 then w, h = mw, mh ; break end
    delete(aid, lid)
  end
  F.stats.made = F.stats.made + 1
  F.at[room] = F.at[room] or {}
  local old = F.at[room][d]
  if old then delete(old[1], old[2]) end
  F.at[room][d] = { aid, lid, { pick[1], pick[2], w, h, z, name } }
end

-- every room's flags again, after a sweep or the switch
function F.redraw_all()
  F.sweep()
  F.stats = { tried = 0, made = 0, failed = 0, err = nil }
  if F.on() and elro.draw_area_stubs then
    local all = {}
    for id in pairs(elro.cs_all_rooms()) do all[id] = true end
    elro.draw_area_stubs(all)
  end
  if type(updateMap) == "function" then pcall(updateMap) end
end

function elro.cmd_flags(arg)
  arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if arg ~= "on" and arg ~= "off" then
    local s = F.stats
    cecho(string.format("\n<green>[elro]: area flags %s. 'mapflags %s' to change it.\n<reset>",
      F.on() and "on" or "off", F.on() and "off" or "on"))
    cecho(string.format("<grey>  last drawing: %d arrow(s), %d flag(s) made, %d left out as a nearby flag says it, %d failed%s<reset>\n",
      s.tried, s.made, s.shared or 0, s.failed, s.err and (" (" .. s.err .. ")") or ""))
    cecho(string.format("<grey>  size: %.2f high, %.2f a letter (zoom %.0f, font %d)%s<reset>\n",
      ch(), cw(), F.zoom, F.font, F.cw and "" or ", not measured yet"))
    return
  end
  F.state = arg == "on"
  pcall(setMapUserData, "elro.flags", arg)
  F.redraw_all()
  if type(saveMap) == "function" then pcall(saveMap) end
  cecho(F.state and "\n<green>[elro]: area flags ON: each blue arrow out of an area carries the name of the area it leads to.\n<reset>"
        or "\n<green>[elro]: area flags OFF. Click a room to see where its arrows lead.\n<reset>")
end

-- once the map is loaded: clear what an earlier session left, and draw them again if on
if type(tempTimer) == "function" then tempTimer(3, function() F.state = nil ; F.redraw_all() end) end
