-- A chat tab pulled out into a pane of its own and put back, against stubbed Mudlet globals.
--   luajit basics/tests/test_chatsplit.lua
local any ; any = setmetatable({}, { __index = function() return any end, __call = function() return any end })
setmetatable(_G, { __index = function(_, k) return function() return any end end })
Geyser = any
gmcp = {}
NannyBasics, MudletBorders = {}, {}
local HOME = os.getenv("TEMP") or os.getenv("TMPDIR") or "."
os.remove(HOME .. "/nanny_chatsplit.txt")
function getMainWindowSize() return 2560, 1143 end
function getMudletHomeDir() return HOME end
function calcFontSize() return 8, 15 end
local mouse = { 100, 100 }
function getMousePosition() return mouse[1], mouse[2] end
yajl = { to_string = function() return "{...}" end }
local timers = {}
function tempTimer(_, fn) timers[#timers + 1] = fn ; return #timers end
function killTimer() end

local HERE = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "../"
dofile(HERE .. "border.lua")
dofile(HERE .. "nannybasics.lua")
local N, B = NannyBasics, MudletBorders

local fails = 0
local function check(ok, msg) print((ok and "ok   " or "FAIL ") .. msg) ; if not ok then fails = fails + 1 end end

N.chatBox = N.chatBox or any
N.channel({ channel = "gossip", talker = "Bob", text = "Bob gossips: hi" })
check(N.tabs.gossip ~= nil and not N.split.gossip, "a channel's first message makes its tab")

-- a click without moving selects the tab
N.tab_press("gossip", { button = "LeftButton" })
N.tab_release("gossip", { button = "LeftButton" })
check(N.current == "gossip" and not N.split.gossip, "a click selects the tab")

-- press and move: the tab is pulled out and the drag goes on as a pane drag
mouse = { 100, 100 }
N.tab_press("gossip", { button = "LeftButton" })
mouse = { 104, 103 }
N.tab_drag_tick()
check(not N.split.gossip, "a few pixels is still a click")
mouse = { 140, 160 }
N.tab_drag_tick()
check(N.split.gossip == true, "moved further: the tab has its own pane")
check(B.slots[N.split_id("gossip")] ~= nil, "...registered as a pane")
check(B._drag and B._drag.id == N.split_id("gossip"), "...and dragged as one")
N.tab_release("gossip", { button = "LeftButton" })
check(B._drag == nil, "the release ends the drag")
check(N.current ~= "gossip", "the chat pane shows another tab")

-- remembered
local fh = io.open(HOME .. "/nanny_chatsplit.txt", "r")
local saved = fh and fh:read("*a") ; if fh then fh:close() end
check(saved == "gossip", "kept in the profile: " .. tostring(saved))

-- its messages go on reaching it and All
local before = #N.tabs.gossip.hist
N.channel({ channel = "gossip", talker = "Bob", text = "Bob gossips: again" })
check(#N.tabs.gossip.hist == before + 1, "a split tab still gets its channel")
N.select("gossip")
check(N.current ~= "gossip", "a split tab is never selected in the chat pane")

-- dropped onto the chat pane: back among the tabs
local slot = B.slots[N.split_id("gossip")]
N.over_chat = function() return true end
check(slot.on_drop(500, 500) == true and not N.split.gossip, "dropped onto Chat: back in")
check(B.slots[N.split_id("gossip")] == nil, "...and no longer a pane")
check(N.current == "gossip", "...selected")

-- right-click offers its own pane; the strip's menu offers the way back
local offered
local real_popup = B.popup
B.popup = function(items) offered = items end
N.tab_press("gossip", { button = "RightButton" })
check(offered and offered[1][1] == "Own pane", "right-click on a tab: 'Own pane'")
offered[1][2]()
check(N.split.gossip == true, "...which splits it")
check(B.slots[N.split_id("gossip")].menu[1][1] == "Back into Chat", "the pane's strip offers 'Back into Chat'")
B.popup = real_popup
N.tab_press("All", { button = "LeftButton" })
mouse = { 300, 300 }
N.tab_drag_tick()
check(not N.split.All, "All cannot be pulled out")
N.tab_release("All", { button = "LeftButton" })

-- by command
N.cmd("chat join Gossip")
check(not N.split.gossip, "'nanny chat join' puts it back, any case")
N.cmd("chat split gossip")
check(N.split.gossip == true, "'nanny chat split'")
N.cmd("chat join gossip")

os.remove(HOME .. "/nanny_chatsplit.txt")
print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
