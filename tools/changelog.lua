-- Writes CHANGELOG.md from the two packages' change tables (mapper/lua/changes.lua and
-- basics/changes.lua), which 'maphelp news' and 'nanny news' show in the game.
-- Run from the repo root:  luajit tools/changelog.lua        ('check' compares instead)

elro, NannyBasics = {}, {}
dofile("mapper/lua/changes.lua")
dofile("basics/changes.lua")
local PACKAGES = { { "Mapper", elro.CHANGES }, { "NannyBasics", NannyBasics.CHANGES } }

-- every version either package has, unreleased first, then newest first
local function key(v)
  if v == "next" then return { math.huge } end
  local t = {}
  for n in v:gmatch("%d+") do t[#t + 1] = tonumber(n) end
  return t
end
local function newer(a, b)
  local x, y = key(a), key(b)
  for i = 1, math.max(#x, #y) do
    if (x[i] or 0) ~= (y[i] or 0) then return (x[i] or 0) > (y[i] or 0) end
  end
  return false
end
local versions, seen, dates = {}, {}, {}
for _, p in ipairs(PACKAGES) do
  for _, c in ipairs(p[2]) do
    if not seen[c.version] then seen[c.version] = true ; versions[#versions + 1] = c.version end
    dates[c.version] = dates[c.version] or c.date
  end
end
table.sort(versions, newer)

local out = { "# Changelog", "",
  "What changed in each release of the mapper (ElrohirMapper) and NannyBasics. In the game,",
  "'maphelp news' and 'nanny news' show the same. Written by tools/changelog.lua from",
  "mapper/lua/changes.lua and basics/changes.lua: edit there.", "" }
for _, v in ipairs(versions) do
  out[#out + 1] = "## " .. (v == "next" and "Not released yet" or (v .. (dates[v] and (" (" .. dates[v] .. ")") or "")))
  out[#out + 1] = ""
  for _, p in ipairs(PACKAGES) do
    for _, c in ipairs(p[2]) do
      if c.version == v then
        out[#out + 1] = "### " .. p[1]
        out[#out + 1] = ""
        for _, it in ipairs(c.items) do
          out[#out + 1] = "- " .. it[1] .. (it[2] and (" (`" .. it[2] .. "`)") or "")
        end
        out[#out + 1] = ""
      end
    end
  end
end
local text = table.concat(out, "\n")

local f = io.open("CHANGELOG.md", "rb")
local old = f and f:read("*a") or ""
if f then f:close() end
if arg[1] == "check" then
  if old:gsub("\r\n", "\n") ~= text then print("changelog: CHANGELOG.md is out of date; run luajit tools/changelog.lua") os.exit(1) end
  print("changelog: CHANGELOG.md matches the change tables")
else
  f = assert(io.open("CHANGELOG.md", "wb"))
  f:write(text) ; f:close()
  print("changelog: CHANGELOG.md written")
end
