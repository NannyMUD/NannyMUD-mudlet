-- xml mode: tags cut, the text between painted in the class's colour, the colours learned from
-- 'colour list'. Run: luajit analysis/test_xml.lua      (from the client dir)
dofile("analysis/engine_load.lua")
local X = elro.xml

local fail, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    fail = fail + 1
    print(string.format("FAIL %-56s got %s want %s", what, tostring(got), tostring(want)))
  end
end
local function span(sps, class)
  for _, s in ipairs(sps) do if s[3] == class then return s end end
end

X.stack, X.open = {}, {}
-- "A " + "boar" + " is here." once cut
local _, _, sp = X.plan("A <monster>boar</monster> is here.")
local s = span(sp, "monster")
eq(s and s[1] == 2 and s[2] == 4, true, "a monster's name: where it stands once the tags are gone")

-- nested: the outer class first, so the inner one is painted over it
_, _, sp = X.plan("<long>A hall. <misc_in_long>A sword</misc_in_long> lies here.</long>")
eq(sp[1][3] == "long" and sp[2][3] == "misc_in_long", true, "outer class first, inner after")
eq(sp[2][1] == 8 and sp[2][2] == 7, true, "...the inner span on the cut line")

-- a class open across lines: the middle line has no tag but is painted all the same
_, _, sp = X.plan("<long>A long hall")
eq(#X.stack == 1 and X.stack[1] == "long", true, "an open class is carried to the next line")
_, _, sp = X.plan("with pillars on both sides")
eq(span(sp, "long") and span(sp, "long")[2], 26, "a line inside it is painted whole")
_, _, sp = X.plan("and a door.</long> Hm.")
eq(span(sp, "long") and span(sp, "long")[2], 11, "the close ends it mid-line")
eq(#X.stack, 0, "...and nothing is open after")

-- game text with angle brackets is not a class
_, _, sp = X.plan("give <item> to <player>")
eq(#sp, 0, "no proven pair: nothing painted")
X.open = {}

-- colours: learned from 'colour list', both modes; until then the defaults
X.colours = {}
eq(X.colour_of("monster")[1], "boldred", "no colours learned: the default scheme")
eq(X.learn_line("Class: 'monster' ('monster') boldgreen"), true, "a 'colour list' line is read")
eq(X.learn_line("Class: 'say' ('<say>say</say>') yellow, background blue"), true, "...in xml mode too, with a background")
eq(X.colour_of("monster")[1], "boldgreen", "the player's own colour")
eq(X.colour_of("say")[2], "blue", "...and background")
eq(X.colour_of("exit"), nil, "once learned, a class the player has not set stays plain")
local c = X.rgb("boldgreen")
eq(c and c[4], true, "bold colours are bold")
eq(X.rgb("default"), nil, "'default' leaves the colour alone")

print(string.format("test_xml: %d check(s), %d failure(s)", checks, fail))
os.exit(fail > 0 and 1 or 0)
