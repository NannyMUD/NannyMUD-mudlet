-- The Tome card against stubbed Mudlet globals: the stored spell and what each bar learns.
--   luajit basics/tests/test_tome.lua
local any ; any = setmetatable({}, { __index = function() return any end, __call = function() return any end })
setmetatable(_G, { __index = function(_, k) return function() return any end end })
Geyser = any
gmcp = {}
NannyBasics, MudletBorders = {}, {}
function getMainWindowSize() return 2560, 1143 end
function getMudletHomeDir() return "." end
function calcFontSize() return 8, 15 end
function getMousePosition() return nil end
yajl = { to_string = function() return "{...}" end }

local clock = 1000
function getEpoch() return clock end
function tempRegexTrigger() return 1 end
function killTrigger() end

local HERE = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "../"
dofile(HERE .. "border.lua")
dofile(HERE .. "nannybasics.lua")
local N = NannyBasics
local T = N.tome

local fails = 0
local function check(ok, msg) print((ok and "ok   " or "FAIL ") .. msg) ; if not ok then fails = fails + 1 end end

local MAGIC = "You feel the magic power surrounds you as you chant"
local TIRED = "You feel mentally exhausted, and fail to memorize"
local LOOSE = "You point at yourself and turn the powers loose."
local function chant(cmd, answer) N.tome_sent(nil, cmd) ; N.tome_line(answer) end
local function release() N.tome_line(LOOSE) end
local function s(w) return T.spells[w] or {} end

check(not N.cd_wanted(), "nothing chanted: the card stays hidden")
N.tome_sent(nil, "chant nosuch")
check(not N.cd_wanted(), "a chant with no answer makes no bar")

clock = clock + 10
chant("chant slow", MAGIC)
check(T.stored == "slow" and T.on.slow == nil, "chant: stored, cooldown not started")
check(N.cd_wanted(), "the card appears")
clock = clock + 30
chant("chant slow", MAGIC)
check(T.on.slow == nil and s("slow").hi == nil, "overwriting teaches nothing")

release()
check(T.stored == nil and T.on.slow == clock, "release starts the cooldown and empties the store")
clock = clock + 40
chant("chant slow;pme", TIRED)
check(s("slow").lo == 40 and s("slow").hi == nil, "refused at 40 s: longer than 40")
check(T.on.slow ~= nil, "a refusal does not restart the timer")
N.tome_line("You point at yourself.")
check(T.on.slow ~= nil, "a bare point changes nothing")

clock = clock + 15
chant("chant Slow;pme", MAGIC)
check(s("slow").hi == 55 and s("slow").lo == 40, "works at 55 s: at most 55, case ignored")
check(T.on.slow == nil and T.stored == "slow", "works: stored again, timer over")

-- the bracket narrows, and a much later cast does not widen it
release()
clock = clock + 500
chant("chant slow", MAGIC)
check(s("slow").hi == 55, "a long wait does not widen the bracket")

-- a passive makes it longer
release()
clock = clock + 80
chant("chant slow", TIRED)
check(s("slow").hi == nil and s("slow").lo == 80, "refused past the limit: the limit is thrown away")

-- a passive makes it shorter
clock = clock + 5
chant("chant slow", MAGIC)
release()
clock = clock + 20
chant("chant slow", MAGIC)
check(s("slow").hi == 20 and s("slow").lo == nil, "works well under the floor: the floor is thrown away")

-- jitter does not throw a bound away
release()
clock = clock + 21
chant("chant slow", TIRED)
check(s("slow").hi == 21 and s("slow").lo == 21, "refused just past the limit: jitter, limit raised to fit")

-- answers belong to the chant that asked
release()
clock = clock + 1
N.tome_sent(nil, "chant combat")
clock = clock + 6
N.tome_line(TIRED)
check(s("slow").lo == 21, "a refusal with only a stale chant outstanding teaches nothing")

N.tome_line(MAGIC)
check(T.stored == "?", "magic line with no chant seen: stored, unnamed")
release()
check(T.stored == nil and T.spells["?"] == nil, "an unnamed release makes no bar")

N.tome_line(LOOSE)
check(T.stored == nil, "release with nothing stored does nothing")

chant("chant illusion", MAGIC)
N.tome_line("You point at Warrior and release the spell.")
check(T.stored == nil and T.on.illusion == clock, "the other release wording starts the cooldown")
T.spells.illusion, T.on.illusion = nil, nil

-- a release leaves what was learned alone, a refusal raises the floor
T.spells.slow, T.on.slow = { lo = 50, hi = 55 }, nil
chant("chant slow", MAGIC)
release()
check(s("slow").lo == 50 and s("slow").hi == 55, "release: the limits stay")
clock = clock + 52
chant("chant slow", TIRED)
check(s("slow").lo == 52, "a refusal in the maybe stretch raises the floor")

-- relearn drops the floor and keeps the limit
N.cmd("tome relearn slow")
check(s("slow").lo == nil and s("slow").hi == 55, "relearn one: floor gone, limit kept")
T.spells.combat = { lo = 10, hi = 12 }
T.spells.slow.lo = 40
N.cmd("tome relearn")
check(s("slow").lo == nil and s("combat").lo == nil and s("combat").hi == 12, "relearn all")
N.cmd("tome relearn nosuch")
check(s("combat").hi == 12, "relearn of an unknown spell changes nothing")
T.spells.combat = nil

-- limits close together are a plain countdown, far apart a maybe
local seen
N.cRows[1] = setmetatable({ cdText = false, cdCol = false, setValue = function(_, _, _, t) seen = t end }, { __index = any })
T.spells.slow, T.on.slow = { lo = 50, hi = 53 }, clock - 51
N.draw_cooldowns()
check(seen:find("slow  2s", 1, true) ~= nil, "limits within five seconds: a countdown to the upper one: " .. tostring(seen))
check(seen:find(N.TOME_DARK.slow, 1, true) ~= nil, "...with the spell's icon")
T.spells.slow, T.on.slow = { lo = 50, hi = 70 }, clock - 60
N.draw_cooldowns()
check(seen:find("slow  maybe, sure in 10s", 1, true) ~= nil, "limits far apart: maybe: " .. tostring(seen))
N.iconSet = "emoji"
N.cRows[1].cdText = false
N.draw_cooldowns()
check(seen:find(N.TOME_ICONS.slow, 1, true) ~= nil, "the emoji set too")
N.iconSet = "dark"
T.on.slow = nil

-- a bar only once the game has refused the spell
N.draw_cooldowns()
local bars = N.cdShown
chant("chant quick", MAGIC)
release()
check(N.cdShown == bars and T.on.quick ~= nil, "never refused: timed, but no bar")
clock = clock + 1
chant("chant quick", TIRED)
check(N.cdShown == bars + 1 and s("quick").lo == 1, "refused once: the bar appears, with what it timed")
T.spells.quick, T.on.quick = nil, nil

-- hide keeps what was learned, show brings the bar back
N.draw_cooldowns()
bars = N.cdShown
N.cmd("tome hide slow")
N.draw_cooldowns()
check(T.hidden.slow and T.spells.slow ~= nil and N.cdShown == bars - 1, "hide: the bar goes, what was learned stays")
N.cmd("tome show slow")
N.draw_cooldowns()
check(not T.hidden.slow and N.cdShown == bars, "show: the bar is back")

-- probe: chant a released spell every few seconds until it works, never over a stored spell
local sent, deleted = {}, 0
function send(c) sent[#sent + 1] = c ; N.tome_sent(nil, c) end
function deleteLine() deleted = deleted + 1 end
function tempTimer() return 7 end
function killTimer() end
T.spells.bolt, T.on.bolt, T.stored = nil, nil, nil
N.cmd("tome probe bolt")
N.tome_probe_tick()
check(#sent == 0, "probe: nothing chanted before the spell is released")
chant("chant bolt", MAGIC)
check(#sent == 0, "...nor while it is stored")
release()
clock = clock + 3
N.tome_probe_tick()
check(sent[1] == "chant bolt", "released: chanted")
N.tome_probe_tick()
check(#sent == 1, "...once until it is answered")
N.tome_line(TIRED)
check(deleted == 1 and s("bolt").lo == 3, "a probe's refusal is hidden and teaches")
clock = clock + 1
N.tome_probe_tick()
check(#sent == 1, "...and the next chant waits its turn")
clock = clock + 2
N.tome_probe_tick()
N.tome_line(MAGIC)
check(s("bolt").hi == 6 and T.stored == "bolt", "a chant that works: stored, bracket 3 to 6")
clock = clock + 3
N.tome_probe_tick()
check(T.probe.bolt == nil, "learned: probing stops by itself")
release()
clock = clock + 3
N.tome_probe_tick()
check(#sent == 2, "...and chants no more")
T.spells.zap = {}
N.cmd("tome probe zap")
T.on.zap = clock
clock = clock + 3
N.tome_probe_tick()
clock = clock + 6
N.tome_probe_tick()
clock = clock + 6
N.tome_probe_tick()
check(T.probe.zap == nil, "no answer twice: probing stops")
T.spells.bolt, T.on.bolt, T.spells.zap, T.on.zap, T.stored = nil, nil, nil, nil, nil

N.cmd("tome forget slow")
check(T.spells.slow == nil and T.on.slow == nil, "forget removes a bar")
check(not N.cd_wanted(), "nothing left: the card hides again")

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
