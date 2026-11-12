-- Writes the README's command reference from the help tables in nannybasics.lua, between the
-- help markers. Run:  luajit basics/help_md.lua        ('check' compares instead of writing)

local HERE = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./")
local BEGIN = "<!-- help:begin (written by help_md.lua from nannybasics.lua: edit there) -->"
local END = "<!-- help:end -->"

-- nannybasics.lua needs Mudlet; nothing it does at load matters here
local function load_help()
  if NannyBasics and NannyBasics.HELP then return NannyBasics.HELP end
  local any ; any = setmetatable({}, { __index = function() return any end, __call = function() return any end })
  setmetatable(_G, { __index = function() return function() return any end end })
  Geyser, gmcp, NannyBasics, MudletBorders = any, {}, {}, {}
  function getMainWindowSize() return 2560, 1143 end
  function getMudletHomeDir() return "." end
  function calcFontSize() return 8, 15 end
  function getMousePosition() return nil end
  yajl = { to_string = function() return "{...}" end }
  dofile(HERE .. "border.lua")
  dofile(HERE .. "nannybasics.lua")
  return NannyBasics.HELP
end

local function markdown()
  local H = load_help()
  local out = {}
  local function add(s) out[#out + 1] = s end
  add(BEGIN)
  add("## Commands") ; add("")
  add("In Mudlet, `nanny help` lists these, `nanny help <command>` shows one in full and"
      .. " `nanny help <word>` finds every entry that mentions the word.") ; add("")
  for _, s in ipairs(H.sections) do
    add("### " .. s.title) ; add("")
    for _, r in ipairs(s.rows) do add("- **`" .. r[1] .. "`** " .. r[3]) end
    add("")
  end
  for _, name in ipairs(H.page_order) do
    local p = H.pages[name]
    add("## " .. p.title) ; add("")
    for _, para in ipairs(p.paras) do
      local h, body = para:match("^(.-)|(.+)$")
      if h and p.code then add("- `" .. h .. "`: " .. body)
      elseif h then add("- **" .. h .. ".** " .. body)
      else
        if out[#out]:sub(1, 2) == "- " then add("") end
        add(para) ; add("")
      end
    end
    if out[#out] ~= "" then add("") end
  end
  add(END)
  return table.concat(out, "\n")
end

local M = {}

-- the README with its help block replaced, or nil and why
function M.spliced(readme)
  local a = readme:find(BEGIN, 1, true)
  local b = readme:find(END, 1, true)
  if not a or not b then return nil, "README.md has no help markers" end
  return readme:sub(1, a - 1) .. markdown() .. readme:sub(b + #END)
end

if not M_HELP_MD_LIB then
  local path = HERE .. "README.md"
  local f = assert(io.open(path, "rb"))
  local readme = f:read("*a") ; f:close()
  local nl = readme:find("\r\n", 1, true) and "\r\n" or "\n"
  local lf = readme:gsub("\r\n", "\n")
  local new, why = M.spliced(lf)
  if not new then print("help_md: " .. why) os.exit(2) end
  if arg and arg[1] == "check" then
    if new ~= lf then print("help_md: README.md is out of date; run luajit basics/help_md.lua") os.exit(1) end
    print("help_md: README.md matches nannybasics.lua")
  else
    local w = assert(io.open(path, "wb"))
    w:write((new:gsub("\n", nl))) ; w:close()
    print("help_md: README.md written")
  end
end

return M
