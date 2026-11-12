-- Writes the README's command reference from lua/help.lua, between the help markers.
-- Run from the client dir:  luajit tools/help_md.lua        ('check' compares instead of writing)

local BEGIN = "<!-- help:begin (written by tools/help_md.lua from lua/help.lua: edit there) -->"
local END = "<!-- help:end -->"

local function markdown()
  elro = elro or {}
  dofile("lua/help.lua")
  local H = elro.HELP
  local out = {}
  local function add(s) out[#out + 1] = s end
  local function rows(sections)
    for _, s in ipairs(sections) do
      add("### " .. s.title) ; add("")
      for _, r in ipairs(s.rows) do add("- **`" .. r[1] .. "`** " .. (r[3] or r[2])) end
      add("")
    end
  end
  add(BEGIN)
  add("## Commands") ; add("")
  add("In Mudlet, `maphelp` lists these, `maphelp <command>` shows one in full and `maphelp <word>`"
      .. " finds every entry that mentions the word.") ; add("")
  rows(H.sections)
  add("## Advanced commands") ; add("")
  add("Shaping the map by hand, mazes, diagnostics and tuning; `maphelp advanced` in Mudlet.") ; add("")
  rows(H.advanced)
  for _, name in ipairs(H.page_order) do
    local p = H.pages[name]
    add("## " .. p.title) ; add("")
    for _, para in ipairs(p.paras) do
      local h, body = para:match("^(.-)|(.+)$")
      if h then add("- **" .. h .. ".** " .. body)
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

local M = { markdown = markdown, BEGIN = BEGIN, END = END }

-- the README with its help block replaced, or nil and why
function M.spliced(readme)
  local a = readme:find(BEGIN, 1, true)
  local b = readme:find(END, 1, true)
  if not a or not b then return nil, "README.md has no help markers" end
  return readme:sub(1, a - 1) .. markdown() .. readme:sub(b + #END)
end

if not M_HELP_MD_LIB then
  local f = assert(io.open("README.md", "rb"))
  local readme = f:read("*a") ; f:close()
  local nl = readme:find("\r\n", 1, true) and "\r\n" or "\n"
  local lf = readme:gsub("\r\n", "\n")
  local new, why = M.spliced(lf)
  if not new then print("help_md: " .. why) os.exit(2) end
  if arg and arg[1] == "check" then
    if new ~= lf then print("help_md: README.md is out of date; run luajit tools/help_md.lua") os.exit(1) end
    print("help_md: README.md matches lua/help.lua")
  else
    local w = assert(io.open("README.md", "wb"))
    w:write((new:gsub("\n", nl))) ; w:close()
    print("help_md: README.md written")
  end
end

return M
