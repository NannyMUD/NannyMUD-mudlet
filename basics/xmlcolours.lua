-- xmlcolours.lua: the game's colours in its xml mode. In the game, colours and xml tags are one
-- system: every coloured piece of text goes through a named class, which the player's style
-- turns into either their colour for it or a tag. xmlcore cuts the tags; this paints the text
-- between them in that class's colour, read from 'colour list' lines as they pass and kept in
-- the profile. Hits get their damage tier's colour from the sound that follows them.

NannyBasics = NannyBasics or {}
NannyBasics.colours = NannyBasics.colours or {}
local C = NannyBasics.colours
local X = NannyXml

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

function C.load()
  C.set = {}
  local f = file()
  if f and type(table.load) == "function" then
    if not pcall(table.load, f, C.set) then C.set = {} end
  end
end

function C.save()
  local f = file()
  if f and type(table.save) == "function" then pcall(table.save, f, C.set) end
end

-- a class's { fg, bg }, or nil: the player's own once any are known, else the defaults
function C.of(class)
  if not C.set then C.load() end
  if next(C.set) then return C.set[class] end
  return C.defaults[class]
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
  C.set[class] = { fg, bg }
  C.save()
  return true
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
  if not n or #C.hit == 0 or type(moveCursor) ~= "function" then return false end
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
  C.learnT = tempRegexTrigger("^Class: '", function() C.learn_line(line or "") end)
end
