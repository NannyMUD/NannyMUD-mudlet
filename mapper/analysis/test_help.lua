-- maphelp: one lookup (exact command in full, else a search) and the README kept in step.
-- Run: luajit analysis/test_help.lua      (from the client dir)

elro = {}
dofile("lua/help.lua")
local H = elro.HELP

local fail, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    fail = fail + 1
    print(string.format("FAIL %-56s got %s want %s", what, tostring(got), tostring(want)))
  end
end

eq(H.lookup("").kind, "list", "bare: the everyday list")
eq(H.lookup("advanced").advanced, true, "'advanced': the rest")
eq(H.lookup("share").kind, "page", "a page by name")
eq(H.lookup("shar").page, H.pages.share, "...or the start of its name")
local r = H.lookup("mapcoins")
eq(r.kind == "detail" and #r.rows == 1 and r.rows[1][1]:match("^mapcoins") ~= nil, true, "an exact command: its full text")
r = H.lookup("mapterrain")
eq(r.kind == "detail" and #r.rows == 2, true, "...every row of that command")
r = H.lookup("mapreturn")
eq(r.kind == "detail" and r.rows[1][1]:match("^mapmark") ~= nil, true, "a word a row answers to counts as exact")
r = H.lookup("MapCoins")
eq(r.kind, "detail", "any case")
r = H.lookup("speedwalk")
eq(r.kind, "found", "any other word: a search")
local names = {}
for _, row in ipairs(r.rows or {}) do names[row[1]:match("^%S+")] = true end
eq(names.mapavoid and names.mapgoto, true, "...through the full texts")
r = H.lookup("double-click")
eq(r.kind == "found" and r.pages[1], "mouse", "...and the pages")
eq(H.lookup("xyzzy").kind, "none", "nothing found says so")

-- every row has a command, a summary and something to show in full
for _, row in ipairs(H.all_rows()) do
  if type(row[1]) ~= "string" or type(row[2]) ~= "string" or #row[2] > 70 then
    eq(row[1], "a row with a summary of at most 70 characters", "row shape")
  end
end

-- the README's reference is written from these tables
M_HELP_MD_LIB = true
local md = dofile("tools/help_md.lua")
local f = assert(io.open("README.md", "rb"))
local readme = f:read("*a"):gsub("\r\n", "\n") ; f:close()
eq(md.spliced(readme), readme, "README.md matches lua/help.lua (run luajit tools/help_md.lua)")

print(string.format("test_help: %d check(s), %d failure(s)", checks, fail))
os.exit(fail == 0 and 0 or 1)
