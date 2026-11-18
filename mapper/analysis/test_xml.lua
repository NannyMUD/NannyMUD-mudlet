-- xmlcore: proven tags cut, each class's text told to listeners, lines handed on once cut.
-- The colours are NannyBasics' (basics/tests/test_xmlcolours.lua).
-- Run: luajit analysis/test_xml.lua      (from the client dir)
dofile("analysis/engine_load.lua")
local X = NannyXml

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

-- nested: the outer class first
_, _, sp = X.plan("<long>A hall. <misc_in_long>A sword</misc_in_long> lies here.</long>")
eq(sp[1][3] == "long" and sp[2][3] == "misc_in_long", true, "outer class first, inner after")
eq(sp[2][1] == 8 and sp[2][2] == 7, true, "...the inner span on the cut line")

-- a class open across lines: the middle line has no tag but is a span all the same
_, _, sp = X.plan("<long>A long hall")
eq(#X.stack == 1 and X.stack[1] == "long", true, "an open class is carried to the next line")
_, _, sp = X.plan("with pillars on both sides")
eq(span(sp, "long") and span(sp, "long")[2], 26, "a line inside it is a span whole")
_, _, sp = X.plan("and a door.</long> Hm.")
eq(span(sp, "long") and span(sp, "long")[2], 11, "the close ends it mid-line")
eq(#X.stack, 0, "...and nothing is open after")

-- game text with angle brackets is not a class
_, _, sp = X.plan("give <item> to <player>")
eq(#sp, 0, "no proven pair: no span")
X.open = {}

-- whole elements come back with their attributes
local _, empty, _, _, wholes = X.plan('<sound class="combat/default/hit_3*" kind="sound"/>')
eq(empty and wholes[1][1] == "sound" and wholes[1][2]:find("hit_3", 1, true) ~= nil, true,
   "a sound tag: the line is empty, the tag handed on with its attributes")

-- strip: listeners hear each class, line readers get the line, an empty line goes
local heard, lines, deleted = {}, {}, 0
X.listen("t", function(class, text) heard[#heard + 1] = class .. ":" .. text end)
X.on_line("t", function(info) lines[#lines + 1] = info end)
selectSection = function() return true end
replace = function() end
deselect = function() end
deleteLine = function() deleted = deleted + 1 end
line = "<monster>A troll.</monster>" ; X.strip()
eq(heard[1], "monster:A troll.", "a listener hears the class and its text")
eq(#lines == 1 and lines[1].text, "A troll.", "a line reader gets the line once cut")
line = '<sound class="miss"/>' ; X.strip()
eq(deleted, 1, "a line left blank is deleted")
line = "no tags here" ; X.strip()
eq(#lines, 2, "an untagged line outside any class is left alone")
X.listen("t", nil) ; X.on_line("t", nil)

print(string.format("test_xml: %d check(s), %d failure(s)", checks, fail))
os.exit(fail > 0 and 1 or 0)
