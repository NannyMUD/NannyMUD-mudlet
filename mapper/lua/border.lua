-- border.lua  (VENDORED: keep BYTE-IDENTICAL with nannybasics/border.lua)
--
-- A shared screen-layout coordinator. Several Mudlet packages each want to park widgets on the
-- window's edges. setBorderLeft/Right/Top/Bottom are absolute setters, so one referee has to
-- own them; this does. Each edge holds a LAYOUT TREE (nested vertical/horizontal splits whose
-- leaves are named cells); a cell holds components stacked. So the right edge can be a big map
-- on top over two columns of panes below, all in one reserved panel -- not competing bands.
--
-- Every split boundary, every gap between stacked panes, and each panel's inner edge gets a
-- draggable bar (a thin label living in the gutter, so it never sits under a widget). A pane
-- registered with a title also gets a title strip; dragging the strip moves the pane into
-- another cell, or splits a cell to make room for it. Sizes, placements and the tree persist.
--
-- Singleton in a neutral global: every package carries a copy and the NEWEST revision wins,
-- whatever the load order; an older copy loading later changes nothing. So the shared API may
-- only grow: B.slot, park, move, remove, where, parked_cell, total, edge_of, cells, set_title,
-- set_hint, clear_width, is_dragging, reset, suspend, resume, is_suspended, save_state, and the
-- MudletBordersChanged event. Raise REV with every change; a break needs a new global name.

local REV = 2
MudletBorders = MudletBorders or {}
local B = MudletBorders
if (B.REV or 0) > REV then return B end
B.REV = REV

B.slots   = B.slots or {}     -- id -> { id, cross, hint, order, title, seq, cb, defCell }
B.cellOf  = B.cellOf or {}    -- slot id -> cell name it sits in (nil = parked/hidden)
B.last    = B.last or {}      -- edge -> last value handed to setBorder*, to skip no-ops
B.ovr     = B.ovr or {}       -- slot id -> size override from dragging a stack splitter
B.nsz     = B.nsz or {}       -- "<splitkey>:<i>" -> size override from dragging a split bar
B.ovrW    = B.ovrW or {}      -- edge -> panel thickness override from dragging an edge bar
B.ordOvr  = B.ordOvr or {}    -- slot id -> stack position set by dropping a pane into a cell
B.parkedAt = B.parkedAt or {} -- slot id -> the cell a parked slot returns to
B.handles = B.handles or {}   -- handle id -> Geyser.Label (bars and title strips)
B.hmeta   = B.hmeta or {}     -- handle id -> drag descriptor
B.byId    = B.byId or {}      -- slot id -> laid rect (title strip included)
B.laidN   = B.laidN or {}     -- "<splitkey>:<i>" -> laid rect
B.cellRect = B.cellRect or {} -- cell -> laid rect, for dropping panes
B._seq    = B._seq or 0
B.SH      = nil               -- title-strip height, measured on first use after each load

B.GUT = B.GUT or 8            -- gutter / handle thickness, px
B.MIN = B.MIN or 48          -- smallest a pane may be dragged to

local EDGES = { "left", "right", "top", "bottom" }

-- The default layout trees. A node is { cell = "name" } or { dir, key, kids, def }. def gives a
-- child's starting size along the split (nil = flex; 0..1 a fraction). Right edge: a big map
-- over two columns, the left (c1) for the score/party cards, the right (c2) wider for chat.
local function default_tree()
  return {
    left   = { cell = "left" },
    top    = { cell = "top" },
    bottom = { cell = "bottom" },
    right  = { dir = "v", key = "R", def = { 0.62 },
               kids = { { cell = "map" },
                        { dir = "h", key = "Rb", def = { 0.4 },
                          kids = { { cell = "c1" }, { cell = "c2" } } } } },
  }
end
-- the default cells always stay in the tree (an empty one is just not drawn), so an owner's
-- default cell is there to come back to; cells made by dropping a pane are pruned when empty.
local PROTECT = { left = true, top = true, bottom = true, map = true, c1 = true, c2 = true }

local function win_size()
  if type(getMainWindowSize) == "function" then
    local ok, w, h = pcall(getMainWindowSize)
    if ok and w and w > 0 then return w, h end
  end
  return 1200, 700
end

-- ---- persistence of sizes, placements and the tree ------------------------------
local function cfg_path() return getMudletHomeDir() .. "/MudletBorders.lua" end
local function save_state()
  if type(table.save) ~= "function" then return end
  pcall(table.save, cfg_path(), { ovr = B.ovr, ovrW = B.ovrW, nsz = B.nsz, cellOf = B.cellOf,
                                   ordOvr = B.ordOvr, parkedAt = B.parkedAt, tree = B.tree,
                                   suspended = B._suspended })
end
B.save_state = save_state
if not B._loaded then
  B._loaded = true
  if type(table.load) == "function" and type(io) == "table" then
    local ok, there = pcall(function() return io.exists and io.exists(cfg_path()) end)
    if ok and there then
      local t = {}
      if pcall(table.load, cfg_path(), t) then
        for _, k in ipairs({ "ovr", "ovrW", "nsz", "cellOf", "ordOvr", "parkedAt", "tree" }) do
          if type(t[k]) == "table" then B[k] = t[k] end
        end
        B._suspended = t.suspended and true or false
      end
    end
  end
end
local function valid_tree(t)
  if type(t) ~= "table" then return false end
  for _, e in ipairs(EDGES) do if type(t[e]) ~= "table" then return false end end
  return true
end
if not valid_tree(B.tree) then B.tree = default_tree() end

-- cell -> edge, and cell -> stacking orientation, built from the trees.
local cellEdge, cellOrient = {}, {}
local function index_tree(node, edge, orient)
  if node.cell then cellEdge[node.cell] = edge ; cellOrient[node.cell] = orient
  else for _, k in ipairs(node.kids) do index_tree(k, edge, orient) end end
end
local function reindex()
  cellEdge, cellOrient = {}, {}
  for _, e in ipairs(EDGES) do
    index_tree(B.tree[e], e, (e == "left" or e == "right") and "v" or "h")
  end
end
reindex()

local function first_leaf(node)
  if node.cell then return node.cell end
  return first_leaf(node.kids[1])
end

-- ---- which slots are where ------------------------------------------------------
local function in_cell(cell)
  local out = {}
  for _, s in pairs(B.slots) do if B.cellOf[s.id] == cell then out[#out + 1] = s end end
  table.sort(out, function(a, b)
    local oa, ob = B.ordOvr[a.id] or a.order or 0, B.ordOvr[b.id] or b.order or 0
    if oa ~= ob then return oa < ob end
    return a.seq < b.seq
  end)
  return out
end

local function occupied(node)
  if node.cell then return #in_cell(node.cell) > 0 end
  for _, k in ipairs(node.kids) do if occupied(k) then return true end end
  return false
end

-- A slot whose cell is gone (pruned, or a stale saved placement) goes back to its owner's
-- default cell, or failing that to the first cell of the right edge.
local function normalize()
  for id, s in pairs(B.slots) do
    local c = B.cellOf[id]
    if c and not cellEdge[c] then
      B.cellOf[id] = (s.defCell and cellEdge[s.defCell] and s.defCell) or first_leaf(B.tree.right)
    end
  end
end

-- A size that is >0 and <1 is a FRACTION of the given span (so defaults scale to the window and
-- the display's DPI); anything >=1 is absolute pixels. Dragged sizes are always px (>= MIN).
local function px(v, span) if v and v > 0 and v < 1 then return math.floor(v * span) end return v end

local function strip_h()
  if not B.SH then
    B.SH = 18
    if type(calcFontSize) == "function" then
      local ok, w, h = pcall(calcFontSize, 9)
      if ok and type(h) == "number" and h > 0 then B.SH = h + 6 end
    end
  end
  return B.SH
end

-- the panel thickness an edge wants: none when it holds no slot, else a drag override, else the
-- widest/tallest placed slot on it (on a top/bottom edge a titled slot also needs its strip's
-- height). The override is kept while the edge is empty, for when a pane comes back.
local function want_thick(edge)
  local W, H = win_size()
  local horiz = (edge == "top" or edge == "bottom")
  local span = horiz and H or W
  local m = 0
  for _, s in pairs(B.slots) do
    local c = B.cellOf[s.id]
    if c and cellEdge[c] == edge then
      local t = (px(s.cross, span) or 0) + ((horiz and s.title) and strip_h() or 0)
      if t > m then m = t end
    end
  end
  if m == 0 then return 0 end
  return B.ovrW[edge] or m
end

-- Opposite panels share the window and leave the text at least TEXT_MIN of it. A dragged width
-- is kept and a panel with none takes what is left; if that still overflows, both shrink in
-- proportion. Dragged widths are not changed, so they return when the other panel closes.
B.TEXT_MIN = B.TEXT_MIN or 0.25
local OPP = { left = "right", right = "left", top = "bottom", bottom = "top" }
local function room_for(edge)
  local W, H = win_size()
  local span = (edge == "top" or edge == "bottom") and H or W
  return span - math.floor(span * B.TEXT_MIN) - 2 * B.GUT
end
local function edge_thick(edge)
  local a = want_thick(edge)
  if a == 0 then return 0 end
  local o = OPP[edge]
  local b, room = want_thick(o), room_for(edge)
  if a + b <= room then return a end
  local mine, theirs = B.ovrW[edge] ~= nil, b > 0 and B.ovrW[o] ~= nil
  if theirs and not mine then a = math.max(B.MIN, room - b)
  elseif mine and not theirs and b > 0 then a = math.min(a, math.max(B.MIN, room - B.MIN))
  else a = math.floor(a * room / (a + b)) end
  return math.max(B.MIN, a)
end
B.total = edge_thick
local function edge_reserve(edge)
  local c = edge_thick(edge)
  return c > 0 and (c + B.GUT) or 0
end

-- ---- layout ---------------------------------------------------------------------
-- Distribute `along` px among `n` items, honouring fixed sizes and sharing the rest, and scaling
-- the fixed ones down if they would not leave each flexible one its minimum. szs[i] is the fixed
-- size of item i or nil for flex; it is indexed 1..n explicitly, since nil entries are holes that
-- ipairs/# would stop at. Returns a list of lengths that sum (with the gutters) to `along`.
local function distribute(szs, n, along)
  local gaps = (n - 1) * B.GUT
  local avail = along - gaps
  local fixed, flex = 0, 0
  for i = 1, n do local s = szs[i] ; if s then fixed = fixed + s else flex = flex + 1 end end
  local scale = 1
  if fixed > 0 and fixed + flex * B.MIN > avail then
    scale = math.max(0, avail - flex * B.MIN) / fixed
  end
  local share = flex > 0 and math.max(B.MIN, math.floor((avail - fixed * scale) / flex)) or 0
  local out = {}
  for i = 1, n do local s = szs[i] ; out[i] = s and math.floor(s * scale) or share end
  return out
end

local hspecs  -- collected during a layout pass, drawn after

-- A cell's slots, stacked along the edge's orientation. A titled slot gets a strip on top and
-- its owner the rect below it; its fixed hint is the CONTENT size, so the strip is added on top.
-- If every slot is fixed the last one stretches, so a cell never shows dead space.
local function lay_cell(cell, x, y, w, h)
  local list = in_cell(cell)
  if #list == 0 then return end
  B.cellRect[cell] = { x = x, y = y, w = w, h = h }
  local vertical = (cellOrient[cell] == "v")
  local along = vertical and h or w
  local SH = strip_h()
  local szs, anyflex = {}, false
  for i, s in ipairs(list) do
    local v = B.ovr[s.id]
    if not v and s.hint then v = px(s.hint, along) + ((vertical and s.title) and SH or 0) end
    szs[i] = v
    if not v then anyflex = true end
  end
  if not anyflex then szs[#list] = nil end
  local lens = distribute(szs, #list, along)
  local p = vertical and y or x
  for i, s in ipairs(list) do
    local len = lens[i]
    local rx, ry, rw, rh
    if vertical then rx, ry, rw, rh = x, p, w, len else rx, ry, rw, rh = p, y, len, h end
    B.byId[s.id] = { x = rx, y = ry, w = rw, h = rh }
    local cy, ch = ry, rh
    if s.title then
      hspecs[#hspecs + 1] = { id = "title:" .. s.id, x = rx, y = ry, w = rw, h = SH, title = s.title,
                              meta = { kind = "pane", id = s.id } }
      cy, ch = ry + SH, rh - SH
    end
    if s.cb then pcall(s.cb, rx, cy, rw, math.max(1, ch)) end
    if i < #list then
      local hid = "stack:" .. cell .. ":" .. i
      if vertical then hspecs[#hspecs + 1] = { id = hid, x = x, y = p + len, w = w, h = B.GUT,
                                               meta = { kind = "stack", aId = s.id, bId = list[i + 1].id, vertical = true } }
      else hspecs[#hspecs + 1] = { id = hid, x = p + len, y = y, w = B.GUT, h = h,
                                   meta = { kind = "stack", aId = s.id, bId = list[i + 1].id, vertical = false } } end
    end
    p = p + len + B.GUT
  end
end

-- A split lays out only its occupied children, so an empty cell takes no room; if the ones left
-- are all fixed the last stretches.
local lay_node
local function lay_split(node, x, y, w, h)
  local idx = {}
  for i, k in ipairs(node.kids) do if occupied(k) then idx[#idx + 1] = i end end
  if #idx == 0 then return end
  local dir = node.dir
  local along = (dir == "v") and h or w
  local szs, anyflex = {}, false
  for n, i in ipairs(idx) do
    local v = B.nsz[node.key .. ":" .. i] or px(node.def and node.def[i], along)
    szs[n] = v
    if not v then anyflex = true end
  end
  if not anyflex then szs[#idx] = nil end
  local lens = distribute(szs, #idx, along)
  local p = (dir == "v") and y or x
  for n, i in ipairs(idx) do
    local len = lens[n]
    local kx, ky, kw, kh
    if dir == "v" then kx, ky, kw, kh = x, p, w, len else kx, ky, kw, kh = p, y, len, h end
    B.laidN[node.key .. ":" .. i] = { x = kx, y = ky, w = kw, h = kh }
    lay_node(node.kids[i], kx, ky, kw, kh)
    if n < #idx then
      local hid = "split:" .. node.key .. ":" .. i
      local meta = { kind = "split", key = node.key, i = i, j = idx[n + 1], dir = dir }
      if dir == "v" then hspecs[#hspecs + 1] = { id = hid, x = x, y = p + len, w = w, h = B.GUT, meta = meta }
      else hspecs[#hspecs + 1] = { id = hid, x = p + len, y = y, w = B.GUT, h = h, meta = meta } end
    end
    p = p + len + B.GUT
  end
end
function lay_node(node, x, y, w, h)
  if node.cell then lay_cell(node.cell, x, y, w, h) else lay_split(node, x, y, w, h) end
end

-- ---- handles and overlays -------------------------------------------------------
local BAR_CSS = { [false] = "background-color: rgba(128,128,150,0.22);",
                  [true]  = "background-color: rgba(150,170,210,0.55);" }
local TITLE_CSS = {
  [false] = "background-color: #1c1a26; color: #b9b2cc; font-weight: bold; font-size: 9pt; "
         .. "padding-left: 6px; border-bottom: 1px solid #2a2436;",
  [true]  = "background-color: #3d3560; color: #ffffff; font-weight: bold; font-size: 9pt; "
         .. "padding-left: 6px; border-bottom: 1px solid #6a4fb0;",
}
local function style(l, active)
  pcall(function() l:setStyleSheet((l._title and TITLE_CSS or BAR_CSS)[active and true or false]) end)
end
local function strip_text(l, title)
  if l._txt == title then return end
  pcall(function() l:echo("&#8801;&nbsp;" .. title) end) ; l._txt = title
end
local function make_handle(id, titled)
  if B.handles[id] then return B.handles[id] end
  if type(Geyser) ~= "table" or not Geyser.Label then return nil end
  local ok, l = pcall(function()
    return Geyser.Label:new({ name = "MB_" .. id, x = 0, y = 0, width = 1, height = 1 })
  end)
  if not ok or not l then return nil end
  l._title = titled
  style(l, false)
  pcall(function() l:setClickCallback(function() B.drag_start(id) end) end)
  pcall(function() l:setReleaseCallback(function() B.drag_end() end) end)
  B.handles[id] = l
  return l
end
-- the pointer over a handle: resize arrows across a bar, a hand on a title strip
local function cursor_for(m)
  if m.kind == "pane" then return "OpenHand" end
  local across_v
  if m.kind == "edge" then across_v = (m.edge == "top" or m.edge == "bottom")
  elseif m.kind == "split" then across_v = (m.dir == "v")
  else across_v = m.vertical end
  return across_v and "ResizeVertical" or "ResizeHorizontal"
end
local function set_cursor(l, shape)
  if l._cur == shape then return end
  l._cur = shape
  pcall(function() l:setCursor(shape) end)
end
local function draw_handles()
  if type(Geyser) ~= "table" or not Geyser.Label then return end
  local used = {}
  for _, sp in ipairs(hspecs) do
    local l = make_handle(sp.id, sp.title ~= nil)
    if l then
      used[sp.id] = true ; B.hmeta[sp.id] = sp.meta
      if not (B._drag and B._drag.hid == sp.id) then set_cursor(l, cursor_for(sp.meta)) end
      pcall(function() l:move(sp.x, sp.y) ; l:resize(sp.w, sp.h) ; l:show() end)
      if sp.title then strip_text(l, sp.title) end
      -- keep handles above the panes (esp. the map's Adjustable.Container, whose resize grips
      -- would otherwise swallow a drag on the bar beside it); not every drag tick, to avoid churn.
      if not B._dragging and type(raiseWindow) == "function" then pcall(raiseWindow, "MB_" .. sp.id) end
    end
  end
  for id, l in pairs(B.handles) do if not used[id] then pcall(function() l:hide() end) end end
end

-- the drop preview: a translucent box over the target, and a line where a joining pane goes
B.ov = B.ov or {}
local OV_CSS = { ghost = "background-color: rgba(110,140,220,0.22); border: 2px solid rgba(150,180,240,0.85);",
                 ins   = "background-color: rgba(230,200,90,0.95);" }
local function show_ov(name, x, y, w, h)
  local l = B.ov[name]
  if not l then
    if type(Geyser) ~= "table" or not Geyser.Label then return end
    local ok, nl = pcall(function()
      return Geyser.Label:new({ name = "MB_ov_" .. name, x = 0, y = 0, width = 1, height = 1 })
    end)
    if not ok or not nl then return end
    l = nl ; B.ov[name] = l
    pcall(function() l:setStyleSheet(OV_CSS[name]) end)
  end
  pcall(function() l:move(x, y) ; l:resize(math.max(1, w), math.max(1, h)) ; l:show() end)
  if not l._up and type(raiseWindow) == "function" then pcall(raiseWindow, "MB_ov_" .. name) ; l._up = true end
end
local function hide_ov(name)
  for nm, l in pairs(B.ov) do
    if not name or nm == name then pcall(function() l:hide() end) ; l._up = nil end
  end
end

-- ---- apply ----------------------------------------------------------------------
function B.apply()
  if B._applying then return end
  B._applying = true
  local set = { left = setBorderLeft, right = setBorderRight,
                top = setBorderTop, bottom = setBorderBottom }
  -- Suspended (e.g. a secondary MultiView session that wants the space): give every border back,
  -- hide the handles, and move every pane off-screen. resume() lays it all out again.
  if B._suspended then
    for _, edge in ipairs(EDGES) do
      if B.last[edge] ~= 0 and type(set[edge]) == "function" then pcall(set[edge], 0) ; B.last[edge] = 0 end
    end
    for _, s in pairs(B.slots) do if s.cb then pcall(s.cb, -10000, -10000, 1, 1) end end
    for _, l in pairs(B.handles) do pcall(function() l:hide() end) end
    hide_ov()
    B._applying = false
    return
  end
  normalize()
  for _, edge in ipairs(EDGES) do
    local v = edge_reserve(edge)
    if B.last[edge] ~= v and type(set[edge]) == "function" then
      pcall(set[edge], v) ; B.last[edge] = v
    end
  end
  local W, H = win_size()
  B.byId, B.laidN, B.cellRect, hspecs = {}, {}, {}, {}
  for _, edge in ipairs(EDGES) do
    local T = edge_thick(edge)
    if T > 0 then
      local x, y, w, h
      if edge == "right" then x, y, w, h = W - T, 0, T, H
      elseif edge == "left" then x, y, w, h = 0, 0, T, H
      elseif edge == "top" then x, y, w, h = edge_reserve("left"), 0, W - edge_reserve("left") - edge_reserve("right"), T
      else x, y, w, h = edge_reserve("left"), H - T, W - edge_reserve("left") - edge_reserve("right"), T end
      -- the edge bar lives in the gutter on the panel's inner side
      if edge == "right" then hspecs[#hspecs + 1] = { id = "edge:right", x = x - B.GUT, y = 0, w = B.GUT, h = H, meta = { kind = "edge", edge = edge } }
      elseif edge == "left" then hspecs[#hspecs + 1] = { id = "edge:left", x = T, y = 0, w = B.GUT, h = H, meta = { kind = "edge", edge = edge } }
      elseif edge == "top" then hspecs[#hspecs + 1] = { id = "edge:top", x = x, y = T, w = w, h = B.GUT, meta = { kind = "edge", edge = edge } }
      else hspecs[#hspecs + 1] = { id = "edge:bottom", x = x, y = H - T - B.GUT, w = w, h = B.GUT, meta = { kind = "edge", edge = edge } } end
      lay_node(B.tree[edge], x, y, w, h)
    end
  end
  draw_handles()
  B._applying = false
end

-- ---- tree edits (dropping a pane) -----------------------------------------------
local function fresh_cell()
  local i = 1
  while cellEdge["x" .. i] do i = i + 1 end
  return "x" .. i
end
local function fresh_key()
  local used = {}
  local function walk(n) if not n.cell then used[n.key] = true ; for _, k in ipairs(n.kids) do walk(k) end end end
  for _, e in ipairs(EDGES) do walk(B.tree[e]) end
  local i = 1
  while used["S" .. i] do i = i + 1 end
  return "S" .. i
end
local function replace_in(node, cell, new)
  for i, k in ipairs(node.kids) do
    if k.cell == cell then node.kids[i] = new ; return true end
    if not k.cell and replace_in(k, cell, new) then return true end
  end
  return false
end
-- split `cell` in two along `side`; the new cell (returned) takes that side.
local function split_cell(cell, side)
  local nc = fresh_cell()
  local first = (side == "left" or side == "top")
  local node = { dir = (side == "left" or side == "right") and "h" or "v", key = fresh_key(),
                 kids = first and { { cell = nc }, { cell = cell } } or { { cell = cell }, { cell = nc } } }
  for _, e in ipairs(EDGES) do
    if B.tree[e].cell == cell then B.tree[e] = node ; return nc end
    if not B.tree[e].cell and replace_in(B.tree[e], cell, node) then return nc end
  end
  return nil
end

-- Drop empty cells made by earlier drops, collapsing a split left with one child. Split sizes are
-- kept per surviving child; the default cells always stay.
local function cell_used(cell)
  for _, c in pairs(B.cellOf) do if c == cell then return true end end
  for _, c in pairs(B.parkedAt) do if c == cell then return true end end
  return false
end
local function prune_node(node)
  if node.cell then
    if PROTECT[node.cell] or cell_used(node.cell) then return node end
    return nil
  end
  local nk, nnsz, ndef = {}, {}, {}
  for i, k in ipairs(node.kids) do
    local pk = prune_node(k)
    if pk then
      nk[#nk + 1] = pk
      nnsz[#nk] = B.nsz[node.key .. ":" .. i]
      ndef[#nk] = node.def and node.def[i]
    end
  end
  for i = 1, #node.kids do B.nsz[node.key .. ":" .. i] = nil end
  if #nk == 0 then return nil end
  if #nk == 1 then return nk[1] end
  node.kids, node.def = nk, ndef
  for i = 1, #nk do B.nsz[node.key .. ":" .. i] = nnsz[i] end
  return node
end
local function prune()
  for _, e in ipairs(EDGES) do B.tree[e] = prune_node(B.tree[e]) or { cell = e } end
  reindex()
end

local function changed(id)
  if type(raiseEvent) == "function" then pcall(raiseEvent, "MudletBordersChanged", id) end
end

local function drop(id, t)
  if t.kind == "join" then
    local list = {}
    for _, s in ipairs(t.others) do list[#list + 1] = s.id end
    table.insert(list, math.min(t.pos, #list + 1), id)
    for i, sid in ipairs(list) do B.ordOvr[sid] = i * 10 end
    B.cellOf[id] = t.cell
  elseif t.kind == "split" then
    local nc = split_cell(t.cell, t.side)
    if not nc then return end
    reindex()
    B.cellOf[id], B.ordOvr[id] = nc, nil
  elseif t.kind == "edge" then
    B.cellOf[id], B.ordOvr[id] = first_leaf(B.tree[t.edge]), nil
  end
  prune()
  changed(id)
end

-- What a pane dropped at (mx, my) would do: join a cell's stack (and where in it), split a cell
-- near one of its edges, or start a panel on an empty window edge.
local SPLIT_BAND, EDGE_ZONE = 0.22, 60
local function hit(mx, my, id)
  for cell, r in pairs(B.cellRect) do
    if cellEdge[cell] and mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then
      local fx, fy = (mx - r.x) / r.w, (my - r.y) / r.h
      local side, m = "left", fx
      if 1 - fx < m then side, m = "right", 1 - fx end
      if fy < m then side, m = "top", fy end
      if 1 - fy < m then side, m = "bottom", 1 - fy end
      if m < SPLIT_BAND then return { kind = "split", cell = cell, side = side, r = r } end
      local vertical = (cellOrient[cell] == "v")
      local others, pos = {}, 1
      for _, s in ipairs(in_cell(cell)) do if s.id ~= id then others[#others + 1] = s end end
      for _, s in ipairs(others) do
        local b = B.byId[s.id]
        if b and (vertical and my > b.y + b.h / 2 or (not vertical) and mx > b.x + b.w / 2) then pos = pos + 1 end
      end
      return { kind = "join", cell = cell, pos = pos, others = others, r = r, vertical = vertical }
    end
  end
  local W, H = win_size()
  if mx < EDGE_ZONE and edge_thick("left") == 0 then return { kind = "edge", edge = "left" } end
  if mx > W - EDGE_ZONE and edge_thick("right") == 0 then return { kind = "edge", edge = "right" } end
  if my < EDGE_ZONE and edge_thick("top") == 0 then return { kind = "edge", edge = "top" } end
  if my > H - EDGE_ZONE and edge_thick("bottom") == 0 then return { kind = "edge", edge = "bottom" } end
  return nil
end

local function show_target(t)
  if not t then hide_ov() ; return end
  if t.kind == "split" then
    local r = t.r
    local x, y, w, h = r.x, r.y, r.w, r.h
    if t.side == "left" then w = r.w / 2
    elseif t.side == "right" then x, w = r.x + r.w / 2, r.w / 2
    elseif t.side == "top" then h = r.h / 2
    else y, h = r.y + r.h / 2, r.h / 2 end
    show_ov("ghost", x, y, w, h) ; hide_ov("ins")
  elseif t.kind == "join" then
    local r = t.r
    show_ov("ghost", r.x, r.y, r.w, r.h)
    local nxt, last = t.others[t.pos], t.others[#t.others]
    local a = nxt and B.byId[nxt.id] or (last and B.byId[last.id])
    if not a then hide_ov("ins")
    elseif t.vertical then show_ov("ins", r.x, (nxt and a.y or a.y + a.h) - 2, r.w, 4)
    else show_ov("ins", (nxt and a.x or a.x + a.w) - 2, r.y, 4, r.h) end
  else
    -- side panels run full height; top and bottom span only the text between them
    local W, H = win_size()
    local l, r = edge_reserve("left"), edge_reserve("right")
    if t.edge == "left" then show_ov("ghost", 0, 0, 200, H)
    elseif t.edge == "right" then show_ov("ghost", W - 200, 0, 200, H)
    elseif t.edge == "top" then show_ov("ghost", l, 0, W - l - r, 120)
    else show_ov("ghost", l, H - 120, W - l - r, 120) end
    hide_ov("ins")
  end
end

-- ---- drag -----------------------------------------------------------------------
local function mouse()
  if type(getMousePosition) ~= "function" then return nil end
  local ok, x, y = pcall(getMousePosition)
  if ok and x then return x, y end
  return nil
end
function B.drag_start(hid)
  local m = B.hmeta[hid]
  local mx, my = mouse()
  if not m or not mx then return end
  local d = { hid = hid, kind = m.kind, edge = m.edge, dir = m.dir, i = m.i, j = m.j, key = m.key,
              aId = m.aId, bId = m.bId, vertical = m.vertical, id = m.id, sx = mx, sy = my }
  if m.kind == "edge" then
    d.startT = edge_thick(m.edge)
  elseif m.kind == "split" then
    local a, b = B.laidN[m.key .. ":" .. m.i], B.laidN[m.key .. ":" .. m.j]
    if not a or not b then return end
    d.aLen = (m.dir == "v") and a.h or a.w
    d.bLen = (m.dir == "v") and b.h or b.w
  elseif m.kind == "stack" then
    local a, b = B.byId[m.aId], B.byId[m.bId]
    if not a or not b then return end
    d.aLen = m.vertical and a.h or a.w
    d.bLen = m.vertical and b.h or b.w
  end
  B._drag, B._dragging = d, true
  if B.handles[hid] then
    style(B.handles[hid], true)
    if m.kind == "pane" then set_cursor(B.handles[hid], "ClosedHand") end
  end
  if type(tempTimer) == "function" then
    if B._dragTimer then pcall(killTimer, B._dragTimer) end
    B._dragTimer = tempTimer(0.03, function() B.drag_move() end, true)
  end
end
function B.drag_move()
  local d = B._drag
  if not d then return end
  local mx, my = mouse()
  if not mx then return end
  local W, H = win_size()
  -- Qt keeps delivering to the pressed label outside the window, so the release still ends the
  -- drag there; outside, sizes stop at the edge and a pane has no target. The timeout is a
  -- failsafe for a release that never arrives.
  local outside = mx < 0 or my < 0 or mx >= W or my >= H
  if not outside then d.outT = nil
  elseif not d.outT then d.outT = os.time()
  elseif os.time() - d.outT > 10 then d.cancel = true ; return B.drag_end() end
  mx, my = math.max(0, math.min(mx, W - 1)), math.max(0, math.min(my, H - 1))
  if d.kind == "pane" then
    -- only the preview moves while dragging a pane; the layout changes once, on the drop
    if not d.moved and math.abs(mx - d.sx) + math.abs(my - d.sy) < 6 then return end
    d.moved = true
    d.target = (not outside) and hit(mx, my, d.id) or nil
    show_target(d.target)
    return
  end
  if d.kind == "edge" then
    local e, v = d.edge
    if e == "right" then v = d.startT + (d.sx - mx)
    elseif e == "left" then v = d.startT + (mx - d.sx)
    elseif e == "top" then v = d.startT + (my - d.sy)
    else v = d.startT + (d.sy - my) end
    -- stop where the opposite panel (its dragged width, or its smallest) and the text begin
    local o = OPP[e]
    local other = want_thick(o)
    local keep = other == 0 and 0 or (B.ovrW[o] and other or B.MIN)
    local cap = math.min(math.floor(((e == "left" or e == "right") and W or H) * 0.6), room_for(e) - keep)
    B.ovrW[e] = math.max(B.MIN, math.min(v, cap))
  elseif d.kind == "split" then
    local along = (d.dir == "v") and (my - d.sy) or (mx - d.sx)
    local combined = d.aLen + d.bLen
    local aNew = math.max(B.MIN, math.min(d.aLen + along, combined - B.MIN))
    B.nsz[d.key .. ":" .. d.i] = aNew
    B.nsz[d.key .. ":" .. d.j] = combined - aNew
  else
    local along = d.vertical and (my - d.sy) or (mx - d.sx)
    local combined = d.aLen + d.bLen
    local aNew = math.max(B.MIN, math.min(d.aLen + along, combined - B.MIN))
    B.ovr[d.aId] = aNew
    B.ovr[d.bId] = combined - aNew
  end
  B.apply()
end
function B.drag_end()
  if B._dragTimer then pcall(killTimer, B._dragTimer) ; B._dragTimer = nil end
  local d = B._drag
  if d and B.handles[d.hid] then
    style(B.handles[d.hid], false)
    if B.hmeta[d.hid] then set_cursor(B.handles[d.hid], cursor_for(B.hmeta[d.hid])) end
  end
  hide_ov()
  B._drag, B._dragging = nil, false
  if d and d.kind == "pane" and d.moved and d.target and not d.cancel then drop(d.id, d.target) end
  B.apply()
  save_state()
end

-- ---- public ---------------------------------------------------------------------
-- spec = { cell, cross, hint, order, title, cb }: cell is where it starts (kept across relayouts so
-- a later move sticks); cross is the panel-thickness it suggests; hint is a fixed content size
-- (nil = flex); order sorts within a cell; title, if given, adds a strip to drag the pane by;
-- cb(x,y,w,h) positions the widget.
function B.slot(id, spec)
  local s = B.slots[id]
  if not s then B._seq = B._seq + 1 ; s = { id = id, seq = B._seq } ; B.slots[id] = s end
  s.cross = tonumber(spec.cross) or 0
  s.hint  = tonumber(spec.hint)
  s.order = tonumber(spec.order) or 0
  s.title = spec.title
  if spec.cb then s.cb = spec.cb end
  local back = B.parkedAt[id]
  if back and B.cellOf[id] == nil and cellEdge[back] then B.cellOf[id] = back end
  B.parkedAt[id] = nil
  if spec.cell ~= nil then
    s.defCell = spec.cell                                      -- the owner's default, for reset
    if B.cellOf[id] == nil then B.cellOf[id] = spec.cell end   -- first placement wins; a move overrides
  end
  B.apply()
  if back then save_state() end
end
-- hide/park a slot (its component is not shown; it comes back to the same cell), or move it.
function B.park(id)
  if B.cellOf[id] then B.parkedAt[id] = B.cellOf[id] end
  B.cellOf[id] = nil ; B.apply() ; save_state()
end
function B.move(id, cell)
  if not cellEdge[cell] then return end
  B.cellOf[id], B.ordOvr[id], B.parkedAt[id] = cell, nil, nil
  prune() ; B.apply() ; save_state()
end
function B.cells() local c = {} for k in pairs(cellEdge) do c[#c + 1] = k end return c end
function B.edge_of(cell) return cellEdge[cell] end
function B.where(id) return B.cellOf[id] end
function B.parked_cell(id) return B.parkedAt[id] end
-- drop a dragged panel width, so the owner's own width applies again
function B.clear_width(edge) B.ovrW[edge] = nil end
function B.is_dragging() return B._dragging and true or false end
function B.remove(id)
  if B.slots[id] then B.slots[id] = nil ; B.cellOf[id] = nil ; B.apply() end
end

-- change a pane's strip text (e.g. the map naming the current room); only adding or removing a
-- strip changes the layout, so plain text changes skip the relayout.
function B.set_title(id, title)
  local s = B.slots[id] ; if not s then return end
  local had = s.title ~= nil
  s.title = title
  if had ~= (title ~= nil) then B.apply() return end
  local l = B.handles["title:" .. id]
  if l and title then strip_text(l, title) end
end

-- update just a slot's fixed stack size (nil = flex), e.g. a party pane that grew a member.
function B.set_hint(id, hint)
  local s = B.slots[id] ; if not s then return end
  s.hint = tonumber(hint)
  B.apply()
end

-- restore the default layout: the default tree, no dragged sizes, and each pane back in its
-- owner's default cell.
function B.reset()
  B.tree = default_tree() ; reindex()
  B.ovr, B.nsz, B.ovrW, B.ordOvr = {}, {}, {}, {}
  B.parkedAt = {}
  for id, s in pairs(B.slots) do
    if s.defCell and B.cellOf[id] then B.cellOf[id] = s.defCell
    elseif s.defCell then B.parkedAt[id] = s.defCell end
  end
  save_state() ; B.apply()
  changed()
end

-- Turn the whole UI off for this session (hand all borders back, hide every pane), or on again.
-- Persisted, so a secondary MultiView session stays off. Spans every package sharing this border.
function B.suspend() B._suspended = true ; save_state() ; B.apply() end
function B.resume() B._suspended = false ; save_state() ; B.apply() end
function B.is_suspended() return B._suspended and true or false end

if type(registerAnonymousEventHandler) == "function" then
  if B._resizeH and type(killAnonymousEventHandler) == "function" then
    pcall(killAnonymousEventHandler, B._resizeH)
  end
  B._resizeH = registerAnonymousEventHandler("sysWindowResizeEvent", function() B.apply() end)
end

return B
