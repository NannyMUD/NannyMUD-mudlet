-- mapimport: join another profile's map into this one. Mudlet can only replace a map, so the
-- other map is loaded for a moment, read into a table, and this one loaded back from a save
-- made just before. Rooms and exits are then merged by the rules onRoom follows.

elro.IMPORT_SKIP_UD = { occl = true, lblv = true, mark = true, note = true }

local function say(s) cecho("\n<cyan>[elro]: " .. s .. "\n<reset>") end
local function warn(s) cecho("\n<red>[elro]: " .. s .. "\n<reset>") end

-- A save of this map that nothing else writes to: Mudlet's own saves in the same second
-- would overwrite a file named like theirs. Mudlet starts from the newest file by time.
local function backup_path(tag)
  return getMudletHomeDir() .. "/map/" .. os.date("%Y-%m-%d#%H-%M-%S") .. "-" .. tag .. "map.dat"
end

-- every other profile with a saved map: { name, path, stamp }, newest map file of each
local function map_dir_newest(dir)
  if not (lfs and lfs.dir) then return nil end
  local best, bestT
  local ok = pcall(function()
    for f in lfs.dir(dir) do
      if f:match("%.dat$") then
        local t = lfs.attributes and lfs.attributes(dir .. "/" .. f, "modification") or 0
        if not best or t > bestT or (t == bestT and f > best) then best, bestT = f, t end
      end
    end
  end)
  return ok and best or nil, bestT
end

function elro.import_sources()
  local home = getMudletHomeDir()
  local root, me = home:match("^(.*)[/\\]([^/\\]+)$")
  local out = {}
  if not root or not (lfs and lfs.dir) then return out end
  pcall(function()
    for p in lfs.dir(root) do
      if p ~= "." and p ~= ".." and p ~= me then
        local f, t = map_dir_newest(root .. "/" .. p .. "/map")
        if f then
          out[#out + 1] = { name = p, path = root .. "/" .. p .. "/map/" .. f,
                            stamp = (t and t > 0) and os.date("%Y-%m-%d %H:%M", t) or f }
        end
      end
    end
  end)
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

-- Everything the merge reads, from the map loaded now. Placeholders and maze vertices are
-- not rooms anyone walked.
function elro.import_snapshot()
  local snap = { rooms = {}, mud = {} }
  for id in pairs(getRooms() or {}) do
    if id ~= elro.FRONTIER_ROOM and id ~= elro.OFF_ROOM and id < elro.MAZE_VBASE then
      local x, y, z = getRoomCoordinates(id)
      snap.rooms[id] = {
        name = getRoomName(id), area = getRoomAreaName(getRoomArea(id)) or "",
        x = x, y = y, z = z, ex = {}, ud = getAllRoomUserData(id) or {},
        locked = type(roomLocked) == "function" and roomLocked(id) or false,
      }
      for d, to in pairs(getRoomExits(id) or {}) do snap.rooms[id].ex[d] = to end
    end
  end
  if type(getAllMapUserData) == "function" then
    for k, v in pairs(getAllMapUserData() or {}) do snap.mud[k] = v end
  else
    for _, k in ipairs({ "elro.smap", "elro.decl", "elro.merge", "elro.hintArea", "elro.hintIgnore", "elro.outer" }) do
      snap.mud[k] = getMapUserData(k)
    end
  end
  return snap
end

-- Load `path`, snapshot it, and load this profile's map back from a save made first. The
-- save is named like Mudlet's own, so it is the newest map should anything stop half way.
function elro.import_read(path)
  local backup = backup_path("import-read")
  if not saveMap(backup) then return nil, "could not save this map first, so nothing was read" end
  local ok, snap = pcall(function()
    if not loadMap(path) then error("Mudlet could not load " .. path) end
    return elro.import_snapshot()
  end)
  if not loadMap(backup) then
    return nil, "this map could not be loaded back. Settings, the Mapper tab, 'Load map...' and pick "
      .. backup .. " before you move."
  end
  elro.import_reloaded()
  if not ok then return nil, tostring(snap) end
  return snap
end

-- after loadMap: what was read from the old map is read again from this one
function elro.import_reloaded()
  elro.cs_reset()
  elro.smap, elro.merge, elro.declWait, elro.outerPick = nil, nil, nil, nil
  elro.hints_loaded = nil
  elro._envSession = nil                 -- a loaded map brings its own terrain colours; set ours again
  if elro.current and type(centerview) == "function" then pcall(centerview, elro.current) end
end

local function lines(s)
  local t = {}
  for l in (s or ""):gmatch("[^\n]+") do t[#t + 1] = l end
  return t
end
local function kv(s)
  local t = {}
  for l in (s or ""):gmatch("[^\n]+") do
    local a, b = l:match("^(.-)\t(.*)$")
    if a and a ~= "" then t[a] = b end
  end
  return t
end
local function set_of(s)
  local t = {}
  for w in (s or ""):gmatch("%S+") do t[w] = true end
  return t
end

-- Merge `snap` into this map. dry: count only. Returns the counts. The rules are onRoom's: a
-- room or exit this map lacks is added; where both have an exit, an observed one replaces an
-- assumed one and otherwise this map's stays; a locked exit is never re-pointed. Two maps
-- disagreeing is not counted as a maze mutation: the area may have changed between visits.
-- What the player chose here (areas, settings) stays.
function elro.import_merge(snap, dry)
  local n = { rooms = 0, exits = 0, promoted = 0, kept = 0, specials = 0, marks = 0,
              markClash = 0, notes = 0, avoid = 0, merges = 0, mergeList = {} }
  local new, touched, areas = {}, {}, {}
  if elro.smap == nil then elro.load_smap() end
  if elro.merge == nil then elro.load_merge() end
  if not elro.hints_loaded then elro.load_hints() end
  if elro.outerPick == nil then elro.load_outer() end
  if elro.declWait == nil then elro.load_decl() end

  local ids = {}
  for id in pairs(snap.rooms) do ids[#ids + 1] = id end
  table.sort(ids)

  -- 1. rooms this map has never seen, with everything recorded on them
  for _, id in ipairs(ids) do
    if not roomExists(id) then
      new[id] = true ; n.rooms = n.rooms + 1
      if not dry then
        local s = snap.rooms[id]
        addRoom(id)
        setRoomName(id, s.name or ("room " .. id))
        local an = (s.area ~= "" and s.area ~= elro.FRONTIER_AREA and s.area ~= elro.OFF_AREA) and s.area
          or s.ud.sarea or "world"
        local aid = elro.areaId(an)
        setRoomArea(id, aid) ; areas[aid] = true
        setRoomCoordinates(id, s.x or 0, s.y or 0, s.z or 0)
        for k, v in pairs(s.ud) do
          if not elro.IMPORT_SKIP_UD[k] then setRoomUserData(id, k, v) end
        end
        touched[id] = true
      end
    end
  end
  local function exists(id) return roomExists(id) or new[id] end

  -- 2. exits, compass ones through the observed/assumed rules
  for _, id in ipairs(ids) do
    local s = snap.rooms[id]
    local dirs = {}
    for d in pairs(s.ex) do dirs[#dirs + 1] = d end
    table.sort(dirs)
    for _, d in ipairs(dirs) do
      local to = s.ex[d]
      if elro.dirNum[d] and to ~= elro.FRONTIER_ROOM and (to == elro.OFF_ROOM or exists(to)) then
        local sAsm = s.ud["assumed_" .. d] == "1"
        local tex = (not new[id]) and (getRoomExits(id) or {}) or {}
        local old = tex[d]
        if old == elro.FRONTIER_ROOM then old = nil end
        local tAsm = getRoomUserData(id, "assumed_" .. d) == "1"
        local tMan = (getRoomUserData(id, "manual_" .. d) or "") ~= ""
        local write, flag
        if new[id] then
          write = true                       -- its user data, flags included, is already copied
        elseif not old then
          write, flag = true, sAsm and "1" or ""
          if (s.ud["manual_" .. d] or "") ~= "" and not dry then setRoomUserData(id, "manual_" .. d, s.ud["manual_" .. d]) end
        elseif old == to then
          if tAsm and not sAsm then
            n.promoted = n.promoted + 1
            if not dry then setRoomUserData(id, "assumed_" .. d, "") ; touched[id] = true end
          end
        elseif not tMan and tAsm and not sAsm then
          write, flag = true, ""
          n.promoted = n.promoted + 1
        else
          n.kept = n.kept + 1
        end
        if write then
          n.exits = n.exits + 1
          if not dry then
            if to == elro.OFF_ROOM then elro.off_room() end
            setExit(id, to, d)
            if flag then setRoomUserData(id, "assumed_" .. d, flag) end
            touched[id] = true
          end
        end
      end
    end
  end

  -- 3. what a room carries besides exits, for rooms both maps have
  for _, id in ipairs(ids) do
    local s = snap.rooms[id]
    if not new[id] then
      -- a room this map only knows as where a move came from: the other map's name for it
      if s.name and s.name ~= ("room " .. id) and getRoomName(id) == ("room " .. id) and not dry then
        setRoomName(id, s.name) ; touched[id] = true
      end
      -- anything recorded there that this map has nothing for; exit flags follow the exits
      for k, v in pairs(s.ud) do
        if v ~= "" and not elro.IMPORT_SKIP_UD[k] and not k:match("^assumed_") and not k:match("^manual_")
           and not k:match("^mut") and (getRoomUserData(id, k) or "") == "" and not dry then
          setRoomUserData(id, k, v) ; touched[id] = true
        end
      end
      for k, v in pairs(s.ud) do
        local d = k:match("^mutdst_(.+)$")
        if d and not dry then
          local have, cur = set_of(getRoomUserData(id, k)), getRoomUserData(id, k) or ""
          for w in v:gmatch("%S+") do if not have[w] then cur = (cur == "" and w) or (cur .. " " .. w) end end
          setRoomUserData(id, k, cur)
          local mk = "mut_" .. d
          local a, b = tonumber(getRoomUserData(id, mk)) or 0, tonumber(s.ud[mk]) or 0
          if b > a then setRoomUserData(id, mk, tostring(b)) end
        end
      end
    end
    -- notes: every line this room lacks
    local have = {}
    for _, l in ipairs(elro.note_lines(id)) do have[l] = true end
    local add = {}
    for _, l in ipairs(lines(s.ud.note)) do if not have[l] then add[#add + 1] = l ; have[l] = true end end
    if #add > 0 then
      n.notes = n.notes + #add
      if not dry then
        local t = new[id] and {} or elro.note_lines(id)
        for _, l in ipairs(add) do t[#t + 1] = l end
        setRoomUserData(id, "note", table.concat(t, "\n"))
      end
    end
    -- marks: a name this map already gives another room stays there
    for name in (s.ud.mark or ""):gmatch("%S+") do
      local at = elro.mark_find(name)
      if at and at ~= id then n.markClash = n.markClash + 1
      elseif not at then
        n.marks = n.marks + 1
        if not dry then
          local cur = new[id] and "" or (getRoomUserData(id, "mark") or "")
          setRoomUserData(id, "mark", cur == "" and name or (cur .. " " .. name))
        end
      end
    end
    if s.locked and not (exists(id) and not new[id] and roomLocked(id)) then
      n.avoid = n.avoid + 1
      if not dry and type(lockRoom) == "function" then lockRoom(id, true) end
    end
  end

  -- 4. recorded special exits, and declared ones still waiting for their room
  for k, v in pairs(kv(snap.mud["elro.smap"])) do
    local a, b = k:match("^(%d+):(%d+)$")
    a, b = tonumber(a), tonumber(b)
    if a and b and exists(a) and exists(b) and not elro.smap[k] then
      n.specials = n.specials + 1
      if not dry then
        elro.smap[k] = v
        if type(addSpecialExit) == "function" then pcall(addSpecialExit, a, b, v) end
        touched[a] = true
      end
    end
  end
  if not dry then
    for to, src, dir in (snap.mud["elro.decl"] or ""):gmatch("(%d+)\t(%d+)\t([^\n]+)") do
      to = tonumber(to)
      elro.declWait[to] = elro.declWait[to] or {}
      elro.declWait[to][src .. ":" .. dir] = true
    end
    for to, set in pairs(elro.declWait) do
      if roomExists(to) then
        for k in pairs(set) do
          local src, d = k:match("^(%d+):(.+)$")
          src = tonumber(src)
          if src and roomExists(src) then elro.decl_link(src, d, to, touched) ; set[k] = nil end
        end
        if next(set) == nil then elro.declWait[to] = nil end
      end
    end
  end

  -- 5. the other map's area merges and hint choices, for areas this map says nothing about
  for a, b in pairs(kv(snap.mud["elro.merge"])) do
    if elro.merge[a] == nil then
      n.merges = n.merges + 1
      n.mergeList[#n.mergeList + 1] = { a, b }
      if not dry then elro.merge[a] = b end
    end
  end
  if not dry then
    for a, b in pairs(kv(snap.mud["elro.hintIgnore"])) do
      if elro.hintIgnore[a] == nil then elro.hintIgnore[a] = b end
    end
    for a, b in pairs(kv(snap.mud["elro.hintArea"])) do
      if elro.hintArea[a] == nil then elro.hintArea[a] = b end
    end
    for w in (snap.mud["elro.outer"] or ""):gmatch("%d+") do
      if roomExists(tonumber(w)) then elro.outerPick[tonumber(w)] = true end
    end
  end

  if dry then return n end

  -- 6. derived state, saved, and laid out like any new exploring
  elro.smap_index_dirty()
  elro.save_smap() ; elro.save_decl() ; elro.save_merge() ; elro.save_hints() ; elro.save_outer()
  elro.cs_reset() ; elro.cs_lists_dirty()
  for id in pairs(touched) do
    if roomExists(id) then
      elro.stub_apply(id)
      elro.glyph_room(id)
      local t = getRoomUserData(id, "terr")
      if t and t ~= "" then elro.terrain_paint(id, t) end
      areas[getRoomArea(id)] = true
    end
  end
  for aid in pairs(areas) do if aid and aid > 0 then elro.dirty[aid] = true end end
  elro.mark_aliases_rebuild()
  if type(saveMap) == "function" then pcall(saveMap) end
  elro.flush_dirty()
  return n
end

local function report(n, name, dry)
  local parts = {
    string.format("%d new room(s)", n.rooms), string.format("%d exit(s)", n.exits),
    string.format("%d exit(s) confirmed", n.promoted), string.format("%d special exit(s)", n.specials),
    string.format("%d mark(s)", n.marks), string.format("%d note line(s)", n.notes),
    string.format("%d avoided room(s)", n.avoid), string.format("%d area merge(s)", n.merges),
  }
  cecho(string.format("\n<cyan>[elro]: %s from '%s': %s.<reset>\n", dry and "would add" or "added",
        name, table.concat(parts, ", ")))
  if n.kept > 0 then
    cecho(string.format("  %d exit(s) lead somewhere else on this map; this map's are kept.\n", n.kept))
  end
  if n.markClash > 0 then
    cecho(string.format("  %d mark name(s) are already used here for another room; this map's are kept.\n", n.markClash))
  end
  table.sort(n.mergeList, function(a, b) return a[1] < b[1] end)
  for _, m in ipairs(n.mergeList) do
    cecho("  The other map draws '" .. m[1] .. "' into '" .. m[2] .. "', and so will this one"
          .. (dry and "" or "; 'mapunmerge " .. m[1] .. "' undoes it") .. ".\n")
  end
end

-- mapimport undo: back to the map saved at the last confirm in this session
function elro.import_undo()
  local u = elro._importUndo
  if not u then warn("nothing to undo: no map was imported in this session.") return end
  if (elro.walk_busy and elro.walk_busy()) or elro.rec then
    warn("not while walking or recording; try again in a moment.") return
  end
  elro.bg_cancel(true)
  if not loadMap(u.path) then
    warn("Mudlet could not load " .. u.path .. ". Settings, the Mapper tab, 'Load map...' can try it by hand.")
    return
  end
  elro._importUndo = nil
  elro.import_reloaded()
  elro.mark_aliases_rebuild()
  if type(saveMap) == "function" then pcall(saveMap) end
  say("the map is back as it was before importing '" .. u.name .. "'.")
end

-- mapimport                    the profiles with a map to import
-- mapimport <profile>          what an import would add (nothing is changed)
-- mapimport <profile> confirm  do it
-- mapimport undo               put back the map saved just before it
function elro.cmd_import(arg)
  arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if arg == "undo" then return elro.import_undo() end
  local confirm = arg:match("%s+confirm$") ~= nil
  local want = (arg:gsub("%s+confirm$", "")):lower()
  local srcs = elro.import_sources()
  if want == "" then
    if #srcs == 0 then say("no other profile has a saved map.") return end
    cecho("\n<cyan>[elro] profiles with a map ('mapimport <name>' shows what it would add):<reset>\n")
    for _, s in ipairs(srcs) do cecho(string.format("  <yellow>%-28s<reset> saved %s\n", s.name, s.stamp)) end
    return
  end
  local pick, many = nil, {}
  for _, s in ipairs(srcs) do
    if s.name:lower() == want then pick = s ; many = { s } ; break end
    if s.name:lower():find(want, 1, true) then many[#many + 1] = s end
  end
  pick = pick or (#many == 1 and many[1]) or nil
  if not pick then
    if #many > 1 then
      local names = {}
      for _, s in ipairs(many) do names[#names + 1] = s.name end
      warn("'" .. want .. "' matches " .. table.concat(names, ", ") .. "; say which.")
    else warn("no profile with a map called '" .. want .. "'. 'mapimport' lists them.") end
    return
  end
  if (elro.walk_busy and elro.walk_busy()) or elro.rec or elro.bg_busy() then
    warn("not while walking, recording or laying out; try again in a moment.") return
  end
  local c = elro._importCache
  local snap
  if c and c.path == pick.path and os.time() - c.at < 600 then snap = c.snap
  else
    local err
    snap, err = elro.import_read(pick.path)
    if not snap then warn(err) return end
    elro._importCache = { path = pick.path, at = os.time(), snap = snap }
  end
  if not confirm then
    report(elro.import_merge(snap, true), pick.name, true)
    cecho(string.format("  That is %s's map as saved %s; close that profile first for its latest.\n"
          .. "  'mapimport %s confirm' adds it. Your map is saved first, and 'mapimport undo' puts it back.\n",
          pick.name, pick.stamp, pick.name))
    return
  end
  elro._importCache = nil
  elro.import_confirm(snap, pick.name)
end

-- save this map where undo finds it, then merge
function elro.import_confirm(snap, name)
  local backup = backup_path("before-import")
  if not saveMap(backup) then warn("could not save this map first, so nothing was imported.") return nil end
  elro._importUndo = { path = backup, name = name }
  local n = elro.import_merge(snap, false)
  report(n, name, false)
  cecho("  The new rooms are being laid out in the background; keep playing.\n"
        .. "  'mapimport undo' puts back the map from before, losing anything explored since. It was saved as\n  "
        .. backup .. "\n")
  return n
end
