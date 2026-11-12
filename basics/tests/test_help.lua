-- 'nanny help': one lookup (a command in full, else a search) and the README kept in step.
--   luajit basics/tests/test_help.lua

local HERE = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "../"
M_HELP_MD_LIB = true
local md = dofile(HERE .. "help_md.lua")
local f = assert(io.open(HERE .. "README.md", "rb"))
local readme = f:read("*a"):gsub("\r\n", "\n") ; f:close()
local fresh = md.spliced(readme)            -- loads nannybasics.lua
local H = NannyBasics.HELP

local fails = 0
local function check(ok, msg) print((ok and "ok   " or "FAIL ") .. msg) ; if not ok then fails = fails + 1 end end

check(H.lookup("").kind == "list", "bare: the list")
local r = H.lookup("rot")
check(r.kind == "detail" and #r.rows == 1 and r.rows[1][1]:match("^nanny rot") ~= nil, "a command: its full text")
check(H.lookup("nanny rot").kind == "detail", "...with 'nanny' in front too")
check(H.lookup("nanny").kind == "detail", "bare 'nanny' is a command of its own")
check(H.lookup("game").kind == "page" and H.lookup("mouse").kind == "page", "the pages by name")
r = H.lookup("foe")
local hit = {}
for _, row in ipairs(r.rows or {}) do hit[row[1]:match("^nanny%s+(%a+)")] = true end
check(r.kind == "found" and hit.rot and r.pages[1] == "game", "any other word searches the rows and pages")
check(H.lookup("xyzzy").kind == "none", "nothing found says so")
for _, row in ipairs(H.all_rows()) do
  if #row[2] > 70 or not row[3] then check(false, "row shape: " .. row[1]) end
end
check(fresh == readme, "README.md matches nannybasics.lua (run luajit basics/help_md.lua)")

print(fails == 0 and "all passed" or (fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
