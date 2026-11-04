-- mapcoins: in a maze of identical rooms, an empty room gets a number of coins no other has.
-- Run: luajit analysis/test_coins.lua      (from the client dir)

dofile("analysis/engine_load.lua")
reset_map()
addRoom(5) ; setRoomArea(5, addAreaName("town")) ; setRoomCoordinates(5, 0, 0, 0)
elro.cs_reset()

local fail, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    fail = fail + 1
    print(string.format("FAIL %-56s got %s want %s", what, tostring(got), tostring(want)))
  end
end

local sent, lineFn, promptFn, sendFn = {}, nil, nil, nil
local own = 0                                   -- prompts still owed for what the mode itself sent
cecho = function() end
send = function(s) sent[#sent + 1] = s ; own = own + 1 ; if sendFn then sendFn("sysDataSendRequest", s) end end
tempRegexTrigger = function(_, fn) lineFn = fn ; return 1 end
tempPromptTrigger = function(fn) promptFn = fn ; return 2 end
registerAnonymousEventHandler = function(_, fn) sendFn = fn ; return 3 end
killTrigger = function() end
killAnonymousEventHandler = function() end

local FOREST = "A deep forest."
-- the player types a command; the game answers with lines, then a prompt
local function drain() while own > 0 do own = own - 1 ; promptFn() end end
local function turn(cmd, lines)
  drain()
  sendFn("sysDataSendRequest", cmd)
  for _, l in ipairs(lines) do line = l ; lineFn() end
  promptFn()
end
local function room(...) return { FOREST, "You are lost in the forest.", ... } end

elro.cmd_coins("on")
eq(sent[1], "look", "switching on looks, to read the room's name")
own = 0
line = FOREST ; lineFn() ; line = "You are lost in the forest." ; lineFn() ; promptFn()
eq(elro.coins.name, FOREST, "...and takes its first line as the maze's name")

sent = {}
turn("east", room("30 gold coins."))
eq(#sent, 0, "a room with coins: nothing dropped")
eq(elro.coins.at, 30, "...it is known by its coins")
turn("e", room("A wasp called Pique."))
eq(sent[1], "drop 1", "an empty room: the lowest number not yet used")
eq(elro.coins.edges[30].east, 1, "the move between them is remembered, 'e' as east")
turn("west", room("30 gold coins."))
eq(elro.coins.edges[1].west, 30, "the way back too")
turn("north", { "You cannot go that way." })
eq(#sent, 1, "a failed move drops nothing")
eq(elro.coins.at, 30, "...and you are still in the room you were in")
turn("south", room())
eq(sent[2], "drop 2", "the next empty room gets the next number")
eq(elro.coins.edges[30].south, 2, "...linked from the room the wall did not move you out of")

-- typing ahead of a prompt: the drop's prompt must not be taken for the next move's answer
sendFn("sysDataSendRequest", "north")           -- before the prompt of 'drop 2'
own = own - 1 ; promptFn()
eq(elro.coins.walls[2], nil, "the drop's prompt does not close the move sent behind it")
for _, l in ipairs(room("1 gold coin.")) do line = l ; lineFn() end ; promptFn()
eq(elro.coins.edges[2].north, 1, "...the move is linked from the room it left")
turn("west", room("2 gold coins."))
eq(elro.coins.edges[1].west, 2, "a way that now leads elsewhere takes the new room")
eq(elro.coins.was[1].west, 30, "...and keeps what it did before")

-- moves in a burst are each followed in turn
drain() ; sendFn("sysDataSendRequest", "north")
sendFn("sysDataSendRequest", "west")
for _, l in ipairs(room("1 gold coin.")) do line = l ; lineFn() end ; promptFn()
for _, l in ipairs(room("30 gold coins.")) do line = l ; lineFn() end ; promptFn()
eq(elro.coins.at, 30, "a burst of moves ends in the right room")
eq(elro.coins.was[1].west, 2, "...each link from the room before it")

-- a move in flight behind a room with no coins: coins sent now would land in the next room
drain() ; sendFn("sysDataSendRequest", "north")
drain() ; sendFn("sysDataSendRequest", "north")
line = FOREST ; lineFn() ; promptFn()
eq(#sent, 2, "a command already in flight: nothing dropped")
eq(elro.coins.at, nil, "...and the room is unknown")
line = FOREST ; lineFn() ; promptFn()
eq(sent[3], "drop 3", "the next room is numbered, with no link")

turn("look", room())
eq(#sent, 3, "a look is not a move")

-- the drawing: COIN_BASE + coins, in its own area, placed by the walk
local B = elro.COIN_BASE
local caid = getRoomArea(B + 30)
eq(caid ~= nil and caid == getRoomArea(B + 1) and caid ~= getRoomArea(5), true, "coin rooms share an area of their own")
eq(getRoomExits(B + 30).east, B + 1, "the walked move is an exit")
eq(getRoomExits(B + 1).west, B + 30, "...both ways when walked both ways")
local x30, y30 = getRoomCoordinates(B + 30)
local x1, y1 = getRoomCoordinates(B + 1)
eq(x1 - x30 == 1 and y1 == y30, true, "east of a room is one step east")
local x2, y2 = getRoomCoordinates(B + 2)
eq(x2 == x30 and y2 == y30 - 1, true, "south of a room is one step south")
local x3, y3 = getRoomCoordinates(B + 3)
eq((x3 ~= x30 or y3 ~= y30) and (x3 ~= x1 or y3 ~= y1) and (x3 ~= x2 or y3 ~= y2), true,
   "a room with no known way in is put on a free spot")
eq(getRoomUserData(B + 2, "coinmaze"), "1", "coin rooms carry the property cleanup looks for")

-- walked, stayed or no move: a direction is tried. Only the untried ones carry a stub.
local stubs = {}
setExitStub = function(id, n, on) stubs[id] = stubs[id] or {} ; stubs[id][n] = on or nil end
getExitStubs = function(id) local t = {} ; for n in pairs(stubs[id] or {}) do t[#t + 1] = n end ; return t end
local at = elro.coins.at                        -- room 3, nothing tried from it yet
turn("north", { "You cannot go that way." })
eq(elro.coins.walls[3].north, true, "a move that shows no room is recorded on the room")
turn("east", room("3 gold coins."))
eq(elro.coins.edges[3].east, 3, "a move that lands in the same coins is a way back here")
local D = elro.dirNum
eq(stubs[B + 3][D.north], nil, "no stub where it did not move you")
eq(stubs[B + 3][D.east], nil, "no stub where it came back")
eq(stubs[B + 3][D.south], true, "a stub on the untested south")
eq(stubs[B + 3][D.west], true, "...and west")
eq(stubs[B + 1][D.east], true, "...on the other rooms too")
eq(stubs[B + 1][D.west], nil, "...but not on a way walked")
eq(stubs[B + 1][D.up], nil, "up is not offered until something goes up")
turn("up", room("3 gold coins."))
eq(stubs[B + 1][D.up], true, "walking up once offers it on every room")
eq(stubs[B + 3][D.up], nil, "...except where it was just tried")
turn("north", room("1 gold coin."))
eq(elro.coins.walls[3].north, nil, "a later move overrides 'no move'")
eq(elro.coins.edges[3].north, 1, "...with the room it reached")
eq(stubs[B + 3][D.north], nil, "...and takes no stub")
local shown = {}
local real_cecho = cecho
cecho = function(s) shown[#shown + 1] = s end
elro.cmd_coins("")
cecho = real_cecho
local listing = table.concat(shown)
eq(listing:find("back here: east, up", 1, true) ~= nil, true, "the list names ways back here")
eq(listing:find("untested: south, west", 1, true) ~= nil, true, "...and what is still untested, in compass order")
turn("south", room("3 gold coins."))

-- an exit that stops working: the newest answer wins, and the list says it changed
turn("east", { "You cannot go that way." })
eq(elro.coins.edges[3].east, nil, "a way that no longer moves you is no longer a way")
eq(elro.coins.walls[3].east, true, "...it is 'no move'")
eq(elro.coins.was[3].east, 3, "...and remembers what it did")
eq(getRoomExits(B + 3).east, nil, "...and its line is gone from the map")
shown = {}
cecho = function(s) shown[#shown + 1] = s end
elro.cmd_coins("")
cecho = real_cecho
eq(table.concat(shown):find("east was 3", 1, true) ~= nil, true, "the list names what changed")

-- only the game's own words are a wall: a room of another name is somewhere else
turn("south", room("3 gold coins."))
eq(elro.coins.edges[3].south, 3, "(south from 3 is a walked way)")
turn("south", { "A deep forest [h].", "You are lost in the forest." })
eq(elro.coins.walls[3].south, nil, "another room's name is not a wall")
eq(elro.coins.other[3].south, "A deep forest [h].", "...it is remembered by what it showed")
eq(elro.coins.at, nil, "...and where you are is unknown")
eq(elro.coins.edges[3].south, nil, "...and the way it replaced is gone")
eq(elro.coins.was[3].south, 3, "...and remembers what it did")
eq(#sent, 3, "...and nothing is dropped there")
shown = {}
cecho = function(s) shown[#shown + 1] = s end
elro.cmd_coins("")
cecho = real_cecho
eq(table.concat(shown):find("elsewhere: south 'A deep forest [h].'", 1, true) ~= nil, true, "the list names it")
turn("north", room("3 gold coins."))
eq(elro.coins.at, 3, "the next room with coins is known again")
eq(elro.coins.edges[3].north, 1, "...with no link made from nowhere")
drain() ; sendFn("sysDataSendRequest", "south")
promptFn()
eq(elro.coins.other[3].south, "A deep forest [h].", "a prompt with no output changes nothing")
eq(elro.coins.at, 3, "...and you are still where you were")
turn("south", { "You cannot go that way." })
eq(elro.coins.walls[3].south, true, "a later wall replaces it")
eq(elro.coins.other[3].south, nil, "...and clears what it showed")
turn("south", room("1 gold coin."))
eq(elro.coins.edges[3].south, 1, "a later move replaces the wall")
turn("east", room("3 gold coins."))
eq(elro.coins.at, 3, "(back in 3)")
turn("south", { "A deep forest [h]." })
turn("up", room("3 gold coins."))
turn("south", room("1 gold coin."))
eq(elro.coins.other[3].south, nil, "a later room clears what it showed")
turn("east", room("3 gold coins."))

-- the layout engine never lays the coin area out; an import never takes it
local laid = {}
local real_one = elro.layout_one
elro.layout_one = function(aid) laid[aid] = true end
elro.dirty[caid] = true ; elro.dirty[getRoomArea(5)] = true
elro.bgLayout = false
elro.flush_dirty()
elro.layout_one = real_one
eq(laid[caid], nil, "relayout skips the coin area")
eq(laid[getRoomArea(5)], true, "...and still lays out the others")
local snap = elro.import_snapshot()
eq(snap.rooms[B + 1], nil, "an import does not take coin rooms")
eq(snap.rooms[5] ~= nil, true, "...but does take real ones")
elro.recompute_areas()
eq(getRoomArea(B + 1), caid, "the area pass leaves coin rooms where they are")

-- the view: the game says "off the map" on every step of a blocked maze; the coin room wins
elro.current, elro.offmap = 5, 0
eq(elro.view_room(), B + 3, "the view stays on the coin room while off the map")
drain() ; sendFn("sysDataSendRequest", "north")
line = "You cannot go that way." ; lineFn() ; promptFn()
eq(elro.view_room(), B + 3, "a wall does not end it")
drain() ; sendFn("sysDataSendRequest", "north")
elro.offmap = nil
line = "A road." ; lineFn() ; promptFn()
eq(elro.coins.at, nil, "a real room named this turn: out of the maze")
eq(elro.view_room(), 5, "...and the view goes back to the map")
elro.offmap = 0
turn("west", room("1 gold coin."))
eq(elro.view_room(), B + 1, "back in the maze, the coin room again")
elro.offmap = nil
elro.coins_off()
eq(elro.view_room(), 5, "off hands the view back")
elro.cmd_coins("on " .. FOREST)

elro.cmd_coins("off")
turn("east", room())
eq(#sent, 3, "off: nothing dropped")
elro.cmd_coins("reset")
eq(next(elro.coins.used), nil, "reset forgets the numbers")
eq(roomExists(B + 1) or roomExists(B + 30), false, "...and deletes the coin rooms")
eq(elro.cs_areas()[elro.COIN_AREA], nil, "...and their area")
eq(roomExists(5), true, "...and nothing else")
elro.cmd_coins("on " .. FOREST)
eq(elro.coins.name, FOREST, "'on <name>' sets the name without a look")
eq(#sent, 3, "...and sends nothing")

print(string.format("test_coins: %d check(s), %d failure(s)", checks, fail))
os.exit(fail == 0 and 0 or 1)
