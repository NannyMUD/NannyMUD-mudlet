-- xmlcore.lua  (VENDORED: keep BYTE-IDENTICAL with basics/xmlcore.lua)
--
-- The game's xml mode (`toggle xml`) wraps text in tags named after its colour classes:
-- <short>, <exit>, <monster>, <say> and more. This cuts the tags out of the screen and tells
-- whoever listens what each class said; how the text looks is a listener's business. Only a
-- tag whose pair is proven is cut: game text can hold a word in angle brackets ("give <item>
-- to <player>"). A pair is proven by its close on the same line, or by a close matching an
-- open of an earlier line; a name once proven is cut at once after.
--
-- Singleton in a neutral global: every package carries a copy and the NEWEST revision wins,
-- whatever the load order. So the shared API may only grow: plan, listen, on_line, strip,
-- known, stack, cost, state, want, on_state, answer, untag. Raise REV with every change; a
-- break needs a new global name.

local REV = 4
NannyXml = NannyXml or {}
local X = NannyXml
if (X.REV or 0) > REV then return X end
X.REV = REV

X.known = X.known or { short = true, long = true, exit = true, prompt = true, monster = true,
                       monster_enter = true, misc_in_long = true }
X.open = X.open or {}                       -- unknown names opened on an earlier line, kept
X.stack = X.stack or {}                     -- classes cut open on an earlier line, still open
X.listeners = X.listeners or {}             -- key -> fn(class, text) for every span
X.lines = X.lines or {}                     -- key -> fn(info) for every tagged line, once cut
X.cost = X.cost or { n = 0, sum = 0, max = 0 }

function X.listen(key, fn) X.listeners[key] = fn end
function X.on_line(key, fn) X.lines[key] = fn end

-- ---- the game's own switch ----
-- 'toggle xml on' sets the mode. Off is 'toggle ansi on': it leaves xml mode for the game's
-- colours, where 'toggle xml off' would leave plain text with none. The answers ("xml mode
-- turned on.", "Ansi mode turned on.") and a proven tag tell where it stands.
-- X.state: true, false, or nil while not known.
X.states = X.states or {}                   -- key -> fn(on) when the mode is seen to change
function X.on_state(key, fn) X.states[key] = fn end

local function set_state(on)
  local was = X.state
  X.state = on
  if was ~= on then for _, fn in pairs(X.states) do pcall(fn, on) end end
end

-- ask for the mode on or off, off to the game's colours unless `plain`; true when sent
function X.want(on, plain)
  if X.state == on then return false end
  if type(send) == "function" then
    send(on and "toggle xml on" or plain and "toggle xml off" or "toggle ansi on", false)
  end
  return true
end

-- the game's answers that tell the mode
function X.answer(s)
  local w = s:match("^xml mode turned (%a+)")
  if w then set_state(w == "on") return true end
  w = s:match("^Ansi mode turned (%a+)")
  if w then if w == "on" then set_state(false) end return true end
  return false
end

-- The tags to cut from line `s` as { start, length }, start counted from 0 as selectSection
-- wants; whether nothing but blanks is left; the spans of each class as { start, length,
-- class, depth }, counted on the line once the tags are gone, outer classes first; the line
-- once cut; and its whole elements (<sound ... />) as { name, attributes }. Learns from the
-- line: opens left unclosed, and names whose pair is proven.
function X.plan(s)
  local tags = {}
  for a, slash, name, attr, b in s:gmatch("()<(/?)([%a_]+)([^<>]*)>()") do
    tags[#tags + 1] = { a - 1, b - a, name = name, close = slash == "/", whole = attr:sub(-1) == "/",
                        attr = attr }
  end
  local cut = {}
  for i, t in ipairs(tags) do
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
  local wholes = {}
  for _, t in ipairs(tags) do if t.whole then wholes[#wholes + 1] = { t.name, t.attr } end end
  return cut, #cut > 0 and not text:match("%S"), spans, text, wholes
end

-- Text that never reaches the console (a GMCP channel message) with its tags cut: a whole
-- element, a name proven before, or one whose close is in the text too. Learns nothing.
function X.untag(s)
  s = tostring(s or "")
  if not s:find("<", 1, true) then return s end
  local closed = {}
  for name in s:gmatch("</([%a_]+)>") do closed[name] = true end
  return (s:gsub("<(/?)([%a_]+)([^<>]*)>", function(_, name, attr)
    if attr:sub(-1) == "/" or X.known[name] or closed[name] then return "" end
  end))
end

-- One line of the console. Listeners hear each span's text; line readers get the line once its
-- tags are cut, while it is still the current line: { spans, wholes, text, here, carried,
-- empty, base }, carried being the classes open from the line before, base the colour of text
-- no trigger has touched (nil when unknown). A line left blank goes.
function X.strip()
  local s = line or ""
  if #X.stack == 0 and not s:find("<", 1, true) then return end
  local t0 = os.clock()
  local carried = {}
  for _, c in ipairs(X.stack) do carried[c] = true end
  local cut, empty, spans, text, wholes = X.plan(s)
  if #cut > 0 and X.state ~= true then set_state(true) end
  for _, sp in ipairs(spans) do
    local piece = text:sub(sp[1] + 1, sp[1] + sp[2])
    for _, fn in pairs(X.listeners) do pcall(fn, sp[3], piece) end
  end
  -- the colour of untouched text, read off a tag before it goes: a listener can tell text a
  -- trigger has coloured already (a highlight) from text no one has
  local base
  if cut[1] and type(getFgColor) == "function" and selectSection(cut[1][1], 1) then
    local r, g, b = getFgColor()
    if r then base = { r, g, b } end
  end
  if not empty then
    -- right to left, so a cut never moves the next one
    for i = #cut, 1, -1 do
      if selectSection(cut[i][1], cut[i][2]) then replace("") end
    end
    deselect()
  end
  local info = { spans = spans, wholes = wholes, text = text, carried = carried, empty = empty,
                 base = base, here = type(getLineNumber) == "function" and getLineNumber() or nil }
  for _, fn in pairs(X.lines) do pcall(fn, info) end
  if type(resetFormat) == "function" then resetFormat() end
  if empty then deleteLine() end
  local d = os.clock() - t0
  X.cost.n, X.cost.sum = X.cost.n + 1, X.cost.sum + d
  if d > X.cost.max then X.cost.max = d end
end

if type(tempRegexTrigger) == "function" then
  if X.tagT then pcall(killTrigger, X.tagT) end
  -- every line: one inside a class opened earlier has no tag of its own
  X.tagT = tempRegexTrigger("^", function() NannyXml.strip() end)
  if X.answerT then pcall(killTrigger, X.answerT) end
  X.answerT = tempRegexTrigger("^(xml|Ansi) mode turned ",
    function() NannyXml.answer(line or "") end)
end
return X
