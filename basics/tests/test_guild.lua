-- Load the real nannybasics.lua with stubbed Mudlet globals and render a Guild.Strigoi payload
-- (placement, gauges, text, merging, and that a squeezed pane never spills past its box).
--   luajit basics/tests/test_guild.lua
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
local default_dark = N.iconSet == "dark"
N.iconSet = "emoji"   -- the emoji checks below; the dark set is tested on its own

-- record what the pane widgets are given
local rec = {}
local function recorder(name)
  return setmetatable({}, { __index = function(t, k)
    if k == "echo" then return function(_, s) rec[name] = s end end
    if k == "setValue" then return function(_, v, m, s) rec[name] = { v, m, s } end end
    if k == "front" then return any end
    return function() return t end
  end })
end
N.gHead, N.gGp, N.gPen, N.gWasp, N.gTxt = recorder("head"), recorder("gp"), recorder("pen"), recorder("wasp"), recorder("txt")

-- the markup of an icon in its fixed slot: on a bar, and in the stack
local function bar(icon, text)
  return "<table cellspacing='0' cellpadding='0'><tr><td width='24' align='center'>" .. icon ..
    "</td><td>&nbsp;" .. text .. "</td></tr></table>"
end
local function slot(inner) return "<td width='30' align='center'>" .. inner .. "</td>" end
local function sub(n) return "<sub style='color:#e0b64a; font-weight:bold;'>" .. n .. "</sub>" end

local fails = 0
local function check(ok, msg) print((ok and "ok   " or "FAIL ") .. msg) ; if not ok then fails = fails + 1 end end

check(MudletBorders.where("nanny:guild") == nil, "no guild data yet: guild pane parked")
check(default_dark, "the dark icons are the default")

N.on_event(nil, "gmcp.Guild.Strigoi")   -- gmcp table empty: v is nil, must not error
gmcp.Guild = { Strigoi = {
  str = 0, stack_size = 6, soultick = { hb = 466, guild_points = 0, combat_hb = 1 }, active = { "wasp" },
  temp = {}, form = "human", penalty = 0, next = 19588066, stack = {}, con = 0, int = 0,
  wasp = { maxhp = 120, level = 8, hp = 120, out = 1 }, dex = 0, points = 121862337, level = 56,
  damage = { "hand-to-hand", "default" } } }
N.on_event(nil, "gmcp.Guild.Strigoi")

check(N.guildName == "Strigoi", "guild name taken from the package")
check(MudletBorders.where("nanny:guild") == "c2", "guild pane placed in c2 on first message")
local c2 = {}
for _, id in ipairs({ "nanny:guild", "nanny:channels" }) do c2[#c2 + 1] = MudletBorders.byId[id] end
check(c2[1] and c2[2] and c2[1].y < c2[2].y, "guild sits above chat in c2")
check(MudletBorders.slots["nanny:guild"].title == "Strigoi", "strip titled Strigoi")
print("  head: " .. tostring(rec.head))
check(rec.gp and rec.gp[2] == 121862337 + 19588066, "GP bar max = points + next (" .. tostring(rec.gp and rec.gp[3]) .. ")")
check(rec.pen and rec.pen[3] == "Penalty  0%", "penalty label " .. tostring(rec.pen and rec.pen[3]))
check(rec.wasp and rec.wasp[3] == "Wasp L8  120/120", "wasp label " .. tostring(rec.wasp and rec.wasp[3]))
print("  txt: " .. tostring(rec.txt))
check(rec.txt and rec.txt:find("<td>0/6 &#183;&nbsp;</td><td>empty</td>", 1, true), "stack 0/6 empty")
check(rec.txt and rec.txt:find(">Str</td><td align='right'>?</td>", 1, true), "no stat changes, no base: plain ?")
check(not rec.txt:find("#6fb8e0", 1, true), "empty temp: no harvest parenthesis")

-- a later message with penalty, a stack, a stat change, a harvest gain, wasp gone
gmcp.Guild.Strigoi = { penalty = 40, stack = { "claw", "drain" }, str = 2, con = -1,
  int = 3, wasp = { out = 0, hp = 0, maxhp = 120, level = 8 }, temp = { int = 3 } }
N.on_event(nil, "gmcp.Guild.Strigoi")
check(rec.pen[3] == "Penalty  40%" and N.gPenCol == "#b03030", "penalty 40% turns red")
check(rec.wasp[3] == "Wasp: not out", "wasp not out")
check(rec.txt:find("<td>2/6 &#183;&nbsp;</td><td>&nbsp;claw&nbsp;</td>" ..
  slot("<span style='font-size:13pt;'>🩸</span>"), 1, true),
  "stack: claw as text (no icon), drain as its icon in a slot")
gmcp.Guild.Strigoi = { stack = { "acidic touch two", "shadow leeches of essence" } }
N.on_event(nil, "gmcp.Guild.Strigoi")
check(rec.txt:find(slot("<span style='font-size:13pt;'>🧪</span>" .. sub(2)) ..
  slot("<span style='font-size:13pt;'>🪱</span>" .. sub(2)), 1, true),
  "variants sharing an icon carry their number")
-- the dark set: tinted glyphs, asking for the plain form of the skull
N.iconSet = "dark"
gmcp.Guild.Strigoi = { stack = { "skullburst", "acidic touch one" } }
N.on_event(nil, "gmcp.Guild.Strigoi")
check(rec.txt:find(slot("<span style='font-size:14pt; color:#d8cfb8;'>☠\239\184\142</span>") ..
  slot("<span style='font-size:14pt; color:#8aa83a;'>⁂\239\184\142</span>" .. sub(1)), 1, true),
  "dark set: skull in bone, acid in rot, the number kept")
N.iconSet = "emoji"
gmcp.Guild.Strigoi = { stack = { "claw", "drain" } }
N.on_event(nil, "gmcp.Guild.Strigoi")
check(rec.txt:find(">Int</td><td align='right'>? <span style='color:#6fb8e0;'>(+3)</span>", 1, true),
  "harvest-only change: no guild parenthesis, harvest in its own colour")
check(rec.txt:find("? <span style='color:#70c070;'>(+2)</span>", 1, true), "no base stats yet: ? and the change")

-- base stats arrive: totals with the guild's change in parentheses, and the pane refreshes
gmcp.Char = { Status = { str = 20, con = 20, int = 18, dex = 20 } }
N.on_event(nil, "gmcp.Char.Status")
check(rec.txt:find("22 <span style='color:#70c070;'>(+2)</span>", 1, true)
  and rec.txt:find("19 <span style='color:#d06060;'>(-1)</span>", 1, true)
  and rec.txt:find(">Int</td><td align='right'>21 <span style='color:#6fb8e0;'>(+3)</span>", 1, true),
  "totals: base + change")

-- the live shape: int 9 of which 3 from harvest -> total base+9, (+6) guild, (+3) harvest
gmcp.Guild.Strigoi = { int = 9, temp = { int = 3 } }
N.on_event(nil, "gmcp.Guild.Strigoi")
check(rec.txt:find(">Int</td><td align='right'>27 <span style='color:#70c070;'>(+6)</span> " ..
  "<span style='color:#6fb8e0;'>(+3)</span>", 1, true), "Int 27 (+6) (+3)")
check(rec.gp[3]:find("141,450,403", 1, true), "merged: GP total kept from the first message")

-- base (the level's starting GP) makes the bar fill within the level; the label stays cumulative
gmcp.Guild.Strigoi = { points = 121920430, base = 118958126, next = 7894907 }
N.on_event(nil, "gmcp.Guild.Strigoi")
check(rec.gp[1] == 121920430 - 118958126 and rec.gp[2] == 121920430 + 7894907 - 118958126,
  "GP bar fills within the level")
check(rec.gp[3] == "GP  121,920,430 / 129,815,337", "GP label cumulative " .. tostring(rec.gp[3]))

-- cooldowns: a length is learned from when a name comes and goes; the wasp and the
-- *_cast_timestamp twins are not cooldowns
local clock = 1000
getEpoch = function() return clock end
local cdRec = {}
for i = 1, 3 do
  N.gCdRows[i] = setmetatable({}, { __index = function(t, k)
    if k == "setValue" then return function(_, v, m, s) cdRec[i] = { v, m, s } end end
    if k == "front" or k == "back" or k == "text" then return any end
    return function() return t end
  end })
end
gmcp.Guild.Strigoi = { active = { "wasp", "shift", "shift_cast_timestamp" } }
N.on_event(nil, "gmcp.Guild.Strigoi")
check(N.gCdShown == 1 and cdRec[1][3] == bar("🔄", "shift  0s, learning"), "one bar, shift, learning: " .. tostring(cdRec[1][3]))
clock = 1030
gmcp.Guild.Strigoi = { active = { "wasp" } }
N.on_event(nil, "gmcp.Guild.Strigoi")
check(N.cd.learned.shift and N.cd.learned.shift[1] == 30, "shift learned as 30 s")
check(cdRec[1][3] == bar("🔄", "shift  ready") and cdRec[1][1] == 1 and cdRec[1][2] == 1, "shift ready, bar full")
clock = 2000
gmcp.Guild.Strigoi = { active = { "shift", "shift_cast_timestamp" } }
N.on_event(nil, "gmcp.Guild.Strigoi")
clock = 2010
N.draw_cooldowns()
check(cdRec[1][3] == bar("🔄", "shift  20s") and cdRec[1][1] == 10 and cdRec[1][2] == 30, "ten seconds in: 20s left, bar a third full")
gmcp.Guild.Strigoi = { active = {} }
N.on_event(nil, "gmcp.Guild.Strigoi")
-- running before the session's first message: its start is unknown, so nothing is learned
N.cd.primed = false
clock = 3000
gmcp.Guild.Strigoi = { active = { "neutrino" } }
N.on_event(nil, "gmcp.Guild.Strigoi")
clock = 3005
gmcp.Guild.Strigoi = { active = {} }
N.on_event(nil, "gmcp.Guild.Strigoi")
check(N.cd.learned.neutrino == nil and N.gCdShown == 1, "a cooldown already running at the start teaches nothing")
check(#N.cd.learned.shift == 2 and N.cd.learned.shift[2] == 10, "second timing of shift kept: 10 s")
gmcp.Guild.Strigoi = { active = { "purge_of_flesh", "shadow_curse" } }
N.on_event(nil, "gmcp.Guild.Strigoi")
check(cdRec[1][3] == bar("🍖", "purge of flesh  0s, learning")
  and cdRec[2][3] == bar("🪱", "shadow curse  0s, learning"),
  "an icon found by the first word: purge, shadow")
N.iconSet = "dark"
N.draw_cooldowns()
check(cdRec[1][3] == bar("<span style='color:#d8cfb8;'>∅\239\184\142</span>", "purge of flesh  0s, learning"),
  "dark set on a bar: the glyph in bone " .. tostring(cdRec[1][3]))
N.iconSet = "emoji"
gmcp.Guild.Strigoi = { active = {} }
N.on_event(nil, "gmcp.Guild.Strigoi")

-- a squeezed pane must not draw past its box: rows that do not fit are hidden
local function tracker()
  local o = { hidden = false, y = 0, h = 0 }
  function o:show() o.hidden = false end
  function o:hide() o.hidden = true end
  function o:move(_, y) o.y = y end
  function o:resize(_, h) o.h = h end
  return o
end
N.gHead, N.gGp, N.gPen, N.gWasp, N.gTxt = tracker(), tracker(), tracker(), tracker(), tracker()
local fit = N.comps.guild.fit
fit(400, 70)                                   -- room for about three gauge rows only
local spill = false
for _, w in ipairs({ N.gHead, N.gGp, N.gPen, N.gWasp, N.gTxt }) do
  if not w.hidden and w.y + w.h > 70 then spill = true end
end
check(not spill, "squeezed guild pane: nothing visible crosses its bottom edge")
check(N.gWasp.hidden and N.gTxt.hidden, "rows that do not fit are hidden")
fit(400, 400)
check(not N.gWasp.hidden and not N.gTxt.hidden and N.gTxt.y + N.gTxt.h == 400, "given room again, all rows return and text fills to the bottom")

-- soultick as the game shows it: total, per beat, per combat beat (rounded down)
N.gHead, N.gGp, N.gPen, N.gWasp, N.gTxt = recorder("head"), recorder("gp"), recorder("pen"), recorder("wasp"), recorder("txt")
gmcp.Guild.Strigoi = { soultick = { guild_points = 89472, hb = 3728, combat_hb = 360 } }
N.on_event(nil, "gmcp.Guild.Strigoi")
check(rec.txt:find("89,472 gp &#183; 24 per beat &#183; 248 per combat beat", 1, true),
  "soultick per beat and per combat beat")
gmcp.Guild.Strigoi = { soultick = { guild_points = 0, hb = 0, combat_hb = 0 } }
N.on_event(nil, "gmcp.Guild.Strigoi")
check(rec.txt:find(">Soultick</td><td>0 gp</td>", 1, true), "no beats yet: total only, no division by zero")

-- the score card: paragon level from (exp + needexp - baseexp), the live payload of plvl 20
N.stTitle, N.stXp, N.stTxt = recorder("stTitle"), recorder("stXp"), recorder("stTxt")
N.status({ level = 19, exp = 16007908, baseexp = 431524, needexp = 5423616, name = "Testchar",
  guild = "Strigoi", race = "human", gold = 1, qp = 1 })
check(rec.stTitle:find("Level 19 &#183; Paragon 20 &#183;", 1, true), "paragon 20 on the subtitle")
check(rec.stXp[1] == 16007908 - 431524 and rec.stXp[2] == 21000000
  and rec.stXp[3] == "Paragon  15,576,384 / 21,000,000", "paragon bar " .. tostring(rec.stXp[3]))
check(not rec.stTxt:find(">NP<", 1, true), "no NP row")
N.status({ level = 12, exp = 50000, baseexp = 40000, needexp = 10000 })
check(not rec.stTitle:find("Paragon", 1, true) and rec.stXp[3] == "XP  50,000 / 60,000", "below 19: no paragon")

-- the druid pane, from live payloads: a pet, fireflies on, barkskin on
N.gHead, N.gGp, N.gPen, N.gWasp, N.gTxt = recorder("head"), recorder("gp"), recorder("pen"), recorder("wasp"), recorder("txt")
local petRec = {}
N.gPetRows[1] = setmetatable({}, { __index = function(t, k)
  if k == "setValue" then return function(_, v, m, s) petRec = { v, m, s } end end
  return function() return t end
end })
local barkRec = {}
N.gBark = setmetatable({}, { __index = function(t, k)
  if k == "setValue" then return function(_, v, m, s) barkRec = { v, m, s } end end
  if k == "front" or k == "back" or k == "text" then return any end
  return function() return t end
end })
gmcp.Guild.Druid = { harmony = 0, arch = 0, tree = "Willow", staff = { fireflies = 1, wielded = 0, held = 1 },
  pets = { { here = 1, hp = 100, name = "Squirrel" } }, pets_max = 1, effects = {},
  barkskin = { on = 1, shimmering = 0 }, points = 30060, level = 5, wand = { held = 0 } }
N.on_event(nil, "gmcp.Guild.Druid")
check(N.guildName == "Druid" and MudletBorders.slots["nanny:guild"].title == "Druid", "pane retitled Druid")
check(rec.head:find("<b>Level 5</b> &#183; Willow", 1, true), "druid header: level and tree")
check(rec.txt:find("color:#555555;'>arch", 1, true), "arch dim while you are not the arch druid")
check(rec.txt:find(">Points</td><td>30,060</td>", 1, true), "points, no bar")
check(rec.txt:find("color:#70c070; font-weight:bold;'>fireflies", 1, true)
  and rec.txt:find("color:#555555;'>harmony", 1, true), "fireflies lit, harmony dim")
check(not rec.txt:find(">barkskin", 1, true), "barkskin is a bar now, not a tag")
check(barkRec[3] == "barkskin  on" and N.gBark.cdCol == "#4f7f3f",
  "barkskin already on at the first message: on, no time " .. tostring(barkRec[3]))
check(rec.txt:find(">staff</span>", 1, true) and rec.txt:find(">no wand</span>", 1, true), "gear: staff, no wand")
check(rec.txt:find(">Pets</td><td>1/1</td>", 1, true), "pets 1/1")
check(petRec[3] == "Squirrel  100%", "pet gauge " .. tostring(petRec[3]))
check(not rec.txt:find("Effects", 1, true), "no effects row while there are none")
gmcp.Guild.Druid = { arch = 1, barkskin = { on = 1, shimmering = 1 }, pets = { { here = 0, hp = 40, name = "Squirrel" } },
  effects = { "arch_druid" } }
N.on_event(nil, "gmcp.Guild.Druid")
check(rec.txt:find("color:#70c070; font-weight:bold;'>arch", 1, true), "arch lit among the buffs")
check(not rec.txt:find("Effects", 1, true), "arch_druid not repeated under Effects")
gmcp.Guild.Druid = { effects = { "arch_druid", "entangle" } }
N.on_event(nil, "gmcp.Guild.Druid")
check(rec.txt:find(">Effects</td><td>entangle</td>", 1, true), "other effects still listed")
check(N.gBark.cdCol == "#b07a20", "shimmering barkskin turns the bar amber")
-- barkskin's length is learned from on to off, then the bar empties as it wears off
clock = 5000
gmcp.Guild.Druid = { barkskin = { on = 0, shimmering = 0 } }
N.on_event(nil, "gmcp.Guild.Druid")
check(barkRec[3] == "barkskin  off" and N.buffs.learned.barkskin == nil, "off; a start not seen taught nothing")
gmcp.Guild.Druid = { barkskin = { on = 1, shimmering = 0 } }
N.on_event(nil, "gmcp.Guild.Druid")
clock = 5010
N.draw_bark()
check(barkRec[3] == "barkskin  10s, learning", "a start seen: counts up " .. tostring(barkRec[3]))
clock = 5090
gmcp.Guild.Druid = { barkskin = { on = 0, shimmering = 0 } }
N.on_event(nil, "gmcp.Guild.Druid")
check(N.buffs.learned.barkskin and N.buffs.learned.barkskin[1] == 90, "barkskin learned as 90 s")
clock = 6000
gmcp.Guild.Druid = { barkskin = { on = 1, shimmering = 0 } }
N.on_event(nil, "gmcp.Guild.Druid")
clock = 6030
N.draw_bark()
check(barkRec[3] == "barkskin  60s" and barkRec[1] == 60 and barkRec[2] == 90, "30 s in: 60 s left, bar two thirds")
check(N.cd.learned.barkskin == nil, "buffs and cooldowns are kept apart")
check(petRec[3] == "Squirrel  40%  (away)", "pet away " .. tostring(petRec[3]))
-- the alchemy pane, from the live payload with the golem and the pelican called out
local petRec2 = {}
N.gPetRows[2] = setmetatable({}, { __index = function(t, k)
  if k == "setValue" then return function(_, v, m, s) petRec2 = { v, m, s } end end
  return function() return t end
end })
local out = { follow = 1, hp = 100, state = "out", foe = "", fighting = 0, here = 1, guiding = 0, camp = 0, chore = "" }
gmcp.Guild.Alchemy = { materials = { earth = 2056, wind = 2087, mercury = 0, water = 1290, metal = 633 },
  concoction_slots = { max = 42, held = 1 }, concoctions = { nigredo = 1 }, slots = { max = 3, out = 2 },
  minions = { golem = out, pelican = out, clockwork = { hp = 100, state = "packed" },
    mandrake = { state = "none" }, ouroboros = { hp = 100, state = "packed" },
    camel = { hp = 100, state = "packed" }, homunculus = { hp = 100, state = "packed" } } }
N.on_event(nil, "gmcp.Guild.Alchemy")
check(N.guildName == "Alchemy" and MudletBorders.slots["nanny:guild"].title == "Alchemy", "pane retitled Alchemy")
check(rec.head:find("Slots 2/3</b> &#183; Held 1/42", 1, true), "alchemy header " .. tostring(rec.head))
check(petRec[3] == "Golem  100%" and petRec2[3] == "Pelican  100%", "golem and pelican bars, in name order")
check(rec.txt:find(">Earth</td><td align='right'>2,056</td>", 1, true)
  and rec.txt:find(">Mercury</td><td align='right'>0</td>", 1, true), "materials grid")
check(rec.txt:find(">Concoctions</td><td>nigredo &#215;1</td>", 1, true), "concoctions with counts")
check(rec.txt:find(">Packed</td><td>camel</td><td align='right' style='color:#dddddd;'>100%</td>" ..
  "<td width='16'></td><td>clockwork</td>", 1, true) and rec.txt:find("<td>ouroboros</td>", 1, true),
  "packed minions two to a line, with HP")
local _, lines = rec.txt:gsub("<tr>", "")
check(lines == 3 + 1 + 2, "four packed minions take two lines (" .. lines .. " rows in all)")
check(not rec.txt:find("mandrake", 1, true), "the mandrake (none) is not listed")
gmcp.Guild.Alchemy = { minions = { camel = { hp = 30, state = "packed" }, clockwork = { hp = 60, state = "packed" } } }
N.on_event(nil, "gmcp.Guild.Alchemy")
check(rec.txt:find("<td>camel</td><td align='right' style='color:#d06060;'>30%</td>", 1, true)
  and rec.txt:find("<td>clockwork</td><td align='right' style='color:#e0a030;'>60%</td>", 1, true),
  "a hurt packed minion stands out: red below 40%, amber below 75%")
gmcp.Guild.Alchemy = { minions = { golem = { follow = 0, hp = 60, state = "out", foe = "a rat", fighting = 1, here = 0 } } }
N.on_event(nil, "gmcp.Guild.Alchemy")
check(petRec[3] == "Golem  60%  fighting a rat  (away)  (staying)", "golem fighting, away, staying: " .. tostring(petRec[3]))

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
