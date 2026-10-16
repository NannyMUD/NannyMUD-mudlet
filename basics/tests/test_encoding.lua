-- 'nanny encoding': a line read as Latin-1 has its UTF-8 and Windows-1252 pieces repaired.
--   luajit basics/tests/test_encoding.lua
local any ; any = setmetatable({}, { __index = function() return any end, __call = function() return any end })
setmetatable(_G, { __index = function(_, k) return function() return any end end })
Geyser = any
gmcp = {}
NannyBasics, MudletBorders = {}, {}
function getMainWindowSize() return 2560, 1143 end
function getMudletHomeDir() return "." end
function calcFontSize() return 8, 15 end
function getEpoch() return os.time() end
function getMousePosition() return nil end
yajl = { to_string = function(t) return "{...}" end }

local HERE = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "../"
dofile(HERE .. "border.lua")
dofile(HERE .. "nannybasics.lua")
local N = NannyBasics

local fails = 0
local function check(ok, what)
  if not ok then fails = fails + 1 ; print("FAIL " .. what) end
end

-- what Mudlet shows for raw bytes when the profile reads the game as Latin-1
local function latin1(...)
  local out = {}
  for _, b in ipairs({ ... }) do
    if b < 0x80 then out[#out + 1] = string.char(b)
    else out[#out + 1] = string.char(0xC0 + math.floor(b / 0x40), 0x80 + b % 0x40) end
  end
  return table.concat(out)
end
local function bytes(s) local t = {} for i = 1, #s do t[i] = s:byte(i) end return t end
local function L(s) return latin1(unpack(bytes(s))) end

-- what the trigger does: each repair replaces the first remaining occurrence
local function repair(s)
  for _, p in ipairs(N.mojibake(s)) do
    local a, b = s:find(p[1], 1, true)
    if a then s = s:sub(1, a - 1) .. p[2] .. s:sub(b + 1) end
  end
  return s
end

-- a UTF-8 sender: "hej å ä ö" arrives as Ã¥ Ã¤ Ã¶ and comes back
local utf8line = "Bob tells you: hej \195\165 \195\164 \195\182"
check(repair(L(utf8line)) == utf8line, "UTF-8 å ä ö repaired")
check(#N.mojibake(L(utf8line)) == 3, "three repairs for three letters")

-- a Latin-1 sender: already right, nothing to do
local latin = latin1(0x68, 0xE5, 0x20, 0xE4, 0x20, 0xF6)   -- "hå ä ö"
check(#N.mojibake(latin) == 0, "Latin-1 å ä ö left alone")
check(latin == "h\195\165 \195\164 \195\182", "Latin-1 bytes read as å ä ö")

-- Windows-1252: 0x92 and 0x96 are a curly quote and a dash, not control characters
check(repair(latin1(0x49, 0x92, 0x6D, 0x20, 0x96)) == "I\226\128\153m \226\128\147", "1252 quote and dash")

-- 3 and 4 bytes: the euro sign and an emoji
check(repair(L("\226\130\172 5")) == "\226\130\172 5", "UTF-8 euro sign")
check(repair(L("\240\159\152\128")) == "\240\159\152\128", "UTF-8 four-byte emoji")

-- not UTF-8, so never decoded as UTF-8: a lone lead byte, an overlong form, a surrogate, past
-- U+10FFFF. A stray 0x80-0x9F byte still gets the Windows-1252 reading, one character each.
local function no_utf8(s)
  for _, p in ipairs(N.mojibake(s)) do if #p[1] ~= 2 then return false end end
  return true
end
check(#N.mojibake(latin1(0xC3, 0x20, 0x41)) == 0, "lone lead byte left alone")
check(#N.mojibake(latin1(0xC0, 0xAF)) == 0, "overlong two-byte form left alone")
check(no_utf8(latin1(0xE0, 0x80, 0x80)), "overlong three-byte form not decoded")
check(repair(latin1(0xE0, 0x80, 0x80)) == "\195\160\226\130\172\226\130\172", "...its 0x80s read as 1252 euro signs")
check(no_utf8(latin1(0xED, 0xA0, 0x80)), "surrogate not decoded")
check(no_utf8(latin1(0xF4, 0x90, 0x80, 0x80)), "past U+10FFFF not decoded")
check(#N.mojibake("plain ascii line") == 0, "ASCII line untouched")

-- a tell from a UTF-8 client: Ä is C3 84, and 84 alone would be a 1252 quote mark
local tell = "Bob tells you: \195\132r bron \195\182ppen? Vi g\195\165r \195\182ver \195\165n n\195\164r solen \195\164r uppe"
check(repair(L(tell)) == tell, "a UTF-8 tell with Ä, ä, ö and å repaired")

-- both senders on one line, and the same letter twice
local mixed = latin1(0xE5) .. " / " .. L("\195\165") .. " / " .. L("\195\165")
check(repair(mixed) == "\195\165 / \195\165 / \195\165", "mixed line, repeated letter")

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
