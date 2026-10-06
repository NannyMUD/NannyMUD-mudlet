-- NannyBasics: NannyMUD's GMCP for players. Vitals and foe gauges, a tabbed channel pane,
-- and a GMCP log, arranged by a small region layout manager: left and right panes run the
-- full height, top and bottom span only the text column, and the text sits in the middle.
-- Move a component between regions with 'nanny place <what> <where>'.
--
-- The panes are plain containers the manager positions absolutely, so -- unlike the map --
-- nothing is bound to a singleton widget; a component can be moved and the pane remade freely.

NannyBasics = NannyBasics or {}
local N = NannyBasics
N.VERSION = "0.7.0"

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
             "Char.Status", "Group.Info", "Guild.Strigoi", "Guild.Alchemy", "Guild.Druid" }
N.GUILD_PANES = { Strigoi = true, Druid = true }
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
N.place = { vitals = "bottom", channels = "c2", log = "c1", status = "c1", party = "c1", guild = "c2" }
N.order = { "vitals", "guild", "channels", "status", "party", "log" }  -- stacking order within a cell

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
N.TITLE = { channels = "Chat", status = "Score", party = "Party", log = "GMCP log" }

-- Register every component as a slot in its cell. channels, status and party are always shown;
-- the GMCP log toggles, and the guild pane waits for its guild's first message. Sizes come from
-- the cell the pane is in NOW (it may have been dragged to another edge); the coordinator stacks
-- each cell and calls the cb back with a rect.
function N.relayout()
  if type(MudletBorders) ~= "table" then return end
  for i, nm in ipairs(N.order) do
    local c = N.comps[nm]
    if c then
      if (nm == "log" and not N.logOn) or (nm == "guild" and not N.guildName) then
        pcall(function() c.box:hide() end)
        MudletBorders.park("nanny:" .. nm)
      else
        local id = "nanny:" .. nm
        -- the guild pane's height depends on which guild it is drawing
        if nm == "guild" and N.guild_card_h then c.hint_h = N.guild_card_h() end
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
        })
      end
    end
  end
end

function N.place_comp(nm, cell)
  if not N.comps[nm] then
    say("no component '" .. tostring(nm) .. "'. Try vitals, channels, status, party or log.") return
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

function N.vitals(v)
  if type(v) ~= "table" or not N.hp then return end
  gauge(N.hp, v.hp, v.maxhp, "HP")
  gauge(N.sp, v.sp, v.maxsp, "SP")
  local hp, max = tonumber(v.hp), tonumber(v.maxhp)
  if hp and max and max > 0 then N.hpFrac = hp / max end
  if N.hpFrac and N.hpFrac < N.PULSE_AT and not N.pulseTimer then
    N.pulseTimer = tempTimer(0.05, N.pulse, true)
  end
  N.pulse()
  N.body_show(v)
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

function N.chat_wrap()
  if not N.chatBox then return end
  local cw = calcFontSize(N.CHAT_FONT) or 8
  local ok, w = pcall(function() return N.chatBox:get_width() end)
  w = (ok and type(w) == "number" and w > 0) and w or 360
  local cols = math.max(20, math.floor((w - 20) / cw))
  for _, t in pairs(N.tabs or {}) do pcall(function() t.con:setWrap(cols) end) end
end

-- each tab's console fills every pixel below the tab bar (see component() on negative heights)
local function fit_channels(w, h)
  for _, t in pairs(N.tabs or {}) do
    pcall(function() t.con:move(0, N.TAB_H) ; t.con:resize("100%", math.max(1, h - N.TAB_H)) end)
  end
end

function N.tab(name)
  if N.tabs[name] then return N.tabs[name] end
  local t = {}
  t.label = Geyser.Label:new({ name = "NChatTab_" .. safe(name) }, N.tabBar)
  t.label:echo("<center>" .. name)
  t.label:setClickCallback(function() N.select(name) end)
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
  return t
end

function N.tab_style(name)
  local t = N.tabs[name]
  local k = (name == N.current) and "active" or (t.unread and "unread" or "idle")
  t.label:setStyleSheet(N.TAB_STYLE[k] .. TAB_SHAPE)
end

function N.select(name)
  N.current = name
  for n, t in pairs(N.tabs) do
    if n == name then t.con:show() ; t.unread = false else t.con:hide() end
    N.tab_style(n)
  end
end

local function put(t, ch, talker, text)
  local w = t.con.name
  setFgColor(w, 120, 120, 120) ; echo(w, os.date("%H:%M") .. " ")
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

function N.channel(v)
  if type(v) ~= "table" or not N.chatBox then return end
  local ch = tostring(v.channel or "?")
  local talker = tostring(v.talker or "")
  -- the game may send the line already wrapped; the pane wraps it to its own width
  local text = tostring(v.text or ""):gsub("\27%[[%d;]*m", ""):gsub("%s*\n%s*", " ")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  for _, name in ipairs({ "All", ch }) do
    local t = N.tab(name)
    put(t, ch, talker, text)
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

-- XP gained per hour this session (the game's own card shows one; GMCP does not, so compute it).
local function rate_str()
  local e = tonumber(N.st.exp) ; if not e then return "?" end
  local now = (type(getEpoch) == "function" and getEpoch()) or os.time()
  if not N.xp0 then N.xp0, N.xpT0 = e, now ; return "..." end
  local dt = now - (N.xpT0 or now)
  if dt < 30 then return "..." end
  local r = (e - N.xp0) / dt * 3600
  if r <= 0 then return "0/hr" end
  return r >= 1000 and string.format("%.0fk/hr", r / 1000) or string.format("%.0f/hr", r)
end

-- Char.Status is sent incrementally -- a combat update may carry only the changed fields (a new
-- exp, no neededexp) and replace the last -- so merge each message into a kept table and render
-- from that, or the XP total and the stats would blank out between full updates.
N.st = N.st or {}
function N.status(v)
  if type(v) ~= "table" then return end
  for k, val in pairs(v) do N.st[k] = val end
  local s = N.st
  local function g(k) return s[k] ~= nil and tostring(s[k]) or "?" end
  -- needexp is experience still to go, so the next-level total is exp + needexp; baseexp is where
  -- the level starts. At level 19 paragon level P+1 costs (P+1) million over baseexp.
  local e, n, b = tonumber(s.exp), tonumber(s.needexp or s.neededexp), tonumber(s.baseexp) or 0
  local para
  if e and n and tonumber(s.level) == 19 then
    local cost = e + n - b
    if cost >= 1e6 and cost % 1e6 == 0 then para = cost / 1e6 - 1 end
  end
  if N.stTitle then
    N.stTitle:echo(string.format(
      "<center><b style='font-size:13pt;'>%s</b></center>" ..
      "<center><span style='color:#9a93b0; font-size:9pt;'>Level %s%s &#183; %s &#183; %s</span></center>",
      g("name"), g("level"), para and (" &#183; Paragon " .. para) or "", g("guild"), g("race")))
  end
  if N.stXp then
    if e and n and para then
      N.stXp:setValue(math.max(e - b, 0), e + n - b, "Paragon  " .. commas(e - b) .. " / " .. commas(e + n - b))
    elseif e and n then
      N.stXp:setValue(math.max(e - b, 0), math.max(e + n - b, 1), "XP  " .. commas(e) .. " / " .. commas(e + n))
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

local function esc(s) return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end

local function guild_dims()
  local lh = N.lh()
  return math.floor(lh * 1.4), math.floor(lh * 1.35) * 7 + 8   -- a gauge row, the text block
end
local function druid_pets_max() return math.max(1, tonumber(N.gd and N.gd.pets_max) or 1) end
local function guild_card_h()
  local row, txt = guild_dims()
  if N.guildName == "Druid" then
    return row * (1 + druid_pets_max()) + math.floor(N.lh() * 1.35) * 5 + 8
  end
  return row * 4 + txt
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

local function fit_guild(w, h)
  if not N.gTxt then return end
  N.gW, N.gH = w, h
  local row = guild_dims()
  local strigoi = { N.gGp, N.gPen, N.gWasp }
  local rows = { { N.gHead, row - 2, row } }
  if N.guildName == "Druid" then
    for _, gg in ipairs(strigoi) do pcall(function() gg:hide() end) end
    for i, r in ipairs(N.gPetRows) do
      if i <= (N.gPetsShown or 0) then rows[#rows + 1] = { r, row - 2, row }
      else pcall(function() r:hide() end) end
    end
  else
    for _, r in ipairs(N.gPetRows) do pcall(function() r:hide() end) end
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

N.gd = N.gd or {}
function N.guild(name, v)
  if type(v) ~= "table" then return end
  local gname = name:match("^Guild%.(.+)$") or name
  if gname ~= N.guildName then
    N.gd, N.guildName = {}, gname
    N.relayout()                       -- first message (or a new guild): place the pane, retitle it
  end
  for k, val in pairs(v) do N.gd[k] = val end
  local g = N.gd
  if not N.gTxt then return end
  if N.guildName == "Druid" then return N.render_druid(g) end
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
  local H = "color:#e0b64a; font-weight:bold;"
  N.gTxt:echo(string.format(
    "<table width='100%%' cellspacing='0' cellpadding='1' style='font-size:10pt;'>" ..
    "<tr><td style='%s'>Active</td><td>%s</td></tr>" ..
    "<tr><td style='%s'>Soultick</td><td>%s</td></tr>" ..
    "</table>" ..
    "<table width='100%%' cellspacing='0' cellpadding='1' style='font-size:10pt; color:#dddddd;'>" ..
    "<tr><td style='%s'>Str</td><td align='right'>%s</td><td width='16'></td><td style='%s'>Int</td><td align='right'>%s</td></tr>" ..
    "<tr><td style='%s'>Dex</td><td align='right'>%s</td><td></td><td style='%s'>Con</td><td align='right'>%s</td></tr>" ..
    "</table>" ..
    -- last, so its varying wrap moves nothing above it
    "<table width='100%%' cellspacing='0' cellpadding='1' style='font-size:10pt;'>" ..
    "<tr><td style='%s'>Stack</td><td>%d/%s &#183; %s</td></tr>" ..
    "</table>",
    H, list(g.active, "none"),
    H, tick,
    H, stat("str"), H, stat("int"), H, stat("dex"), H, stat("con"),
    H, #st, esc(g.stack_size or "?"), list(st, "empty")))
end

-- A buff as a tag: lit while on, amber while it is about to wear off, dim when off.
local function tag(name, on, fading)
  local c = (fading and "#e0a030") or (on and "#70c070") or "#555555"
  return string.format("<span style='color:%s;%s'>%s</span>", c, on and " font-weight:bold;" or "", name)
end

-- Guild.Druid: level, points, tree, arch (whether you are the arch druid now), harmony,
-- staff {held, wielded, fireflies}, wand {held}, barkskin {on, shimmering}, pets, effects.
function N.render_druid(g)
  N.gHead:echo(string.format("<b>Level %s</b> &#183; %s", esc(g.level or "?"), esc(g.tree or "?")))
  local pets = type(g.pets) == "table" and g.pets or {}
  local max = druid_pets_max()
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
  local st = type(g.staff) == "table" and g.staff or {}
  local bk = type(g.barkskin) == "table" and g.barkskin or {}
  local hm = tonumber(g.harmony) or 0
  local staff = tonumber(st.wielded) == 1 and "staff (wielded)" or (tonumber(st.held) == 1 and "staff" or nil)
  local gear = {}
  gear[#gear + 1] = staff and tag(staff, true) or tag("no staff", false)
  gear[#gear + 1] = tag(tonumber((type(g.wand) == "table" and g.wand or {}).held) == 1 and "wand" or "no wand",
    tonumber((type(g.wand) == "table" and g.wand or {}).held) == 1)
  local buffs = {
    tag("arch", tonumber(g.arch) == 1),
    tag("barkskin", tonumber(bk.on) == 1, tonumber(bk.shimmering) == 1),
    tag("fireflies", tonumber(st.fireflies) == 1),
    tag(hm > 1 and ("harmony " .. hm) or "harmony", hm > 0),
  }
  local H = "color:#e0b64a; font-weight:bold;"
  local fx = list(g.effects, nil)
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

-- ================= wiring =========================================================

function N.on_event(_, ev)
  local name = ev:gsub("^gmcp%.", "")
  local v = at(name)
  log(name, v)
  if name == "Char.Vitals" then N.vitals(v)
  elseif name == "Char.Foe" then N.foe_show(v)
  elseif name == "Comm.Channel.Text" then N.channel(v)
  elseif name == "Char.Status" then N.status(v)
  elseif name == "Group.Info" then N.party(v)
  elseif N.GUILD_PANES[name:match("^Guild%.(.+)$") or ""] then N.guild(name, v) end
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

-- nanny [log | hello | reload | update | place <what> <where> | layout]
function N.cmd(arg)
  arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local verb, rest = arg:match("^(%S+)%s*(.*)$")
  if arg == "log" then
    N.log_toggle()
  elseif verb == "place" then
    local what, where = rest:match("^(%S+)%s+(%S+)$")
    if what then N.place_comp(what, where)
    else say("usage: nanny place <vitals|channels|status|party|log> <cell>  (cells: " ..
             table.concat(type(MudletBorders) == "table" and MudletBorders.cells() or {}, ", ") .. ")") end
  elseif verb == "layout" then
    local parts = {}
    for _, nm in ipairs(N.order) do
      local cell = type(MudletBorders) == "table" and MudletBorders.where("nanny:" .. nm) or N.place[nm]
      parts[#parts + 1] = nm .. "=" .. tostring(cell or "hidden")
    end
    say("layout: " .. table.concat(parts, ", ") .. (N.logOn and "  (log shown)" or "  (log hidden)"))
  elseif verb == "update" then
    N.update(false, rest)
  elseif arg == "hello" then
    N.hello()
    say("asked the game for: " .. table.concat(N.WANT, ", "))
  elseif arg == "reset" then
    if type(MudletBorders) == "table" then MudletBorders.reset() ; N.relayout() end
    say("layout sizes reset to defaults (placements kept).")
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
      local fh = io.open(src_file(), "w")
      if fh then fh:write(path) ; fh:close() end
      N.SRC = path
      say(path == "" and "back to the built-in copy from the next start." or
          ("loading from " .. path .. "; 'nanny reload' now."))
    end
  elseif arg == "reload" then
    if N.SRC == "" then say("no source file set: 'nanny src <path to nannybasics.lua>' first.") return end
    local ok, err = N.load_file()
    if not ok then cecho("\n<red>[nanny]: reload failed: " .. tostring(err) .. "\n<reset>") end
  else
    local names = {}
    for k, n in pairs(N.seen) do names[#names + 1] = k .. " x" .. n end
    table.sort(names)
    say("received: " .. (#names > 0 and table.concat(names, ", ") or "nothing yet") ..
        "\n  In the game: 'toggle gmcp', then 'toggle gmcp vitals', 'channels', 'foe', 'discord'," ..
        "\n  'status' (score: XP gauge + stats) and 'group' (party: HP/SP of each member)." ..
        "\n  Drag a pane by its title strip to move it: onto a pane to stack with it, near a pane's" ..
        "\n  edge to split it, or to an empty window edge. Drag the thin bars to resize." ..
        "\n  'nanny place <comp> <cell>' also moves a pane; 'nanny reset' restores the default." ..
        "\n  'nanny off' hides the whole right side (for an extra MultiView session); 'nanny on' back." ..
        "\n  'nanny log' shows/hides the GMCP log, 'nanny layout' lists placement, 'nanny hello' re-asks." ..
        "\n  'nanny update' installs the newest release. This is NannyBasics " .. N.VERSION .. ".")
  end
end

-- ================= startup ========================================================

N._lh = nil   -- recompute the text-row height on each load (code or font may have changed)
component("vitals", { build = build_vitals, hint_h = 2 * N.BAR })
component("channels", { build = build_channels, fit = fit_channels })
component("status", { build = build_status, hint_h = status_card_h(), fit = fit_status })
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
N.status(at("Char.Status"))
N.party(at("Group.Info"))
for k, v in pairs(type(at("Guild")) == "table" and at("Guild") or {}) do
  if N.GUILD_PANES[k] then N.guild("Guild." .. k, v) end
end
-- re-render the card every 20s so XP/hr stays live (and decays) between Char.Status messages
if N.rateTimer then killTimer(N.rateTimer) ; N.rateTimer = nil end
N.rateTimer = tempTimer(20, function() if next(N.st) then N.status(N.st) end end, true)
N.relayout()
N.register()
if N.alias then killAlias(N.alias) end
N.alias = tempAlias("^nanny(?:\\s+(.+))?$", function() N.cmd(matches[2]) end)
if type(gmcp) == "table" then N.hello() end
say("NannyBasics " .. N.VERSION .. " loaded. Type 'nanny' for commands.")
-- once per session, not on every reload; a few seconds in, after the profile has settled
if not N._checked and type(tempTimer) == "function" then
  N._checked = true
  tempTimer(5, function() pcall(N.check_latest) end)
end
