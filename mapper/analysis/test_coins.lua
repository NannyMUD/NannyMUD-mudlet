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

-- walked, stayed or no move: a direction is tried. Only the untried ones lead to the frontier,
-- and Mudlet's own stubs from an older map are taken off.
local F = elro.FRONTIER_ROOM
local stubs = { [B + 3] = { [elro.dirNum.south] = true } }
setExitStub = function(id, n, on) stubs[id] = stubs[id] or {} ; stubs[id][n] = on or nil end
getExitStubs = function(id) local t = {} ; for n in pairs(stubs[id] or {}) do t[#t + 1] = n end ; return t end
local function ex(id) return getRoomExits(id) or {} end
local at = elro.coins.at                        -- room 3, nothing tried from it yet
turn("north", { "You cannot go that way." })
eq(elro.coins.walls[3].north, true, "a move that shows no room is recorded on the room")
turn("east", room("3 gold coins."))
eq(elro.coins.edges[3].east, 3, "a move that lands in the same coins is a way back here")
eq(next(stubs[B + 3]), nil, "an old Mudlet stub is taken off")
eq(ex(B + 3).north, nil, "nothing where it did not move you")
eq(ex(B + 3).east, B + 3, "where it came back, the way back")
eq(ex(B + 3).south, F, "untested south leads to the frontier")
eq(ex(B + 3).west, F, "...and west")
eq(ex(B + 1).east, F, "...on the other rooms too")
eq(ex(B + 1).west, B + 30, "...but not on a way walked")
eq(ex(B + 1).up, nil, "up is not offered on every room")
turn("northeast", { "What?" })
turn("northwest", { "A deep forest [h]." })
turn("south", room("3 gold coins."))
eq(ex(B + 1).northeast, nil, "a wall does not offer its direction on every room")
eq(ex(B + 1).northwest, nil, "...nor does a way out of the maze")
turn("up", room("3 gold coins."))
eq(ex(B + 1).up, nil, "...not even once something went up")
eq(ex(B + 3).up, B + 3, "...but is shown where it was walked")
turn("north", room("1 gold coin."))
eq(elro.coins.walls[3].north, nil, "a later move overrides 'no move'")
eq(elro.coins.edges[3].north, 1, "...with the room it reached")
eq(ex(B + 3).north, B + 1, "...and leads there, not to the frontier")

-- each walked way leaves its room in its own direction and ends beside the room it reached
local lines = {}
addCustomLine = function(id, pts, d) lines[id] = lines[id] or {} ; lines[id][d] = pts ; return true end
getCustomLines = function(id) return lines[id] or {} end
removeCustomLine = function(id, d) if lines[id] then lines[id][d] = nil end end
turn("north", room("1 gold coin."))
local nl = lines[B + 3] and lines[B + 3].n
x3, y3 = getRoomCoordinates(B + 3)
x1, y1 = getRoomCoordinates(B + 1)
eq(nl ~= nil and nl[1][1] == x3 and nl[1][2] > y3, true, "the line for north leaves northward")
local last = nl and nl[#nl]
eq(last ~= nil and math.abs(last[1] - x1) < 0.6 and math.abs(last[2] - y1) < 0.6, true, "...and ends at the room it reached")
eq(lines[B + 3].e ~= nil, true, "a way back here is drawn as a loop")
eq(lines[B + 3].u, nil, "up has no line of its own")
local sl = lines[B + 3].s
eq(sl ~= nil and #sl == 2 and sl[2][2] - y3 > -0.5 and sl[2][2] < y3, true, "an untested way is a short line, short of half a cell")
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
eq(lines[B + 3].e, nil, "...the drawn one too")
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
local said = 0
elro.coins.lostSaid = nil                       -- as if lost without a word, e.g. typed ahead
local real_cecho2 = cecho
cecho = function(s) if s:find("position unknown", 1, true) then said = said + 1 end end
turn("north", { "In this cave, you can't determine directions." })
turn("north", { "In this cave, you can't determine directions." })
cecho = real_cecho2
eq(said, 1, "while lost, 'position unknown' is said once")
turn("north", room("3 gold coins."))
eq(elro.coins.at, 3, "the next room with coins is known again")
eq(elro.coins.edges[3].north, 1, "...with no link made from nowhere")
drain() ; sendFn("sysDataSendRequest", "south")
promptFn()
eq(elro.coins.other[3].south, "A deep forest [h].", "a prompt with no output changes nothing")
eq(elro.coins.at, 3, "...and you are still where you were")
turn("south", { "What?" })
eq(elro.coins.walls[3].south, true, "a later wall replaces it, 'What?' too")
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
eq(laid[caid], nil, "relayout skips the coin area")
eq(laid[getRoomArea(5)], true, "...and still lays out the others")
laid = {}
elro.cmd_coins("layout")
eq(laid[caid], true, "'mapcoins layout' has the engine lay it out")
eq(elro.coins.layoutOnce, nil, "...once")
laid = {}
elro.dirty[caid] = true
elro.flush_dirty()
eq(laid[caid], nil, "...and the next relayout skips it again")
elro.layout_one = real_one
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

-- a cave of forward, right, back and left: moves turn into compass directions from the facing,
-- and what the room says is in front, right and left marks its walls (from a live session)
elro.cmd_coins("reset")
elro.cmd_coins("on A dark room.")
local function cave(...) return { "A dark room.", "You are somewhere in a large cave with many rooms.", ... } end
local K = elro.coins
turn("forward", cave("In front of you is a cave wall, to your right is",
                     "an exit and to your left is a straight passage", "leading downward."))
local s1 = K.at
eq(K.heading, "north", "forward from the start: facing north")
eq(K.walls[s1].north, true, "'in front of you is a cave wall' is a wall")
eq(K.walls[s1].east == nil and K.walls[s1].west == nil, true, "...the exit and the passage are ways to try")
turn("right", cave("In front of you is a cave wall.", "53 gold coins."))
eq(K.edges[s1].east, 53, "right while facing north is east")
eq(K.heading, "east", "...and you face the way you went")
eq(K.walls[53].north and K.walls[53].south and K.walls[53].east, true, "sides not named are walls too")
turn("left", { "You walk into a wall." })
eq(K.at == 53 and K.heading == "east", true, "walking into a wall moves and turns nothing")
turn("back", cave("In front of you is a straight passage leading",
                  "downward and to your left is an exit.", s1 .. " gold coin" .. (s1 == 1 and "" or "s") .. "."))
eq(K.edges[53].west, s1, "back while facing east is west")
eq(K.heading, "west", "...and turns you round")
eq(K.walls[s1].south, nil, "the exit now on the left (south) is a way to try")
eq(K.walls[s1].north, true, "...and the wall stays")
turn("west", { "In this cave, you can't determine directions, so you can", "only move relative to your current heading." })
eq(K.at == s1 and (K.other[s1] or {}).west == nil and (K.walls[s1] or {}).west == nil, true,
   "in such a cave a compass word is no move and records nothing")
turn("turn left", { "What?" })
eq(K.heading, "west", "a turn the game does not know turns nothing")
turn("turn left", { "You turn left." })
eq(K.heading, "south", "a turn left while facing west faces south")
turn("forward", cave("In front of you is a cave wall."))
eq(K.edges[s1].south ~= nil, true, "...and forward then goes south")

-- a curving passage turns you while you walk it (the hole, from a live session)
elro.cmd_coins("reset")
elro.cmd_coins("on A dark room.")
K = elro.coins
turn("forward", { "A dark room.", "You are in a hole in a large cave.",
                  "In front of you is a cave wall and to your right", "the hole continues curving to the left." })
local h = K.at
local here
local real_cecho3 = cecho
cecho = function(s) if s:find("[maze] room", 1, true) then here = s end end
turn("right", cave("In front of you is an exit, to your right is a", "straight tunnel leading downward and to your left",
                   "is a straight wet tunnel."))
eq(K.edges[h].east ~= nil, true, "right from the hole facing north goes east")
eq(K.heading, "north", "...and the hole curving to the left leaves you facing north")
local p = K.at
local wp = K.walls[p] or {}
eq(wp.north == nil and wp.east == nil and wp.west == nil and K.desc[p].north:find("exit") ~= nil, true,
   "...so the room's sides are read from north")
eq(here and here:find("facing north: <green>untested: forward, right, left, back", 1, true) ~= nil, true,
   "each move says what is untested, by the words you move with: " .. tostring(here))
turn("left", { "You walk into a wall." })
cecho = real_cecho3
eq(here and here:find("untested: forward, right, back", 1, true) ~= nil and here:find("wall: left", 1, true) ~= nil,
   true, "...and a wall: " .. tostring(here))

-- a room seen before puts the facing right when it has gone wrong
K.heading = "west"                              -- as if a turn went unseen
local before = K.at
turn("back", cave("In front of you is an exit, to your right is a", "straight tunnel leading downward and to your left",
                  "is a straight wet tunnel.", p .. " gold coin" .. (p == 1 and "" or "s") .. "."))
eq(K.at == p and K.heading == "north", true, "the room's own words correct the facing: " .. tostring(K.heading))

-- a corridor reads the same from both ends: that is no reason to turn you
elro.cmd_coins("reset")
elro.cmd_coins("on A dark room.")
K = elro.coins
turn("forward", cave("In front of you is a straight passage."))
local c1 = K.at
turn("forward", cave("In front of you is a cave wall."))
turn("back", cave("In front of you is a straight passage.", c1 .. " gold coin" .. (c1 == 1 and "" or "s") .. "."))
eq(K.at == c1 and K.heading == "south", true, "walking back down a corridor keeps you facing south: " .. tostring(K.heading))
elro.cmd_coins("relearn")
eq(next(K.edges) == nil and K.used[c1] == true and getRoomExits(B + c1).north == F, true,
   "relearn forgets the ways and keeps the numbers")
drain() ; sent = {}
turn("forward", cave("In front of you is a cave wall."))
eq(sent[1] ~= nil and sent[1] ~= "drop " .. c1, true, "...so a new room never gets a number already lying somewhere: " .. tostring(sent[1]))

-- two-way: the way back is behind you, after a curve too; a pair is one line with no arrow
elro.cmd_coins("reset")
elro.cmd_coins("on A dark room.")
elro.cmd_coins("twoway on")
K = elro.coins
turn("forward", { "A dark room.", "You are in a hole in a large cave.",
                  "In front of you is a cave wall and to your right", "the hole continues curving to the left." })
h = K.at
turn("right", cave("In front of you is an exit."))
p = K.at
eq(K.edges[h].east, p, "(right from the hole is east)")
eq(K.edges[p].south, h, "two-way: behind you after the curve leads back")
eq(ex(B + p).north, F, "a new room shows its untested ways at once")
eq(lines[B + p] and lines[B + p].n ~= nil, true, "...drawn")
local pl, ph = lines[B + h] and lines[B + h].e, lines[B + p] and lines[B + p].s
eq(pl ~= nil and #pl >= 3 and ph ~= nil and #ph == 2, true, "a pair is one line from one end, nothing from the other")
turn("back", { "You walk into a wall." })
eq(K.edges[p].south == nil and K.walls[p].south == true, true, "a wall where two-way guessed a way back replaces the guess")
elro.cmd_coins("twoway off")
eq(K.twoway, false, "'twoway off' switches it off")

-- go: a step at a time to the nearest room with an untested way, in the words you move with
elro.cmd_coins("reset")
elro.cmd_coins("on " .. FOREST)
K = elro.coins
K.used = { [1] = true, [2] = true, [3] = true }
K.edges = { [1] = { east = 2 }, [2] = { west = 1, east = 3 }, [3] = { west = 2 } }
K.walls = { [1] = { north = true, south = true, west = true }, [2] = { north = true, south = true } }
K.at = 1
drain() ; sent = {}
elro.cmd_coins("go")
eq(sent[1], "east", "go: the first step toward the nearest untested way")
for _, l in ipairs(room("2 gold coins.")) do line = l ; lineFn() end ; promptFn()
eq(sent[2], "east", "...the next step is chosen on arrival")
for _, l in ipairs(room("3 gold coins.")) do line = l ; lineFn() end ; promptFn()
eq(#sent == 2 and K.walk == nil, true, "...and it stops in the room with untested ways")
elro.cmd_coins("go 1")
eq(sent[3], "west", "go <n>: toward that room")
sendFn("sysDataSendRequest", "look")
eq(K.walk, nil, "anything typed by hand stops the walk")
K.relSeen, K.heading, K.at, K.q = true, "east", 3, {}
sent = {}
elro.cmd_coins("go 1")
eq(sent[1], "back", "in a cave of forward and back, the step is said that way")

print(string.format("test_coins: %d check(s), %d failure(s)", checks, fail))
os.exit(fail == 0 and 0 or 1)
