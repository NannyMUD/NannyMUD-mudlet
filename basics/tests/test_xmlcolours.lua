-- The game's colours in xml mode: classes painted in the player's colours, learned from
-- 'colour list'; a hit painted in its damage tier's colour when its sound follows.
--   luajit basics/tests/test_xmlcolours.lua
local HERE = (arg and arg[0] or ""):match("^(.-)tests[/\\][^/\\]*$") or "basics/"

local fail, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    fail = fail + 1
    print(string.format("FAIL %-56s got %s want %s", what, tostring(got), tostring(want)))
  end
end

-- a fake console: lines of { text, colour per character }
local buf, cur, sel = {}, 0, nil
local function push(s) buf[#buf + 1] = { t = s, c = {} } ; cur = #buf - 1 ; line = s end
getLineNumber = function() return cur end
moveCursor = function(x, y) cur = y ; buf[y + 1].x = x return true end
selectSection = function(a, n) sel = { cur, a, n } return true end
deselect = function() sel = nil end
resetFormat = function() end
setBold = function() end
setFgColor = function(r, g, b)
  local L = buf[sel[1] + 1]
  for i = sel[2] + 1, sel[2] + sel[3] do L.c[i] = r .. "," .. g .. "," .. b end
end
setBgColor = function() end
replace = function(s)
  local L = buf[sel[1] + 1]
  L.t = L.t:sub(1, sel[2]) .. s .. L.t:sub(sel[2] + sel[3] + 1)
end
insertText = function(s)
  local L = buf[cur + 1]
  L.t = L.t:sub(1, L.x) .. s .. L.t:sub(L.x + 1)
end
deleteLine = function() table.remove(buf, cur + 1) end
color_table = { tomato = { 255, 99, 71 } }

NannyXml, NannyBasics = nil, {}
dofile(HERE .. "xmlcore.lua")
dofile(HERE .. "xmlcolours.lua")
local C = NannyBasics.colours

-- colours: learned from 'colour list', both modes; until then the defaults
C.set = {}
eq(C.of("monster")[1], "boldred", "no colours learned: the default scheme")
eq(C.learn_line("Class: 'monster' ('monster') boldgreen"), true, "a 'colour list' line is read")
eq(C.learn_line("Class: 'say' ('<say>say</say>') yellow, background blue"), true, "...in xml mode too, with a background")
eq(C.of("monster")[1], "boldgreen", "the player's own colour")
eq(C.of("say")[2], "blue", "...and background")
eq(C.of("exit"), nil, "once learned, a class the player has not set stays plain")
local c = C.rgb("boldgreen")
eq(c and c[4], true, "bold colours are bold")
eq(C.rgb("default"), nil, "'default' leaves the colour alone")

-- a class is painted once its tags are cut
push("A <monster>troll</monster> is here.") ; NannyXml.strip()
eq(buf[1].t, "A troll is here.", "the tags are cut")
eq(buf[1].c[3] ~= nil and buf[1].c[1] == nil, true, "the monster's name is painted, the rest not")

-- hits by tier: off by default, so the player's own attack colour stands
C.set, C.opts = { attack = { "red" } }, {}
push("<attack>You hit the troll.</attack>") ; NannyXml.strip()
push('<sound class="combat/default/hit_7*"/>') ; NannyXml.strip()
eq(buf[#buf].t, "You hit the troll.", "hits off by default: no tier")
buf = {}
cecho = function() end
C.cmd("hits on")
eq(C.opt("hits"), true, "nanny xml hits on")
-- on: the sound after the hit paints it and puts the tier in front
push("<attack>You hit the troll very hard.</attack>") ; NannyXml.strip()
push('<sound class="combat/default/hit_7*" kind="sound"/>') ; NannyXml.strip()
eq(#buf, 1, "the sound's own line goes")
eq(buf[1].t, "7: You hit the troll very hard.", "the hit gets its tier in front")
eq(buf[1].c[10], "255,99,71", "...and tier 7's colour")
push("<attack>You miss.</attack>") ; NannyXml.strip()
push('<sound class="combat/default/miss*"/>') ; NannyXml.strip()
eq(buf[2].t, "You miss.", "a miss: no tier")

-- the game's switch: 'toggle xml on', and off by going back to the game's colours
local sent = {}
send = function(s) sent[#sent + 1] = s end
tempTimer = function() end
NannyXml.state = nil
C.cmd("on")
eq(sent[1], "toggle xml on", "nanny xml on: the game is asked")
NannyXml.answer("xml mode turned on.")
eq(NannyXml.state, true, "...and now it is on")
eq(sent[2], "colour list", "xml coming on reads the player's colours")
eq(C.quiet, true, "...quietly")
C.learn_line("Class: 'tell' ('<tell>tell</tell>') boldcyan")
C.quiet_end()
eq(C.of("tell")[1] == "boldcyan" and C.of("attack") == nil, true, "a fresh list replaces the old one")
C.ask_colours() ; C.quiet_end()
eq(C.of("monster"), nil, "an empty list: the player sees no colours, so nothing is painted")
C.cmd("defaults on")
eq(C.of("monster")[1], "boldred", "'nanny xml defaults on': the defaults all the same")
C.cmd("defaults off")
eq(C.of("monster"), nil, "...and off again")
eq(#sent, 3, "...no more toggles sent")
C.cmd("on")
eq(#sent, 3, "already on: nothing sent")
C.cmd("off")
eq(sent[4], "toggle ansi on", "nanny xml off: back to the game's colours, not to plain text")
NannyXml.answer("Ansi mode turned on.")
eq(NannyXml.state, false, "...and xml mode is known to be off")
-- a player who wants plain text says so once
NannyXml.state = true
C.cmd("off plain")
eq(sent[#sent], "toggle xml off", "nanny xml off plain: plain text, no colours")
NannyXml.answer("xml mode turned off.")
NannyXml.state = true
C.cmd("off")
eq(sent[#sent], "toggle xml off", "...and remembered for the next 'nanny xml off'")
NannyXml.state = true
C.cmd("off ansi")
eq(sent[#sent], "toggle ansi on", "'off ansi' goes back to the game's colours")

print(string.format("test_xmlcolours: %d check(s), %d failure(s)", checks, fail))
os.exit(fail > 0 and 1 or 0)
