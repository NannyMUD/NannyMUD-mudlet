-- Offline test of the layout coordinator (border.lua): title strips, dragging a pane to split a
-- cell / join a stack / open an empty edge, pruning, reset, and set_title. Mudlet is stubbed.
--   luajit basics/tests/test_border.lua
-- a stub label that keeps its click callback and text, so the test can click it
local function L()
  local t = {}
  local mt = { __index = function(_, k)
    if k == "setClickCallback" then return function(self, f) self._click = f return self end end
    if k == "echo" then return function(self, s) self._echoed = s return self end end
    return function() return t end
  end }
  return setmetatable(t, mt)
end
Geyser = { Label = { new = function() return L() end } }
local W, H = 2560, 1143
function getMainWindowSize() return W, H end
local BORD = { left = 0, right = 0, top = 0, bottom = 0 }     -- the profile's borders
function setBorderLeft(v) BORD.left = v end function setBorderRight(v) BORD.right = v end
function setBorderTop(v) BORD.top = v end function setBorderBottom(v) BORD.bottom = v end
function getBorderLeft() return BORD.left end function getBorderRight() return BORD.right end
function getBorderTop() return BORD.top end function getBorderBottom() return BORD.bottom end
function registerAnonymousEventHandler() end function killAnonymousEventHandler() end
function getMudletHomeDir() return "." end
function calcFontSize(n) return 8, 15 end
local MX, MY = 0, 0
function getMousePosition() return MX, MY end
io = io or {} ; io.exists = function() return false end
table.save = nil ; table.load = nil
local HERE = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "../"
dofile(HERE .. "border.lua")
local B = MudletBorders
local function cb() end
B.slot("elromap:map",   { cell="map", cross=0.5, title="Map", cb=cb })
B.slot("nanny:vitals",  { cell="bottom", cross=56, cb=cb, order=11 })
B.slot("nanny:channels",{ cell="c2", cross=0.45, title="Chat", cb=cb, order=12 })
B.slot("nanny:status",  { cell="c1", cross=0.45, hint=180, title="Score", cb=cb, order=13 })
B.slot("nanny:party",   { cell="c1", cross=0.45, title="Party", cb=cb, order=14 })

local fails = 0
local function check(ok, msg) print((ok and "ok   " or "FAIL ") .. msg) ; if not ok then fails = fails + 1 end end
local function onscreen()
  for id, r in pairs(B.byId) do
    if r.x < 0 or r.y < 0 or r.x + r.w > W + 1 or r.y + r.h > H + 1 or r.w <= 0 or r.h <= 0 then return false, id end
  end
  return true
end
local function drag(id, tx, ty)
  local s = B.byId[id]
  MX, MY = s.x + 10, s.y + 5                      -- on the title strip
  B.drag_start("title:" .. id)
  MX, MY = tx, ty ; B.drag_move()
  B.drag_end()
end

-- the score card's content box is its hint; the strip sits above it
local st = B.byId["nanny:status"]
check(st.h == 180 + B.SH, "status slot = card " .. 180 .. " + strip " .. B.SH .. " (got " .. st.h .. ")")

-- 1. split: drop Score near the LEFT edge of the chat cell -> chat cell splits, Score on the left
local ch = B.byId["nanny:channels"]
drag("nanny:status", ch.x + 5, ch.y + ch.h / 2)
local sc = B.where("nanny:status")
check(sc ~= "c1" and sc ~= "c2", "split put Score in a new cell (" .. tostring(sc) .. ")")
check(B.edge_of(sc) == "right", "new cell is on the right edge")
check(B.byId["nanny:status"].x < B.byId["nanny:channels"].x, "Score sits left of Chat")
local ok, bad = onscreen() ; check(ok, "everything on-screen after split " .. tostring(bad))

-- 2. join: drop Party into the middle of Score's cell, above Score -> stacked, Party first
local s2 = B.byId["nanny:status"]
drag("nanny:party", s2.x + s2.w / 2, s2.y + s2.h * 0.3)
check(B.where("nanny:party") == sc, "Party joined Score's cell")
check(B.byId["nanny:party"].y < B.byId["nanny:status"].y, "Party stacked above Score")

-- 3. c1 is now empty but protected: it stays in the tree, takes no room
local found = false
for _, c in ipairs(B.cells()) do if c == "c1" then found = true end end
check(found, "empty default cell c1 kept in the tree")
ok, bad = onscreen() ; check(ok, "everything on-screen after join " .. tostring(bad))

-- 4. edge: drop Chat at the far left of the text area -> a left panel appears
drag("nanny:channels", 20, H / 2)
check(B.where("nanny:channels") == "left", "Chat dropped on the empty left edge")
check(B.total("left") > 0, "left panel now has a width")

-- 5. move Score+Party out of the user cell -> it is pruned and its split collapses
B.move("nanny:status", "c1") ; B.move("nanny:party", "c1")
local still = false
for _, c in ipairs(B.cells()) do if c == sc then still = true end end
check(not still, "emptied user cell " .. sc .. " pruned")

-- 6. reset restores the default tree and placements
B.reset()
check(B.where("nanny:channels") == "c2" and B.where("nanny:status") == "c1", "reset restores placements")
check(B.tree.right.key == "R" and B.tree.left.cell == "left", "reset restores the default tree")
ok, bad = onscreen() ; check(ok, "everything on-screen after reset " .. tostring(bad))

-- 7. a click on a strip without moving drops nothing
local before = B.where("nanny:party")
local p = B.byId["nanny:party"] ; MX, MY = p.x + 10, p.y + 5
B.drag_start("title:nanny:party") ; B.drag_move() ; B.drag_end()
check(B.where("nanny:party") == before, "a click without a drag moves nothing")

-- 8. set_title changes the map strip's text without a relayout
local applies = 0
local real_apply = B.apply
B.apply = function(...) applies = applies + 1 ; return real_apply(...) end
B.set_title("elromap:map", "Map &#183; the village green &#183; 2 &#183; world")
check(B.handles["title:elromap:map"]._txt == "Map &#183; the village green &#183; 2 &#183; world", "map strip shows the room")
check(applies == 0, "a title change did not relayout")
B.apply = real_apply

-- 9. a pane parked from a cell of its own comes back there (the guild pane before its data)
B.slot("nanny:guild", { cell="c2", cross=0.45, title="Strigoi", cb=cb, order=15 })
local c2 = B.byId["nanny:channels"]
drag("nanny:guild", c2.x + c2.w - 5, c2.y + c2.h / 2)
local gc = B.where("nanny:guild")
check(gc ~= "c2" and gc ~= "c1", "guild split into a cell of its own (" .. tostring(gc) .. ")")
B.park("nanny:guild")
check(B.where("nanny:guild") == nil, "parked guild is hidden")
B.move("nanny:party", "c2")                       -- a prune runs while the guild is parked
local kept = false
for _, c in ipairs(B.cells()) do if c == gc then kept = true end end
check(kept, "a parked pane's cell survives a prune")
B.slot("nanny:guild", { cell="c2", cross=0.45, title="Strigoi", cb=cb, order=15 })
check(B.where("nanny:guild") == gc, "unparked guild returns to " .. tostring(gc))
B.park("nanny:guild") ; B.reset()
check(B.where("nanny:guild") == nil and B.parkedAt["nanny:guild"] == "c2", "reset keeps a parked pane hidden, home = default")

-- 10. a pane dropped on the empty top edge, the panel resized, then the pane dragged back: the
-- emptied top takes no room and accepts a drop again; its size returns with the next pane
B.slot("nanny:guild", { cell="c2", cross=0.45, title="Strigoi", cb=cb, order=15 })
drag("nanny:party", W / 4, 20)
check(B.edge_of(B.where("nanny:party")) == "top" and B.total("top") > 0, "Party opened a top panel")
B.ovrW.top = 300                                  -- as if the top panel's bar had been dragged
B.apply()
local c1 = B.byId["nanny:status"]
drag("nanny:party", c1.x + c1.w / 2, c1.y + c1.h * 0.7)
check(B.where("nanny:party") == "c1", "Party dragged back into c1")
check(B.total("top") == 0, "the emptied top panel takes no room (got " .. B.total("top") .. ")")
drag("nanny:party", W / 4, 20)
check(B.edge_of(B.where("nanny:party")) == "top", "the empty top edge takes a drop again")
check(B.total("top") == 300, "and comes back at its dragged size")

-- 11. the pointer leaving the window keeps the drag going; released outside, a pane stays put
local home = B.where("nanny:status")
local st2 = B.byId["nanny:status"]
MX, MY = st2.x + 10, st2.y + 5 ; B.drag_start("title:nanny:status")
MX, MY = -200, H / 2 ; B.drag_move()
check(B._drag ~= nil, "a drag outside the window is not cancelled")
B.drag_end()
check(B.where("nanny:status") == home, "released outside: the pane did not move")
-- a bar dragged past the window edge stops at the edge
local eb = B.hmeta["edge:right"]
check(eb ~= nil, "right panel has an edge bar")
MX, MY = W - B.total("right") - 4, H / 2 ; B.drag_start("edge:right")
MX = -500 ; B.drag_move() ; B.drag_end()
check(B.total("right") == math.floor(W * 0.6), "edge bar dragged outside stops at its cap (" .. B.total("right") .. ")")

-- 12. a pane dropped on the empty left edge with the right panel dragged wide: the left takes
-- what is left, the text keeps its minimum, and the left's own bar is on screen
B.ovrW.right = 1536 ; B.apply()
drag("nanny:party", 20, H / 2)
check(B.edge_of(B.where("nanny:party")) == "left", "Party opened a left panel")
local L_, R_ = B.total("left"), B.total("right")
check(R_ == 1536, "the dragged right width is kept (" .. R_ .. ")")
check(W - L_ - R_ - 2 * B.GUT >= math.floor(W * B.TEXT_MIN), "the text keeps its minimum (left " .. L_ .. ")")
local lb = B.hmeta["edge:left"] and B.handles["edge:left"]
check(lb ~= nil, "the left panel has its bar")
-- dragging the left bar wider stops before the text minimum
MX, MY = L_ + 4, H / 2 ; B.drag_start("edge:left")
MX = W - 10 ; B.drag_move() ; B.drag_end()
check(W - B.total("left") - B.total("right") - 2 * B.GUT >= math.floor(W * B.TEXT_MIN),
  "a dragged left bar stops at the text minimum (left " .. B.total("left") .. ", right " .. B.total("right") .. ")")
B.move("nanny:party", "c1")
check(B.total("left") == 0 and B.total("right") == 1536, "left closed: right back to its width")

-- 13. newest copy wins: an older revision loading later changes nothing, a newer one takes over
local f = io.open(HERE .. "border.lua") ; local src = f:read("*a") ; f:close()
local rev = tonumber(src:match("\nlocal REV = (%d+)\n"))
check(rev and B.REV == rev, "the loaded copy registered its REV " .. tostring(rev))
local live_slot, live_where = B.slot, B.where("nanny:status")
local older = src:gsub("\nlocal REV = %d+\n", "\nlocal REV = " .. (rev - 1) .. "\n")
assert(loadstring(older))()
check(B.slot == live_slot and B.REV == rev, "an older copy loading later left the live code alone")
check(B.where("nanny:status") == live_where, "and the layout state")
local newer = src:gsub("\nlocal REV = %d+\n", "\nlocal REV = " .. (rev + 1) .. "\n")
assert(loadstring(newer))()
check(B.slot ~= live_slot and B.REV == rev + 1, "a newer copy replaced the code")
check(B.where("nanny:status") == live_where, "and kept the layout state")

-- 14. a left border set in Mudlet's preferences and saved with the profile survives a restart,
-- and a panel opened on that edge goes inside it
local function copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o end
local store
table.save = function(_, t) store = copy(t) end
table.load = function(_, t) for k, v in pairs(copy(store)) do t[k] = v end end
io.exists = function() return store ~= nil end
B.save_state()
check(BORD.left == 0, "left border is 0 with no left panel")
BORD.left = 10                                     -- the player's preference, saved in the profile
local rightBefore = BORD.right
MudletBorders = nil ; dofile(HERE .. "border.lua") ; B = MudletBorders
B.slot("elromap:map",   { cell="map", cross=0.5, title="Map", cb=cb })
B.slot("nanny:vitals",  { cell="bottom", cross=56, cb=cb, order=11 })
B.slot("nanny:channels",{ cell="c2", cross=0.45, title="Chat", cb=cb, order=12 })
B.slot("nanny:status",  { cell="c1", cross=0.45, hint=180, title="Score", cb=cb, order=13 })
B.slot("nanny:party",   { cell="c1", cross=0.45, title="Party", cb=cb, order=14 })
check(BORD.left == 10 and B.margin.left == 10, "after a restart the left border is still 10 (" .. BORD.left .. ")")
check((B.margin.right or 0) == 0 and BORD.right == rightBefore, "the right border is unchanged (" .. BORD.right .. ")")
drag("nanny:party", 20, H / 2)
check(B.edge_of(B.where("nanny:party")) == "left", "Party opened a left panel")
check(B.byId["nanny:party"].x == 10, "the left panel starts inside the margin (x " .. B.byId["nanny:party"].x .. ")")
check(BORD.left == 10 + B.total("left") + B.GUT, "the left border is margin + panel + gutter (" .. BORD.left .. ")")
BORD.left = BORD.left - 4 ; B.apply()             -- the preference lowered mid-session
check(B.margin.left == 6, "a change in the preferences mid-session moves the margin (" .. B.margin.left .. ")")
B.move("nanny:party", "c1")
check(BORD.left == 6, "left panel closed: the border is the margin again (" .. BORD.left .. ")")

-- 15. the X closes a pane and it stays closed across a restart; the right-click menu and a
-- reset bring it back; a left click on a strip still drags
local hidden = 0
local function chat() return { cell="c2", cross=0.45, title="Chat", cb=cb, order=12,
                               on_hide=function() hidden = hidden + 1 end } end
B.slot("nanny:channels", chat())
check(B.hmeta["close:nanny:channels"] ~= nil, "a pane with on_hide has an X")
check(B.hmeta["close:nanny:status"] == nil, "a pane without one has none")
B.handles["close:nanny:channels"]._click({ button = "LeftButton" })
check(B.is_closed("nanny:channels") and B.where("nanny:channels") == nil and hidden > 0, "the X closed Chat")
check(B.total("right") > 0 and B.where("nanny:status") ~= nil, "the rest of the panel stays")
check(B.byId["nanny:channels"] == nil, "a closed pane is not laid out")
MudletBorders = nil ; dofile(HERE .. "border.lua") ; B = MudletBorders
B.slot("elromap:map",   { cell="map", cross=0.5, title="Map", cb=cb })
B.slot("nanny:vitals",  { cell="bottom", cross=56, cb=cb, order=11 })
B.slot("nanny:status",  { cell="c1", cross=0.45, hint=180, title="Score", cb=cb, order=13 })
B.slot("nanny:party",   { cell="c1", cross=0.45, title="Party", cb=cb, order=14 })
hidden = 0
B.slot("nanny:channels", chat())
check(B.is_closed("nanny:channels") and B.where("nanny:channels") == nil and hidden > 0,
  "Chat is still closed after a restart, and its owner was told to hide it")
MX, MY = 100, 100
B.handles["title:nanny:status"]._click({ button = "RightButton" })
check(B.menuL[1]._echoed == "Show Chat" and B.menuL[2]._echoed == "Reset layout",
  "right-click on Score: Show Chat, Reset layout (" .. tostring(B.menuL[1]._echoed) .. ")")
B.menuL[1]._click()
check(not B.is_closed("nanny:channels") and B.where("nanny:channels") == "c2", "Show Chat put it back in c2")
B.handles["title:nanny:channels"]._click({ button = "RightButton" })
check(B.menuL[1]._echoed == "Hide Chat", "right-click on Chat offers to hide it")
B.menuL[1]._click()
check(B.is_closed("nanny:channels"), "Hide Chat closed it")
B.reset()
check(not B.is_closed("nanny:channels") and B.where("nanny:channels") == "c2", "a reset shows closed panes again")
local p2 = B.byId["nanny:party"] ; MX, MY = p2.x + 10, p2.y + 5
B.handles["title:nanny:party"]._click({ button = "LeftButton" })
check(B._drag ~= nil and B._drag.kind == "pane", "a left click on a strip still starts a drag")
B.drag_end()

-- 16. Mudlet's starter interface is asked to stand aside once per package, never when it is
-- already hidden, and not again after a restart (so 'baseui show' sticks)
local raised = {}
function raiseEvent(ev, arg) raised[#raised + 1] = ev .. ":" .. tostring(arg) end
check(not B.claim_screen("NannyBasics") and #raised == 0, "no starter interface, nothing asked")
local dormant = false
BaseUI = { dormant = function() return dormant end }
check(B.claim_screen("NannyBasics") and raised[#raised] == "sysServerGuiInstalled:NannyBasics",
  "asked it to stand aside for NannyBasics (" .. tostring(raised[#raised]) .. ")")
local n = #raised
check(not B.claim_screen("NannyBasics") and #raised == n, "not asked twice")
dormant = true
check(not B.claim_screen("ElrohirMapper") and #raised == n, "not asked when it is already hidden")
dormant = false
MudletBorders = nil ; dofile(HERE .. "border.lua") ; B = MudletBorders
check(not B.claim_screen("NannyBasics") and not B.claim_screen("ElrohirMapper") and #raised == n,
  "after a restart neither package asks again, so 'baseui show' sticks")
BaseUI = nil ; raiseEvent = nil

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
