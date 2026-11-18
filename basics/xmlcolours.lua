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
C.OPT_DEFAULT = { hits = false, off = "ansi" }
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
  return { c[1], c[2], c[3], bold ~= nil }
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

-- nanny xml [on|off|hits on|off]
function C.cmd(arg)
  arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local function say(s) cecho("\n<cyan>[nanny]: " .. s .. "<reset>\n") end
  local h = arg:match("^hits%s+(%a+)$")
  local d = arg:match("^defaults%s+(%a+)$")
  if d == "on" or d == "off" then
    if not C.set then C.load() end
    -- on: the defaults wherever the game has no colours of yours; off: back to the list's say
    C.opts.defaults = d == "on" or nil
    C.save()
    say(d == "on" and "the default colours are used where you set none in the game."
        or "colours as your 'colour list' says: none set, nothing painted.")
  elseif h == "on" or h == "off" then
    if not C.set then C.load() end
    C.opts.hits = h == "on"
    C.save()
    say(h == "on" and "hits are coloured by their damage tier, with the tier in front."
        or "hits keep their class colour, no tier.")
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
      C.opt("hits") and "on" or "off"))
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
-- A hit's sound comes after its text: <sound class=".../hit_N*" .../>. The text of the latest
-- <attack> or <attacked> is remembered by line, and the sound paints it in tier N's colour
-- with "N: " in front.
C.HIT = C.HIT or { "light_yellow", "light_yellow", "khaki", "yellow", "orange",
                   "dark_orange", "tomato", "deep_pink" }
C.HIT_CLASS = { attack = true, attacked = true }
C.hit = C.hit or {}                         -- { { line, start, length } } of the latest hit

function C.hit_sound(attr, here)
  local n = tonumber((attr or ""):match("hit_(%d+)"))
  if not n or not C.opt("hits") or #C.hit == 0 or type(moveCursor) ~= "function" then return false end
  -- a hit more than a few lines back is not this sound's
  if here and C.hit[#C.hit][1] < here - 5 then C.hit = {} return false end
  local name = C.HIT[n] or "blue"
  local c = type(color_table) == "table" and color_table[name] or { 0, 0, 255 }
  for i, p in ipairs(C.hit) do
    moveCursor(0, p[1])
    if selectSection(p[2], p[3]) then setFgColor(c[1], c[2], c[3]) end
    deselect()
    if i == 1 then moveCursor(p[2], p[1]) ; insertText(n .. ": ") end
  end
  C.hit = {}
  if here then moveCursor(0, here) end
  return true
end

-- every tagged line once cut: paint its classes, note a hit, and colour one when its sound comes
function C.line(info)
  if info.empty then
    for _, w in ipairs(info.wholes) do if w[1] == "sound" then C.hit_sound(w[2], info.here) end end
    return
  end
  for _, sp in ipairs(info.spans) do
    paint(sp)
    -- a hit's text, line by line; a new one starts over unless it runs on from the line before
    if C.HIT_CLASS[sp[3]] and info.here then
      if not (info.carried[sp[3]] and sp[1] == 0) then C.hit = {} end
      C.hit[#C.hit + 1] = { info.here, sp[1], sp[2] }
    end
  end
  deselect()
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
