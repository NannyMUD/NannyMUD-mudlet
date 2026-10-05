-- mapwin: the map as a small resizable window pinned over the top right of the session's text.

elro = elro or {}

local BOX, MAPPER = "elroMinimap", "elroMinimapMapper"
local DEFAULT_W, DEFAULT_H = 380, 380
local DOCK_W = 0.5                 -- default docked-panel width, as a fraction of the window width

local function say(s) cecho("\n<green>[elro]: " .. s .. "\n<reset>") end

-- Mudlet's generic_mapper answers mapOpenEvent with a 'look' and its quick-start help. Its
-- handler is registered by NAME, so wrapping the global mutes that one event and leaves
-- the package installed and untouched.
local function quietly(fn)
  local orig = type(map) == "table" and map.eventHandler
  if type(orig) == "function" and type(tempTimer) == "function" then
    map.eventHandler = function(event, ...)
      if event == "mapOpenEvent" then return end
      return orig(event, ...)
    end
    tempTimer(0.5, function() map.eventHandler = orig end)
  end
  fn()
end

-- calcFontSize rounds to whole pixels; measured at ten times the size it keeps one decimal.
local function char_width()
  local ok, w = pcall(function()
    return (calcFontSize(getFontSize("main") * 10, getFont("main"))) / 10
  end)
  if ok and type(w) == "number" and w > 0 then return w end
  return (calcFontSize("main"))
end

-- Right edge of THIS session's text, left of the scrollbar, in Geyser's coordinates.
-- getMainWindowSize is exact when it is this pane, but a session that began in single view
-- keeps reporting the whole window under MultiView. It is believed only when it agrees with
-- the column count, and each time it is, it calibrates the cell width the fallback uses
-- (calcFontSize reads 11.3 where the real cell is 11.46).
local SCROLLBAR = 17
local function pane_width()
  local full = (getMainWindowSize())
  local ok, cols = pcall(getColumnCount, "main")
  if not ok or type(cols) ~= "number" or cols <= 0 then return full - SCROLLBAR end
  local l = type(getBorderLeft) == "function" and getBorderLeft() or 0
  local r = type(getBorderRight) == "function" and getBorderRight() or 0
  local base = char_width()
  if elro._winCwBase ~= base then elro._winCw, elro._winCwBase = nil, base end
  local est = l + cols * base
  local text = full - SCROLLBAR - r
  if text >= est and text <= est * 1.06 then
    local cw = (text - l) / cols
    if not elro._winCw or cw < elro._winCw then elro._winCw = cw end
    return math.floor(text)
  end
  return math.floor(l + cols * (elro._winCw or base))
end

-- Where the box's left edge belongs. elro.miniLeft is read back from the saved x at build.
local function want_x(box, pw)
  if elro.miniLeft then return type(getBorderLeft) == "function" and getBorderLeft() or 0 end
  return math.max(0, pw - box:get_width())
end

-- The embedded mapper is a widget Mudlet also resizes on its own (seen after focus changes:
-- it painted black over part of the text, outside its frame). Geyser's reposition is a
-- createMapper at the frame's geometry, which with the widget already made is a resize.
local function refit()
  if elro.miniMap and not (elro.miniMap.hidden or elro.miniMap.auto_hidden) then
    pcall(function() elro.miniMap:reposition() end)
  end
end

-- Keep the size the player chose, in pixels, and pin the corner.
local function anchor()
  if elro._mapDock then return end           -- the dock drives its own geometry
  local box = elro.miniBox
  if not box or box.hidden or box.auto_hidden or box.minimized then return end
  local pw = pane_width()
  box:resize(math.min(box:get_width(), pw), box:get_height())
  box:move(want_x(box, pw), 0)
  refit()
end

-- A session opening beside this one raises no resize event, so once a second while the
-- window is up, check that it is still in its corner. Ends when it is closed.
local function watch()
  if elro._winWatch or type(tempTimer) ~= "function" then return end
  local function tick()
    elro._winWatch = nil
    local box = elro.miniBox
    if not box or box.hidden or box.auto_hidden then return end
    local ok, off = pcall(function() return box:get_x() - want_x(box, pane_width()) end)
    if ok and not box.minimized and math.abs(off) > 1 then anchor() else refit() end
    elro._winWatch = tempTimer(1, tick)
  end
  tick()
end

local function save_path()
  return getMudletHomeDir() .. "/AdjustableContainer/" .. BOX .. ".lua"
end

-- The container's own save file is the record: no file means never opened.
local function was_open()
  if type(io.exists) ~= "function" or not io.exists(save_path()) then return false end
  local t = {}
  if not pcall(table.load, save_path(), t) then return false end
  return not t.hidden
end

-- The side is not stored separately: a box saved at the left edge is a left box.
local function saved_left()
  if type(io.exists) ~= "function" or not io.exists(save_path()) then return false end
  local t = {}
  if not pcall(table.load, save_path(), t) then return false end
  local x = tonumber((tostring(t.x):match("^(-?[%d%.]+)")))
  local l = type(getBorderLeft) == "function" and getBorderLeft() or 0
  return x ~= nil and x <= l
end

-- createMapper can refuse by returning nil and a message, without throwing, and Geyser does
-- not look. Asked at zero size before anything is built; returns Mudlet's reason on a refusal.
local function can_embed()
  local made, why = false, nil
  quietly(function()
    local ok, res, msg = pcall(createMapper, 0, 0, 0, 0)
    made = (ok and res == true) or (type(raiseWindow) == "function" and raiseWindow("mapper") == true)
    if not made then why = tostring((ok and msg) or res or "no reason given") end
  end)
  return made, why
end

local function build()
  -- Mudlet's own map window holds the profile's one map widget, and an older version (or the
  -- Map button) may have left it open across a mapupdate; ours would then stay blank.
  if type(closeMapWidget) == "function" then pcall(closeMapWidget) ; elro._dockOpen = false end
  if not can_embed() then return false end
  elro.miniLeft = saved_left()
  quietly(function()
    elro.miniBox = Adjustable.Container:new({
      name = BOX, titleText = "Map", padding = 4,
      x = 0, y = 0, width = DEFAULT_W, height = DEFAULT_H,
      autoSave = true, autoLoad = true,
    })
    elro.miniMap = Geyser.Mapper:new({
      name = MAPPER, x = 0, y = 0, width = "100%", height = "100%",
    }, elro.miniBox)
  end)
  return true
end

-- Mudlet's own banner (name / id (area)) fills a small map, and its font cannot be set.
-- Swap it for name / id; the map's right-click menu still switches either.
local INFO = "Room name"
local function compact_banner()
  if type(enableMapInfo) ~= "function" or type(disableMapInfo) ~= "function" then return end
  pcall(disableMapInfo, "Short")
  pcall(disableMapInfo, "Full")
  pcall(enableMapInfo, INFO)
end

if type(registerMapInfo) == "function" then
  pcall(registerMapInfo, INFO, function(room)
    -- the id too: it is what mapgoto and mapavoid take
    return room and (tostring(getRoomName(room) or "") .. " / " .. tostring(room)) or "",
           false, false, 255, 255, 255
  end)
end

-- Docked, the map's title strip names the room instead, so the banner goes; it comes back when
-- the map leaves the dock.
local function banner_off()
  if type(disableMapInfo) ~= "function" then return end
  for _, k in ipairs({ "Short", "Full", INFO }) do pcall(disableMapInfo, k) end
end

local function html(s) return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end

local function show()
  elro.miniBox:show()
  anchor()
  watch()
  -- The container is a black label under the map; nothing guarantees the map stacks above it.
  if elro.miniMap and type(raiseWindow) == "function" then pcall(raiseWindow, "mapper") end
  -- view_room, not elro.current: off the map the view belongs on the placeholder. At load
  -- no room has arrived yet, and Mudlet's own last position is the next best thing.
  local at = elro.view_room() or (type(getPlayerRoom) == "function" and getPlayerRoom()) or nil
  if at and type(centerview) == "function" then pcall(centerview, at) end
end

-- Mudlet's own map widget, what the Map button opens: docked or floating as Mudlet last had
-- it, size and place remembered by Mudlet. The default since the embedded form lost
-- console paints (rows of text never drawn while it was up; see DESIGN.md).
local function dock_open()
  quietly(function() pcall(openMapWidget) end)
  elro._dockOpen = true
  local at = elro.view_room() or (type(getPlayerRoom) == "function" and getPlayerRoom()) or nil
  if at and type(centerview) == "function" then pcall(centerview, at) end
end
local function dock_close()
  pcall(closeMapWidget)
  elro._dockOpen = false
end
-- Whether the player closed the docked map with 'mapwin': the one state Mudlet does not
-- keep for us across restarts. The file exists while it is closed by choice.
local function dock_closed_marker() return getMudletHomeDir() .. "/elro_export/.mapwin_closed" end
local function dock_remember(closed)
  local dir = getMudletHomeDir() .. "/elro_export"
  if lfs and lfs.mkdir then pcall(lfs.mkdir, dir) end
  if closed then
    local f = io.open(dock_closed_marker(), "w")
    if f then f:write(os.date()) ; f:close() end
  else
    pcall(os.remove, dock_closed_marker())
  end
end

-- The map's chosen mode persists across restarts (the Adjustable box is "shown" for both dock
-- and embed, so its save file cannot tell them apart). "dock" is the default when nothing is set.
local function mode_path() return getMudletHomeDir() .. "/elro_export/.mapmode" end
local function set_mode(m)
  local dir = getMudletHomeDir() .. "/elro_export"
  if lfs and lfs.mkdir then pcall(lfs.mkdir, dir) end
  local f = io.open(mode_path(), "w") ; if f then f:write(m) ; f:close() end
end
local function get_mode()
  local ok, f = pcall(io.open, mode_path(), "r") ; if not ok or not f then return nil end
  local m = f:read("*l") ; f:close()
  return m and (m:gsub("%s", "")) or nil
end

-- ================= the docked map =================================================
-- Unlike 'mapwin embed', which floats the window over the text, the dock registers the map
-- as a slot on the right edge through the border coordinator (border.lua). It shares that
-- column with any other package's slots (e.g. NannyBasics' chat), stacked -- map on top. It
-- reuses the embedded window's box and mapper, so the singleton map widget is never
-- reparented; the coordinator just moves and resizes the box into its slot.
local DOCK = "elromap:map"
local function dock_fit(x, y, w, h)
  if not elro.miniBox or w <= 0 or h <= 0 then return end
  pcall(function() elro.miniBox:move(x, y) ; elro.miniBox:resize(w, h) end)
  -- refit is a createMapper at the new frame; skip it on the per-tick layouts of a live drag,
  -- the coordinator's final apply (drag end) does it once.
  if not (type(MudletBorders) == "table" and MudletBorders.is_dragging()) then refit() end
end

local function dock_slot()
  MudletBorders.slot(DOCK, {
    cell = "map", cross = elro._dockW or DOCK_W, hint = nil,   -- the map cell (top of the panel)
    order = 0, title = elro._dockTitle or "Map", cb = dock_fit,
  })
end

-- The strip over the docked map names the room the view is on. Called on every move.
function elro.dock_title(id)
  if not elro._mapDock or type(MudletBorders) ~= "table" or not MudletBorders.set_title then return end
  id = id or elro.view_room()
  local t = "Map"
  if id == elro.OFF_ROOM then t = "Map &#183; off the map"
  elseif id and roomExists(id) then
    local an = getRoomAreaName(getRoomArea(id))
    t = "Map &#183; " .. html(getRoomName(id) or "") .. " &#183; " .. id
      .. ((type(an) == "string" and an ~= "") and (" &#183; " .. html(an)) or "")
  end
  elro._dockTitle = t
  MudletBorders.set_title(DOCK, t)
end

-- leaving the dock: the strip goes with it, so the banner comes back
local function undock()
  elro._mapDock = false
  pcall(MudletBorders.remove, DOCK)
  compact_banner()
end

function elro.mapwin_dock(arg)
  if type(Adjustable) ~= "table" or not Geyser.Mapper or type(MudletBorders) ~= "table" then
    cecho("\n<red>[elro]: this Mudlet is too old for the docked map (needs 4.8).\n<reset>") return
  end
  -- 'mapwin dock' with the dock already up closes it and gives the border back.
  if elro._mapDock and arg == nil then
    undock()
    if elro.miniBox then pcall(function() elro.miniBox:unlockContainer() ; elro.miniBox:hide() end) end
    set_mode("off")
    say("map dock closed, border released. 'mapwin dock' reopens it, 'mapwin embed' is the floating one.")
    return
  end
  local can, why = can_embed()
  if not can then
    cecho("\n<red>[elro]: Mudlet would not put the map in a window (" .. why .. "). Its own Map "
      .. "button still works.\n<reset>")
    return
  end
  if not elro.miniBox then build() end
  local box = elro.miniBox
  -- A dock size of its own: the embedded window's saved size is unrelated and can be huge.
  if tonumber(arg) then MudletBorders.clear_width("right") end  -- explicit width wins over a drag
  elro._dockW = tonumber(arg) or elro._dockW or DOCK_W
  elro._mapDock = true
  set_mode("dock")
  quietly(function()
    box:show()
    if box.minimized then box:restore() end
    box:lockContainer("full")
  end)
  -- the box restores its own saved state, hidden included; record it shown so a restore that
  -- lands after this (seen at start-up) does not hide the docked map
  pcall(function() box:save() end)
  dock_slot()                                         -- reserves the edge and lays it out
  banner_off()
  if elro.miniMap and type(raiseWindow) == "function" then pcall(raiseWindow, "mapper") end
  local at = elro.view_room() or (type(getPlayerRoom) == "function" and getPlayerRoom()) or nil
  if at and type(centerview) == "function" then pcall(centerview, at) end
  elro.dock_title(at)
  local wpx = (type(MudletBorders) == "table" and MudletBorders.total("right")) or 0
  say("map docked on the right (" .. wpx .. "px), frameless, sharing the column with any panes. "
    .. "'mapwin dock <width>' resizes it, 'mapwin dock' again closes it.")
end

function elro.mapwin(arg)
  if type(openMapWidget) ~= "function" or type(closeMapWidget) ~= "function" then
    cecho("\n<red>[elro]: this Mudlet is too old for mapwin (needs 4.8).\n<reset>") return
  end
  local embedded = elro.miniBox and not (elro.miniBox.hidden or elro.miniBox.auto_hidden)
  if arg and arg:match("^dock") then
    dock_close()
    return elro.mapwin_dock(arg:match("^dock%s+(%d+)$"))
  end
  if elro._mapDock then                       -- any other mapwin verb leaves the dock first
    undock()
    if elro.miniBox then pcall(function() elro.miniBox:unlockContainer() end) end
  end
  if arg == "embed" then
    dock_close()
    return elro.mapwin_embed(nil)
  elseif arg ~= nil and not embedded then
    say("'mapwin " .. arg .. "' applies to the embedded window ('mapwin embed'). The map you "
      .. "have is Mudlet's own: drag its title bar to float it, resize it by its edges, the Map "
      .. "button or 'mapwin' closes it.")
    return
  elseif arg == nil and not embedded then
    -- one map widget per profile: once it has been inside our label it stays bound there
    if elro.miniBox then
      say("the map is still bound to the embedded window from earlier in this session, and "
        .. "Mudlet cannot dock it again until it restarts. Restart Mudlet and type 'mapwin', "
        .. "or 'mapwin embed' to use the small window now.")
      return
    end
    if elro._dockOpen then dock_close() ; dock_remember(true) else
      dock_open() ; dock_remember(false)
      say("map open. Drag its title bar to float it, or dock it to a side; 'mapwin' again "
        .. "closes it. 'mapwin embed' is the small window over the text instead.")
    end
    return
  end
  return elro.mapwin_embed(arg)
end

function elro.mapwin_embed(arg)
  if type(Adjustable) ~= "table" or type(Geyser) ~= "table" or not Geyser.Mapper then
    cecho("\n<red>[elro]: this Mudlet is too old for the embedded window (needs 4.8).\n<reset>") return
  end
  local can, why = can_embed()
  if not can then
    if elro.miniBox then elro.miniBox:hide() end
    cecho("\n<red>[elro]: Mudlet would not put the map in a window (" .. why .. "). Its own Map "
      .. "button still works. To change over: close that Map, restart Mudlet, type 'mapwin'.\n<reset>")
    return
  end
  local fresh = not elro.miniBox
  local first = type(io.exists) == "function" and not io.exists(save_path())
  if fresh then build() end
  local box = elro.miniBox
  if first or arg == "reset" then compact_banner() end
  if arg == "reset" then
    elro.miniLeft = false
    box:detach()
    box:unlockContainer()
    if box.minimized then box:restore() end
    box:resize(DEFAULT_W, DEFAULT_H)
    quietly(show)
    say("map window back to its first size in the top right corner, unlocked.")
  elseif arg == "lock" then
    quietly(show)
    box:lockContainer("full")
    say("map window locked: no frame, and it cannot be resized. 'mapwin unlock' undoes it.")
  elseif arg == "unlock" then
    box:unlockContainer()
    quietly(show)
    say("map window unlocked: drag its inner or bottom edge to resize it.")
  elseif arg == "left" or arg == "right" then
    elro.miniLeft = (arg == "left")
    quietly(show)
    say("map window in the top " .. arg .. " corner.")
  elseif fresh then
    show()
    say("map window open. Drag its inner or bottom edge to resize it, 'mapwin left' moves it "
      .. "to the other corner, 'mapwin lock' removes the frame, 'mapwin' again closes it.")
  elseif box.hidden or box.auto_hidden then
    quietly(show)
  else
    box:hide()
  end
  box:save()
  set_mode((elro.miniBox and not (elro.miniBox.hidden or elro.miniBox.auto_hidden)) and "embed" or "off")
end

-- Open on a first install, afterwards only what the player left open. Type-guarded for the
-- offline harness.
function elro.mapwin_boot()
  if elro.miniBox or type(Adjustable) ~= "table" or type(getMudletHomeDir) ~= "function" then return end
  if type(io.exists) ~= "function" then return end
  local mode = get_mode()
  -- a player who chose the floating window keeps it
  if mode == "embed" then
    if not build() then return end
    show()
    return
  end
  if mode == "off" then return end     -- closed by choice
  -- otherwise the docked panel: the default on a first start and whenever "dock" was the last mode
  if type(MudletBorders) ~= "table" then return end
  local first = not io.exists(getMudletHomeDir() .. "/elro_export/.mapwin_seen")
  if first then
    local dir = getMudletHomeDir() .. "/elro_export"
    if lfs and lfs.mkdir then pcall(lfs.mkdir, dir) end
    local f = io.open(dir .. "/.mapwin_seen", "w")
    if f then f:write(os.date()) ; f:close() end
  end
  elro.mapwin_dock(nil)
  -- and if something hid the box after all, show it again once start-up has settled
  for _, t in ipairs({ 1, 3 }) do
    tempTimer(t, function()
      local b = elro.miniBox
      if not (elro._mapDock and b and (b.hidden or b.auto_hidden)) then return end
      quietly(function() b:show() ; b:lockContainer("full") end)
      pcall(function() b:save() end)
      dock_slot()
      if type(raiseWindow) == "function" then pcall(raiseWindow, "mapper") end
    end)
  end
  if first then
    say("this is the map, docked in a panel on the right; drag the bars to resize it, 'mapwin "
      .. "dock' closes it, 'mapwin embed' floats it instead, 'maphelp' has the rest.")
  end
end

-- A reload or reinstall keeps the window (elro survives) but not this module's timer chain.
if elro._winWatch and type(killTimer) == "function" then pcall(killTimer, elro._winWatch) end
elro._winWatch = nil
-- 1.2.0 could leave an empty frame behind; the zero-size probe also needs the map put back.
-- A reload keeps elro._mapDock but not the coordinator's callback or the frameless lock, so
-- the dock is re-established here rather than through the float path.
if elro._mapDock and type(MudletBorders) == "table" then
  if not can_embed() then
    undock()
    if elro.miniBox then pcall(function() elro.miniBox:hide() end) end
  else
    pcall(function() elro.miniBox:show() ; elro.miniBox:lockContainer("full") end)
    dock_slot()
    banner_off()
    elro.dock_title()
  end
elseif elro.miniBox and type(createMapper) == "function" then
  if not can_embed() then elro.miniBox:hide()
  elseif not (elro.miniBox.hidden or elro.miniBox.auto_hidden) then show() end
end
-- An install in mid-session gets no sysLoadEvent; boot does nothing the second time.
if type(tempTimer) == "function" then tempTimer(1, function() elro.mapwin_boot() end) end

if type(registerAnonymousEventHandler) == "function" then
  for _, k in ipairs({ "_winLoad", "_winResize", "_winDrop", "_winMapOpen" }) do
    if elro[k] and type(killAnonymousEventHandler) == "function" then
      pcall(killAnonymousEventHandler, elro[k])
    end
  end
  elro._winLoad = registerAnonymousEventHandler("sysLoadEvent",
    function() elro.mapwin_boot() end)
  -- The Map button opens the same widget behind our back; there is no close event, so a
  -- 'mapwin' after a button close opens rather than closes. One extra keystroke, no harm.
  elro._winMapOpen = registerAnonymousEventHandler("mapOpenEvent", function()
    if not (elro.miniBox and not (elro.miniBox.hidden or elro.miniBox.auto_hidden)) then
      elro._dockOpen = true
    end
    -- opening the map can load it, and with it the terrain colours an older map saved
    if elro.terrain_env_init then
      elro.terrain_env_init()
      if type(updateMap) == "function" then pcall(updateMap) end
    end
  end)
  elro._winResize = registerAnonymousEventHandler("sysWindowResizeEvent", anchor)
  -- A drag or resize just ended: keep the new size, snap back to the corner.
  elro._winDrop = registerAnonymousEventHandler("AdjustableContainerRepositionFinish",
    function(_, name)
      if name ~= BOX or not elro.miniBox then return end
      anchor()
      elro.miniBox:save()
    end)
end
