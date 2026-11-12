-- The Strigoi rotation against stubbed Mudlet globals: when powers go out, and why they stop.
--   luajit basics/tests/test_rotation.lua
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
local sent, refusedFn, deleted, nextLine = {}, nil, 0, {}
function send(c) sent[#sent + 1] = c end
function deleteLine() deleted = deleted + 1 end
function tempLineTrigger(_, _, f) nextLine[#nextLine + 1] = f end
function tempRegexTrigger(p, f)
  if p:find("cannot take hold", 1, true) then refusedFn = f end
  return 1
end
function killTrigger() end

local HERE = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "../"
dofile(HERE .. "border.lua")
dofile(HERE .. "nannybasics.lua")
local N = NannyBasics
local R = N.rot

local fails = 0
local function check(ok, msg) print((ok and "ok   " or "FAIL ") .. msg) ; if not ok then fails = fails + 1 end end

local stack = { "a", "b", "c" }
local function guild(s) gmcp.Guild = { Strigoi = { stack = s or stack } } ; N.on_event(nil, "gmcp.Guild.Strigoi") end
local function foe(name) gmcp.Char = gmcp.Char or {} ; gmcp.Char.Foe = name and { name = name } or {} ; N.on_event(nil, "gmcp.Char.Foe") end
local function push(x) table.remove(stack, 1) ; stack[#stack + 1] = x ; guild() end
local function refuse(text, tail)
  line = text .. (tail or "")
  matches = { text, text }
  refusedFn()
end
local function last() return sent[#sent] end
local TOOSOON = "Something far powerful than you won't allow that so fast."
local COOL = "The power cannot take hold again while"
local LOW = "You are mentally weak to do that."

guild()
foe("the dragoon")
check(#sent == 0, "no rotation set: nothing sent")
N.cmd("rot set burn umbra, embrace , wildbound ghostveil")
check(R.saved.current == "burn" and #R.saved.variants.burn == 3, "set: comma list, spaces trimmed, picked")
N.cmd("rot set embrace, umbra, wither")
check(R.saved.variants["embrace,"] == nil and R.saved.current == "burn", "set: a first command taken for the name is refused")
guild()
check(#sent == 0, "mode off: nothing sent")

N.cmd("rot auto")
check(last() == "umbra" and #sent == 1, "auto with a foe: first power goes out")
guild()
check(#sent == 1, "waits: a message with no change sends nothing")
push("umbra")
check(last() == "embrace" and #sent == 2, "lands: next power")
guild() ; guild()
check(#sent == 2, "two silent messages: still waiting, it may be landing")
push("embrace")
check(last() == "wildbound ghostveil", "a lagging landing still counts")
push("extra combat damage")
check(#sent == 3, "an entry that is not this power does not count")
push("wildbound ghostveil")
check(last() == "umbra" and #sent == 4, "the list wraps")

-- several pushes in one message, the power not newest
table.remove(stack, 1) ; stack[#stack + 1] = "umbra"
table.remove(stack, 1) ; stack[#stack + 1] = "extra combat damage"
guild()
check(last() == "embrace", "landed though something else was pushed after it")

-- a short rotation: the power is already in the stack from last time
N.cmd("rot set two umbra, embrace")
stack = { "umbra", "embrace", "umbra", "embrace", "umbra", "embrace" }
guild()
check(R.pending and R.pending.cmd == "umbra", "new variant starts at the top")
local n = #sent
guild()
check(#sent == n, "already in the stack is not a landing")
push("umbra")
check(last() == "embrace", "a new push of it is")

-- no reply: gives up after three messages, says so
local p = R.pending.cmd
n = #sent
guild() ; guild()
check(#sent == n, "two messages: not given up")
guild()
check(#sent == n + 1 and last() ~= p and R.note == "no reply: " .. p, "third: moved on and noted")
push(last())
check(R.note == nil, "a landing clears the note")

-- refusals: move on at once and hide, wrapped lines too
N.cmd("rot set burn umbra, embrace, wither")
guild()
check(last() == "umbra", "fresh variant")
deleted, nextLine = 0, {}
refuse(COOL, " they are still suffering or recovering")
check(deleted == 1 and last() == "embrace", "cooldown: hidden, next power now")
local f = table.remove(nextLine, 1)
line = "from its effects."
f()
check(deleted == 2 and #nextLine == 1, "the wrapped rest is hidden too")
f = table.remove(nextLine, 1)
line = "> "
f()
check(deleted == 3, "then a bare prompt")
deleted, nextLine = 0, {}
refuse(LOW)
check(deleted == 1 and last() == "wither" and #nextLine == 1, "no SP: hidden, next power")
line = "> The dragoon hits you."
nextLine[1]()
check(deleted == 1, "a prompt with text on it is kept")
nextLine = {}

-- a whole list refused: pause, then start again
n = #sent
refuse(COOL)
check(#sent == n and R.holdUntil == clock + 1, "whole list refused: pauses")
guild()
check(#sent == n, "no send during the pause")
clock = clock + 1.5
N.rot_tick()
check(#sent == n + 1 and R.holdUntil == nil, "pause over: goes again")

-- too soon: same power at the next message
local cmd = R.pending.cmd
refuse(TOOSOON)
n = #sent
check(R.pending == nil and R.soon == 1, "too soon: waits")
clock = clock + 0.5
N.rot_tick()
check(#sent == n, "the second timer does not retry it")
guild()
check(#sent == n + 1 and last() == cmd, "next message: the same power")
refuse(TOOSOON)
guild()
check(last() == cmd, "second retry, same power")
stack[#stack] = "zzz" ; stack[1] = cmd
push(cmd)

-- a room without magic: too soon on everything ends blocked, visibly
check(R.soon == 0 and R.blocked == nil, "landing resets the count")
cmd = R.pending.cmd
refuse(TOOSOON) ; guild() ; refuse(TOOSOON) ; guild()
check(last() == cmd, "up to the limit on one power")
n = #sent
refuse(TOOSOON)
check(#sent == n + 1 and last() ~= cmd and last() ~= R.last, "limit reached: moves on at once, not to the last power")
deleted = 0
refuse(TOOSOON)
check(deleted == 1 and R.blocked == TOOSOON and R.holdUntil == clock + 10, "whole list but the last power: blocked for 10 s")
n = #sent
guild()
check(#sent == n, "blocked: no sends")
clock = clock + 11
N.rot_tick()
check(#sent == n + 1, "blocked: one probe after the wait")
deleted, nextLine = 0, {}
refuse(TOOSOON)
check(deleted == 0 and R.holdUntil == clock + 10, "blocked: the line is no longer hidden, wait again")
foe("the guard")
check(R.blocked == nil and #sent == n + 2, "a new foe lifts the block")

-- the player spamming a power by hand: refusals right after typing are not the helper's
local waiting = R.pending
n, deleted = #sent, 0
N.rot_sent("sysDataSendRequest", "shadow leeches of soul\n")
refuse(TOOSOON)
check(R.pending == waiting and R.soon == 0 and deleted == 0, "too soon just after typing: answers the player, shown")
guild()
check(#sent == n, "...and the power out is not sent again")
clock = clock + 2
N.rot_sent("sysDataSendRequest", waiting.cmd .. "\n")
refuse(TOOSOON)
check(R.pending == nil and R.soon == 1 and deleted == 1, "its own send is not typing: a refusal counts again")

-- no foe stops it
foe(nil)
check(R.pending == nil and R.foe == nil, "fight over: nothing waiting")
n = #sent
guild()
check(#sent == n, "no foe: nothing sent")
refuse(COOL)
check(#sent == n, "a refusal of a hand-typed command changes nothing")
deleted = 0
refuse(COOL)
check(deleted == 0, "...and is not hidden")

-- out of SP: the one power that costs none must not be sent over and over
N.cmd("rot set sp umbra, skullburst, embrace")
foe("the guard")
check(last() == "umbra", "out of SP: starts at the top")
refuse(LOW)
check(last() == "skullburst", "refused for SP: on to the one that needs none")
push("skullburst")
check(last() == "embrace", "it lands, next power")
refuse(LOW)
check(last() == "umbra", "refused, the next")
n = #sent
refuse(LOW)
check(#sent == n and R.holdUntil == clock + 1, "the rest refused: pauses, skullburst not sent again")
clock = clock + 1.5
N.rot_tick()
check(last() == "embrace" and #sent == n + 1, "after the pause: skipped again")
refuse(LOW) ; refuse(LOW)
check(last() == "umbra", "still only the others")
clock = clock + 1.5
N.rot_tick()
push("embrace")
check(last() == "umbra", "SP back: the list goes on")
push("umbra")
check(last() == "skullburst", "others landed: it may go again")
-- it kills the foe before the stack shows it
foe(nil)
check(R.pending == nil and R.last == "skullburst", "fight over with it out: counted as used")
foe("the next guard")
check(last() == "embrace", "the next fight does not start with it again")
foe(nil)
N.cmd("rot del sp")

-- an opener: first in each fight unless the stack holds it, without moving the list
N.cmd("rot set op embrace, umbra, wither")
N.cmd("rot open wither")
check(R.saved.openers.op == "wither", "opener saved for the rotation picked")
stack = { "a", "b", "c" }
guild()
foe("the rat")
check(last() == "wither", "new fight: the opener first")
push("wither")
check(last() == "embrace", "lands: the list from where it was")
push("embrace")
check(last() == "umbra", "and on")
push("umbra")
check(last() == "wither" and not R.pending.opener, "the list's own turn for it still comes round")
foe(nil)
foe("the bat")
check(last() ~= "wither", "wither in the stack: no opener")
stack = { "x", "y", "z" }
guild()
foe(nil)
foe("the owl")
check(last() == "wither", "out of the stack: the opener again")
n = #sent
local place = R.i
refuse(COOL)
check(#sent == n + 1 and last() ~= "wither" and R.i == place, "refused: dropped, the list goes on from its place")
foe(nil)
foe("the fox")
check(last() == "wither", "next fight")
refuse(TOOSOON)
n = #sent
guild()
check(#sent == n + 1 and last() == "wither", "too soon: tried again at the next message")
refuse(TOOSOON)
guild()
check(last() == "wither", "and once more")
n = #sent
refuse(TOOSOON)
check(#sent == n + 1 and not R.pending.opener, "the limit: dropped, the list goes on")
foe("the wolf")
check(R.opening == true, "another foe mid-fight asks for the opener once free")
foe(nil)
N.cmd("rot open off")
check(R.saved.openers.op == nil, "opener off")
foe("the cat")
check(R.pending and not R.pending.opener, "no opener any more")
foe(nil)
N.cmd("rot del op")

-- key mode
N.cmd("rot key")
foe("the guard")
n = #sent
guild()
check(#sent == n, "key: nothing on its own")
N.cmd("rot go")
check(#sent == n + 1, "key: one per press")
N.cmd("rot go")
check(#sent == n + 1, "key: not while one is waiting")
push(R.pending.cmd)
check(#sent == n + 1, "key: a landing does not send the next")
N.cmd("rot go")
check(#sent == n + 2, "key: the next press does")
refuse(COOL)
check(#sent == n + 3, "key: a refusal walks on within the same press")

-- the trace prints on every path without getting in the way
N.cmd("rot trace")
check(R.trace == true, "trace on")
local waited = R.pending
guild()
refuse(COOL)
N.cmd("rot trace")
check(R.trace == false and R.pending ~= waited, "trace off, and the rotation ran through it")

-- the strip
N.rot_click({ button = "LeftButton" })
check(R.saved.mode == "auto" and R.pending ~= nil, "left click: key to auto, and it starts")
N.rot_click({ button = "LeftButton" })
check(R.saved.mode == "off" and R.pending == nil, "left click: auto to off, nothing waiting")
N.rot_click({ button = "RightButton" })
check(R.saved.current == "two", "right click: the next variant")
N.cmd("rot del two")
check(R.saved.current == "burn" and R.saved.variants.two == nil, "deleting the current one picks another")
N.cmd("rot del burn")
check(R.saved.current == nil and next(R.saved.variants) == nil, "deleted the last: none left")
N.cmd("rot auto")
guild()
check(R.pending == nil, "auto with no rotation: nothing")

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
