-- NannyBasics: NannyMUD's GMCP for players. Vitals and foe gauges under the text, a
-- tabbed channel pane, and a GMCP log that stays hidden until asked for.

NannyBasics = NannyBasics or {}
local N = NannyBasics

-- The source on disk wins over the copy built into the package (development only; a
-- player has no such file and gets the built-in copy).
N.SRC = N.SRC or ""

function N.load_file()
  local f = io.open(N.SRC, "r")
  if not f then return false, "no file at " .. N.SRC end
  f:close()
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

N.WANT = { "Char 1", "Comm.Channel 1", "External.Discord 1" }
-- Room.Info is the mapper's; it is listed only so the log shows it.
N.EVENTS = { "Char.Vitals", "Char.Foe", "Comm.Channel.Text",
             "External.Discord.Info", "External.Discord.Status", "Room.Info" }
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

-- ---- the bar under the text: foe above, HP and SP below -------------------------

N.BAR = 28
N.PULSE_AT = 0.4
N.HP_BASE, N.HP_PEAK = { 176, 48, 48 }, { 255, 190, 170 }

local function gauge_style(g, front, back)
  g.front:setStyleSheet("background-color: " .. front .. "; border-radius: 3px;")
  g.back:setStyleSheet("background-color: " .. back .. "; border-radius: 3px;")
  g.text:setStyleSheet("background-color: rgba(0,0,0,0); padding-left: 8px; font-weight: bold;")
end

function N.bar_make()
  if not N.bar then
    N.bar = Geyser.Container:new({ name = "NannyBar", x = 0, y = -2 * N.BAR,
      width = "100%", height = 2 * N.BAR })
    N.foe = Geyser.Gauge:new({ name = "NannyFoe", x = "1%", y = 3, width = "98%", height = N.BAR - 6 }, N.bar)
    N.hp = Geyser.Gauge:new({ name = "NannyHP", x = "1%", y = N.BAR + 3, width = "48.5%", height = N.BAR - 6 }, N.bar)
    N.sp = Geyser.Gauge:new({ name = "NannySP", x = "50.5%", y = N.BAR + 3, width = "48.5%", height = N.BAR - 6 }, N.bar)
  end
  setBorderBottom(2 * N.BAR)
  gauge_style(N.foe, "#b07a20", "#3a2a0c")
  gauge_style(N.hp, "#b03030", "#3a1414")
  gauge_style(N.sp, "#3050b0", "#141c3a")
end

local function gauge(g, cur, max, label)
  cur, max = tonumber(cur), tonumber(max)
  if not cur then return end
  if not max or max == 0 then max = cur end
  g:setValue(math.max(cur, 0), math.max(max, 1), label .. " " .. cur .. "/" .. max)
end

local function hp_colour(c)
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
  local k = 1 - math.max(f, 0) / N.PULSE_AT      -- 0 at the threshold, 1 at no HP
  local hz, amp = 0.8 + 2.2 * k, 0.35 + 0.65 * k
  local s = amp * (0.5 + 0.5 * math.sin(2 * math.pi * hz * getEpoch()))
  local c = {}
  for i = 1, 3 do c[i] = math.floor(N.HP_BASE[i] + (N.HP_PEAK[i] - N.HP_BASE[i]) * s + 0.5) end
  hp_colour(c)
end

function N.vitals(v)
  if type(v) ~= "table" then return end
  gauge(N.hp, v.hp, v.maxhp, "HP")
  gauge(N.sp, v.sp, v.maxsp, "SP")
  local hp, max = tonumber(v.hp), tonumber(v.maxhp)
  if hp and max and max > 0 then N.hpFrac = hp / max end
  if N.hpFrac and N.hpFrac < N.PULSE_AT and not N.pulseTimer then
    N.pulseTimer = tempTimer(0.05, N.pulse, true)
  end
  N.pulse()
end

-- show_shape()'s ten bands, as the middle of each band.
N.SHAPE = {
  ["undamaged"] = 95, ["superior"] = 85, ["very good"] = 75, ["good"] = 65, ["fair"] = 55,
  ["fairly poor"] = 45, ["poor"] = 35, ["weak"] = 25, ["very weak"] = 15, ["deplorable"] = 5,
}

-- An empty message, or none, is no fight.
function N.foe_show(v)
  local name, shape = type(v) == "table" and v.name, type(v) == "table" and v.shape
  if not name or name == "" then
    N.foe:setValue(0, 100, "no foe")
    return
  end
  N.foe:setValue(N.SHAPE[tostring(shape or ""):lower()] or 50, 100,
                 tostring(name) .. ": " .. tostring(shape or "?"))
end

-- ---- the channel pane: an All tab and one per channel ---------------------------

N.TAB_H = 22
N.TAB_STYLE = {
  idle   = "background-color: #262626; color: #b0b0b0;",
  active = "background-color: #404040; color: #ffffff; font-weight: bold;",
  unread = "background-color: #5a3a10; color: #ffcc66; font-weight: bold;",
}
local TAB_SHAPE = " border: 1px solid #3a3a3a; border-bottom: none;" ..
                  " border-top-left-radius: 4px; border-top-right-radius: 4px;"

-- A channel's colour, the same every session.
N.PALETTE = { { 120, 200, 255 }, { 255, 180, 90 }, { 150, 230, 140 }, { 230, 140, 230 },
              { 255, 230, 120 }, { 140, 220, 220 }, { 255, 140, 140 }, { 190, 170, 255 } }
local function chan_colour(name)
  local h = 0
  for i = 1, #name do h = (h * 31 + name:byte(i)) % 2147483647 end
  return N.PALETTE[h % #N.PALETTE + 1]
end

local function safe(name) return (name:gsub("[^%w]", "_")) end

-- Wrap the consoles at the pane's width: Mudlet keeps the width the window was made
-- with, so a dock that grows would still wrap at its first, narrow size.
N.CHAT_FONT = 10
function N.chat_wrap()
  if not N.chatBox then return end
  local cw = calcFontSize(N.CHAT_FONT) or 8
  local cols = math.max(20, math.floor((N.chatBox:get_width() - 20) / cw))
  for _, t in pairs(N.tabs or {}) do t.con:setWrap(cols) end
end

function N.chat_make()
  if N.chatBox then return end
  N.chatBox = Geyser.UserWindow:new({ name = "NannyChat", titleText = "Channels",
    docked = true, dockPosition = "right" })
  N.tabBar = Geyser.HBox:new({ name = "NannyTabBar", x = 0, y = 0, width = "100%", height = N.TAB_H },
                             N.chatBox)
  N.tabs, N.tabOrder = N.tabs or {}, N.tabOrder or {}
end

function N.tab(name)
  if N.tabs[name] then return N.tabs[name] end
  local t = {}
  t.label = Geyser.Label:new({ name = "NannyTab_" .. safe(name) }, N.tabBar)
  t.label:echo("<center>" .. name)
  t.label:setClickCallback(function() N.select(name) end)
  t.con = Geyser.MiniConsole:new({ name = "NannyCon_" .. safe(name), x = 0, y = N.TAB_H,
    width = "100%", height = -N.TAB_H, autoWrap = false, scrollBar = true, fontSize = N.CHAT_FONT,
    color = "black" }, N.chatBox)
  N.tabs[name] = t
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

-- One line into one tab: the time, the channel in its colour, the talker in white.
local function put(t, ch, talker, text)
  local w = t.con.name
  setFgColor(w, 120, 120, 120) ; echo(w, os.date("%H:%M") .. " ")
  local c = chan_colour(ch)
  setFgColor(w, c[1], c[2], c[3]) ; echo(w, "[" .. ch .. "] ")
  if talker ~= "" and text:sub(1, #talker) == talker then
    setFgColor(w, 255, 255, 255) ; echo(w, talker)
    text = text:sub(#talker + 1)
  end
  setFgColor(w, 200, 200, 200) ; echo(w, text .. "\n")
  resetFormat(w)
end

function N.channel(v)
  if type(v) ~= "table" then return end
  local ch = tostring(v.channel or "?")
  local talker = tostring(v.talker or "")
  -- The game may send the line already wrapped; the pane wraps it to its own width.
  local text = tostring(v.text or ""):gsub("\27%[[%d;]*m", ""):gsub("%s*\n%s*", " ")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  for _, name in ipairs({ "All", ch }) do
    local t = N.tab(name)
    put(t, ch, talker, text)
    if name ~= N.current then t.unread = true ; N.tab_style(name) end
  end
end

-- ---- the GMCP log, hidden until 'nanny log' -------------------------------------

function N.log_toggle()
  if not N.logBox then
    N.logBox = Geyser.UserWindow:new({ name = "NannyLog", titleText = "GMCP log",
      docked = true, dockPosition = "right" })
    N.logWin = Geyser.MiniConsole:new({ name = "NannyLogText", x = 0, y = 0, width = "100%",
      height = "100%", autoWrap = true, scrollBar = true, fontSize = 9 }, N.logBox)
    N.logOn = true
  else
    N.logOn = not N.logOn
    if N.logOn then N.logBox:show() else N.logBox:hide() end
  end
  say("GMCP log " .. (N.logOn and "shown" or "hidden"))
end

local function log(name, v)
  N.seen[name] = (N.seen[name] or 0) + 1
  if not N.logOn then return end
  local w = N.logWin.name
  setFgColor(w, 120, 120, 120) ; echo(w, os.date("%H:%M:%S") .. " ")
  setFgColor(w, 230, 200, 80) ; echo(w, name .. " ")
  setFgColor(w, 220, 220, 220) ; echo(w, json(v) .. "\n")
  resetFormat(w)
end

-- ---- wiring ---------------------------------------------------------------------

function N.on_event(_, ev)
  local name = ev:gsub("^gmcp%.", "")
  local v = at(name)
  log(name, v)
  if name == "Char.Vitals" then N.vitals(v)
  elseif name == "Char.Foe" then N.foe_show(v)
  elseif name == "Comm.Channel.Text" then N.channel(v) end
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
  N.handlers[#N.handlers + 1] = registerAnonymousEventHandler("sysUserWindowResizeEvent",
    function(_, _, _, name) if name == "NannyChat" then N.chat_wrap() end end)
end

-- nanny [log | hello | reload]
function N.cmd(arg)
  arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if arg == "log" then
    N.log_toggle()
  elseif arg == "hello" then
    N.hello()
    say("asked the game for: " .. table.concat(N.WANT, ", "))
  elseif arg == "reload" then
    local ok, err = N.load_file()
    if not ok then cecho("\n<red>[nanny]: reload failed: " .. tostring(err) .. "\n<reset>") end
  else
    local names = {}
    for k, n in pairs(N.seen) do names[#names + 1] = k .. " x" .. n end
    table.sort(names)
    say("received: " .. (#names > 0 and table.concat(names, ", ") or "nothing yet") ..
        "\n  In the game: 'toggle gmcp', then 'toggle gmcp vitals', 'channels', 'foe', 'discord'." ..
        "\n  'nanny log' shows or hides the GMCP log, 'nanny hello' asks the game again.")
  end
end

N.bar_make()
N.chat_make()
if not N.tabs["All"] then N.tab("All") end
N.select(N.current or "All")
N.chat_wrap()
if N.pulseTimer then killTimer(N.pulseTimer) ; N.pulseTimer = nil end
N.vitals(at("Char.Vitals"))
N.foe_show(at("Char.Foe"))
N.register()
if N.alias then killAlias(N.alias) end
N.alias = tempAlias("^nanny(?:\\s+(.+))?$", function() N.cmd(matches[2]) end)
if type(gmcp) == "table" then N.hello() end
