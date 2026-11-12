-- NannyBasics: NannyMUD's GMCP for players. Vitals and foe gauges, a tabbed channel pane,
-- and a GMCP log, arranged by a small region layout manager: left and right panes run the
-- full height, top and bottom span only the text column, and the text sits in the middle.
-- Move a component between regions with 'nanny place <what> <where>'.
--
-- The panes are plain containers the manager positions absolutely, so -- unlike the map --
-- nothing is bound to a singleton widget; a component can be moved and the pane remade freely.

NannyBasics = NannyBasics or {}
local N = NannyBasics
N.VERSION = "0.8.5"

-- Development only: a source file on disk wins over the copy built into the package. Off
-- unless the profile has nanny_src.txt naming it ('nanny src <path>' writes that file).
local function src_file() return getMudletHomeDir() .. "/nanny_src.txt" end
if not N.SRC then
  local fh = type(getMudletHomeDir) == "function" and io.open(src_file(), "r")
  N.SRC = fh and (fh:read("*l") or ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
  if fh then fh:close() end
end

function N.load_file()
  local fh = io.open(N.SRC, "r")
  if not fh then return false, "no file at " .. N.SRC end
  fh:close()
  N.fromFile = true
  local ok, err = pcall(dofile, N.SRC)
  N.fromFile = nil
  return ok, err
end

if not N.fromFile then
  local ok, err = N.load_file()
  if ok then return end
  if err and not tostring(err):find("^no file") then
    cecho("\n<red>[nanny]: " .. tostring(err) .. "; using the built-in copy.\n<reset>")
  end
end

-- The border coordinator (border.lua) is shared with the mapper, vendored identically. The
-- shipped package has it prepended into this script; in development N.SRC points at the file
-- on disk, so re-source the sibling border.lua to pick up edits on 'nanny reload'.
if N.SRC and N.SRC ~= "" then
  local dir = N.SRC:match("^(.*)[/\\][^/\\]+$")
  if dir then pcall(dofile, dir .. "/border.lua") end
end

N.WANT = { "Char 1", "Comm.Channel 1", "External.Discord 1", "Group 1", "Guild 1" }
-- Room.Info is the mapper's, listed so the log shows it. Char.Status rides the "Char"
-- subscription; Group.Info and the guild packages need their own top-level lines above. Every
-- guild package is logged; only those in N.GUILD_PANES get the guild pane, which is built for them.
N.EVENTS = { "Char.Vitals", "Char.Foe", "Comm.Channel.Text",
             "External.Discord.Info", "External.Discord.Status", "Room.Info",
             "Char.Status", "Group.Info", "Guild.Strigoi", "Guild.Alchemy", "Guild.Druid",
             "Guild.Vampire", "Guild.Druid.Owl" }
N.GUILD_PANES = { Strigoi = true, Druid = true, Alchemy = true, Vampire = true }
N.seen = N.seen or {}

local function say(s) cecho("\n<cyan>[nanny]: " .. s .. "\n<reset>") end

-- The decoded message: gmcp.Char.Vitals for "Char.Vitals".
local function at(path)
  local t = gmcp
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return t
end

local function json(v)
  if type(v) ~= "table" then return tostring(v) end
  local ok, s = pcall(yajl.to_string, v)
  return ok and s or "(not encodable)"
end


-- ================= the shared layout ============================================
-- Components are plain containers positioned by the shared border coordinator (border.lua).
-- Each sits in a named cell of its layout tree; the coordinator reserves the panel border,
-- stacks the cell's components and draws the drag bars. Placement and sizes persist there, so
-- there is no settings file of our own.

N.BAR = 28                                  -- a gauge row's height
N.SIDE_W = 0.45                             -- panel width a side component suggests (fraction of window)
N.comps = N.comps or {}                     -- name -> { box, hint_h }
-- default cells: the score card and party in the left column, chat in the wider right column,
-- vitals on the bottom (the log joins the left column when shown). The coordinator's saved
-- placement overrides these, and 'nanny reset' restores them.
-- always the literal (not `or`): N survives a reload, and this is only a default seed now -- real
-- placement lives in the coordinator -- so a default tweak must take effect on the next reload.
N.place = { vitals = "bottom", channels = "c2", log = "c1", status = "c1", cooldowns = "c1", party = "c1", guild = "c2" }
N.order = { "vitals", "guild", "channels", "status", "cooldowns", "party", "log" }  -- stacking order within a cell

-- register a component once; opts.build(box) makes its widgets as children of box, and the
-- optional opts.fit(w, h) lays them out in absolute px after every resize (a negative Geyser
-- height anchors the bottom edge that far UP from the parent's bottom, leaving a dead strip, so
-- "fill below a header" must be computed). On a reload the box is kept (rebuilding Geyser widgets
-- mid-session collides), but hint_h and fit are refreshed so changed defaults take effect.
local function component(nm, opts)
  if N.comps[nm] then
    N.comps[nm].hint_h, N.comps[nm].fit = opts.hint_h, opts.fit
    return N.comps[nm]
  end
  local box = Geyser.Container:new({ name = "NB_" .. nm, x = 0, y = 0, width = 100, height = 100 })
  local c = { box = box, hint_h = opts.hint_h, fit = opts.fit }
  opts.build(box)
  N.comps[nm] = c
  return c
end

-- Lay rows { widget, height, step } top-down in a box of height h; `fill` takes what is left.
-- A row that would cross the bottom is hidden: Geyser does not clip a child to its container, so a
-- squeezed pane would otherwise spill over the splitter below it and block the drag.
local function fit_rows(h, rows, fill)
  local y = 0
  for _, r in ipairs(rows) do
    local w, rh = r[1], r[2]
    if y + rh <= h then pcall(function() w:show() ; w:move(0, y) ; w:resize("100%", rh) end)
    else pcall(function() w:hide() end) end
    y = y + (r[3] or rh)
  end
  if not fill then return end
  if y < h then pcall(function() fill:show() ; fill:move(0, y) ; fill:resize("100%", h - y) end)
  else pcall(function() fill:hide() end) end
end

-- a component's panel-thickness suggestion and its fixed stack size (nil = flex), from the
-- orientation of the cell it is in: side cells stack vertically (a fixed height if it has one),
-- top/bottom cells stack horizontally (flex width).
local function slot_spec(nm, cell)
  local c = N.comps[nm]
  local edge = type(MudletBorders) == "table" and MudletBorders.edge_of(cell)
  if edge == "left" or edge == "right" then return N.SIDE_W, c.hint_h end
  return (c.hint_h or N.BAR * 2), nil
end

-- the title strip each pane is dragged by; vitals is a plain bar along the bottom
N.TITLE = { channels = "Chat", status = "Score", party = "Party", log = "GMCP log", cooldowns = "Cooldowns" }

-- Register every component as a slot in its cell. channels, status and party are always shown;
-- the GMCP log toggles, and the guild pane waits for its guild's first message. Sizes come from
-- the cell the pane is in NOW (it may have been dragged to another edge); the coordinator stacks
-- each cell and calls the cb back with a rect.
function N.relayout()
  if type(MudletBorders) ~= "table" then return end
  for i, nm in ipairs(N.order) do
    local c = N.comps[nm]
    if c then
      if (nm == "log" and not N.logOn) or (nm == "guild" and not N.guildName)
         or (nm == "cooldowns" and not N.cd_wanted()) then
        pcall(function() c.box:hide() end)
        MudletBorders.park("nanny:" .. nm)
      else
        local id = "nanny:" .. nm
        -- the guild pane's height depends on which guild it is drawing
        if nm == "guild" and N.guild_card_h then c.hint_h = N.guild_card_h() end
        if nm == "cooldowns" then c.hint_h = N.cd_card_h() end
        local cross, hint = slot_spec(nm, MudletBorders.where(id) or
          MudletBorders.parked_cell(id) or N.place[nm])
        MudletBorders.slot("nanny:" .. nm, {
          cell = N.place[nm], cross = cross, hint = hint, order = 10 + i,
          title = (nm == "guild" and N.guildName) or N.TITLE[nm],
          cb = function(x, y, w, h)
            pcall(function() c.box:show() ; c.box:move(x, y) ; c.box:resize(w, h) end)
            if c.fit then pcall(c.fit, w, h) end
            if nm == "channels" then N.chat_wrap() end
          end,
          on_hide = function() pcall(function() c.box:hide() end) end,
        })
      end
    end
  end
  -- chat tabs with a pane of their own: start beside the chat pane, go back into it when
  -- dropped onto it or from their strip's right-click menu
  local chatCell = MudletBorders.where("nanny:channels") or N.place.channels
  local names = {}
  for name, t in pairs(N.tabs or {}) do if N.split[name] and t.pane then names[#names + 1] = name end end
  table.sort(names)
  for k, name in ipairs(names) do
    local t = N.tabs[name]
    local edge = MudletBorders.edge_of(MudletBorders.where(N.split_id(name)) or chatCell)
    MudletBorders.slot(N.split_id(name), {
      cell = chatCell, order = 30 + k, title = name,
      cross = (edge == "left" or edge == "right") and N.SIDE_W or N.BAR * 2,
      cb = function(x, y, w, h)
        pcall(function() t.pane:show() ; t.pane:move(x, y) ; t.pane:resize(w, h) end)
        pcall(function() t.con:move(0, 0) ; t.con:resize(w, h) end)
        N.chat_wrap()
      end,
      menu = { { "Back into Chat", function() N.chat_join(name) end } },
      on_drop = function(mx, my)
        if N.over_chat(mx, my) then N.chat_join(name) ; return true end
      end,
    })
  end
end

-- a pane by the name on its strip or its own: chat, score, the guild's name, ...
function N.comp_named(word)
  word = tostring(word or ""):lower()
  for nm in pairs(N.comps) do
    local t = (nm == "guild" and N.guildName) or N.TITLE[nm]
    if word == nm or (t and word == t:lower()) then return nm end
  end
end

-- 'nanny hide <pane>' / 'nanny show <pane>': the same as the X on its strip and the right-click menu
function N.show_comp(word, on)
  local nm = N.comp_named(word)
  if not nm then say("no pane '" .. tostring(word) .. "'. Try vitals, chat, score, cooldowns, party, guild or log.") return end
  if type(MudletBorders) ~= "table" or not MudletBorders.close then say("this layout cannot hide panes.") return end
  if on then
    if nm == "log" then N.logOn = true end
    MudletBorders.open("nanny:" .. nm)
  else
    MudletBorders.close("nanny:" .. nm)
  end
  N.relayout()
  say(nm .. (on and " shown" or " hidden; 'nanny show " .. word .. "' or a right-click on any strip brings it back"))
end

function N.place_comp(word, cell)
  local nm = N.comp_named(word)
  if not nm then
    say("no pane '" .. tostring(word) .. "'. Try vitals, chat, score, cooldowns, party, guild or log.") return
  end
  if type(MudletBorders) ~= "table" or not MudletBorders.edge_of(cell) then
    say("place it in which cell? " .. table.concat(type(MudletBorders) == "table" and MudletBorders.cells() or {}, ", ")) return
  end
  if nm == "log" and not N.logOn then N.logOn = true end   -- placing the log shows it
  MudletBorders.move("nanny:" .. nm, cell)
  N.relayout()
  say(nm .. " -> " .. cell)
end

-- ================= vitals: HP, SP and the foe =====================================

N.PULSE_AT = 0.4
N.HP_BASE, N.HP_PEAK = { 176, 48, 48 }, { 255, 190, 170 }

local function gauge_style(g, front, back)
  g.front:setStyleSheet("background-color: " .. front .. "; border-radius: 3px;")
  g.back:setStyleSheet("background-color: " .. back .. "; border-radius: 3px;")
  g.text:setStyleSheet("background-color: rgba(0,0,0,0); padding-left: 8px; font-weight: bold;")
end

local function build_vitals(box)
  N.foe = Geyser.Gauge:new({ name = "NannyFoe", x = 0, y = 0, width = "100%", height = "48%" }, box)
  N.hp = Geyser.Gauge:new({ name = "NannyHP", x = 0, y = "50%", width = "49%", height = "48%" }, box)
  N.sp = Geyser.Gauge:new({ name = "NannySP", x = "51%", y = "50%", width = "49%", height = "48%" }, box)
  gauge_style(N.foe, "#b07a20", "#3a2a0c")
  gauge_style(N.hp, "#b03030", "#3a1414")
  gauge_style(N.sp, "#3050b0", "#141c3a")
  N.foe_show(nil)
end

local function gauge(g, cur, max, label)
  cur, max = tonumber(cur), tonumber(max)
  if not cur then return end
  if not max or max == 0 then max = cur end
  g:setValue(math.max(cur, 0), math.max(max, 1), label .. " " .. cur .. "/" .. max)
end

local function hp_colour(c)
  if not N.hp then return end
  N.hp.front:setStyleSheet(string.format("background-color: rgb(%d,%d,%d); border-radius: 3px;",
                                         c[1], c[2], c[3]))
end

-- Below PULSE_AT of max HP the bar pulses, faster and brighter the lower it is.
function N.pulse()
  local f = N.hpFrac
  if not f or f >= N.PULSE_AT then
    if N.pulseTimer then killTimer(N.pulseTimer) ; N.pulseTimer = nil end
    hp_colour(N.HP_BASE)
    return
  end
  local k = 1 - math.max(f, 0) / N.PULSE_AT
  local hz, amp = 0.8 + 2.2 * k, 0.35 + 0.65 * k
  local s = amp * (0.5 + 0.5 * math.sin(2 * math.pi * hz * getEpoch()))
  local c = {}
  for i = 1, 3 do c[i] = math.floor(N.HP_BASE[i] + (N.HP_PEAK[i] - N.HP_BASE[i]) * s + 0.5) end
  hp_colour(c)
end

local function hp_pulse(cur, max)
  cur, max = tonumber(cur), tonumber(max)
  if cur and max and max > 0 then N.hpFrac = cur / max end
  if N.hpFrac and N.hpFrac < N.PULSE_AT and not N.pulseTimer then
    N.pulseTimer = tempTimer(0.05, N.pulse, true)
  end
  N.pulse()
end

-- A vampire is sent no Char.Vitals: its blood takes the HP gauge at full width, SP hidden.
local function blood_mode(on)
  if not N.hp or N.bloodMode == on then return end
  N.bloodMode = on
  pcall(function()
    if on then N.sp:hide() ; N.hp:resize("100%", "48%")
    else N.hp:resize("49%", "48%") ; N.sp:show() end
  end)
end

function N.vitals(v)
  if type(v) ~= "table" or not N.hp then return end
  blood_mode(false)
  gauge(N.hp, v.hp, v.maxhp, "HP")
  gauge(N.sp, v.sp, v.maxsp, "SP")
  hp_pulse(v.hp, v.maxhp)
  N.body_show(v)
end

function N.blood(bp, maxbp)
  if not N.hp or not tonumber(bp) then return end
  blood_mode(true)
  gauge(N.hp, bp, maxbp, "BP")
  hp_pulse(bp, maxbp)
end

N.SHAPE = {
  ["undamaged"] = 95, ["superior"] = 85, ["very good"] = 75, ["good"] = 65, ["fair"] = 55,
  ["fairly poor"] = 45, ["poor"] = 35, ["weak"] = 25, ["very weak"] = 15, ["deplorable"] = 5,
}

function N.foe_show(v)
  if not N.foe then return end
  local name, shape = type(v) == "table" and v.name, type(v) == "table" and v.shape
  if not name or name == "" then N.foe:setValue(0, 100, "no foe") ; return end
  N.foe:setValue(N.SHAPE[tostring(shape or ""):lower()] or 50, 100,
                 tostring(name) .. ": " .. tostring(shape or "?"))
end

-- ================= channels =======================================================

N.TAB_H = 22
N.CHAT_FONT = 10
N.TAB_STYLE = {
  idle   = "background-color: #262626; color: #b0b0b0;",
  active = "background-color: #404040; color: #ffffff; font-weight: bold;",
  unread = "background-color: #5a3a10; color: #ffcc66; font-weight: bold;",
}
local TAB_SHAPE = " border: 1px solid #3a3a3a; border-bottom: none;" ..
                  " border-top-left-radius: 4px; border-top-right-radius: 4px;"

N.PALETTE = { { 120, 200, 255 }, { 255, 180, 90 }, { 150, 230, 140 }, { 230, 140, 230 },
              { 255, 230, 120 }, { 140, 220, 220 }, { 255, 140, 140 }, { 190, 170, 255 } }
local function chan_colour(name)
  local h = 0
  for i = 1, #name do h = (h * 31 + name:byte(i)) % 2147483647 end
  return N.PALETTE[h % #N.PALETTE + 1]
end

local function safe(name) return (name:gsub("[^%w]", "_")) end

local function build_channels(box)
  N.chatBox = box
  N.tabBar = Geyser.HBox:new({ name = "NannyChatTabs", x = 0, y = 0, width = "100%", height = N.TAB_H }, box)
  N.tabs, N.tabOrder = N.tabs or {}, N.tabOrder or {}
end

local CHAT_KEEP = 500                  -- messages per tab kept to print again at a new width
local replay

-- channels with a pane of their own, kept in the profile directory, one name a line
local function split_file() return getMudletHomeDir() .. "/nanny_chatsplit.txt" end
if not N.split then
  N.split = {}
  local fh = io.open(split_file(), "r")
  if fh then
    for l in fh:lines() do if l ~= "" then N.split[l] = true end end
    fh:close()
  end
end

-- each tab wraps at the width of the pane it is in: the chat pane, or its own
function N.chat_wrap()
  if not N.chatBox then return end
  local cw = calcFontSize(N.CHAT_FONT) or 8
  local function cols_of(box)
    local ok, w = pcall(function() return box:get_width() end)
    w = (ok and type(w) == "number" and w > 0) and w or 360
    return math.max(20, math.floor((w - 20) / cw))
  end
  local changed = false
  for name, t in pairs(N.tabs or {}) do
    local cols = cols_of(N.split[name] and t.pane or N.chatBox)
    pcall(function() t.con:setWrap(cols) end)
    if t.cols and t.cols ~= cols then changed = true end
    t.cols = cols
  end
  -- Mudlet never re-wraps printed text, so a new width prints the kept messages again,
  -- once the size has settled: a drag resizes many times
  if changed then
    if N.chatReplayT then pcall(killTimer, N.chatReplayT) end
    N.chatReplayT = tempTimer(0.5, function() N.chatReplayT = nil ; replay() end)
  end
end

-- each tab's console fills every pixel below the tab bar (see component() on negative heights)
local function fit_channels(w, h)
  for name, t in pairs(N.tabs or {}) do
    if not N.split[name] then
      pcall(function() t.con:move(0, N.TAB_H) ; t.con:resize("100%", math.max(1, h - N.TAB_H)) end)
    end
  end
end

function N.tab(name)
  if N.tabs[name] then return N.tabs[name] end
  local t = { hist = {} }
  t.label = Geyser.Label:new({ name = "NChatTab_" .. safe(name) }, N.tabBar)
  t.label:echo("<center>" .. name)
  -- a press selects on release unless the tab is pulled out; a right-click offers its own pane.
  -- A Mudlet with no release callback keeps the plain click.
  if pcall(function() t.label:setReleaseCallback(function(ev) N.tab_release(name, ev) end) end) then
    t.label:setClickCallback(function(ev) N.tab_press(name, ev) end)
  else
    t.label:setClickCallback(function() N.select(name) end)
  end
  t.con = Geyser.MiniConsole:new({ name = "NChatCon_" .. safe(name), x = 0, y = N.TAB_H,
    width = "100%", height = 10, autoWrap = false, scrollBar = true, fontSize = N.CHAT_FONT,
    color = "black" }, N.chatBox)
  N.tabs[name] = t
  local ok, bh = pcall(function() return N.chatBox:get_height() end)
  if ok and type(bh) == "number" then fit_channels(nil, bh) end
  N.chat_wrap()
  N.tabOrder[#N.tabOrder + 1] = name
  if N.current and N.current ~= name then t.con:hide() end
  N.tab_style(name)
  -- a channel given its own pane in an earlier session gets it back on its first message
  if N.split[name] then N.chat_split(name) end
  return t
end

function N.tab_style(name)
  local t = N.tabs[name]
  local k = (name == N.current) and "active" or (t.unread and "unread" or "idle")
  t.label:setStyleSheet(N.TAB_STYLE[k] .. TAB_SHAPE)
end

function N.select(name)
  if N.split[name] then return end
  N.current = name
  for n, t in pairs(N.tabs) do
    -- a tab in its own pane is always shown, whichever tab the chat pane has selected
    if not N.split[n] then
      if n == name then t.con:show() ; t.unread = false else t.con:hide() end
      N.tab_style(n)
    end
  end
end

-- ---- a chat tab in a pane of its own ----
local function split_save()
  local names = {}
  for n in pairs(N.split) do names[#names + 1] = n end
  table.sort(names)
  local fh = io.open(split_file(), "w")
  if fh then fh:write(table.concat(names, "\n")) ; fh:close() end
end

function N.split_id(name) return "nanny:chat:" .. safe(name) end

local function label_out(name)
  local t = N.tabs[name]
  if t then pcall(function() N.tabBar:remove(t.label) ; t.label:hide() ; N.tabBar:organize() end) end
end

-- is the pointer over the chat pane (to drop a tab back into it)?
function N.over_chat(mx, my)
  if not (N.chatBox and mx) then return false end
  local ok, inside = pcall(function()
    local x, y = N.chatBox:get_x(), N.chatBox:get_y()
    local w, h = N.chatBox:get_width(), N.chatBox:get_height()
    if type(x) ~= "number" or type(w) ~= "number" then return false end
    return mx >= x and mx < x + w and my >= y and my < y + h
  end)
  return ok and inside or false
end

-- Give a tab its own pane. `keepLabel` leaves its tab in the bar until the mouse is released:
-- Qt sends the release to the label that was pressed, and that release ends the drag.
function N.chat_split(name, keepLabel)
  local t = N.tabs[name]
  if not t or name == "All" then return false end
  N.split[name] = true
  split_save()
  if not t.pane then
    t.pane = Geyser.Container:new({ name = "NChatPane_" .. safe(name), x = 0, y = 0, width = 100, height = 100 })
  end
  pcall(function() t.con:changeContainer(t.pane) end)
  pcall(function() t.con:move(0, 0) ; t.con:resize("100%", "100%") ; t.con:show() end)
  if not keepLabel then label_out(name) end
  if N.current == name then N.select("All") end
  N.relayout()
  return true
end

function N.chat_join(name)
  local t = N.tabs[name]
  if not N.split[name] then return false end
  N.split[name] = nil
  split_save()
  if type(MudletBorders) == "table" then MudletBorders.remove(N.split_id(name)) end
  if t then
    if t.pane then pcall(function() t.pane:hide() end) end
    pcall(function() t.con:changeContainer(N.chatBox) end)
    pcall(function() N.tabBar:add(t.label) ; t.label:show() ; N.tabBar:organize() end)
    local ok, bh = pcall(function() return N.chatBox:get_height() end)
    if ok and type(bh) == "number" then fit_channels(nil, bh) end
    N.select(name)
  end
  N.relayout()
  return true
end

function N.tab_press(name, ev)
  if type(ev) == "table" and ev.button == "RightButton" then
    if type(MudletBorders) == "table" and MudletBorders.popup and name ~= "All" then
      MudletBorders.popup({ { "Own pane", function() N.chat_split(name) end } })
    end
    return
  end
  local mx, my = getMousePosition()
  N.tabDrag = { name = name, sx = mx, sy = my }
  if N.tabDragT then pcall(killTimer, N.tabDragT) end
  N.tabDragT = tempTimer(0.03, function() N.tab_drag_tick() end, true)
end

-- a tab moved this far while held is pulled out of the bar into a pane of its own
local PULL = 12
function N.tab_drag_tick()
  local d = N.tabDrag
  local mx, my = getMousePosition()
  if not d or d.torn or not mx or not d.sx then return end
  if math.abs(mx - d.sx) + math.abs(my - d.sy) < PULL or d.name == "All" then return end
  if N.tabDragT then pcall(killTimer, N.tabDragT) ; N.tabDragT = nil end
  if type(MudletBorders) ~= "table" or not MudletBorders.drag_pane then return end
  d.torn = N.chat_split(d.name, true)
  if d.torn then MudletBorders.drag_pane(N.split_id(d.name)) end
end

function N.tab_release(name, ev)
  if N.tabDragT then pcall(killTimer, N.tabDragT) ; N.tabDragT = nil end
  local d = N.tabDrag
  N.tabDrag = nil
  if type(ev) == "table" and ev.button == "RightButton" then return end
  if d and d.torn then
    MudletBorders.drag_end()
    label_out(d.name)
    return
  end
  N.select(name)
end

local function put(t, ch, talker, text, at)
  local w = t.con.name
  setFgColor(w, 120, 120, 120) ; echo(w, at .. " ")
  -- the line names its channel itself, by a tag ([Treasure]) or a verb (You say:); add nothing
  local c = chan_colour(ch)
  local tag, rest = text:match("^(%b[])%s*(.*)$")
  if tag then
    setFgColor(w, c[1], c[2], c[3]) ; echo(w, tag .. " ")
    text = rest
  end
  if talker ~= "" and text:sub(1, #talker) == talker then
    setFgColor(w, 255, 255, 255) ; echo(w, talker)
    text = text:sub(#talker + 1)
  end
  if tag then setFgColor(w, 200, 200, 200) else setFgColor(w, c[1], c[2], c[3]) end
  echo(w, text .. "\n")
  resetFormat(w)
end

-- every tab cleared and its kept messages printed again at the console's current wrap
replay = function()
  for _, t in pairs(N.tabs or {}) do
    if t.hist then
      pcall(clearWindow, t.con.name)
      for _, m in ipairs(t.hist) do put(t, m[1], m[2], m[3], m[4]) end
    end
  end
end

function N.channel(v)
  if type(v) ~= "table" or not N.chatBox then return end
  local ch = tostring(v.channel or "?")
  local talker = tostring(v.talker or "")
  -- the game may send the line already wrapped; the pane wraps it to its own width
  local text = tostring(v.text or ""):gsub("\27%[[%d;]*m", ""):gsub("%s*\n%s*", " ")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  local at = os.date("%H:%M")
  for _, name in ipairs({ "All", ch }) do
    local t = N.tab(name)
    -- a tab made before a reload holds lines never kept: it is never cleared to print again
    if t.hist then
      t.hist[#t.hist + 1] = { ch, talker, text, at }
      if #t.hist > CHAT_KEEP then table.remove(t.hist, 1) end
    end
    put(t, ch, talker, text, at)
    if name ~= N.current then t.unread = true ; N.tab_style(name) end
  end
end

-- ================= the GMCP log ===================================================

local function build_log(box)
  N.logWin = Geyser.MiniConsole:new({ name = "NannyLogText", x = 0, y = 0, width = "100%",
    height = "100%", autoWrap = true, scrollBar = true, fontSize = 9, color = "black" }, box)
end

function N.log_toggle()
  N.logOn = not N.logOn
  if N.logOn and type(MudletBorders) == "table" and MudletBorders.open then MudletBorders.open("nanny:log") end
  N.relayout()
  say("GMCP log " .. (N.logOn and ("shown (" .. N.place.log .. ")") or "hidden"))
end

local function log(name, v)
  N.seen[name] = (N.seen[name] or 0) + 1
  if not N.logOn or not N.logWin then return end
  local w = N.logWin.name
  setFgColor(w, 120, 120, 120) ; echo(w, os.date("%H:%M:%S") .. " ")
  setFgColor(w, 230, 200, 80) ; echo(w, name .. " ")
  setFgColor(w, 220, 220, 220) ; echo(w, json(v) .. "\n")
  resetFormat(w)
end

-- ================= status: what 'score' shows =====================================
-- One XP gauge (the only score field that reads as a bar) over a block of text for the rest.

local function commas(n)
  n = tostring(tonumber(n) or n)
  while true do local s ; n, s = n:gsub("^(-?%d+)(%d%d%d)", "%1,%2") ; if s == 0 then break end end
  return n
end

-- Pixel height of one row of the card's own 10pt text, in the same coordinate system as the pane
-- boxes, so the card is sized to its content. Panes sized in these rows fit at any font/DPI.
function N.lh()
  if not N._lh then
    N._lh = 15
    if type(calcFontSize) == "function" then
      local ok, w, h = pcall(calcFontSize, 10)
      if ok and type(h) == "number" and h > 0 then N._lh = h
      elseif ok and type(w) == "number" and w > 0 then N._lh = math.floor(w * 1.8) end
    end
  end
  return N._lh
end

-- The card's parts, in text rows: a two-line title, the XP gauge, the body gauges, and the grid
-- (5 rows of about 1.33 rows' height each once cell padding is counted, plus the label's padding).
local function status_dims()
  local lh = N.lh()
  return math.floor(lh * 3.2), math.floor(lh * 1.5), math.floor(lh * 7.3), math.floor(lh * 1.25)
end

-- The card's own height, so it shows in full; any spare falls inside the card, in its colour.
local function status_card_h()
  local th, gh, gr, bh = status_dims()
  return th + gh + 3 + bh + gr
end

-- the body gauges under the XP bar: key in Char.Vitals, label, colours
N.BODY = { { "tox", "Tox", "#4f8f2f", "#18280f" }, { "full", "Full", "#a0702c", "#30210d" },
           { "soak", "Soak", "#2c8a9a", "#0d2a30" }, { "weight", "Weight", "#7a7a7a", "#262626" } }
N.vt = N.vt or {}

local function style_body()
  for i, g in ipairs(N.stBodyG or {}) do
    local b = N.BODY[i]
    g.front:setStyleSheet("background-color: " .. b[3] .. "; border-radius: 3px;")
    g.back:setStyleSheet("background-color: " .. b[4] .. "; border-radius: 3px;")
    g.text:setStyleSheet("background-color: rgba(0,0,0,0); padding-left: 5px; font-size: 8pt; font-weight: bold;")
  end
end

-- Made on first use, not in build_status: a reload keeps the old card and does not rebuild it.
local function body_row()
  if N.stBody or not (N.comps.status and N.comps.status.box) then return N.stBody end
  N.stBody = Geyser.Container:new({ name = "NannyStBody", x = 0, y = 0, width = "100%", height = 10 },
    N.comps.status.box)
  N.stBodyG = {}
  local n = #N.BODY
  for i, b in ipairs(N.BODY) do
    local g = Geyser.Gauge:new({ name = "NannyBody_" .. b[1], x = ((i - 1) * 100 / n) .. "%", y = 0,
      width = (100 / n - 1) .. "%", height = "100%" }, N.stBody)
    g:setValue(0, 1, b[2])
    N.stBodyG[i] = g
  end
  style_body()
  N.body_show({})
  return N.stBody
end

-- Tox, Full and Soak are percentages; Weight is carried against maxweight.
function N.body_show(v)
  if type(v) ~= "table" then return end
  for k, val in pairs(v) do N.vt[k] = val end
  if not body_row() then return end
  for i, b in ipairs(N.BODY) do
    local cur = tonumber(N.vt[b[1]])
    if cur then
      if b[1] == "weight" then
        local mx = math.max(tonumber(N.vt.maxweight) or cur, 1)
        N.stBodyG[i]:setValue(math.max(cur, 0), mx, b[2] .. " " .. cur .. "/" .. mx)
      else
        N.stBodyG[i]:setValue(math.max(0, math.min(cur, 100)), 100, b[2] .. " " .. cur .. "%")
      end
    end
  end
end

-- Stylesheets are applied here rather than only at build, so a reload restyles the kept widgets.
-- The grid hugs the top of its label; Qt otherwise centres label text vertically.
local function style_status()
  if not N.stTxt then return end
  N.stTitle:setStyleSheet("background-color: #16131f; color: #e6e0f0; padding: 3px; border-bottom: 1px solid #2a2436;")
  N.stXp.front:setStyleSheet("background-color: #6a4fb0; border-radius: 3px;")
  N.stXp.back:setStyleSheet("background-color: #241a3a; border-radius: 3px;")
  N.stXpOver = false
  N.stXp.text:setStyleSheet("background-color: rgba(0,0,0,0); padding-left: 8px; font-weight: bold;")
  N.stTxt:setStyleSheet("background-color: #101010; color: #d0d0d0; padding: 4px; "
    .. "qproperty-alignment: 'AlignLeft | AlignTop';")
  style_body()
end

-- A card: name and level/guild/race on top, an XP bar, then a two-column grid of the rest. The
-- sizes here are placeholders; fit_status sets the real ones from the box.
local function build_status(box)
  N.stTitle = Geyser.Label:new({ name = "NannyStTitle", x = 0, y = 0, width = "100%", height = 10 }, box)
  N.stXp = Geyser.Gauge:new({ name = "NannyXp", x = 0, y = 10, width = "100%", height = 10 }, box)
  N.stTxt = Geyser.Label:new({ name = "NannyStatusText", x = 0, y = 20, width = "100%", height = 10 }, box)
  style_status()
end

-- Title and gauge at their own heights, the grid filling every pixel below them, so the card's
-- colour reaches the splitter under it.
local function fit_status(w, h)
  if not N.stTxt then return end
  local th, gh, _, bh = status_dims()
  local rows = { { N.stTitle, th }, { N.stXp, gh, gh + 3 } }
  if body_row() then rows[3] = { N.stBody, bh } end
  fit_rows(h, rows, N.stTxt)
end

local function per_hour(r)
  if r <= 0 then return "0/hr" end
  return r >= 1000 and string.format("%.0fk/hr", r / 1000) or string.format("%.0f/hr", r)
end

-- XP gained per hour this session (the game's own card shows one; GMCP does not, so compute it).
local function rate_str()
  local e = tonumber(N.st.exp) ; if not e then return "?" end
  local now = (type(getEpoch) == "function" and getEpoch()) or os.time()
  if not N.xp0 then N.xp0, N.xpT0 = e, now ; return "..." end
  local dt = now - (N.xpT0 or now)
  if dt < 30 then return "..." end
  return per_hour((e - N.xp0) / dt * 3600)
end

-- The server sends Char.Status whole, and leaves the next level's needs out once they are met,
-- so a message with a level replaces the kept table. Anything else is merged.
N.st = N.st or {}

-- What the server said while a level was still short, per character, kept in the profile so
-- the card is right past the target and after a restart. A paragon's level and baseexp hold
-- until the next advance; a level's NP target and base are fixed.
local function levels_file() return getMudletHomeDir() .. "/nanny_levels.lua" end
if not N.lv then
  N.lv = {}
  if type(table.load) == "function" then pcall(table.load, levels_file(), N.lv) end
end
local function level_rec(name)
  local k = tostring(name):lower()
  local L = N.lv[k]
  if type(L) ~= "table" then L = {} ; N.lv[k] = L end
  L.np = type(L.np) == "table" and L.np or {}
  return L
end
-- Paragon level P+1 is (P+1) million spent over baseexp, the server's needexp target.
local function learn_level(L, s, lvl, e, np)
  local changed
  local n, b = tonumber(s.needexp or s.neededexp), tonumber(s.baseexp)
  if lvl == 19 and e and n and b then
    local cost = e + n - b
    if cost >= 1e6 and cost % 1e6 == 0 and (L.para ~= cost / 1e6 - 1 or L.base ~= b) then
      L.para, L.base, changed = cost / 1e6 - 1, b, true
    end
  end
  local nn, nb = tonumber(s.neednp), tonumber(s.basenp) or 0
  if lvl and np and nn then
    local t = L.np[lvl]
    if not t or t.total ~= np + nn or t.base ~= nb then L.np[lvl], changed = { base = nb, total = np + nn }, true end
  end
  if changed and type(table.save) == "function" then pcall(table.save, levels_file(), N.lv) end
end
local function xp_back(over)
  if N.stXpOver == over then return end
  N.stXpOver = over
  N.stXp.back:setStyleSheet("background-color: " .. (over and "#8a6a1a" or "#241a3a") .. "; border-radius: 3px;")
end
-- Mudlet merges each message into gmcp and never drops a key, so the fields the server sends
-- only while they apply are cleared once read: the next message then says whether they still do.
local STATUS_SOMETIMES = { "needexp", "neededexp", "baseexp", "neednp", "needgold", "basenp" }
function N.status_consume(v)
  if type(v) ~= "table" then return end
  for _, k in ipairs(STATUS_SOMETIMES) do v[k] = nil end
end
function N.status(v)
  if type(v) ~= "table" then return end
  if v.level ~= nil then N.st = {} end
  for k, val in pairs(v) do N.st[k] = val end
  local s = N.st
  local function g(k) return s[k] ~= nil and tostring(s[k]) or "?" end
  local L = s.name and level_rec(s.name)
  local lvl, e, np = tonumber(s.level), tonumber(s.exp), tonumber(s.np)
  if L then learn_level(L, s, lvl, e, np) end
  -- what counts toward the next level, and how much it takes
  -- (P+1) million to take the next paragon level and a million left after it: (P+2) million.
  -- The label counts a paragon's XP from baseexp, NP as it stands.
  local para, unit, cur, need, shown
  if L and lvl == 19 and L.para and e then
    para, unit, shown = L.para, "Paragon", 0
    cur, need = e - L.base, (L.para + 2) * 1e6
  elseif L and lvl and L.np[lvl] and np then
    local t = L.np[lvl]
    unit, shown, cur, need = "NP", t.base, np - t.base, t.total - t.base
  end
  local over = need and cur >= need
  if N.stTitle then
    N.stTitle:echo(string.format(
      "<center><b style='font-size:13pt;'>%s</b></center>" ..
      "<center><span style='color:#9a93b0; font-size:9pt;'>Level %s%s &#183; %s &#183; %s</span></center>",
      g("name"), g("level"), para and (" &#183; Paragon " .. para) or "", g("guild"), g("race")))
  end
  if N.stXp then
    xp_back(over and true or false)
    if over then
      -- the fill ends at the target, the gold beyond it is the surplus
      N.stXp:setValue(need, math.max(cur, 1), unit .. "  " .. commas(need + shown) .. " reached  +" .. commas(cur - need))
    elseif need then
      N.stXp:setValue(math.max(cur, 0), math.max(need, 1), unit .. "  " .. commas(cur + shown) .. " / " .. commas(need + shown))
    elseif e then N.stXp:setValue(1, 1, "XP " .. commas(e)) end
  end
  if N.stTxt then
    local H = "color:#e0b64a; font-weight:bold;"   -- gold, bold, for the row headings
    N.stTxt:echo(string.format(
      "<table width='100%%' cellspacing='0' cellpadding='1' style='font-size:10pt;'>" ..
      "<tr><td style='%s'>Gold</td><td align='right'>%s</td></tr>" ..
      "<tr><td style='%s'>QP</td><td align='right'>%s</td></tr>" ..
      "<tr><td style='%s'>XP/hr</td><td align='right' style='color:#b8a6e6;'>%s</td></tr>" ..
      "</table>" ..
      "<table width='100%%' cellspacing='0' cellpadding='1' style='font-size:10pt; color:#dddddd;'>" ..
      "<tr><td style='%s'>Str</td><td align='right'>%s</td><td width='16'></td><td style='%s'>Int</td><td align='right'>%s</td></tr>" ..
      "<tr><td style='%s'>Dex</td><td align='right'>%s</td><td></td><td style='%s'>Con</td><td align='right'>%s</td></tr>" ..
      "</table>",
      H, commas(s.gold or "?"), H, g("qp"), H, rate_str(),
      H, g("str"), H, g("int"), H, g("dex"), H, g("con")))
  end
  -- the guild pane's stat totals are built on these base stats
  if N.guildName and (v.str or v.con or v.int or v.dex) then N.guild("Guild." .. N.guildName, {}) end
end

-- ================= party: your group =============================================
-- One row per member: name (leader, follow state, away marked), with small HP and SP gauges.
-- Rows are pooled.

N.partyRows = N.partyRows or {}

-- row metrics from the font: a name line over a line of HP/SP gauges, so rows are not cramped on
-- a high-DPI display. Returns the name height, gauge height, and the full row pitch.
local function party_dims()
  local lh = N.lh()
  local nameH, gH = math.floor(lh * 1.05), math.floor(lh)
  return nameH, gH, nameH + gH + math.floor(lh * 0.35)
end

local function party_row(i)
  if N.partyRows[i] then return N.partyRows[i] end
  local nameH, gH = party_dims()
  local r = {}
  r.name = Geyser.Label:new({ name = "NPartyName" .. i, x = 0, y = 0, width = "100%", height = nameH }, N.partyBox)
  r.name:setStyleSheet("background-color: rgba(0,0,0,0); color: #cfcfcf; font-weight: bold; font-size: 9pt;")
  r.hp = Geyser.Gauge:new({ name = "NPartyHp" .. i, x = 0, y = 0, width = "49%", height = gH }, N.partyBox)
  r.sp = Geyser.Gauge:new({ name = "NPartySp" .. i, x = "51%", y = 0, width = "49%", height = gH }, N.partyBox)
  r.hp.front:setStyleSheet("background-color: #b03030; border-radius: 2px;")
  r.hp.back:setStyleSheet("background-color: #3a1414; border-radius: 2px;")
  r.sp.front:setStyleSheet("background-color: #3050b0; border-radius: 2px;")
  r.sp.back:setStyleSheet("background-color: #141c3a; border-radius: 2px;")
  for _, gg in ipairs({ r.hp, r.sp }) do
    gg.text:setStyleSheet("background-color: rgba(0,0,0,0); padding-left: 4px;")
  end
  N.partyRows[i] = r
  return r
end

local function build_party(box) N.partyBox = box end

function N.party(v)
  if type(v) ~= "table" or not N.partyBox then return end
  local ms = type(v.members) == "table" and v.members or {}
  local nameH, gH, prow = party_dims()
  for i, m in ipairs(ms) do
    local r = party_row(i)
    local base = (i - 1) * prow
    pcall(function()
      r.name:move(0, base) ; r.name:resize("100%", nameH) ; r.name:show()
      r.hp:move(0, base + nameH) ; r.hp:resize("49%", gH) ; r.hp:show()
      r.sp:move("51%", base + nameH) ; r.sp:resize("49%", gH) ; r.sp:show()
    end)
    local nm = tostring(m.name or "?") .. (tonumber(m.leader) == 1 and "  (leader)" or "")
    if tonumber(m.never) == 1 then nm = nm .. "  (never follows)"
    elseif tonumber(m.following) == 1 and tonumber(m.leader) ~= 1 then nm = nm .. "  (follows)" end
    if tonumber(m.here) ~= 1 then nm = nm .. "  (away)" end
    r.name:echo(nm)
    local function setg(gg, pct, cur, lbl)
      local p = tonumber(pct) ; p = p and math.max(0, math.min(100, p)) or 0
      gg:setValue(p, 100, lbl .. " " .. tostring(cur or "?"))
    end
    setg(r.hp, m.hppct, m.hp, "HP")
    setg(r.sp, m.sppct, m.sp, "SP")
  end
  for i = #ms + 1, #N.partyRows do
    local r = N.partyRows[i]
    pcall(function() r.name:hide() ; r.hp:hide() ; r.sp:hide() end)
  end
end

-- ================= guild: Guild.<Name> ============================================
-- One pane, drawn by the guild's own renderer below. Strigoi: a header (level, form, damage),
-- gauges for guild points, the command penalty and the wasp, then the rest as text. Druid: a
-- header (level, tree), one HP gauge per pet, then the rest as text, arch among the buffs.
-- Alchemy: a header (minions out, concoctions held), one HP gauge per minion out, then
-- materials, concoctions and the packed minions.

local function esc(s) return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end

local function guild_dims()
  local lh = N.lh()
  return math.floor(lh * 1.4), math.floor(lh * 1.35) * 7 + 8   -- a gauge row, the text block
end
-- Alchemy minions in one state
local function minions_in(state)
  local n = 0
  for _, m in pairs(type((N.gd or {}).minions) == "table" and N.gd.minions or {}) do
    if type(m) == "table" and m.state == state then n = n + 1 end
  end
  return n
end
local function packed_count() return minions_in("packed") end
-- Druid and Alchemy draw one gauge per pet or minion out: a Druid's room is kept for as many
-- pets as allowed; an Alchemist's follows the minions out, since one called out leaves Packed.
local BAR_GUILDS = { Druid = true, Alchemy = true }
-- a header and text only: a vampire's blood is in the vitals bar
local TEXT_GUILDS = { Vampire = true }
local function bars_max()
  local n = N.guildName == "Alchemy" and minions_in("out") or (N.gd or {}).pets_max
  return math.max(1, tonumber(n) or 1)
end
local function guild_card_h()
  local row, txt = guild_dims()
  if TEXT_GUILDS[N.guildName] then
    return row + math.floor(N.lh() * 1.35) * 4 + 8   -- powers, toggles, and room for more
  end
  if BAR_GUILDS[N.guildName] then
    -- Alchemy: materials 3, concoctions 1, packed minions two to a line, and a spare
    local lines = N.guildName == "Alchemy" and (5 + math.max(1, math.ceil(packed_count() / 2))) or 5
    local extra = N.guildName == "Druid" and 1 or 0   -- the barkskin bar
    return row * (1 + bars_max() + extra) + math.floor(N.lh() * 1.35) * lines + 8
  end
  return row * 5 + txt   -- 5: header, GP, penalty, wasp, rotation
end
N.guild_card_h = guild_card_h

local function style_guild()
  if not N.gTxt then return end
  N.gHead:setStyleSheet("background-color: #16131f; color: #e6e0f0; padding-left: 6px; "
    .. "qproperty-alignment: 'AlignLeft | AlignVCenter';")
  gauge_style(N.gGp, "#2f8f6a", "#10301f")
  gauge_style(N.gPen, "#3a8f3a", "#1a2a1a")
  gauge_style(N.gWasp, "#b0902a", "#3a300c")
  N.gPenCol = nil
  N.gTxt:setStyleSheet("background-color: #101010; color: #d0d0d0; padding: 4px; "
    .. "qproperty-alignment: 'AlignLeft | AlignTop'; qproperty-wordWrap: true;")
end

local function build_guild(box)
  N.gHead = Geyser.Label:new({ name = "NannyGuildHead", x = 0, y = 0, width = "100%", height = 10 }, box)
  N.gGp = Geyser.Gauge:new({ name = "NannyGuildGp", x = 0, y = 10, width = "100%", height = 10 }, box)
  N.gPen = Geyser.Gauge:new({ name = "NannyGuildPen", x = 0, y = 20, width = "100%", height = 10 }, box)
  N.gWasp = Geyser.Gauge:new({ name = "NannyGuildWasp", x = 0, y = 30, width = "100%", height = 10 }, box)
  N.gTxt = Geyser.Label:new({ name = "NannyGuildTxt", x = 0, y = 40, width = "100%", height = 10 }, box)
  style_guild()
end

-- One gauge per pet, made on first use in the guild pane and kept (a reload keeps the pane).
N.gPetRows = N.gPetRows or {}
local function pet_row(i)
  if N.gPetRows[i] then return N.gPetRows[i] end
  local g = Geyser.Gauge:new({ name = "NannyGuildPet" .. i, x = 0, y = 0, width = "100%", height = 10 },
    N.comps.guild.box)
  gauge_style(g, "#4f8f2f", "#18280f")
  N.gPetRows[i] = g
  return g
end

-- An icon per Strigoi power, looked up by the whole name, then its first word ("shadow_curse"
-- finds shadow). Only emoji that need no variation selector, so they draw on every platform.
N.STRIGOI_ICONS = {
  drain = "🩸", foresee = "🔮", mark = "🎯", soultick = "⏳", evaluate = "🔍", morph = "🎭",
  bane = "🐌", hemal = "🧲", phantom = "👻", phantom_claws = "🐾", phantom_rend = "💥",
  phantom_vitalash = "💗", phantom_wraith = "👻", revivus = "✨", graveveil = "🪦", shift = "🔄",
  harvest = "🌾", purge = "🍖", shadow = "🪱", timewrap = "⌛", wasp = "🐝", wither = "🥀",
  prescience = "👀", vex = "⚡", vex_of_the_mighty = "💪", vex_of_the_storm = "🌀",
  vex_of_the_sage = "📖", vex_of_the_steadfast = "⚓", vex_of_the_unbroken = "🗿",
  ["vex_of_the_sharp-eyed"] = "🦅", acidic = "🧪", rejuvenate = "💚", skullburst = "💀",
  neutrino = "💫", soulstrike = "🔱", umbra = "🌑", wildbound = "🐺", wildbound_razorwind = "💨",
  wildbound_stoneform = "🪨", wildbound_ghostveil = "👤", wildbound_ironmaw = "🦈",
  soulhail = "🧊", embrace = "🦇", extra_combat_damage = "➕",
}
-- variants that share an icon get a small number beside it in the stack
N.STRIGOI_MARKS = {
  acidic_touch_one = 1, acidic_touch_two = 2,
  shadow_leeches_of_vitality = 1, shadow_leeches_of_essence = 2, shadow_leeches_of_soul = 3,
}
local function power_mark(name)
  return N.STRIGOI_MARKS[tostring(name):lower():gsub("%s+", "_")]
end

-- The dark set: plain symbol glyphs, tinted. Blood for feeding and wounds, bone for death,
-- bruise for the spectral, rot for curses and acid. None has an emoji form except the skull:
-- where the font lacks a glyph, Qt falls back to the emoji font and the tint is lost.
local BLOOD, BONE, BRUISE, ROT = "#b02a2a", "#d8cfb8", "#9a7ad0", "#8aa83a"
N.STRIGOI_DARK = {
  drain = { "†", BLOOD }, foresee = { "☽", BRUISE }, mark = { "⌖", BLOOD },
  soultick = { "⧗", BONE }, evaluate = { "◉", BONE }, morph = { "☿", BRUISE },
  bane = { "⚯", ROT }, hemal = { "☩", BLOOD }, phantom = { "♆", BRUISE },
  phantom_claws = { "⋔", BONE }, phantom_rend = { "✕", BLOOD }, phantom_vitalash = { "❥", BLOOD },
  phantom_wraith = { "♆", BRUISE }, revivus = { "☥", BONE }, graveveil = { "♰", BONE },
  shift = { "⇅", BLOOD }, harvest = { "♄", BONE }, purge = { "∅", ROT }, shadow = { "☾", BRUISE },
  timewrap = { "∞", BRUISE }, wasp = { "✷", ROT }, wither = { "❧", ROT },
  prescience = { "⊙", BRUISE }, vex = { "✠", BLOOD }, vex_of_the_mighty = { "♜", BLOOD },
  vex_of_the_storm = { "☈", BRUISE }, vex_of_the_sage = { "☉", BRUISE },
  vex_of_the_steadfast = { "♖", BONE }, vex_of_the_unbroken = { "▣", BONE },
  ["vex_of_the_sharp-eyed"] = { "◎", BLOOD }, acidic = { "⁂", ROT }, rejuvenate = { "☤", BONE },
  skullburst = { "☠", BONE }, neutrino = { "✺", BRUISE }, soulstrike = { "☇", BRUISE },
  umbra = { "◐", BRUISE }, wildbound = { "♞", BONE }, wildbound_razorwind = { "≋", BONE },
  wildbound_stoneform = { "◆", BONE }, wildbound_ghostveil = { "◌", BRUISE },
  wildbound_ironmaw = { "▼", BLOOD }, soulhail = { "✻", BRUISE }, embrace = { "⛧", BLOOD },
  extra_combat_damage = { "✚", BLOOD },
}
-- U+FE0E asks for the plain glyph where a font also has a coloured emoji for it (the skull)
local TEXT_FORM = "\239\184\142"

-- which set: "dark" (the default) or "emoji", kept in the profile directory
local function icons_file() return getMudletHomeDir() .. "/nanny_icons.txt" end
if not N.iconSet then
  local fh = io.open(icons_file(), "r")
  N.iconSet = fh and fh:read("*l") or "dark"
  if fh then fh:close() end
  if N.iconSet ~= "emoji" then N.iconSet = "dark" end
end

local function lookup(t, name)
  local k = tostring(name):lower():gsub("%s+", "_")
  return t[k] or t[k:match("^[^_]+")]
end
local function power_icon(name)
  if N.iconSet == "dark" then
    local d = lookup(N.STRIGOI_DARK, name)
    return d and (d[1] .. TEXT_FORM), d and d[2]
  end
  return lookup(N.STRIGOI_ICONS, name)
end
-- An icon as HTML: in the stack at size, a dark glyph in its tint; on a bar, a dark glyph
-- in bone, since a tint can vanish into the bar's colour.
local function icon_html(name, on_bar)
  local icon, tint = power_icon(name)
  if not icon then return nil end
  if on_bar then return tint and ("<span style='color:" .. BONE .. ";'>" .. icon .. "</span>") or icon end
  return "<span style='font-size:" .. (tint and "14" or "13") .. "pt;" ..
    (tint and (" color:" .. tint .. ";") or "") .. "'>" .. icon .. "</span>"
end

-- The stack as chips: a short name on a dark ground in the power's colour group, readable
-- without learning the icons. Variants get their own short names; any other name is shown
-- whole. "chips" (the default) or "icons", kept in the profile directory.
N.STRIGOI_SHORT = {
  acidic_touch_one = "acid 1", acidic_touch_two = "acid 2",
  shadow_leeches_of_vitality = "leech vit", shadow_leeches_of_essence = "leech ess",
  shadow_leeches_of_soul = "leech soul", purge_of_flesh = "purge",
  phantom_claws = "claws", phantom_rend = "rend", phantom_vitalash = "vitalash",
  phantom_wraith = "wraith", vex_of_the_mighty = "vex might", vex_of_the_storm = "vex storm",
  vex_of_the_sage = "vex sage", vex_of_the_steadfast = "vex stead",
  vex_of_the_unbroken = "vex unbroken", ["vex_of_the_sharp-eyed"] = "vex eye",
  wildbound_razorwind = "razorwind", wildbound_stoneform = "stoneform",
  wildbound_ghostveil = "ghostveil", wildbound_ironmaw = "ironmaw",
  extra_combat_damage = "+dmg",
}
local CHIP_MAX = 14   -- a name longer than this, not in the table above, is cut
local CHIP_GROUND = { [BLOOD] = "#5a1818", [BONE] = "#48433a", [BRUISE] = "#3b2a55", [ROT] = "#34421a" }

local function stack_file() return getMudletHomeDir() .. "/nanny_stack.txt" end
if not N.stackStyle then
  local fh = io.open(stack_file(), "r")
  N.stackStyle = fh and fh:read("*l") or "chips"
  if fh then fh:close() end
  if N.stackStyle ~= "icons" then N.stackStyle = "chips" end
end

local function chip_html(name)
  local k = tostring(name):lower():gsub("%s+", "_")
  local d = lookup(N.STRIGOI_DARK, name)
  local ground = d and CHIP_GROUND[d[2]] or "#333333"
  local s = N.STRIGOI_SHORT[k] or tostring(name)
  if #s > CHIP_MAX then s = s:sub(1, CHIP_MAX - 1) .. "…" end
  return "<span style='background-color:" .. ground .. "; color:#e6dcc8;'>&nbsp;" ..
    esc(s) .. "&nbsp;</span>"
end

-- Timers the game sends no times for: each one's length is learned from when it starts and
-- stops, the median of the last few, kept in a file of its own in the profile directory.
-- on[name] = { t = when it started, clean = whether the start was seen }.
local TIMER_KEEP = 5
local function timer_set(file)
  local T = { learned = {}, on = {}, primed = false }
  local path = getMudletHomeDir() .. "/" .. file
  if type(table.load) == "function" then pcall(table.load, path, T.learned) end

  function T.length(name)
    local s = T.learned[name]
    if type(s) ~= "table" or #s == 0 then return nil end
    local c = {}
    for i, d in ipairs(s) do c[i] = d end
    table.sort(c)
    return c[math.ceil(#c / 2)]
  end

  -- every name known, learned or running now, in a fixed order
  function T.names()
    local seen, out = {}, {}
    for k in pairs(T.learned) do seen[k] = true end
    for k in pairs(T.on) do seen[k] = true end
    for k in pairs(seen) do out[#out + 1] = k end
    table.sort(out)
    return out
  end

  -- cur: the set of names running now. The first call of a session finds some already
  -- running, started who knows when, so those teach nothing.
  function T.update(cur)
    local now = getEpoch()
    for k in pairs(cur) do
      if not T.on[k] then T.on[k] = { t = now, clean = T.primed } end
    end
    for k, on in pairs(T.on) do
      if not cur[k] then
        if on.clean then
          local s = T.learned[k] or {}
          s[#s + 1] = math.floor(now - on.t + 0.5)
          while #s > TIMER_KEEP do table.remove(s, 1) end
          T.learned[k] = s
          if type(table.save) == "function" then pcall(table.save, path, T.learned) end
        end
        T.on[k] = nil
      end
    end
    T.primed = true
  end
  return T
end

-- Strigoi cooldowns: every name in "active" but the wasp (it has its own gauge), the totem
-- (two seconds, not worth a bar) and the *_cast_timestamp twins, matched by first word.
-- Druid buffs: barkskin, from its "on".
N.cd = N.cd or timer_set("nanny_cooldowns.lua")
N.buffs = N.buffs or timer_set("nanny_buffs.lua")
local CD_SKIP = { wasp = true, totem = true }
local function cd_skip(k)
  return CD_SKIP[k:match("^[^_]+")] or k:match("_cast_timestamp$")
end

-- Strigoi buffs the game sends no times for: harvest, on while any stat has a harvest bonus.
-- A new harvest while one is on raises the bonus and starts the timer again.
N.sbuffs = N.sbuffs or timer_set("nanny_strigoi_buffs.lua")
function N.track_harvest(temp)
  local sum = 0
  for _, x in pairs(type(temp) == "table" and temp or {}) do sum = sum + math.abs(tonumber(x) or 0) end
  -- the game's text runs ahead of its data: a bonus not yet sent, or one not yet taken away
  local on = N.sbuffs.on.harvest
  if sum == 0 then N.harvestFaded = nil end
  if (sum == 0 and on and on.text and getEpoch() - on.t < 10) or (sum > 0 and N.harvestFaded) then return end
  if on and sum > (N.harvestSum or 0) and getEpoch() - on.t > 5 then
    N.sbuffs.on.harvest = { t = getEpoch(), clean = true }
  end
  N.harvestSum = sum
  N.sbuffs.update(sum > 0 and { harvest = true } or {})
end

-- The game's own lines: a harvest that worked (worded by the stat gained) and its end. A gain
-- line restarts the bar, since a second harvest can leave the bonus as it was; one a moment
-- after the guild data started it is the same harvest.
local HARVEST_LINES = "^(?:> )*(?:The (?:magical )?essence of the dead (fades|fills you|empowers you)"
  .. "|You look lighter, your movements silent like the shadows!"
  .. "|Your muscles swell with strength, gaining the power of the fallen!)"
function N.harvest_line(what)
  if N.guildName ~= "Strigoi" then return end
  local now, on = getEpoch(), N.sbuffs.on.harvest
  if what == "fades" then
    N.sbuffs.update({})
    N.harvestSum, N.harvestFaded = 0, true
  else
    N.harvestFaded = nil
    if not on or now - on.t > 5 then N.sbuffs.on.harvest = { t = now, clean = true, text = true } end
  end
  N.draw_cooldowns()
end

function N.track_cooldowns(active)
  if type(active) ~= "table" then return end
  local cur = {}
  for _, x in ipairs(active) do
    local k = tostring(x)
    if not cd_skip(k) then cur[k] = true end
  end
  N.cd.update(cur)
end

-- A bar that empties as a buff wears off: time left once its length is learned, counting up
-- until then; amber while it shimmers, dim when off.
local function buff_bar(g, name, on, shimmering)
  local run, len, now = N.buffs.on[name], N.buffs.length(name), getEpoch()
  local col
  if not on then
    col = "#2a2a2a"
    g:setValue(0, 1, name .. "  off")
  elseif run and len then
    local left = math.max(0, math.ceil(run.t + len - now))
    col = shimmering and "#b07a20" or "#4f7f3f"
    g:setValue(left, math.max(len, 1), name .. "  " .. left .. "s")
  else
    col = shimmering and "#b07a20" or "#4f7f3f"
    -- counting up only from a start that was seen
    g:setValue(1, 1, name .. ((run and run.clean) and ("  " .. math.floor(now - run.t) .. "s, learning") or "  on"))
  end
  if g.cdCol ~= col then g.cdCol = col ; gauge_style(g, col, "#161a14") end
end

local function bark_row()
  if not N.gBark then
    N.gBark = Geyser.Gauge:new({ name = "NannyGuildBark", x = 0, y = 0, width = "100%", height = 10 },
      N.comps.guild.box)
  end
  return N.gBark
end

-- barkskin from the druid's last message; the second timer redraws it between messages
function N.draw_bark()
  if not (N.comps.guild and N.comps.guild.box) then return end
  local bk = type(N.gd.barkskin) == "table" and N.gd.barkskin or {}
  buff_bar(bark_row(), "barkskin", tonumber(bk.on) == 1, tonumber(bk.shimmering) == 1)
end

-- an icon in a slot of fixed width, so text after it lines up whatever the glyph's width
local SLOT_W = 24
local function slotted(icon, text)
  if not icon then return text end
  return "<table cellspacing='0' cellpadding='0'><tr><td width='" .. SLOT_W ..
    "' align='center'>" .. icon .. "</td><td>&nbsp;" .. text .. "</td></tr></table>"
end

-- ================= tome spells ====================================================
-- The game never says when a chanted spell can be chanted again, so each length is bracketed
-- from play: a refusal proves it is longer than the time since release, a chant that works
-- proves it is no longer than that. Why: basics/README.md, Tome.
local TOME_ANSWER, TOME_SLOP = 5, 2   -- seconds a chant may wait for its answer; timing jitter
local TOME_TIGHT = 5                  -- limits this close are as good as knowing the length
local TOME_LINES = "^(?:> )*(You feel the magic power surrounds you as you chant"
  .. "|You feel mentally exhausted, and fail to memorize"
  .. "|You point at .+ and\\b|(?:turn )?(?:the )?powers loose\\.$)"

local function tome_load()
  local t = { spells = {}, on = {} }
  if type(table.load) == "function" then pcall(table.load, getMudletHomeDir() .. "/nanny_tome.lua", t) end
  t.spells, t.on, t.hidden = t.spells or {}, t.on or {}, t.hidden or {}
  return t
end
N.tome = N.tome or tome_load()
local TM = N.tome
TM.asked = TM.asked or {}             -- chants sent and not answered yet, oldest first
TM.hidden = TM.hidden or {}           -- spells whose bar the player hid; what was learned is kept
TM.probe = TM.probe or {}             -- spells being probed this session: word -> time of last chant
N.cRows = N.cRows or {}

local function tome_save()
  if type(table.save) ~= "function" then return end
  pcall(table.save, getMudletHomeDir() .. "/nanny_tome.lua",
    { spells = TM.spells, on = TM.on, stored = TM.stored, hidden = TM.hidden })
end

local function tome_names()
  local out = {}
  for k in pairs(TM.spells) do out[#out + 1] = k end
  table.sort(out)
  return out
end

-- only spells the game has refused: nothing else proves a spell has a cooldown at all
local function tome_bars()
  local out = {}
  for _, w in ipairs(tome_names()) do
    local s = TM.spells[w]
    if (s.cd or s.lo) and not TM.hidden[w] then out[#out + 1] = w end
  end
  return out
end

local function tome_used() return TM.stored ~= nil or next(TM.spells) ~= nil end

-- the Strigoi's bars; the skip list also hides a length learned before a name joined it
local function strigoi_cds()
  local names = {}
  if N.guildName ~= "Strigoi" then return names end
  for _, k in ipairs(N.cd.names()) do if not cd_skip(k) then names[#names + 1] = k end end
  return names
end

-- the Strigoi's buffs running now: a bar only while one is on
local function strigoi_buffs()
  local names = {}
  if N.guildName ~= "Strigoi" then return names end
  for _, k in ipairs(N.sbuffs.names()) do if N.sbuffs.on[k] then names[#names + 1] = k end end
  return names
end

function N.cd_wanted() return tome_used() or #strigoi_cds() > 0 or #strigoi_buffs() > 0 end

-- the space between two groups of bars on the Cooldowns card
local CD_GAP = 4

function N.cd_card_h()
  local row = guild_dims()
  local groups = 0
  for _, k in ipairs({ #strigoi_buffs(), #strigoi_cds(), #tome_bars() }) do if k > 0 then groups = groups + 1 end end
  return row * ((tome_used() and 1 or 0) + #strigoi_cds() + #strigoi_buffs() + #tome_bars())
    + math.max(0, groups - 1) * CD_GAP + 4
end

-- every command going out; a line can hold several, split by the game on ';'
function N.tome_sent(_, cmd)
  for part in tostring(cmd or ""):gmatch("[^;]+") do
    local w = part:match("^%s*[Cc]hant%s+(.-)%s*$")
    if w and w ~= "" then TM.asked[#TM.asked + 1] = { word = w:lower(), t = getEpoch(), probe = N._probing } end
  end
end

-- the chant this answer belongs to, and its record; nil if none was seen recently
local function tome_take()
  local now = getEpoch()
  while TM.asked[1] and now - TM.asked[1].t > TOME_ANSWER do table.remove(TM.asked, 1) end
  local a = table.remove(TM.asked, 1)
  return a and a.word, a
end

local function tome_worked(s, e)
  s.hi = math.min(s.hi or math.huge, math.ceil(e))
  if e < (s.lo or 0) - TOME_SLOP then s.lo = nil
  elseif (s.lo or 0) > s.hi then s.lo = s.hi end
end

local function tome_refused(s, e)
  s.lo = math.max(s.lo or 0, math.floor(e))
  if s.hi and e > s.hi + TOME_SLOP then s.hi = nil
  elseif s.hi and s.hi < s.lo then s.hi = s.lo end
end

function N.tome_line(text)
  local now = getEpoch()
  if text:find("^You feel the magic") then
    local w = tome_take()
    TM.stored = w or "?"
    if w then
      if TM.probe[w] then TM.probe[w].miss = 0 end
      TM.spells[w] = TM.spells[w] or {}
      if TM.on[w] then tome_worked(TM.spells[w], now - TM.on[w]) ; TM.on[w] = nil end
    end
  elseif text:find("^You feel mentally") then
    local w, a = tome_take()
    if not w then return end
    if TM.probe[w] then TM.probe[w].miss = 0 end
    -- a probe's refusal every few seconds would bury the game's text
    if a.probe and type(deleteLine) == "function" then deleteLine() end
    local s = TM.spells[w] or {}
    TM.spells[w], s.cd = s, true
    if TM.on[w] then tome_refused(s, now - TM.on[w]) end
  else
    local w = TM.stored
    if not w then return end
    TM.stored = nil
    if w ~= "?" then
      TM.spells[w] = TM.spells[w] or {}
      TM.on[w] = now
    end
  end
  tome_save()
  N.draw_cooldowns()
end

-- ---- probing: chant a released spell every few seconds until a chant works ----
-- It never chants while a spell is stored, which a chant that works would replace.
local PROBE_EVERY, PROBE_MISS = 3, 2

local function learned(s) return s and s.lo and s.hi and s.hi - s.lo <= TOME_TIGHT end

local function probe_stop(w, why)
  TM.probe[w] = nil
  if why then say(why) end
  if not next(TM.probe) and N.tProbeT then pcall(killTimer, N.tProbeT) ; N.tProbeT = nil end
end

local function asked_for(w)
  for _, a in ipairs(TM.asked) do if a.word == w then return true end end
  return false
end

function N.tome_probe_tick()
  local now = getEpoch()
  -- a probe's chant with no answer at all: no tome, asleep, or a word the game does not know
  for i = #TM.asked, 1, -1 do
    local a = TM.asked[i]
    if a.probe and now - a.t > TOME_ANSWER then
      table.remove(TM.asked, i)
      local p = TM.probe[a.word]
      if p then
        p.miss = p.miss + 1
        if p.miss >= PROBE_MISS then probe_stop(a.word, "probing " .. a.word .. " stopped: the game did not answer its chant.") end
      end
    end
  end
  for w, p in pairs(TM.probe) do
    local s = TM.spells[w]
    if learned(s) then
      probe_stop(w, string.format("%s learned: its cooldown is %d to %d seconds. Probing stopped.", w, s.lo, s.hi))
    elseif TM.on[w] and TM.stored == nil and now - p.last >= PROBE_EVERY and not asked_for(w) then
      p.last = now
      N._probing = true
      send("chant " .. w, false)
      N._probing = nil
    end
  end
end

local function probe_start(w)
  TM.probe[w] = { last = 0, miss = 0 }
  if not N.tProbeT and type(tempTimer) == "function" then
    N.tProbeT = tempTimer(1, function() N.tome_probe_tick() end, true)
  end
end

-- An icon per tome spell, found by any word of its name, so whichever word is chanted
-- ("golden" or "touch") finds it. Emoji only where no variation selector is needed.
N.TOME_ICONS = {
  fireball = "🔥", farflung = "🔥", fearful = "😨", fear = "😨", sword = "🤺", instant = "🤺",
  sensitive = "👀", combat = "😤", fury = "😤", heal = "🩹", others = "🩹", stamina = "🏃",
  unnatural = "🏃", water = "🐟", breathing = "🐟", illusion = "🪞", multiplicative = "🪞",
  delay = "⌛", red = "⌛", midas = "🪙", golden = "🪙", touch = "🪙", curse = "🧿",
  slow = "🐌", thunder = "🔊", deafening = "🔊", control = "🎯",
  amplifier = "📢", damage = "📢", duplicator = "🔁", hastiness = "💨", haste = "💨",
  ice = "🧊", arrow = "🧊", iron = "👊", fist = "👊", lightning = "⚡", mastery = "🎓",
  rain = "☔", targeted = "☔", thunderbolt = "💥",
}
-- the dark set's plain glyphs, drawn in bone on the bar like the Strigoi's
N.TOME_DARK = {
  fireball = "✹", farflung = "✹", fearful = "⊗", fear = "⊗", sword = "†", instant = "†",
  sensitive = "◉", combat = "✶", fury = "✶", heal = "✚", others = "✚", stamina = "⇑",
  unnatural = "⇑", water = "≈", breathing = "≈", illusion = "❖", multiplicative = "❖",
  delay = "⧖", red = "⧖", midas = "◈", golden = "◈", touch = "◈", curse = "☋",
  slow = "∿", thunder = "❂", deafening = "❂", control = "⌖",
  amplifier = "⊕", damage = "⊕", duplicator = "⧉", hastiness = "»", haste = "»",
  ice = "✧", arrow = "✧", iron = "■", fist = "■", lightning = "↯", mastery = "♛",
  rain = "⁞", targeted = "⁞", thunderbolt = "☇",
}
local function tome_icon(w)
  local k = tostring(w):lower()
  local t = N.iconSet == "dark" and N.TOME_DARK or N.TOME_ICONS
  local icon = t[k]
  if not icon then
    for x in k:gmatch("%a+") do if t[x] then icon = t[x] ; break end end
  end
  if icon and N.iconSet == "dark" then
    return "<span style='color:" .. BONE .. ";'>" .. icon .. TEXT_FORM .. "</span>"
  end
  return icon
end

-- value, max, text, colour and ground of one spell's bar
local function tome_bar(w, now)
  local on, s = TM.on[w], TM.spells[w] or {}
  local e, lo, hi, g = on and now - on, s.lo or 0, s.hi, "#16182a"
  local icon = tome_icon(w)
  local function label(t) return slotted(icon, w .. "  " .. t) end
  if not on or (hi and e >= hi) then return 1, 1, label("ready"), "#3a8f3a", g end
  local sure = hi and hi - lo <= TOME_TIGHT and hi or lo
  if e < sure then return e, hi or lo, label(math.ceil(sure - e) .. "s"), "#4a5a9a", g end
  if hi then return e, hi, label("maybe, sure in " .. math.ceil(hi - e) .. "s"), "#b07a20", g end
  return 0, 1, label(math.floor(e) .. "s, learning"), "#4a5a9a", g
end

-- the same for a Strigoi power, whose start and stop the game reports
local function strigoi_bar(k, now)
  local on, len = N.cd.on[k], N.cd.length(k)
  local icon, dark = icon_html(k, true), N.iconSet == "dark"
  local label, ground = k:gsub("_", " "), dark and "#140e1a" or "#16182a"
  local running = dark and "#3b2a55" or "#4a5a9a"
  if not on then return 1, 1, slotted(icon, label .. "  ready"), dark and "#6e1c1c" or "#3a8f3a", ground end
  if len then
    local left = math.ceil(on.t + len - now)
    if left < 0 then return len, len, slotted(icon, label .. "  " .. -left .. "s over"), running, ground end
    return len - left, len, slotted(icon, label .. "  " .. left .. "s"), running, ground
  end
  return 0, 1, slotted(icon, label .. "  " .. math.floor(now - on.t) .. "s, learning"), running, ground
end

-- a Strigoi buff: empties as it wears off once its length is learned, counts up until then
local function sbuff_bar(k, now)
  local run, len = N.sbuffs.on[k], N.sbuffs.length(k)
  local icon, col, ground = icon_html(k, true), "#2f6f9a", "#101c26"
  if len then
    local left = math.ceil(run.t + len - now)
    -- still on past what was learned: the length varies, so say by how much
    if left < 0 then return 0, len, slotted(icon, k .. " bonus  " .. -left .. "s over"), col, ground end
    return left, len, slotted(icon, k .. " bonus  " .. left .. "s"), col, ground
  end
  -- counting up only from a start that was seen
  local up = run.clean and ("  " .. math.floor(now - run.t) .. "s, learning") or "  on"
  return 1, 1, slotted(icon, k .. " bonus" .. up), col, ground
end

local function cd_row(i)
  if N.cRows[i] then return N.cRows[i] end
  local g = Geyser.Gauge:new({ name = "NannyCd" .. i, x = 0, y = 0, width = "100%", height = 10 },
    N.comps.cooldowns.box)
  N.cRows[i] = g
  return g
end

local function cd_set(g, v, max, text, col, ground)
  if text ~= g.cdText then g.cdText = text ; g:setValue(v, math.max(max, 1), text) end
  if col ~= g.cdCol then g.cdCol = col ; gauge_style(g, col, ground) end
end

-- A bar per cooldown, filling as it recharges: full when ready.
function N.draw_cooldowns()
  if not (N.comps.cooldowns and N.tStored) then return end
  local now, n = getEpoch(), 0
  -- buffs, then the Strigoi's cooldowns, then the tome's; a gap where the group changes
  local group = {}
  for _, k in ipairs(strigoi_buffs()) do n = n + 1 ; group[n] = 1 ; cd_set(cd_row(n), sbuff_bar(k, now)) end
  for _, k in ipairs(strigoi_cds()) do n = n + 1 ; group[n] = 2 ; cd_set(cd_row(n), strigoi_bar(k, now)) end
  for _, w in ipairs(tome_bars()) do n = n + 1 ; group[n] = 3 ; cd_set(cd_row(n), tome_bar(w, now)) end
  N.cdGroup = group
  local stored = TM.stored == "?" and "a spell" or TM.stored
  local head = "Stored: " .. (stored and ("<b>" .. esc(stored) .. "</b>") or "nothing")
  if head ~= N.tHead then N.tHead = head ; N.tStored:echo(head) end
  local shape = n .. tostring(tome_used()) .. table.concat(group)
  if shape ~= N.cdShape then N.cdShape, N.cdShown = shape, n ; N.relayout() end
end

local function build_cooldowns(box)
  N.tStored = Geyser.Label:new({ name = "NannyTomeStored", x = 0, y = 0, width = "100%", height = 10 }, box)
  N.tStored:setStyleSheet("background-color: #16131f; color: #e6e0f0; padding-left: 6px; "
    .. "qproperty-alignment: 'AlignLeft | AlignVCenter';")
end

local function fit_cooldowns(_, h)
  if not N.tStored then return end
  local row, rows = guild_dims(), {}
  if tome_used() then rows[1] = { N.tStored, row - 2, row }
  else pcall(function() N.tStored:hide() end) end
  for i, g in ipairs(N.cRows) do
    if i <= (N.cdShown or 0) then
      local next_g = (N.cdGroup or {})[i + 1]
      rows[#rows + 1] = { g, row - 2, row + ((next_g and next_g ~= N.cdGroup[i]) and CD_GAP or 0) }
    else pcall(function() g:hide() end) end
  end
  fit_rows(h, rows)
end

function N.tome_cmd(rest)
  local verb, word = rest:match("^(%S+)%s*(.-)%s*$")
  word = (word or ""):lower()
  if verb == "relearn" then
    local any_spell = false
    for w, s in pairs(TM.spells) do
      if word == "" or w == word then s.lo, any_spell = nil, true end
    end
    if not any_spell then say("no bar called '" .. word .. "'.") return end
    tome_save()
    N.draw_cooldowns()
    say((word == "" and "every spell" or word) .. ": try it early, the bar will say maybe from the release.")
    return
  elseif verb == "forget" and word ~= "" then
    if not TM.spells[word] then say("no bar called '" .. word .. "'.") return end
    TM.spells[word], TM.on[word], TM.hidden[word] = nil, nil, nil
    probe_stop(word)
    tome_save()
    N.draw_cooldowns()
    say("forgot " .. word .. ".")
    return
  elseif (verb == "hide" or verb == "show") and word ~= "" then
    if not TM.spells[word] then say("no spell called '" .. word .. "' has been chanted.") return end
    TM.hidden[word] = verb == "hide" or nil
    tome_save()
    N.draw_cooldowns()
    say(word .. (verb == "hide" and " hidden; what was learned is kept. 'nanny tome show " .. word .. "' brings it back."
      or " shown again."))
    return
  elseif verb == "probe" and word ~= "" then
    if word == "off" then
      for w in pairs(TM.probe) do probe_stop(w) end
      say("probing stopped.")
      return
    end
    if learned(TM.spells[word]) then say(word .. " is already learned; 'nanny tome relearn " .. word .. "' first.") return end
    probe_start(word)
    say("probing " .. word .. ": after you release it, it is chanted every " .. PROBE_EVERY .. " seconds until a chant"
      .. " works, never while a spell is stored. It stops once the cooldown is known; 'nanny tome probe off' stops it now.")
    return
  end
  say("stored: " .. tostring(TM.stored or "nothing") .. ". 'nanny help tome' for the commands.")
  for _, w in ipairs(tome_names()) do
    local s = TM.spells[w]
    say(w .. ": " .. (s.hi and ("at most " .. s.hi .. "s") or "no upper limit yet") ..
      (s.lo and (", more than " .. s.lo .. "s") or "") ..
      ((s.cd or s.lo) and "" or ", never refused so no bar") ..
      (TM.hidden[w] and ", hidden" or "") .. (TM.probe[w] and ", probing" or ""))
  end
end

-- The rotation strip, made on first use: a reload keeps the pane built by the copy before it.
local function rot_row()
  if not N.gRot then
    N.gRot = Geyser.Label:new({ name = "NannyGuildRot", x = 0, y = 0, width = "100%", height = 10 },
      N.comps.guild.box)
    N.gRot:setStyleSheet("background-color: #1a1a24; color: #d0d0d0; padding-left: 6px; "
      .. "qproperty-alignment: 'AlignLeft | AlignVCenter';")
    N.gRot:setClickCallback(function(ev) N.rot_click(ev) end)
    N.rot_draw()
  end
  return N.gRot
end

local function fit_guild(w, h)
  if not N.gTxt then return end
  N.gW, N.gH = w, h
  local row = guild_dims()
  local strigoi = { N.gGp, N.gPen, N.gWasp, rot_row() }
  local rows = { { N.gHead, row - 2, row } }
  if TEXT_GUILDS[N.guildName] then
    local all = { N.gBark }
    for _, list in ipairs({ strigoi, N.gPetRows }) do
      for _, gg in ipairs(list) do all[#all + 1] = gg end
    end
    for _, gg in pairs(all) do pcall(function() gg:hide() end) end
  elseif BAR_GUILDS[N.guildName] then
    for _, gg in ipairs(strigoi) do pcall(function() gg:hide() end) end
    for i, r in ipairs(N.gPetRows) do
      if i <= (N.gPetsShown or 0) then rows[#rows + 1] = { r, row - 2, row }
      else pcall(function() r:hide() end) end
    end
    if N.gBark then
      if N.guildName == "Druid" then rows[#rows + 1] = { N.gBark, row - 2, row }
      else pcall(function() N.gBark:hide() end) end
    end
  else
    for _, r in ipairs(N.gPetRows) do pcall(function() r:hide() end) end
    if N.gBark then pcall(function() N.gBark:hide() end) end
    for _, gg in ipairs(strigoi) do rows[#rows + 1] = { gg, row - 2, row } end
  end
  fit_rows(h, rows, N.gTxt)
end

-- the penalty bar turns amber, then red, as repeating yourself starts to cost
local function penalty_colour(p)
  local c = (p >= 35 and "#b03030") or (p >= 10 and "#b07a20") or "#3a8f3a"
  if c ~= N.gPenCol then
    N.gPenCol = c
    N.gPen.front:setStyleSheet("background-color: " .. c .. "; border-radius: 3px;")
  end
end

local function list(t, empty)
  if type(t) ~= "table" or #t == 0 then return empty end
  local out = {}
  for i, x in ipairs(t) do out[i] = esc(type(x) == "table" and json(x) or x) end
  return table.concat(out, " &#183; ")
end

-- the stack's count, then its chips, or a row of icons in slots of fixed width (a name with
-- no icon yet shown as text)
local function stack_icons(st, size)
  if N.stackStyle == "chips" then
    local chips = {}
    for i, x in ipairs(st) do chips[i] = chip_html(type(x) == "table" and json(x) or tostring(x)) end
    return #st .. "/" .. esc(size or "?") .. " &#183; " .. (#st > 0 and table.concat(chips, " ") or "empty")
  end
  local cells = { "<td>" .. #st .. "/" .. esc(size or "?") .. " &#183;&nbsp;</td>" }
  if #st == 0 then cells[2] = "<td>empty</td>" end
  for _, x in ipairs(st) do
    local name = type(x) == "table" and json(x) or tostring(x)
    local icon, mark = icon_html(name), power_mark(name)
    cells[#cells + 1] = icon and ("<td width='" .. (SLOT_W + 6) .. "' align='center'>" .. icon ..
      (mark and ("<sub style='color:#e0b64a; font-weight:bold;'>" .. mark .. "</sub>") or "") .. "</td>")
      or ("<td>&nbsp;" .. esc(name) .. "&nbsp;</td>")
  end
  return "<table cellspacing='0' cellpadding='0'><tr>" .. table.concat(cells) .. "</tr></table>"
end

N.gd = N.gd or {}
function N.guild(name, v)
  if type(v) ~= "table" then return end
  local gname = name:match("^Guild%.(.+)$") or name
  if gname ~= N.guildName then
    N.gd, N.guildName = {}, gname
    N.draw_cooldowns()                 -- another guild's bars must not stay on the card
    N.relayout()                       -- first message (or a new guild): place the pane, retitle it
  end
  -- Owl is Guild.Druid.Owl's own message, kept under Guild.Druid by Mudlet
  for k, val in pairs(v) do if k ~= "Owl" then N.gd[k] = val end end
  if gname == "Strigoi" then N.track_cooldowns(v.active) ; N.track_harvest(N.gd.temp) end
  local g = N.gd
  if gname == "Vampire" then N.blood(g.bp, g.maxbp) end
  if not N.gTxt then return end
  if N.guildName == "Vampire" then return N.render_vampire(g) end
  if N.guildName == "Druid" then return N.render_druid(g) end
  if N.guildName == "Alchemy" then return N.render_alchemy(g) end
  local dmg = type(g.damage) == "table" and table.concat(g.damage, " / ") or tostring(g.damage or "")
  N.gHead:echo(string.format("<b>Level %s</b> &#183; %s &#183; <span style='color:#9a93b0;'>%s</span>",
    esc(g.level or "?"), esc(g.form or "?"), esc(dmg)))
  local pts, nx = tonumber(g.points), tonumber(g.next)
  -- base is the GP the current level starts at, so the bar fills within the level
  local base = tonumber(g.base) or 0
  if pts and nx then
    N.gGp:setValue(math.max(pts - base, 0), math.max(pts + nx - base, 1),
      "GP  " .. commas(pts) .. " / " .. commas(pts + nx))
  elseif pts then N.gGp:setValue(1, 1, "GP " .. commas(pts)) end
  local p = tonumber(g.penalty) or 0
  penalty_colour(p)
  N.gPen:setValue(math.max(0, math.min(p, 100)), 100, "Penalty  " .. p .. "%")
  local w = type(g.wasp) == "table" and g.wasp
  if w and tonumber(w.out) == 1 then
    N.gWasp:setValue(tonumber(w.hp) or 0, math.max(1, tonumber(w.maxhp) or 1),
      "Wasp L" .. tostring(w.level or "?") .. "  " .. tostring(w.hp or "?") .. "/" .. tostring(w.maxhp or "?"))
  else
    N.gWasp:setValue(0, 1, "Wasp: not out")
  end
  N.draw_cooldowns()
  -- Char.Status sends base stats; the guild sends its total change, of which temp is the part
  -- from harvest. Shown as total (guild) (harvest).
  local temp = type(g.temp) == "table" and g.temp or {}
  local function paren(d, col)
    if d == 0 then return "" end
    return string.format(" <span style='color:%s;'>(%s%d)</span>", col, d > 0 and "+" or "", d)
  end
  local function stat(k)
    local d, t, base = tonumber(g[k]) or 0, tonumber(temp[k]) or 0, tonumber(N.st[k])
    return (base and tostring(base + d) or "?") ..
      paren(d - t, d - t > 0 and "#70c070" or "#d06060") .. paren(t, "#6fb8e0")
  end
  local st, sk = type(g.stack) == "table" and g.stack or {}, type(g.soultick) == "table" and g.soultick or {}
  -- growth since the soulmark as the game's 'soultick' shows it: total, then per (combat) beat
  local gp, hb, chb = tonumber(sk.guild_points) or 0, tonumber(sk.hb) or 0, tonumber(sk.combat_hb) or 0
  local tick = commas(gp) .. " gp"
  if hb > 0 then tick = tick .. " &#183; " .. commas(math.floor(gp / hb)) .. " per beat" end
  if chb > 0 then tick = tick .. " &#183; " .. commas(math.floor(gp / chb)) .. " per combat beat" end
  -- since 'soultick reset', at a heartbeat of about 2 s: 1800 beats an hour
  local gph = hb > 0 and per_hour(gp / hb * 1800) or "..."
  local H = "color:#e0b64a; font-weight:bold;"
  N.gTxt:echo(string.format(
    "<table width='100%%' cellspacing='0' cellpadding='1' style='font-size:10pt;'>" ..
    "<tr><td style='%s'>Soultick</td><td>%s</td></tr>" ..
    "<tr><td style='%s'>GP/hr</td><td style='color:#b8a6e6;'>%s</td></tr>" ..
    "</table>" ..
    "<table width='100%%' cellspacing='0' cellpadding='1' style='font-size:10pt; color:#dddddd;'>" ..
    "<tr><td style='%s'>Str</td><td align='right'>%s</td><td width='16'></td><td style='%s'>Int</td><td align='right'>%s</td></tr>" ..
    "<tr><td style='%s'>Dex</td><td align='right'>%s</td><td></td><td style='%s'>Con</td><td align='right'>%s</td></tr>" ..
    "</table>" ..
    -- last, so its varying wrap moves nothing above it
    "<table width='100%%' cellspacing='0' cellpadding='1' style='font-size:10pt;'>" ..
    "<tr><td style='%s'>Stack</td><td>%s</td></tr>" ..
    "</table>",
    H, tick, H, gph,
    H, stat("str"), H, stat("int"), H, stat("dex"), H, stat("con"),
    H, stack_icons(st, g.stack_size)))
end

-- A buff as a tag: lit while on, amber while it is about to wear off, dim when off.
local function tag(name, on, fading)
  local c = (fading and "#e0a030") or (on and "#70c070") or "#555555"
  return string.format("<span style='color:%s;%s'>%s</span>", c, on and " font-weight:bold;" or "", name)
end

local DRUID_SHOWN = { arch_druid = true }   -- the arch tag among the buffs

-- Guild.Druid: level, points, tree, arch (whether you are the arch druid now), harmony,
-- staff {held, wielded, fireflies}, wand {held}, barkskin {on, shimmering}, pets, effects.
-- The spells stored in the wand, from 'help druids gmcp' (shape not yet seen): any list or
-- mapping under wand but "held", as names, or "name xN" for counts.
local function wand_spells(w)
  local out = {}
  for k, val in pairs(w) do
    if k ~= "held" then
      if type(val) == "table" then
        if #val > 0 then
          for _, s in ipairs(val) do out[#out + 1] = esc(type(s) == "table" and json(s) or s) end
        else
          for name, n in pairs(val) do
            out[#out + 1] = esc(name) .. ((tonumber(n) or 1) > 1 and (" &#215;" .. n) or "")
          end
        end
      elseif type(k) == "number" then out[#out + 1] = esc(val)
      else out[#out + 1] = esc(k) .. " " .. esc(val) end
    end
  end
  table.sort(out)
  return out
end

function N.render_druid(g)
  -- an Elder is also sent gexp (percent) and place (among all druids by guild points)
  local head = string.format("<b>Level %s</b> &#183; %s", esc(g.level or "?"), esc(g.tree or "?"))
  if g.gexp ~= nil then head = head .. " &#183; gexp " .. esc(tostring(g.gexp):gsub("%%$", "")) .. "%" end
  if g.place ~= nil then head = head .. " &#183; #" .. esc(g.place) end
  N.gHead:echo(head)
  local pets = type(g.pets) == "table" and g.pets or {}
  local max = bars_max()
  if max ~= N.gPetsMax then N.gPetsMax = max ; N.relayout() end   -- room for another pet row
  for i = 1, math.min(#pets, max) do
    local p, row = pets[i], pet_row(i)
    local hp = math.max(0, math.min(tonumber(p.hp) or 0, 100))
    row:setValue(hp, 100, esc(p.name or "?") .. "  " .. hp .. "%" ..
      (tonumber(p.here) == 1 and "" or "  (away)"))
  end
  if N.gPetsShown ~= math.min(#pets, max) then
    N.gPetsShown = math.min(#pets, max)
    if N.gW then fit_guild(N.gW, N.gH) end
  end
  local bk = type(g.barkskin) == "table" and g.barkskin or {}
  N.buffs.update(tonumber(bk.on) == 1 and { barkskin = true } or {})
  N.draw_bark()
  local st = type(g.staff) == "table" and g.staff or {}
  local hm = tonumber(g.harmony) or 0
  local staff = tonumber(st.wielded) == 1 and "staff (wielded)" or (tonumber(st.held) == 1 and "staff" or nil)
  local gear = {}
  gear[#gear + 1] = staff and tag(staff, true) or tag("no staff", false)
  local wand = type(g.wand) == "table" and g.wand or {}
  if tonumber(wand.held) == 1 then
    local spells = wand_spells(wand)
    gear[#gear + 1] = tag("wand", true) .. (#spells > 0 and (": " .. table.concat(spells, ", ")) or "")
  else
    gear[#gear + 1] = tag("no wand", false)
  end
  local buffs = {
    tag("arch", tonumber(g.arch) == 1),
    tag("fireflies", tonumber(st.fireflies) == 1),
    tag(hm > 1 and ("harmony " .. hm) or "harmony", hm > 0),
  }
  local H = "color:#e0b64a; font-weight:bold;"
  -- effects the pane already shows elsewhere
  local fx = {}
  for _, e in ipairs(type(g.effects) == "table" and g.effects or {}) do
    if not DRUID_SHOWN[e] then fx[#fx + 1] = e end
  end
  fx = list(fx, nil)
  N.gTxt:echo(string.format(
    "<table width='100%%' cellspacing='0' cellpadding='1' style='font-size:10pt;'>" ..
    "<tr><td style='%s'>Points</td><td>%s</td></tr>" ..
    "<tr><td style='%s'>Buffs</td><td>%s</td></tr>" ..
    "<tr><td style='%s'>Gear</td><td>%s</td></tr>" ..
    "<tr><td style='%s'>Pets</td><td>%d/%d</td></tr>" ..
    (fx and "<tr><td style='%s'>Effects</td><td>%s</td></tr>" or "%s%s") ..
    "</table>",
    H, commas(tonumber(g.points) or 0),
    H, table.concat(buffs, " &#183; "),
    H, table.concat(gear, " &#183; "),
    H, #pets, max,
    fx and H or "", fx or ""))
end

-- Guild.Vampire, from 'help vampire_gmcp' (no live payload seen yet): bp, maxbp (into the
-- vitals bar), gen, potency, age (online, in minutes), veil, celerity, toggles (bpinfo,
-- autosuck, shape, wimpy in BP with 0 off, and for the eldest hide shape). A flag may come as
-- 1/0, true/false or "on"/"off"; toggles as a mapping or as a list of what is on. Anything
-- else is shown as it comes, so a field the help does not name is still seen.
local function flag(x)
  if type(x) == "boolean" then return x end
  if type(x) == "number" then return x ~= 0 end
  local s = tostring(x or ""):lower()
  return s == "1" or s == "on" or s == "yes" or s == "true"
end
local function age_text(m)
  m = tonumber(m)
  if not m then return nil end
  local d, h = math.floor(m / 1440), math.floor(m % 1440 / 60)
  if d > 0 then return d .. "d " .. h .. "h" end
  return h > 0 and (h .. "h " .. math.floor(m % 60) .. "m") or (math.floor(m) .. "m")
end
local VAMP_KNOWN = { bp = true, maxbp = true, gen = true, potency = true, age = true,
  veil = true, celerity = true, toggles = true }
local TOGGLE_ORDER = { "bpinfo", "autosuck", "shape", "wimpy", "hideshape" }

local function vampire_toggles(t)
  if type(t) ~= "table" then return nil end
  local out, byKey = {}, {}
  if #t > 0 then                                     -- a list of what is on
    for _, x in ipairs(t) do out[#out + 1] = tag(esc(x), true) end
    return table.concat(out, " &#183; ")
  end
  for k, val in pairs(t) do byKey[tostring(k):lower():gsub("[^%w]", "")] = { k, val } end
  local function one(key)
    local e = byKey[key]
    if not e then return end
    byKey[key] = nil
    local name, val = tostring(e[1]):gsub("_", " "), e[2]
    if key == "wimpy" then
      local n = tonumber(val) or 0
      out[#out + 1] = tag(n > 0 and ("wimpy " .. n .. " bp") or "wimpy off", n > 0)
    else
      out[#out + 1] = tag(esc(name), flag(val))
    end
  end
  for _, key in ipairs(TOGGLE_ORDER) do one(key) end
  local rest = {}
  for key in pairs(byKey) do rest[#rest + 1] = key end
  table.sort(rest)
  for _, key in ipairs(rest) do one(key) end
  return #out > 0 and table.concat(out, " &#183; ") or nil
end

function N.render_vampire(g)
  local head = { "<b>Gen " .. esc(g.gen or "?") .. "</b>" }
  if g.potency ~= nil then head[#head + 1] = "potency " .. esc(g.potency) end
  local age = age_text(g.age)
  if age then head[#head + 1] = "<span style='color:#9a93b0;'>age " .. age .. "</span>" end
  N.gHead:echo(table.concat(head, " &#183; "))
  local H = "color:#e0b64a; font-weight:bold;"
  local rows = {
    string.format("<tr><td style='%s'>Powers</td><td>%s</td></tr>", H,
      tag("veil", flag(g.veil)) .. " &#183; " .. tag("celerity", flag(g.celerity))),
  }
  local tg = vampire_toggles(g.toggles)
  if tg then rows[#rows + 1] = string.format("<tr><td style='%s'>Toggles</td><td>%s</td></tr>", H, tg) end
  local other = {}
  for k, val in pairs(g) do
    if not VAMP_KNOWN[k] then other[#other + 1] = esc(k) .. " " .. esc(type(val) == "table" and json(val) or val) end
  end
  table.sort(other)
  if #other > 0 then
    rows[#rows + 1] = string.format("<tr><td style='%s'>Other</td><td>%s</td></tr>", H, table.concat(other, " &#183; "))
  end
  N.gTxt:echo("<table width='100%' cellspacing='0' cellpadding='1' style='font-size:10pt;'>" ..
    table.concat(rows) .. "</table>")
end

local function cap(s) s = tostring(s or "?") ; return s:sub(1, 1):upper() .. s:sub(2) end

-- Guild.Alchemy: materials {earth, wind, water, metal, mercury}, concoctions {name = count} in
-- concoction_slots {max, held}, and minions {name = {state "out"|"packed"|"none", hp, and when out
-- follow, here, fighting, foe, chore, guiding, camp}}, at most slots.max of them out.
function N.render_alchemy(g)
  local sl = type(g.slots) == "table" and g.slots or {}
  local cs = type(g.concoction_slots) == "table" and g.concoction_slots or {}
  local mins = type(g.minions) == "table" and g.minions or {}
  local max = bars_max()
  -- a new slot, or a minion packed or called out, changes the pane's height
  if max ~= N.gPetsMax or packed_count() ~= N.gPackedN then
    N.gPetsMax, N.gPackedN = max, packed_count()
    N.relayout()
  end
  N.gHead:echo(string.format("<b>Slots %s/%s</b> &#183; Held %s/%s",
    esc(sl.out or 0), esc(sl.max or "?"), esc(cs.held or 0), esc(cs.max or "?")))
  local names = {}
  for nm in pairs(mins) do names[#names + 1] = nm end
  table.sort(names)
  local shown, packed = 0, {}
  for _, nm in ipairs(names) do
    local m = type(mins[nm]) == "table" and mins[nm] or {}
    if m.state == "out" and shown < max then
      shown = shown + 1
      local hp = math.max(0, math.min(tonumber(m.hp) or 0, 100))
      local doing = (tonumber(m.fighting) == 1 and ("  fighting " .. esc(m.foe ~= "" and m.foe or "?")))
        or ((m.chore or "") ~= "" and ("  " .. esc(m.chore))) or ""
      pet_row(shown):setValue(hp, 100, cap(nm) .. "  " .. hp .. "%" .. doing ..
        (tonumber(m.here) == 0 and "  (away)" or "") .. (tonumber(m.follow) == 0 and "  (staying)" or ""))
    elseif m.state == "packed" then
      packed[#packed + 1] = { nm, math.max(0, math.min(tonumber(m.hp) or 0, 100)) }
    end
  end
  if N.gPetsShown ~= shown then
    N.gPetsShown = shown
    if N.gW then fit_guild(N.gW, N.gH) end
  end
  local mt = type(g.materials) == "table" and g.materials or {}
  local function mat(k) return commas(tonumber(mt[k]) or 0) end
  local pots = {}
  for nm, n in pairs(type(g.concoctions) == "table" and g.concoctions or {}) do
    pots[#pots + 1] = esc(nm) .. " &#215;" .. esc(n)
  end
  table.sort(pots)
  local H = "color:#e0b64a; font-weight:bold;"
  -- the packed minions two to a line, HP amber below 75% and red below 40%
  local function cell(p)
    if not p then return "<td></td><td></td>" end
    local c = (p[2] < 40 and "#d06060") or (p[2] < 75 and "#e0a030") or "#dddddd"
    return string.format("<td>%s</td><td align='right' style='color:%s;'>%d%%</td>", esc(p[1]), c, p[2])
  end
  local prow = {}
  for i = 1, #packed, 2 do
    prow[#prow + 1] = string.format("<tr><td style='%s'>%s</td>%s<td width='16'></td>%s</tr>",
      H, i == 1 and "Packed" or "", cell(packed[i]), cell(packed[i + 1]))
  end
  if #prow == 0 then prow[1] = string.format("<tr><td style='%s'>Packed</td><td>none</td></tr>", H) end
  N.gTxt:echo(string.format(
    "<table width='100%%' cellspacing='0' cellpadding='1' style='font-size:10pt; color:#dddddd;'>" ..
    "<tr><td style='%s'>Earth</td><td align='right'>%s</td><td width='16'></td><td style='%s'>Wind</td><td align='right'>%s</td></tr>" ..
    "<tr><td style='%s'>Water</td><td align='right'>%s</td><td></td><td style='%s'>Metal</td><td align='right'>%s</td></tr>" ..
    "<tr><td style='%s'>Mercury</td><td align='right'>%s</td><td></td><td></td><td></td></tr>" ..
    "</table>" ..
    -- the varying rows last, so their wrap moves nothing above them
    "<table width='100%%' cellspacing='0' cellpadding='1' style='font-size:10pt;'>" ..
    "<tr><td style='%s'>Concoctions</td><td>%s</td></tr>" ..
    "</table>" ..
    "<table width='100%%' cellspacing='0' cellpadding='1' style='font-size:10pt; color:#dddddd;'>" ..
    "%s</table>",
    H, mat("earth"), H, mat("wind"), H, mat("water"), H, mat("metal"), H, mat("mercury"),
    H, #pots > 0 and table.concat(pots, " &#183; ") or "none", table.concat(prow)))
end

-- ================= Strigoi power rotation =========================================
-- One power at a time, only with a foe: the next one goes out when the last shows up in the
-- stack, or the game refuses it. Variants, mode and key are kept in the profile.

local ROT_WAIT, ROT_SOON, ROT_PAUSE, ROT_BLOCK, ROT_STALE, ROT_ANSWER = 3, 3, 1, 10, 10, 1
local ROT_REFUSED = "^(?:> )*(The power cannot take hold again while"
  .. "|You call upon the shadows, but the curse"
  .. "|You are mentally weak to do that\\."
  .. "|Something far powerful than you won't allow that so fast\\.)"

N.rot = N.rot or {}
local R = N.rot
local function rot_file() return getMudletHomeDir() .. "/nanny_rotation.lua" end
if not R.saved then
  R.saved = {}
  if type(table.load) == "function" then pcall(table.load, rot_file(), R.saved) end
  R.saved.variants = R.saved.variants or {}
  R.saved.mode = R.saved.mode or "off"
end
R.saved.openers = R.saved.openers or {}
local function rot_save()
  if type(table.save) == "function" then pcall(table.save, rot_file(), R.saved) end
end

local function rot_clear()
  R.soon, R.passed, R.capped, R.blocked, R.holdUntil, R.note = 0, 0, false, nil, nil, nil
end
if R.soon == nil then rot_clear() end
R.i = R.i or 1

local function rot_list() return R.saved.variants[R.saved.current or ""] or {} end
local function rot_step()
  R.i = R.i % math.max(#rot_list(), 1) + 1
  R.soon = 0
end
local function first_word(s) return tostring(s):lower():match("^%s*(%S+)") or "" end
local function copy_list(t)
  local out = {}
  for i, x in ipairs(type(t) == "table" and t or {}) do out[i] = x end
  return out
end

-- What was pushed onto a first-in-first-out stack between two looks at it.
local function stack_new(old, new)
  for k = 0, #old do
    local same = true
    for j = 1, math.min(#old - k, #new) do
      if old[k + j] ~= new[j] then same = false ; break end
    end
    if same then
      local out = {}
      for j = #old - k + 1, #new do out[#out + 1] = new[j] end
      return out
    end
  end
end

function N.rot_draw()
  if not N.gRot then return end
  local S, list = R.saved, rot_list()
  if #list == 0 then
    N.gRot:echo("<span style='color:#777777;'>Rotation: none set. 'nanny rot' for how.</span>")
    return
  end
  local COL = { off = "#777777", key = "#e0b64a", auto = "#70c070" }
  local detail
  if R.blocked then detail = "<span style='color:#d06060;'>blocked: " .. esc(R.blocked) .. "</span>"
  elseif R.note then detail = "<span style='color:#e0a030;'>" .. esc(R.note) .. "</span>"
  elseif R.pending then detail = "sent: " .. esc(R.pending.cmd)
  else detail = "next: " .. esc(list[(R.i - 1) % #list + 1]) end
  N.gRot:echo(string.format("<b style='color:%s;'>%s</b> &#183; %s &#183; %s",
    COL[S.mode] or "#777777", S.mode, esc(S.current), detail))
end

local function rot_trace(s)
  if R.trace then cecho("\n<grey>[rot " .. string.format("%.1f", getEpoch() % 1000) .. "] " .. s .. "<reset>\n") end
end

local function rot_go()
  local list = rot_list()
  if N.guildName ~= "Strigoi" or R.saved.mode == "off" or not R.foe or R.pending or #list == 0 then return end
  if R.holdUntil and getEpoch() < R.holdUntil then return end
  R.holdUntil = nil
  R.i = (R.i - 1) % #list + 1
  -- a new foe: the opener first, unless the stack already holds it
  local cmd, opener = R.opening and R.saved.openers[R.saved.current], false
  R.opening = false
  if cmd then
    local word = first_word(cmd)
    opener = true
    for _, x in ipairs(copy_list(N.gd.stack)) do
      if first_word(x) == word then cmd, opener = nil, false ; break end
    end
  end
  if not cmd then
    -- never the same power twice running, even when it is the only one the game will take
    if #list > 1 and list[R.i] == R.last then rot_step() end
    cmd = list[R.i]
  end
  R.pending = { cmd = cmd, word = first_word(cmd), stack = copy_list(N.gd.stack), beats = 0, t = getEpoch(),
                opener = opener }
  send(cmd, false)
  rot_trace("sent: " .. cmd)
  N.rot_draw()
end
local function rot_auto() if R.saved.mode == "auto" then rot_go() end end

-- The power out is done with, whether or not the stack ever showed it.
local function rot_done()
  local p = R.pending
  R.last, R.pending = p.cmd, nil
  if p.opener then R.soon = 0 else rot_step() end
end

local function rot_no_reply()
  rot_trace("no reply: " .. R.pending.cmd)
  R.note = "no reply: " .. R.pending.cmd
  rot_done()
end

-- How many refusals make a whole pass: the last power is not tried again.
local function rot_pass_len()
  local list = rot_list()
  for _, c in ipairs(list) do
    if c == R.last and #list > 1 then return #list - 1 end
  end
  return #list
end

-- A Guild.Strigoi message: did the power land? It shows a message after the SP is spent, so
-- silence is only given up on after several, or a power still landing would be sent twice.
function N.rot_guild(v)
  local p = R.pending
  if not p then return rot_auto() end
  if type(v.stack) == "table" then
    local fresh = stack_new(p.stack, v.stack)
    p.stack = copy_list(v.stack)
    for _, x in ipairs(fresh) do
      rot_trace("stack got: " .. tostring(x) .. " (waiting for " .. p.cmd .. ")")
      if first_word(x) == p.word then
        rot_clear()
        rot_done()
        rot_auto()
        return N.rot_draw()
      end
    end
  end
  p.beats = p.beats + 1
  if p.beats >= ROT_WAIT then rot_no_reply() ; rot_auto() end
  N.rot_draw()
end

-- Hides the rest of a wrapped sentence (at most three lines in all), then a bare prompt.
local function hide_tail(done, n)
  tempLineTrigger(1, 1, function()
    if done then
      if line:match("^>%s*$") then deleteLine() end
    else
      deleteLine()
      hide_tail(n >= 2 or line:match("%.%s*$") ~= nil, n + 1)
    end
  end)
end

-- "Too soon" also means a room without magic: a few tries on one power, then the rest get one
-- each, and a whole list of refusals after that stops hiding the line and slows to a probe.
function N.rot_refusal(text)
  if not R.pending then return end
  -- it answers what the player just typed, and the power out may yet land
  if R.typedAt and getEpoch() - R.typedAt < ROT_ANSWER then
    rot_trace("not ours, just typed: " .. text)
    return
  end
  rot_trace("refused " .. R.pending.cmd .. ": " .. text)
  if not R.blocked then
    deleteLine()
    hide_tail(line:match("%.%s*$") ~= nil, 1)
  end
  local opener = R.pending.opener
  R.pending = nil
  -- an opener is extra: too soon gets the usual retries, anything else just drops it
  if opener then
    if text:find("^Something") and R.soon + 1 < ROT_SOON then
      R.soon, R.opening = R.soon + 1, true
      return N.rot_draw()
    end
    R.soon = 0
    rot_go()
    return N.rot_draw()
  end
  if R.blocked then
    R.holdUntil = getEpoch() + ROT_BLOCK
    rot_step()
    return N.rot_draw()
  end
  local soon = text:find("^Something") ~= nil
  if soon and not R.capped then
    R.soon = R.soon + 1
    if R.soon < ROT_SOON then return N.rot_draw() end
    R.capped = true
  end
  R.passed = R.passed + 1
  rot_step()
  if R.passed >= rot_pass_len() then
    if R.capped then R.blocked = text end
    R.holdUntil = getEpoch() + (R.capped and ROT_BLOCK or ROT_PAUSE)
    R.passed, R.capped = 0, false
    return N.rot_draw()
  end
  rot_go()
  N.rot_draw()
end

-- Every command going out, the rotation's own included.
function N.rot_sent(_, cmd)
  cmd = (tostring(cmd or ""):gsub("%s+$", ""))
  if not (R.pending and cmd == R.pending.cmd) then R.typedAt = getEpoch() end
end

-- Char.Foe: no foe stops everything; a new one lifts what the last one blocked.
function N.rot_foe(v)
  local name = type(v) == "table" and v.name ~= "" and v.name or nil
  if name == R.foe then return end
  R.foe = name
  rot_trace("foe: " .. tostring(name))
  -- a power that killed the foe never reaches the stack in time
  if not name and R.pending then rot_done() end
  R.opening = name ~= nil
  rot_clear()
  rot_auto()
  N.rot_draw()
end

function N.rot_tick()
  local now = getEpoch()
  if R.pending and now - R.pending.t > ROT_STALE then rot_no_reply() ; N.rot_draw() end
  if R.holdUntil and now >= R.holdUntil then rot_auto() end
end

function N.rot_press()
  if R.saved.mode == "key" then rot_go() end
end

local function rot_mode(m)
  R.saved.mode, R.pending = m, nil
  rot_clear()
  rot_save()
  rot_auto()
  N.rot_draw()
end

local function rot_names()
  local names = {}
  for k in pairs(R.saved.variants) do names[#names + 1] = k end
  table.sort(names)
  return names
end

local function rot_use(name)
  R.saved.current, R.pending, R.i, R.last = name, nil, 1, nil
  rot_clear()
  rot_save()
  N.rot_draw()
end

-- The strip: left click steps the mode, right click the variant.
function N.rot_click(ev)
  if type(ev) == "table" and ev.button == "RightButton" then
    local names = rot_names()
    if #names == 0 then return end
    local at_i = 0
    for i, k in ipairs(names) do if k == R.saved.current then at_i = i end end
    rot_use(names[at_i % #names + 1])
  else
    rot_mode(({ off = "key", key = "auto", auto = "off" })[R.saved.mode] or "off")
  end
end

local function rot_bind()
  if N.rotKey then pcall(killKey, N.rotKey) ; N.rotKey = nil end
  local k = R.saved.key
  if k and type(tempKey) == "function" and type(mudlet) == "table" and mudlet.key and mudlet.key[k] then
    N.rotKey = tempKey(mudlet.key[k], "NannyBasics.rot_press()")
  end
end

function N.rot_cmd(arg)
  local verb, rest = arg:match("^(%S+)%s*(.*)$")
  local S = R.saved
  if verb == "set" then
    local name, cmds = rest:match("^(%S+)%s+(.+)$")
    if not name or name:find(",", 1, true) then
      say("the first word is the rotation's name: nanny rot set <name> <command>, <command>, ...")
      return
    end
    local list = {}
    for c in cmds:gmatch("[^,]+") do
      c = c:gsub("^%s+", ""):gsub("%s+$", "")
      if c ~= "" then list[#list + 1] = c end
    end
    S.variants[name] = list
    rot_use(name)
    say("rotation " .. name .. ": " .. table.concat(list, ", ") .. ".")
  elseif verb == "use" then
    if not S.variants[rest] then say("no rotation called '" .. rest .. "'.") return end
    rot_use(rest)
  elseif verb == "del" then
    if not S.variants[rest] then say("no rotation called '" .. rest .. "'.") return end
    S.variants[rest], S.openers[rest] = nil, nil
    if S.current == rest then rot_use(rot_names()[1]) else rot_save() end
    say("rotation " .. rest .. " deleted.")
  elseif verb == "off" or verb == "key" or verb == "auto" then
    rot_mode(verb)
  elseif verb == "go" then
    N.rot_press()
  elseif verb == "open" then
    if not S.current then say("pick a rotation first.") return end
    if rest == "" then say("usage: nanny rot open <command>, or nanny rot open off") return end
    S.openers[S.current] = rest ~= "off" and rest or nil
    rot_save()
    say(S.openers[S.current] and ("rotation " .. S.current .. " opens each fight with " .. rest ..
        ", unless your stack already holds it.") or ("rotation " .. S.current .. ": no opener."))
  elseif verb == "trace" then
    R.trace = not R.trace
    say("rotation trace " .. (R.trace and "on." or "off."))
  elseif verb == "bind" then
    local k = rest:upper()
    if k == "OFF" then S.key = nil
    elseif type(mudlet) == "table" and mudlet.key and mudlet.key[k] then S.key = k
    else say("usage: nanny rot bind <key, such as F5> or nanny rot bind off") return end
    rot_save()
    rot_bind()
    say(S.key and ("key " .. S.key .. " sends the next power while the mode is key.") or "key unbound.")
  else
    say("rotation mode: " .. S.mode .. (S.key and (", key " .. S.key) or "") .. ".")
    for _, k in ipairs(rot_names()) do
      say((k == S.current and "* " or "  ") .. k .. ": " .. table.concat(S.variants[k], ", ") ..
          (S.openers[k] and ("  (opens with " .. S.openers[k] .. ")") or ""))
    end
    say("'nanny rot set <name> <command>, <command>, ...' saves a rotation, 'nanny rot use <name>' " ..
        "picks one, 'nanny rot del <name>' deletes one, 'nanny rot open <command>' starts each fight " ..
        "with that command unless your stack holds it ('nanny rot open off' stops that)." ..
        "\n  'nanny rot off|key|auto': auto sends powers on its own during a fight; key sends one " ..
        "for each 'nanny rot go'.\n  'nanny rot bind F5' puts that on a key. On the guild pane's " ..
        "strip, left click steps the mode and right click the rotation.")
  end
end

-- ================= wiring =========================================================

function N.on_event(_, ev)
  local name = ev:gsub("^gmcp%.", "")
  local v = at(name)
  log(name, v)
  if name == "Char.Vitals" then N.vitals(v)
  elseif name == "Char.Foe" then N.foe_show(v) ; N.rot_foe(v)
  elseif name == "Comm.Channel.Text" then N.channel(v)
  elseif name == "Char.Status" then N.status(v) ; N.status_consume(v)
  elseif name == "Group.Info" then N.party(v)
  elseif name == "Guild.Druid.Owl" then N.owl(v)
  elseif N.GUILD_PANES[name:match("^Guild%.(.+)$") or ""] then
    N.guild(name, v)
    if name == "Guild.Strigoi" and type(v) == "table" then N.rot_guild(v) end
  end
end

-- Guild.Druid.Owl: what the owl sees while it watches where the druid is not, "with the line
-- it saw" (shape not yet seen). Into a chat tab of its own, and All.
function N.owl(v)
  local line = type(v) == "string" and v or
    (type(v) == "table" and (v.line or v.text or v.message or v.msg))
  if type(v) == "table" and not line then
    for _, x in pairs(v) do if type(x) == "string" then line = x ; break end end
  end
  if not line then return end
  N.channel({ channel = "Owl", talker = "", text = "[Owl] " .. tostring(line) })
end

function N.hello()
  if type(sendGMCP) ~= "function" then return end
  sendGMCP("Core.Supports.Add " .. yajl.to_string(N.WANT))
end

function N.register()
  for _, id in ipairs(N.handlers or {}) do pcall(killAnonymousEventHandler, id) end
  N.handlers = {}
  for _, e in ipairs(N.EVENTS) do
    N.handlers[#N.handlers + 1] = registerAnonymousEventHandler("gmcp." .. e, N.on_event)
  end
  N.handlers[#N.handlers + 1] = registerAnonymousEventHandler("sysProtocolEnabled",
    function(_, proto) if proto == "GMCP" then N.hello() end end)
  -- a pane dropped on another edge needs sizes suited to its new place
  N.handlers[#N.handlers + 1] = registerAnonymousEventHandler("MudletBordersChanged",
    function() N.relayout() end)
  -- resize is handled by the border coordinator, which repositions every owner's panes.
end

-- ================= updating =======================================================
-- 'nanny update' downloads the newest release FIRST and swaps only once it is on disk, so a
-- failed download changes nothing. The swap runs from timers: the alias belongs to the package
-- being removed, but functions and timers live on in the Lua state. Same shape as mapupdate.
N.REPO = "NannyMUD/NannyMUD-mudlet"
N.UPDATE_URL = "https://github.com/" .. N.REPO .. "/releases/latest/download/NannyBasics.mpackage"

-- Whether a package of that name is installed (true when Mudlet cannot say).
local function installed(name)
  if type(getPackages) ~= "function" then return true end
  for _, p in ipairs(getPackages() or {}) do if p == name then return true end end
  return false
end

function N.update_swap(path)
  if N._updBusy then return end
  N._updBusy = true
  local function try(left)
    local ok, err = pcall(installPackage, path)
    if ok and installed("NannyBasics") then
      N._updBusy = nil
      cecho("<green>[nanny]: updated.\n<reset>")
    elseif left > 0 then
      tempTimer(2, function() try(left - 1) end)
    else
      N._updBusy = nil
      cecho("\n<red>[nanny]: the install failed" .. (ok and "" or ": " .. tostring(err)) ..
            ".\n  Drag " .. path .. " onto Mudlet to finish by hand.\n<reset>")
    end
  end
  tempTimer(0.1, function()
    pcall(uninstallPackage, "NannyBasics")
    tempTimer(1, function() try(1) end)
  end)
end

-- Download url to <profile>/nanny_update/<name>, then call done(path), or fail(why).
local function fetch(name, url, done, fail)
  local dir = getMudletHomeDir() .. "/nanny_update"
  if lfs and lfs.mkdir then pcall(lfs.mkdir, dir) end
  local path = dir .. "/" .. name
  os.remove(path)
  local hd, he
  hd = registerAnonymousEventHandler("sysDownloadDone", function(_, file)
    if file ~= path then return end
    pcall(killAnonymousEventHandler, hd) ; pcall(killAnonymousEventHandler, he)
    done(path)
  end)
  he = registerAnonymousEventHandler("sysDownloadError", function(_, why, file)
    if file and file ~= path then return end
    pcall(killAnonymousEventHandler, hd) ; pcall(killAnonymousEventHandler, he)
    if fail then fail(why) end
  end)
  downloadFile(path, url)
end

-- Every release carries both packages at one version, so one command updates both; `alone` is
-- set when the mapper's update calls this, so the two do not call each other back.
function N.update(alone, file)
  local now = os.time()
  if N._updAt and now - N._updAt < 30 then return end
  N._updAt = now
  -- a local build (testing): swap it in, no download, the other package left alone
  if file and file ~= "" then
    file = file:gsub("\\", "/")
    local fh = io.open(file, "rb")
    if not fh then say("no such file: " .. file) return end
    fh:close()
    N.update_swap(file)
    return
  end
  if type(installPackage) ~= "function" or type(uninstallPackage) ~= "function"
     or type(downloadFile) ~= "function" then
    say("this Mudlet cannot update packages from a script. Get the new one by hand:\n  " .. N.UPDATE_URL)
    return
  end
  say("downloading the newest NannyBasics...")
  -- the file name is the package name to Mudlet
  fetch("NannyBasics.mpackage", N.UPDATE_URL, N.update_swap, function(why)
    cecho("\n<red>[nanny]: the download failed (" .. tostring(why) .. "). Nothing was changed.\n<reset>")
  end)
  if not alone and installed("ElrohirMapper") and type(elro) == "table"
     and type(elro.cmd_update) == "function" then
    elro.cmd_update("", true)
  end
end

-- "0.10.2" > "0.9.9": compared part by part as numbers
local function newer(a, b)
  local pa, pb = {}, {}
  for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
  for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x > y end
  end
  return false
end
N.newer = newer

-- Once per session: ask GitHub for the latest release and say so if it is newer. The packages
-- share one version, so only the first of them to get here asks (NannyMUDUpdates is shared with
-- the mapper). Silent when up to date and on any error.
function N.check_latest()
  if type(downloadFile) ~= "function" or type(yajl) ~= "table" then return end
  NannyMUDUpdates = NannyMUDUpdates or {}
  if NannyMUDUpdates.checked then return end
  NannyMUDUpdates.checked = true
  fetch("latest.json", "https://api.github.com/repos/" .. N.REPO .. "/releases/latest", function(path)
    local f = io.open(path, "r") ; if not f then return end
    local body = f:read("*a") ; f:close()
    local ok, t = pcall(yajl.to_value, body)
    local tag = ok and type(t) == "table" and t.tag_name
    if type(tag) == "string" and newer(tag, N.VERSION) then
      local names = installed("ElrohirMapper") and "ElrohirMapper and NannyBasics" or "NannyBasics"
      cecho(string.format("\n<yellow>[nanny]: version %s of %s is out (you have %s). Type 'nanny update'.\n<reset>",
        (tag:gsub("^v", "")), names, N.VERSION))
    end
  end)
end

-- ================= encoding =======================================================
-- 'nanny encoding on': a player's text reaches us in whatever their client sent, UTF-8 or a
-- one-byte set. Latin-1 decoding keeps every byte, so a stretch that is valid UTF-8 can be decoded
-- again, and the 0x80-0x9F controls read as Windows-1252.
local function enc_file() return getMudletHomeDir() .. "/nanny_encoding.txt" end

N.CP1252 = { [0x80] = 0x20AC, [0x82] = 0x201A, [0x83] = 0x0192, [0x84] = 0x201E, [0x85] = 0x2026,
  [0x86] = 0x2020, [0x87] = 0x2021, [0x88] = 0x02C6, [0x89] = 0x2030, [0x8A] = 0x0160,
  [0x8B] = 0x2039, [0x8C] = 0x0152, [0x8E] = 0x017D, [0x91] = 0x2018, [0x92] = 0x2019,
  [0x93] = 0x201C, [0x94] = 0x201D, [0x95] = 0x2022, [0x96] = 0x2013, [0x97] = 0x2014,
  [0x98] = 0x02DC, [0x99] = 0x2122, [0x9A] = 0x0161, [0x9B] = 0x203A, [0x9C] = 0x0153,
  [0x9E] = 0x017E, [0x9F] = 0x0178 }

local function utf8_char(cp)
  local f = math.floor
  if cp < 0x80 then return string.char(cp)
  elseif cp < 0x800 then return string.char(0xC0 + f(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return string.char(0xE0 + f(cp / 0x1000), 0x80 + f(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(0xF0 + f(cp / 0x40000), 0x80 + f(cp / 0x1000) % 0x40,
                     0x80 + f(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

-- s (UTF-8, as Mudlet hands a line over) as a list of code points
local function codepoints(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local b = s:byte(i)
    local len = b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1
    local cp = b
    if len > 1 and i + len - 1 <= n then
      cp = b % (len == 2 and 0x20 or len == 3 and 0x10 or 0x08)
      for k = 1, len - 1 do cp = cp * 0x40 + s:byte(i + k) % 0x40 end
    else
      len = 1
    end
    out[#out + 1] = cp
    i = i + len
  end
  return out
end

-- The repairs a Latin-1-decoded line needs, in order: { { from, to }, ... }.
function N.mojibake(s)
  local cps, subs, i = codepoints(s), {}, 1
  while i <= #cps do
    local c, len, cp = cps[i], 0, nil
    if c >= 0xC2 and c <= 0xDF then len = 2
    elseif c >= 0xE0 and c <= 0xEF then len = 3
    elseif c >= 0xF0 and c <= 0xF4 then len = 4 end
    if len > 0 and i + len - 1 <= #cps then
      -- the second byte's range rules out overlong forms, surrogates and code points past U+10FFFF
      local lo, hi = 0x80, 0xBF
      if c == 0xE0 then lo = 0xA0 elseif c == 0xED then hi = 0x9F
      elseif c == 0xF0 then lo = 0x90 elseif c == 0xF4 then hi = 0x8F end
      cp = c % (len == 2 and 0x20 or len == 3 and 0x10 or 0x08)
      for k = 1, len - 1 do
        local x = cps[i + k]
        if x < (k == 1 and lo or 0x80) or x > (k == 1 and hi or 0xBF) then cp = nil ; break end
        cp = cp * 0x40 + x % 0x40
      end
    end
    if cp then
      local from = {}
      for k = 0, len - 1 do from[#from + 1] = utf8_char(cps[i + k]) end
      subs[#subs + 1] = { table.concat(from), utf8_char(cp) }
      i = i + len
    else
      if N.CP1252[c] then subs[#subs + 1] = { utf8_char(c), utf8_char(N.CP1252[c]) } end
      i = i + 1
    end
  end
  return subs
end

-- the trigger's work: swap only the broken pieces, so the line keeps its colours
local function enc_line()
  if not line:find("[\194\195]") then return end
  for _, p in ipairs(N.mojibake(line)) do
    if selectString(p[1], 1) > -1 then replace(p[2], true) end
  end
  deselect()
end

local function enc_trigger()
  if N.encTrig then killTrigger(N.encTrig) ; N.encTrig = nil end
  if N.encOn then N.encTrig = tempRegexTrigger("[^\\x00-\\x7f]", enc_line) end
end

-- Mudlet's own name for Latin-1, from its list
local function latin1_name()
  if type(getServerEncodingsList) ~= "function" then return nil end
  for _, e in ipairs(getServerEncodingsList() or {}) do
    local k = tostring(e):upper():gsub("[^%w]", "")
    if k == "ISO88591" or k == "LATIN1" then return e end
  end
end

-- on: read the game as Latin-1 and repair; off: back to the encoding there was before
function N.encoding(on)
  if on then
    local lat = latin1_name()
    if not lat or type(setServerEncoding) ~= "function" then
      say("this Mudlet cannot set the server encoding.")
      return false
    end
    local cur = type(getServerEncoding) == "function" and getServerEncoding() or nil
    if cur and cur ~= lat then N.encPrev = cur end
    setServerEncoding(lat)
  elseif N.encOn and N.encPrev and type(setServerEncoding) == "function" then
    setServerEncoding(N.encPrev)
  end
  N.encOn = on
  local fh = io.open(enc_file(), "w")
  if fh then fh:write((on and "on" or "off") .. "\n" .. (N.encPrev or "") .. "\n") ; fh:close() end
  enc_trigger()
  return true
end

-- on unless the player turned it off
do
  local fh = io.open(enc_file(), "r")
  N.encOn = true
  if fh then
    N.encOn = fh:read("*l") ~= "off"
    N.encPrev = fh:read("*l")
    fh:close()
  end
  if N.encPrev == "" then N.encPrev = nil end
end

-- ================= help ===========================================================
-- 'nanny help' reads these tables; help_md.lua writes the README's reference from them.
-- A row is { command, one-line summary, full text }; a page is a title and paragraphs,
-- "Head|text" being a paragraph under a heading.

local HELP = {}
HELP.sections = {
  { title = "Panes and layout", rows = {
    { "nanny place <pane> <cell>", "move a pane by name",
      "Move a pane to a cell, the same as dragging it by its title strip. Bare 'nanny place' lists the cells; 'nanny layout' says where each pane is now." },
    { "nanny hide <pane>", "close a pane",
      "Close a pane, the same as the X on its title strip. The panes: vitals, chat, score, cooldowns, party, guild and log." },
    { "nanny show <pane>", "bring a closed pane back",
      "Bring a closed pane back, the same as its entry in the right-click menu of any strip or bar." },
    { "nanny layout", "where each pane is", "Where each pane is, and whether the GMCP log is shown." },
    { "nanny chat split|join <tab>", "a chat tab in a pane of its own, or back",
      "'split' gives a chat tab a pane of its own, which you place like any other pane; 'join' puts it back among the tabs. The same by mouse: drag a tab out of the tab bar, or right-click it for 'Own pane'; drag the pane's strip onto the chat pane, or right-click the strip for 'Back into Chat'. Its messages still show under All. Remembered across restarts." },
    { "nanny reset", "every pane back to its default place and size",
      "Put every pane back in its default place and size, closed ones too." },
    { "nanny off", "hide the whole panel",
      "Hide the whole panel, map and panes, so the text has the whole window: for a second session in MultiView. It stays off across restarts of this profile until 'nanny on'." },
    { "nanny on", "bring the panel back", "Bring the panel back after 'nanny off'." },
  } },
  { title = "The game's data", rows = {
    { "nanny", "what has arrived from the game",
      "Which kinds of data the game has sent so far, and how often. A pane that stays empty usually needs its toggle in the game: 'nanny help game' lists them." },
    { "nanny log", "show or hide the GMCP log",
      "Show or hide the GMCP log, the raw data as it arrives. Hidden by default." },
    { "nanny hello", "ask the game for its data again",
      "Ask the game again for every kind of data NannyBasics reads; useful after a toggle in the game." },
    { "nanny encoding [on|off]", "repair å, ä and ö in other players' text",
      "Players' text reaches you in whatever encoding their own client uses, so some players' letters come out wrong. With this on, the game is read as Latin-1, which keeps every byte, and UTF-8 and Windows text is turned back into the right letters; what you type goes out as Latin-1. On from the start; 'off' puts back the encoding your profile had before." },
  } },
  { title = "Guilds", rows = {
    { "nanny rot [set|use|del|off|key|auto|go|bind|open|trace]", "a Strigoi power rotation",
      "For the Strigoi: repeating a power costs you, so you mix several. Bare, your lists, the mode and the commands. 'set <name> <power>, <power>, ...' saves a list, written exactly as you would type the powers, and picks it; 'use <name>' picks one, 'del <name>' deletes one. 'off', 'key' and 'auto' set the mode: stopped, one power each time you press, or on its own. 'go' sends the next power in key mode, and 'bind <key>' puts that on a key such as F5 ('bind off' removes it). 'open <power>' starts each new fight with that power ('open off' stops). 'trace' prints every send, landing and refusal, or stops. It needs the foe gauge and the guild pane, and nothing goes out without a foe." },
    { "nanny tome [probe|hide|show|relearn|forget] [spell]", "what the Cooldowns card has learned",
      "Bare, the spell you have stored and what the Cooldowns card has learned about each spell's cooldown. 'probe <spell>' learns a cooldown for you: after each release the spell is chanted every few seconds until a chant works, never while a spell is stored, and the game's refusals are hidden; it stops by itself once the cooldown is known, 'probe off' stops it at once. 'hide <spell>' hides a bar and keeps what was learned, 'show <spell>' brings it back. 'relearn' (or 'relearn <spell>') after something shortened your cooldowns: the bar says maybe from the release, and a few early tries find the new length. 'forget <spell>' wipes what was learned about a spell." },
    { "nanny icons [dark|emoji]", "the cooldown icons",
      "The icons on the cooldown bars, the Strigoi's powers and the tome's spells alike: dark symbols, or emoji." },
    { "nanny stack [chips|icons]", "how the Strigoi stack is shown",
      "How the guild pane shows your stack: each power by a short name on a tinted ground (chips), or as icons." },
  } },
  { title = "The package", rows = {
    { "nanny help [command or word]", "this list; a command in full, or a search",
      "Bare, this list. 'nanny help <command>' gives that command in full ('nanny help rot'); any other word lists every command and page that mentions it. The pages: 'nanny help mouse' (what dragging and clicking do) and 'nanny help game' (the toggles in the game)." },
    { "nanny update [file]", "install the newest release",
      "Download the newest release and swap it in, the map too if you have it. If the download fails nothing is changed; your layout is kept. With a file, install that package file instead. Shortly after Mudlet starts you are told when a release is out." },
    { "nanny src [path|off]", "development: load the code from a file",
      "For development: load nannybasics.lua from this path instead of the package's own copy, so 'nanny reload' picks up edits; 'off' goes back to the built-in copy from the next start." },
    { "nanny reload", "development: load the code again", "Load the file set with 'nanny src' again." },
  } },
}
HELP.pages = {
  mouse = { title = "Dragging and clicking", paras = {
    "Moving a pane|Drag a pane by its title strip: onto another pane to stack with it, near a pane's edge to split that space, or to an empty edge of the window to open a panel there.",
    "Resizing|Drag the thin bars between panes, and at a panel's inner edge.",
    "Closing|The X at the right end of a title strip closes that pane. Right-click any strip or bar for a menu that shows closed panes again or resets the layout.",
    "Chat tabs|Drag a tab out of the chat's tab bar to give it a pane of its own, placed where you drop it; right-clicking the tab does the same. Drag that pane's strip back onto the chat pane, or right-click the strip, to put it back among the tabs.",
    "The rotation strip|On the Strigoi guild pane, left click steps the mode, right click picks the next list.",
    "Sizes, places and closed panes are remembered across restarts.",
  } },
  game = { title = "In the game", code = true, paras = {
    "The game sends each kind of data only to players who ask. Each toggle is typed in the game and remembered when you log in again.",
    "toggle gmcp|GMCP itself; Mudlet has it on by default.",
    "toggle gmcp vitals|The HP and SP gauges and the body gauges.",
    "toggle gmcp foe|The foe gauge.",
    "toggle gmcp channels|The chat pane.",
    "toggle gmcp status|The score card.",
    "toggle gmcp group|The party pane.",
    "toggle gmcp discord|Discord status from your client.",
    "toggle strigoi gmcp|The guild pane, for the Strigoi.",
    "toggle druids gmcp|The guild pane, for druids.",
    "toggle vampires gmcp|The guild pane and your blood, for vampires.",
  } },
}
HELP.page_order = { "mouse", "game" }

-- the word after 'nanny' that names a row, or "nanny" for the bare command
local function help_word(row) return row[1]:match("^nanny%s+(%a+)") or "nanny" end

function HELP.all_rows()
  local out = {}
  for _, s in ipairs(HELP.sections) do for _, r in ipairs(s.rows) do out[#out + 1] = r end end
  return out
end

-- what 'nanny help <arg>' shows: the list, a page, a command in full, a search, or nothing
function HELP.lookup(arg)
  arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("^nanny%s+", "")
  if arg == "" then return { kind = "list" } end
  for name, p in pairs(HELP.pages) do
    if arg == name or (#arg >= 4 and name:sub(1, #arg) == arg) then return { kind = "page", page = p } end
  end
  local exact = {}
  for _, r in ipairs(HELP.all_rows()) do if help_word(r) == arg then exact[#exact + 1] = r end end
  if #exact > 0 then return { kind = "detail", rows = exact } end
  local rows, pages = {}, {}
  for _, r in ipairs(HELP.all_rows()) do
    if (r[1] .. " " .. r[2] .. " " .. r[3]):lower():find(arg, 1, true) then rows[#rows + 1] = r end
  end
  for _, name in ipairs(HELP.page_order) do
    local p = HELP.pages[name]
    if (p.title .. " " .. table.concat(p.paras, " ")):lower():find(arg, 1, true) then pages[#pages + 1] = name end
  end
  if #rows == 0 and #pages == 0 then return { kind = "none", word = arg } end
  return { kind = "found", rows = rows, pages = pages, word = arg }
end
N.HELP = HELP

local function wrap(text, width)
  local lines, cur = {}, ""
  for w in tostring(text):gmatch("%S+") do
    if cur == "" then cur = w
    elseif #cur + 1 + #w <= width then cur = cur .. " " .. w
    else lines[#lines + 1] = cur ; cur = w end
  end
  if cur ~= "" then lines[#lines + 1] = cur end
  return lines
end

function N.help(arg)
  local ok, width = pcall(getWindowWrap, "main")
  if not ok or type(width) ~= "number" or width < 40 then width = 80 end
  local col = width >= 90 and 34 or 26
  local function short_row(cmd, text)
    local own = #cmd + 2 >= col
    if own then cecho("<yellow>  " .. cmd .. "<reset>\n") end
    for i, l in ipairs(wrap(text, width - col - 1)) do
      if i == 1 and not own then
        cecho(string.format("<yellow>  %s<reset>%s%s\n", cmd, string.rep(" ", col - 2 - #cmd), l))
      else
        cecho(string.rep(" ", col) .. l .. "\n")
      end
    end
  end
  local function para(text, indent)
    for _, l in ipairs(wrap(text, width - #indent)) do cecho(indent .. l .. "\n") end
  end
  local r = HELP.lookup(arg)
  if r.kind == "list" then
    cecho("\n<cyan>NannyBasics " .. N.VERSION .. "<reset>: commands\n")
    for _, s in ipairs(HELP.sections) do
      cecho("\n<cyan>" .. s.title:upper() .. "<reset>\n")
      for _, row in ipairs(s.rows) do short_row(row[1], row[2]) end
    end
    cecho("\n")
    short_row("nanny help <command>", "that command in full")
    short_row("nanny help <word>", "every entry that mentions the word")
    short_row("nanny help mouse|game", "dragging and clicking; the toggles in the game")
  elseif r.kind == "detail" then
    for _, row in ipairs(r.rows) do
      cecho("\n<yellow>  " .. row[1] .. "<reset>\n")
      para(row[3], "    ")
    end
  elseif r.kind == "page" then
    cecho("\n<cyan>NannyBasics<reset>: " .. r.page.title .. "\n\n")
    for _, p in ipairs(r.page.paras) do
      local h, body = p:match("^(.-)|(.+)$")
      if h then cecho("<yellow>  " .. h .. "<reset>\n") ; para(body, "    ") else para(p, "  ") end
      cecho("\n")
    end
  elseif r.kind == "found" then
    cecho(string.format("\n<cyan>[nanny]: help that mentions '%s':<reset>\n", r.word))
    for _, row in ipairs(r.rows) do short_row(row[1], row[2]) end
    for _, name in ipairs(r.pages) do short_row("nanny help " .. name, HELP.pages[name].title) end
  else
    cecho(string.format("\n<yellow>[nanny]: nothing in the help mentions '%s'. 'nanny help' lists the commands.<reset>\n", r.word))
  end
  cecho("\n")
end

-- nanny [help | log | hello | reload | update | encoding | place <what> <where> | layout | ...]
function N.cmd(arg)
  arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local verb, rest = arg:match("^(%S+)%s*(.*)$")
  if arg == "log" then
    N.log_toggle()
  elseif verb == "help" then
    N.help(rest)
  elseif verb == "chat" then
    local how, word = rest:match("^(%a+)%s+(.+)$")
    local name
    for n in pairs(N.tabs or {}) do if word and n:lower() == word:lower() then name = n end end
    if (how == "split" or how == "join") and not name then
      say("no chat tab called '" .. tostring(word) .. "' yet; it appears with its first message.")
    elseif how == "split" then
      if name == "All" then say("'All' stays in the chat pane.")
      elseif N.split[name] then say(name .. " already has its own pane.")
      else N.chat_split(name) ; say(name .. " has its own pane; drag its strip onto Chat to put it back.") end
    elseif how == "join" then
      if N.chat_join(name) then say(name .. " is back in the chat pane.") else say(name .. " is already in the chat pane.") end
    else
      say("'nanny chat split <tab>' gives a tab its own pane, 'nanny chat join <tab>' puts it back.")
    end
  elseif verb == "place" then
    local what, where = rest:match("^(%S+)%s+(%S+)$")
    if what then N.place_comp(what, where)
    else say("usage: nanny place <vitals|chat|score|cooldowns|party|guild|log> <cell>  (cells: " ..
             table.concat(type(MudletBorders) == "table" and MudletBorders.cells() or {}, ", ") .. ")") end
  elseif verb == "hide" or verb == "show" then
    if rest == "" then say("usage: nanny " .. verb .. " <vitals|chat|score|party|guild|log>") return end
    N.show_comp(rest, verb == "show")
  elseif verb == "layout" then
    local parts = {}
    for _, nm in ipairs(N.order) do
      local cell = type(MudletBorders) == "table" and MudletBorders.where("nanny:" .. nm) or N.place[nm]
      parts[#parts + 1] = nm .. "=" .. tostring(cell or "hidden")
    end
    say("layout: " .. table.concat(parts, ", ") .. (N.logOn and "  (log shown)" or "  (log hidden)"))
  elseif verb == "update" then
    N.update(false, rest)
  elseif verb == "rot" then
    N.rot_cmd(rest)
  elseif verb == "tome" then
    N.tome_cmd(rest)
  elseif arg == "hello" then
    N.hello()
    say("asked the game for: " .. table.concat(N.WANT, ", "))
  elseif arg == "reset" then
    if type(MudletBorders) == "table" then MudletBorders.reset() ; N.relayout() end
    say("every pane back in its default place and size, closed ones too.")
  elseif arg == "off" then
    if type(MudletBorders) == "table" then MudletBorders.suspend() end
    say("right-side UI off for this session (map and panes); the text has the whole window. "
      .. "'nanny on' brings it back. Stays off across restarts of this profile.")
  elseif arg == "on" then
    if type(MudletBorders) == "table" then MudletBorders.resume() ; N.relayout() end
    say("right-side UI on.")
  elseif verb == "src" then
    -- development: load nannybasics.lua from this path instead of the package; "off" stops it
    if rest == "" then
      say(N.SRC ~= "" and ("loading from " .. N.SRC) or "loading the built-in copy (no source file set).")
    else
      local path = rest == "off" and "" or rest:gsub("\\", "/")
      if path ~= "" and not path:lower():match("%.lua$") then
        say("'nanny src' takes the nannybasics.lua source file. To install a package file, use "
          .. "'nanny update " .. path .. "'.")
        return
      end
      local fh = io.open(src_file(), "w")
      if fh then fh:write(path) ; fh:close() end
      N.SRC = path
      say(path == "" and "back to the built-in copy from the next start." or
          ("loading from " .. path .. "; 'nanny reload' now."))
    end
  elseif verb == "stack" then
    if rest ~= "chips" and rest ~= "icons" then
      say("stack: " .. N.stackStyle .. ". 'nanny stack chips' or 'nanny stack icons' to switch.")
      return
    end
    N.stackStyle = rest
    local fh = io.open(stack_file(), "w")
    if fh then fh:write(rest) ; fh:close() end
    if N.guildName == "Strigoi" then N.guild("Guild.Strigoi", {}) end
    say("stack: " .. rest .. ".")
  elseif verb == "icons" then
    if rest ~= "emoji" and rest ~= "dark" then
      say("icons: " .. N.iconSet .. ". 'nanny icons emoji' or 'nanny icons dark' to switch.")
      return
    end
    N.iconSet = rest
    local fh = io.open(icons_file(), "w")
    if fh then fh:write(rest) ; fh:close() end
    if N.guildName == "Strigoi" then N.guild("Guild.Strigoi", {}) end
    say("icons: " .. rest .. ".")
  elseif verb == "encoding" then
    if rest == "on" or rest == "off" then
      if not N.encoding(rest == "on") then return end
    end
    say(N.encOn and "encoding repair on: the game is read as Latin-1, and other players' " ..
        "UTF-8 and Windows text is turned back into å, ä and ö. 'nanny encoding off' undoes it."
        or "encoding repair off. 'nanny encoding on' repairs å, ä and ö sent by other players' clients.")
  elseif arg == "reload" then
    if N.SRC == "" then say("no source file set: 'nanny src <path to nannybasics.lua>' first.") return end
    local ok, err = N.load_file()
    if not ok then cecho("\n<red>[nanny]: reload failed: " .. tostring(err) .. "\n<reset>") end
  else
    local names = {}
    for k, n in pairs(N.seen) do names[#names + 1] = k .. " x" .. n end
    table.sort(names)
    say("received: " .. (#names > 0 and table.concat(names, ", ") or "nothing yet") ..
        "\n  A pane that stays empty needs its toggle in the game: 'nanny help game' lists them." ..
        "\n  'nanny help' lists the commands. This is NannyBasics " .. N.VERSION .. ".")
  end
end

-- ================= startup ========================================================

N._lh = nil   -- recompute the text-row height on each load (code or font may have changed)
component("vitals", { build = build_vitals, hint_h = 2 * N.BAR })
component("channels", { build = build_channels, fit = fit_channels })
component("status", { build = build_status, hint_h = status_card_h(), fit = fit_status })
component("cooldowns", { build = build_cooldowns, hint_h = N.cd_card_h(), fit = fit_cooldowns })
component("party", { build = build_party })
component("guild", { build = build_guild, hint_h = guild_card_h(), fit = fit_guild })
component("log", { build = build_log })
style_guild()
style_status()   -- a reload keeps the old widgets; give them the current styles
if not N.tabs["All"] then N.tab("All") end
N.select(N.current or "All")
if N.pulseTimer then killTimer(N.pulseTimer) ; N.pulseTimer = nil end
N.vitals(at("Char.Vitals"))
N.foe_show(at("Char.Foe"))
-- Need fields still in gmcp at load were left by a copy that did not clear them, so they are
-- stale: drop them, as a restart would. Then draw the last message as read.
local cs = at("Char.Status")
if type(cs) == "table" then
  for _, k in ipairs(STATUS_SOMETIMES) do
    if cs[k] ~= nil then N.status_consume(cs) ; N.status_consume(N.st) ; break end
  end
end
N.status(next(N.st) and N.st or cs)
N.party(at("Group.Info"))
for k, v in pairs(type(at("Guild")) == "table" and at("Guild") or {}) do
  if N.GUILD_PANES[k] then N.guild("Guild." .. k, v) end
end
-- re-render the card every 20s so XP/hr stays live (and decays) between Char.Status messages
if N.rateTimer then killTimer(N.rateTimer) ; N.rateTimer = nil end
N.rateTimer = tempTimer(20, function() if next(N.st) then N.status(N.st) end end, true)
-- count the Strigoi cooldown bars and the barkskin bar down between messages
if N.cdTimer then killTimer(N.cdTimer) ; N.cdTimer = nil end
N.cdTimer = tempTimer(1, function()
  if (N.guildName == "Strigoi" and (next(N.cd.on) or next(N.sbuffs.on))) or next(TM.on) then N.draw_cooldowns() end
  if N.guildName == "Druid" and next(N.buffs.on) then N.draw_bark() end
  N.rot_tick()
end, true)
N.draw_cooldowns()
N.relayout()
N.register()
if N.encOn then N.encoding(true) end
if N.rotTrig then killTrigger(N.rotTrig) end
N.rotTrig = tempRegexTrigger(ROT_REFUSED, function() N.rot_refusal(matches[2]) end)
if N.rotSentId then killAnonymousEventHandler(N.rotSentId) end
N.rotSentId = registerAnonymousEventHandler("sysDataSendRequest", function(...) N.rot_sent(...) end)
if N.tomeTrig then killTrigger(N.tomeTrig) end
N.tomeTrig = tempRegexTrigger(TOME_LINES, function() N.tome_line(matches[2]) end)
if N.harvestTrig then killTrigger(N.harvestTrig) end
N.harvestTrig = tempRegexTrigger(HARVEST_LINES, function() N.harvest_line(matches[2]) end)
if N.tomeSentId then killAnonymousEventHandler(N.tomeSentId) end
N.tomeSentId = registerAnonymousEventHandler("sysDataSendRequest", function(...) N.tome_sent(...) end)
rot_bind()
N.rot_foe(at("Char.Foe"))
if N.alias then killAlias(N.alias) end
N.alias = tempAlias("^nanny(?:\\s+(.+))?$", function() N.cmd(matches[2]) end)
if type(gmcp) == "table" then N.hello() end
say("NannyBasics " .. N.VERSION .. " loaded. Type 'nanny' for commands.")
-- once per session, not on every reload; a few seconds in, after the profile has settled
if not N._checked and type(tempTimer) == "function" then
  N._checked = true
  tempTimer(5, function() pcall(N.check_latest) end)
end
-- Mudlet's starter interface would draw a second map, chat and bars over ours
if type(tempTimer) == "function" then
  tempTimer(3, function()
    if type(MudletBorders) == "table" and MudletBorders.claim_screen
       and MudletBorders.claim_screen("NannyBasics") then
      say("Mudlet's starter interface has stepped aside for NannyBasics; 'baseui show' brings it back.")
    end
  end)
end
