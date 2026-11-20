-- xmlcolours.lua: the game's colours in its xml mode. In the game, colours and xml tags are one
-- system: every coloured piece of text goes through a named class, which the player's style
-- turns into either their colour for it or a tag. xmlcore cuts the tags; this paints the text
-- between them in that class's colour, read from 'colour list' lines as they pass and kept in
-- the profile. Hits get their damage tier's colour from the sound that follows them.

NannyBasics = NannyBasics or {}
NannyBasics.colours = NannyBasics.colours or {}
local C = NannyBasics.colours
local X = NannyXml
C.opts = C.opts or {}

-- Until any 'colour list' line is read, these, in the game's colour names.
C.defaults = {
  short = { "boldwhite" }, exit = { "green" }, monster = { "boldred" }, player = { "boldmagenta" },
  misc_in_long = { "yellow" }, say = { "yellow" }, said = { "yellow" }, tell = { "boldgreen" },
  told = { "green" }, whisper = { "cyan" }, whispered = { "cyan" }, shout = { "boldyellow" },
  shouted = { "boldyellow" }, attack = { "red" }, attacked = { "boldred" }, died = { "boldred" },
  killed = { "boldred" }, hpinfo = { "magenta" }, danger = { "red" }, npc_said = { "yellow" },
}
local function file()
  return type(getMudletHomeDir) == "function" and (getMudletHomeDir() .. "/nanny_colours.lua") or nil
end

-- the file holds the classes learned and, under "_opt", the player's switches
function C.load()
  C.set = {}
  local f = file()
  if f and type(table.load) == "function" then
    if not pcall(table.load, f, C.set) then C.set = {} end
  end
  C.opts = C.set._opt or {}
  C.set._opt = nil
end

function C.save()
  local f = file()
  if not f or type(table.save) ~= "function" then return end
  local t = { _opt = C.opts }
  for k, v in pairs(C.set or {}) do t[k] = v end
  pcall(table.save, f, t)
end

-- a switch, as the player set it or else its default. Hits are off until asked for: their tier
-- colours would paint over the player's own attack colours.
C.OPT_DEFAULT = { hits = false, numbers = false, off = "ansi" }
function C.opt(name)
  if not C.set then C.load() end
  local v = C.opts[name]
  if v == nil then v = C.OPT_DEFAULT[name] end
  return v
end

-- a class's { fg, bg }, or nil: the player's own once any are known. An empty 'colour list'
-- means the player set none and saw the game's text uncoloured, so nothing is painted then,
-- unless they asked for the defaults; before any list is read, the defaults.
function C.of(class)
  if not C.set then C.load() end
  if next(C.set) then return C.set[class] end
  local d = C.opts.defaults
  if d == true or (d == nil and not C.opts.empty) then return C.defaults[class] end
  return nil
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
function C.rgb(name)
  if not name or name == "default" then return nil end
  if name == "bold" then return { nil, nil, nil, true } end
  if name == "underline" then return { nil, nil, nil, false, true } end
  local bold, base = name:match("^(bold)(%a+)$")
  base = base or name
  local ct = type(color_table) == "table"
    and color_table["ansi_" .. (bold and "light_" or "") .. base] or nil
  local c = ct or (bold and LIGHT or BASE)[base]
  if not c then return nil end
  -- "boldred" is the terminal's bright red, as the game's own colours show it, not a bold font
  return { c[1], c[2], c[3] }
end

-- one line of 'colour list': "Class: 'say' ('say') yellow, background blue". The class's own
-- name in brackets is drawn in its colour, or tagged in xml mode, so it is skipped.
function C.learn_line(s)
  local class, rest = s:match("^Class: '([%w_]+)' %(.-%) (.+)$")
  if not class then return false end
  local fg, bg = rest:match("^(%S+), background (%S+)$")
  fg = fg or rest:match("^(%S+)$")
  if not fg then return false end
  if not C.set then C.load() end
  -- a list asked for afresh replaces the old one: a class removed in the game goes here too
  if C.fresh then C.set, C.fresh = {}, false end
  C.opts.empty = nil
  C.set[class] = { fg, bg }
  C.save()
  return true
end

-- Ask the game for 'colour list' with its lines kept off the screen, up to the next prompt.
-- A list with no classes means the player set none: the defaults then.
function C.ask_colours()
  if type(send) ~= "function" then return end
  C.quiet, C.fresh = true, true
  send("colour list", false)
  if type(tempTimer) == "function" then tempTimer(5, function() C.quiet_end() end) end
end

function C.quiet_end()
  if not C.quiet then return end
  C.quiet = false
  if C.fresh then C.set, C.fresh = {}, false ; C.opts.empty = true ; C.save() end
end

-- nanny xml [on|off|hits on|off|numbers on|off|defaults on|off]
function C.cmd(arg)
  arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local function say(s) cecho("\n<cyan>[nanny]: " .. s .. "<reset>\n") end
  local h = arg:match("^hits%s+(%a+)$")
  local d = arg:match("^defaults%s+(%a+)$")
  local nb = arg:match("^numbers%s+(%a+)$")
  if nb == "on" or nb == "off" then
    if not C.set then C.load() end
    C.opts.numbers = nb == "on"
    C.save()
    say((nb == "on" and "a coloured hit gets its tier in front ('7: You hit ...')."
         or "a coloured hit keeps its text as it was, colour only.")
        .. (C.opt("hits") and "" or " Hits are not coloured now: 'nanny xml hits on'."))
  elseif d == "on" or d == "off" then
    if not C.set then C.load() end
    -- on: the defaults wherever the game has no colours of yours; off: back to the list's say
    C.opts.defaults = d == "on" or nil
    C.save()
    say(d == "on" and "the default colours are used where you set none in the game."
        or "colours as your 'colour list' says: none set, nothing painted.")
  elseif h == "trace" then
    C.htrace = not C.htrace
    say(C.htrace and "tracing hits: how each hit and sound pair. 'nanny xml hits trace' again stops."
        or "hit tracing off.")
  elseif h == "on" or h == "mine" or h == "off" then
    if not C.set then C.load() end
    C.opts.hits = h == "mine" and "mine" or h == "on"
    C.save()
    say(h == "off" and "hits keep their class colour, no tier."
        or ((h == "on" and "your hits (warm) and the hits on you (cool) are" or "your hits are")
            .. " coloured by their damage tier" .. (C.opt("numbers") and ", with the tier in front."
            or "; 'nanny xml numbers on' puts the tier in front.")
            .. (h == "mine" and " Hits on you keep their own colour." or "")))
  elseif arg == "on" or arg:match("^off") then
    local on = arg == "on"
    -- off goes back to the game's colours, or to plain text for a player who chose that once
    local how = arg:match("^off%s+(%a+)$")
    if how == "plain" or how == "ansi" then
      if not C.set then C.load() end
      C.opts.off = how
      C.save()
    elseif not on and arg ~= "off" then
      say("'nanny xml off', 'nanny xml off ansi' (the game's colours) or 'nanny xml off plain' (no colours).")
      return
    end
    local plain = not on and C.opt("off") == "plain"
    if not X.want(on, plain) then
      say("the game's xml mode is already " .. (on and "on" or "off") .. ".")
    else
      say(on and "asking the game to turn xml mode on."
          or plain and "asking the game to leave xml mode for plain text, no colours."
          or "asking the game to leave xml mode for its own colours.")
    end
  else
    local n = 0
    if not C.set then C.load() end
    for _ in pairs(C.set) do n = n + 1 end
    say(string.format("xml mode is %s. Colours: %s. Hits by damage tier: %s. 'nanny help xml' explains.",
      X.state == true and "on" or X.state == false and "off" or "not known yet (on once tags are seen)",
      n > 0 and (n .. " class(es) of yours, from 'colour list'")
        or C.of("say") and "the defaults"
        or "none (your 'colour list' is empty; 'nanny xml defaults on' for ours)",
      C.opt("hits") and ((C.opt("hits") == "mine" and "yours only" or "yours and on you")
        .. (C.opt("numbers") and ", tier in front" or "")) or "off"))
  end
end

-- xml mode seen to come on: read the player's colours, quietly
if X and X.on_state then
  X.on_state("colours", function(on) if on then C.ask_colours() end end)
end

local function paint(sp)
  local c = C.of(sp[3])
  if not c then return end
  local fg, bg = C.rgb(c[1]), C.rgb(c[2])
  if not fg and not bg then return end
  if not selectSection(sp[1], sp[2]) then return end
  if fg then
    if fg[1] then setFgColor(fg[1], fg[2], fg[3]) end
    if fg[4] and type(setBold) == "function" then setBold(true) end
    if fg[5] and type(setUnderline) == "function" then setUnderline(true) end
  end
  if bg and bg[1] then setBgColor(bg[1], bg[2], bg[3]) end
end

-- ---- hits by tier ----
-- Each hit sends a sound after its text: <sound class=".../hit_N*" .../>, or ".../miss*" for a
-- miss. Two attacks can both come before their sounds, so every <attack> or <attacked> waits
-- in order, and each sound paints the oldest one in tier N's colour, "N: " in front if asked.
-- A hit on you (<attacked>) takes the tier from a scale of its own, so the two stay apart;
-- 'hits mine' leaves it in its class colour. RGB, not colour names: a name Mudlet lacks
-- would fall back to something unrelated.
-- tier 0 is a miss: the muted foot of the scale
-- set afresh on every load: a reinstall keeps the old table otherwise
C.HIT = {
  [0] = { 210, 180, 140 },                                        -- tan
  { 255, 255, 224 }, { 255, 255, 224 }, { 240, 230, 140 },        -- light yellow, khaki
  { 255, 255, 0 }, { 255, 165, 0 }, { 255, 140, 0 },              -- yellow, orange, dark orange
  { 255, 99, 71 }, { 255, 20, 147 },                              -- tomato, deep pink
}
-- hits on you: a cool scale of its own, rising the same way
C.HIT_IN = {
  [0] = { 119, 136, 153 },                                        -- light slate grey
  { 176, 196, 222 }, { 135, 206, 250 }, { 135, 206, 235 },        -- light steel, light sky, sky blue
  { 0, 191, 255 }, { 30, 144, 255 }, { 123, 104, 238 },           -- deep sky, dodger, medium slate blue
  { 186, 85, 211 }, { 255, 0, 255 },                              -- medium orchid, magenta
}
C.HIT_CLASS = { attack = true, attacked = true }
C.hits = C.hits or {}                       -- waiting for a sound: { class, { line, start, length }... }
C.early = C.early or {}                     -- sounds that came before their hit: { n, line }
local GONE = 5                              -- lines after which a hit or a sound no longer pairs

-- 'nanny xml hits trace': how each hit and sound paired. Printed after the line is done, since
-- text echoed mid-line would shift what is being painted.
local function htrace(fmt, ...)
  if not C.htrace or type(tempTimer) ~= "function" then return end
  local s = string.format(fmt, ...)
  tempTimer(0, function() cecho("\n<dim_grey>[hits] " .. s .. "<reset>") end)
end

-- paint hit h (its lines so far) in tier n of its scale; true when painted
local function paint_hit(h, n, here)
  local on_you = h.class == "attacked"
  if on_you and C.opt("hits") == "mine" then return false end
  local scale = on_you and C.HIT_IN or C.HIT
  local c = scale[n] or scale[#scale]
  -- checked before the cursor leaves this line: the tag reader deletes whatever line it is on
  if type(c) ~= "table" or not c[3] then return false end
  h.c = c
  for i, p in ipairs(h) do
    moveCursor(0, p[1])
    if selectSection(p[2], p[3]) then setFgColor(c[1], c[2], c[3]) end
    deselect()
    if i == 1 and C.opt("numbers") then moveCursor(p[2], p[1]) ; insertText(n .. ": ") end
  end
  if here then moveCursor(0, here) end
  return true
end

local function prune(here)
  if not here then return end
  while C.hits[1] and C.hits[1][#C.hits[1]][1] < here - GONE do
    htrace("a hit on line %d never got its sound", C.hits[1][1][1])
    table.remove(C.hits, 1)
  end
  while C.early[1] and C.early[1][2] < here - GONE do
    htrace("a tier %d sound never got its hit", C.early[1][1])
    table.remove(C.early, 1)
  end
end

-- a sound: it paints the oldest hit waiting, or waits a few lines for the next hit
function C.hit_sound(attr, here)
  local n = tonumber((attr or ""):match("hit_(%d+)")) or ((attr or ""):match("/miss") and 0)
  if not n or not C.opt("hits") or type(moveCursor) ~= "function" then return false end
  prune(here)
  local h = table.remove(C.hits, 1)
  if not h then
    C.early[#C.early + 1] = { n, here or 0 }
    htrace("tier %d sound with no hit waiting: it waits for the next", n)
    return false
  end
  htrace("tier %d sound paints the %s on line %d", n, h.class, h[1][1])
  return paint_hit(h, n, here)
end

-- every tagged line once cut: paint its classes, note a hit, and colour one when its sound comes
function C.line(info)
  if info.empty then
    for _, w in ipairs(info.wholes) do if w[1] == "sound" then C.hit_sound(w[2], info.here) end end
    return
  end
  local now = {}                            -- hits a waiting sound paints, once the spans are done
  for _, sp in ipairs(info.spans) do
    paint(sp)
    -- a hit's text, line by line: a new one is a hit of its own unless it runs on from the line before
    if C.HIT_CLASS[sp[3]] and info.here and C.opt("hits") then
      prune(info.here)
      local seg = { info.here, sp[1], sp[2] }
      local cur = C.cur
      if cur and info.carried[sp[3]] and sp[1] == 0 then
        cur[#cur + 1] = seg
        if cur.c and selectSection(sp[1], sp[2]) then setFgColor(cur.c[1], cur.c[2], cur.c[3]) end
      else
        cur = { class = sp[3], seg }
        C.cur = cur
        local s = table.remove(C.early, 1)
        if s then
          now[#now + 1] = { cur, s[1] }
          htrace("the %s on line %d takes the tier %d sound that came first", sp[3], info.here, s[1])
        else
          C.hits[#C.hits + 1] = cur
        end
      end
    end
  end
  deselect()
  for _, p in ipairs(now) do paint_hit(p[1], p[2], info.here) end
  for _, w in ipairs(info.wholes) do if w[1] == "sound" then C.hit_sound(w[2], info.here) end end
end

if X and X.on_line then X.on_line("colours", C.line) end
if type(tempRegexTrigger) == "function" then
  if C.learnT then pcall(killTrigger, C.learnT) end
  C.learnT = tempRegexTrigger("^Class: '", function()
    C.learn_line(line or "")
    if C.quiet then deleteLine() end
  end)
end
if type(tempPromptTrigger) == "function" then
  if C.promptT then pcall(killTrigger, C.promptT) end
  C.promptT = tempPromptTrigger(function() C.quiet_end() end)
end
