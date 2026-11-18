-- The game's xml mode (`toggle xml`) wraps text in tags named after its colour classes:
-- <short>, <exit>, <monster>, <say> and more. In ANSI mode the same classes are the player's
-- colours ('colour list'), so here the tags are cut out and the text between them painted in
-- that class's colour. Only a tag whose pair is proven is cut: game text can hold a word in
-- angle brackets ("give <item> to <player>"). A pair is proven by its close on the same line,
-- or by a close matching an open of an earlier line; a name once proven is cut at once after.

elro.xml = elro.xml or {}
local X = elro.xml
X.known = X.known or { short = true, long = true, exit = true, prompt = true, monster = true,
                       monster_enter = true, misc_in_long = true }
X.open = X.open or {}                       -- unknown names opened on an earlier line, kept
X.stack = X.stack or {}                     -- classes cut open on an earlier line, still open

-- ---- colours ----
-- The player's colours by class, { fg, bg } in the game's colour names, read from 'colour
-- list' and kept in the profile. Until any are read, these:
X.defaults = {
  short = { "boldwhite" }, exit = { "green" }, monster = { "boldred" }, player = { "boldmagenta" },
  misc_in_long = { "yellow" }, say = { "yellow" }, said = { "yellow" }, tell = { "boldgreen" },
  told = { "green" }, whisper = { "cyan" }, whispered = { "cyan" }, shout = { "boldyellow" },
  shouted = { "boldyellow" }, attack = { "red" }, attacked = { "boldred" }, died = { "boldred" },
  killed = { "boldred" }, hpinfo = { "magenta" }, danger = { "red" }, npc_said = { "yellow" },
}
local FILE = type(getMudletHomeDir) == "function" and (getMudletHomeDir() .. "/elro_colours.lua") or nil

function X.load_colours()
  X.colours = {}
  if FILE and type(table.load) == "function" then
    local ok = pcall(table.load, FILE, X.colours)
    if not ok then X.colours = {} end
  end
end

function X.save_colours()
  if FILE and type(table.save) == "function" then pcall(table.save, FILE, X.colours) end
end

-- a class's { fg, bg }, or nil: the player's own once any are known, else the defaults
function X.colour_of(class)
  if not X.colours then X.load_colours() end
  if next(X.colours) then return X.colours[class] end
  return X.defaults[class]
end

-- The standard terminal colours, used when Mudlet's own ANSI palette cannot be read.
local BASE = {
  black = { 0, 0, 0 }, red = { 128, 0, 0 }, green = { 0, 179, 0 }, yellow = { 128, 128, 0 },
  blue = { 0, 0, 128 }, magenta = { 128, 0, 128 }, cyan = { 0, 128, 128 }, white = { 192, 192, 192 },
}
local LIGHT = {
  black = { 128, 128, 128 }, red = { 255, 0, 0 }, green = { 0, 255, 0 }, yellow = { 255, 255, 0 },
  blue = { 0, 0, 255 }, magenta = { 255, 0, 255 }, cyan = { 0, 255, 255 }, white = { 255, 255, 255 },
}

-- the game's colour name as { r, g, b, bold, underline }, or nil for "default"
function X.rgb(name)
  if not name or name == "default" then return nil end
  if name == "bold" then return { nil, nil, nil, true } end
  if name == "underline" then return { nil, nil, nil, false, true } end
  local bold, base = name:match("^(bold)(%a+)$")
  base = base or name
  local ct = type(color_table) == "table"
    and color_table["ansi_" .. (bold and "light_" or "") .. base] or nil
  local c = ct or (bold and LIGHT or BASE)[base]
  if not c then return nil end
  return { c[1], c[2], c[3], bold ~= nil }
end

-- one line of 'colour list': "Class: 'say' ('say') yellow, background blue". The class's own
-- name in brackets is drawn in its colour, or tagged in xml mode, so it is skipped.
function X.learn_line(s)
  local class, rest = s:match("^Class: '([%w_]+)' %(.-%) (.+)$")
  if not class then return false end
  local fg, bg = rest:match("^(%S+), background (%S+)$")
  fg = fg or rest:match("^(%S+)$")
  if not fg then return false end
  if not X.colours then X.load_colours() end
  X.colours[class] = { fg, bg }
  X.save_colours()
  return true
end

-- ---- reading a line ----
-- The tags to cut from line `s` as { start, length }, start counted from 0 as selectSection
-- wants; whether nothing but blanks is left; and the spans to paint as { start, length,
-- class, depth }, counted on the line once the tags are gone. Learns from the line: opens
-- left unclosed, and names whose pair is proven.
function X.plan(s)
  local tags = {}
  for a, slash, name, attr, b in s:gmatch("()<(/?)([%a_]+)([^<>]*)>()") do
    tags[#tags + 1] = { a - 1, b - a, name = name, close = slash == "/", whole = attr:sub(-1) == "/" }
  end
  local cut = {}
  for i, t in ipairs(tags) do
    -- a self-closing tag (<sound ... />) is a whole element
    local ok = t.whole or X.known[t.name]
    if not ok then
      if t.close then
        for j = i - 1, 1, -1 do if tags[j].name == t.name and not tags[j].close then ok = true end end
        if not ok and X.open[t.name] then ok = true end
      else
        for j = i + 1, #tags do if tags[j].name == t.name and tags[j].close then ok = true end end
      end
    end
    if t.close and ok then X.known[t.name] = true ; X.open[t.name] = nil end
    if not t.close and not t.whole and not ok then X.open[t.name] = true end
    t.cut = ok
    if ok then cut[#cut + 1] = { t[1], t[2] } end
  end
  -- walk the line as it reads once cut: where each class starts and ends
  local stack, spans = {}, {}
  for _, c in ipairs(X.stack) do stack[#stack + 1] = { c, 0 } end
  local pos, from, rest = 0, 1, {}
  for _, t in ipairs(tags) do
    if t.cut then
      local seg = s:sub(from, t[1])
      rest[#rest + 1] = seg
      pos = pos + #seg
      from = t[1] + t[2] + 1
      if not t.whole then
        if t.close then
          for k = #stack, 1, -1 do
            if stack[k][1] == t.name then
              if pos > stack[k][2] then spans[#spans + 1] = { stack[k][2], pos - stack[k][2], t.name, k } end
              table.remove(stack, k)
              break
            end
          end
        else
          stack[#stack + 1] = { t.name, pos }
        end
      end
    end
  end
  local seg = s:sub(from)
  rest[#rest + 1] = seg
  pos = pos + #seg
  -- what stays open runs to the end of the line, and on into the next
  X.stack = {}
  for k, e in ipairs(stack) do
    if pos > e[2] then spans[#spans + 1] = { e[2], pos - e[2], e[1], k } end
    X.stack[#X.stack + 1] = e[1]
  end
  table.sort(spans, function(a, b) if a[4] ~= b[4] then return a[4] < b[4] end return a[1] < b[1] end)
  local text = table.concat(rest)
  return cut, #cut > 0 and not text:match("%S"), spans, text
end

-- Readers of what the tags say: fn(class, text) for every span, in line order of reading.
X.listeners = X.listeners or {}
function X.listen(key, fn) X.listeners[key] = fn end

local function paint(sp)
  local c = X.colour_of(sp[3])
  if not c then return end
  local fg, bg = X.rgb(c[1]), X.rgb(c[2])
  if not fg and not bg then return end
  if not selectSection(sp[1], sp[2]) then return end
  if fg then
    if fg[1] then setFgColor(fg[1], fg[2], fg[3]) end
    if fg[4] and type(setBold) == "function" then setBold(true) end
    if fg[5] and type(setUnderline) == "function" then setUnderline(true) end
  end
  if bg and bg[1] then setBgColor(bg[1], bg[2], bg[3]) end
end

X.cost = X.cost or { n = 0, sum = 0, max = 0 }

local function strip()
  local s = line or ""
  if #X.stack == 0 and not s:find("<", 1, true) then return end
  local t0 = os.clock()
  local cut, empty, spans, text = X.plan(s)
  for _, sp in ipairs(spans) do
    local piece = text:sub(sp[1] + 1, sp[1] + sp[2])
    for _, fn in pairs(X.listeners) do pcall(fn, sp[3], piece) end
  end
  if not empty then
    -- right to left, so a cut never moves the next one
    for i = #cut, 1, -1 do
      if selectSection(cut[i][1], cut[i][2]) then replace("") end
    end
    for _, sp in ipairs(spans) do paint(sp) end
    deselect()
    if type(resetFormat) == "function" then resetFormat() end
  else
    deleteLine()
  end
  if elro.mobs and elro.mobs.time then elro.mobs.time(X.cost, t0) end
end

if type(tempRegexTrigger) == "function" then
  for _, k in ipairs({ "tagT", "promptT", "learnT" }) do
    if X[k] then pcall(killTrigger, X[k]) ; X[k] = nil end
  end
  -- every line: one inside a class opened earlier has no tag of its own
  X.tagT = tempRegexTrigger("^", strip)
  X.learnT = tempRegexTrigger("^Class: '", function() X.learn_line(line or "") end)
end
