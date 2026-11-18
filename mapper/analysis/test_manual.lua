-- mapmanual: a maze learned from what its rooms show, look-alike rooms told apart by the walk.
--   luajit analysis/test_manual.lua

dofile("analysis/engine_load.lua")

local fail, ntest = 0, 0
local function eq(got, want, what)
  ntest = ntest + 1
  if got ~= want then
    fail = fail + 1
    print(string.format("  FAIL: %s -- got %s want %s", what, tostring(got), tostring(want)))
  end
end

-- map user data, special exits and hooks, as Mudlet keeps them
local UD, SPX = {}, {}
function getMapUserData(k) return UD[k] or "" end
function setMapUserData(k, v) UD[k] = v end
function addSpecialExit(a, b, cmd) SPX[a] = SPX[a] or {} ; SPX[a][cmd] = b end
function removeSpecialExit(a, cmd) if SPX[a] then SPX[a][cmd] = nil end end
function getSpecialExits(a)
  local t = {}
  for cmd, b in pairs(SPX[a] or {}) do t[b] = { [cmd] = "0" } end
  return t
end
function tempRegexTrigger() return 1 end
function tempPromptTrigger() return 2 end
function registerAnonymousEventHandler() return 3 end
function killTrigger() end
function killAnonymousEventHandler() end
elro.flush_dirty = function() end

local M = elro.manual
local function room(name, exits) return { name, "Reality seems thin here.", "  There are some obvious exits: " .. exits } end

-- one command: what was sent, then the lines that came back, then the prompt
local function step(cmd, lines)
  M.sent(cmd)
  for _, l in ipairs(lines) do M.line(l) end
  M.prompt()
end

local function fresh()
  reset_map() ; elro.cs_reset()
  for k in pairs(UD) do UD[k] = nil end
  for k in pairs(SPX) do SPX[k] = nil end
  M.data, M.areas, M.learn, M.last, M.belief, M.here, M.view, M.q = {}, nil, nil, nil, nil, nil, nil, {}
  M.res, M.blk, M.names, M.twoway = {}, {}, nil, nil
  elro.smap = {}
  elro.offmap = 0
end

local function rooms_of(area)
  local n = 0
  for id in pairs(getRooms()) do if getRoomUserData(id, "manual") == area then n = n + 1 end end
  return n
end

-- the key: first line and exits, a wrapped exit line joined, the order of the exits fixed
do
  fresh()
  M.sent("look")
  M.line("!!SOUND(combat/default/miss* V=50 L=1 P=50 T=sound)")
  M.line("** HP: 159/244   SP: 244/244")
  M.line("A small cyan room.")
  M.line("  There are six obvious exits: east, south, down, meta-south, meta-east")
  M.line("            and meta-up.")
  M.line("Gerda the grumpy cook.")
  eq(M.res[1] and M.res[1].k, "A small cyan room.\tdown,east,meta-east,meta-south,meta-up,south",
     "a wrapped exit line, a sound code skipped")
end

-- the walk from the maze itself
do
  fresh()
  elro.cmd_manual("on blue maze")
  local blue1 = room("A small blue room.", "west, north and south.")
  local white = room("A small white room.", "west, south and up.")
  local red1 = room("A small red room.", "west, south and down.")
  local green1 = room("A small green room.", "east, south and meta-north.")
  local cyan = room("A small cyan room.", "east, south, down, meta-south, meta-east and meta-up.")
  local blue2 = room("A small blue room.", "east and up.")
  local green2 = room("A small green room.", "west and up.")
  local yellow = room("A small yellow room.", "west, south and down.")
  local red2 = room("A small red room.", "west and north.")
  local green3 = room("A small green room.", "east, north and down.")
  step("look", blue1)
  step("north", white)
  step("north", { "You walk into a wall." })
  step("up", red1)
  step("west", green1)
  step("meta-north", cyan)
  step("down", blue2)
  step("east", green2)
  step("up", yellow)
  step("west", cyan)
  step("east", yellow)
  step("south", red2)
  step("west", green3)
  eq(rooms_of("blue maze"), 10, "ten rooms: the cyan and the yellow room each seen twice")
  local D = M.data["blue maze"]
  local S = D.S
  local function id_at(g) return S.id[S.find(g)] end
  -- rooms seen, in order (the wall is no room): blue white red green cyan blue green yellow
  -- cyan yellow red green
  eq(id_at(5), id_at(9), "the cyan room met again is the same room")
  eq(getRoomExits(id_at(9)).down, id_at(6), "down from the cyan room")
  local spx = SPX[id_at(4)] or {}
  eq(spx["meta-north"], id_at(5), "meta-north is a special exit")
  eq(elro.smap[id_at(4) .. ":" .. id_at(5)], "meta-north", "and the mapper's command record")
  eq(getRoomExits(id_at(2)).north, nil, "the wall is no exit")
  eq(getRoomExits(id_at(1)).south, elro.FRONTIER_ROOM, "a named exit not walked is unexplored")
  eq(M.view, id_at(12), "the view follows")
  -- ways not yet walked that no stub can show: the glyph, in the untried colour
  local function glyph(g) return harness_map().rooms[id_at(g)].ch end
  local function untried(g)
    local c, u = harness_map().rooms[id_at(g)].chcol, elro.classColours.untried
    return c ~= nil and c[1] == u[1] and c[2] == u[2] and c[3] == u[3]
  end
  eq(glyph(3), "D", "the red room's down, never walked, shows")
  eq(untried(3), true, "in the untried colour")
  eq(glyph(5), "M", "the cyan room's meta exits")
  eq(untried(5), true, "two of them never walked")
  eq(glyph(4), "M", "the green room's meta-north")
  eq(untried(4), false, "walked: the usual colour")
  eq(glyph(2) or "", "", "the white room's up was walked: no glyph")
end

-- two rooms that look alike, told apart when the walk shows they differ
local A = room("A grey room.", "east and west.")
local B = room("A plain room.", "east and west.")
local C = room("A dark room.", "east and west.")
do
  fresh()
  elro.cmd_manual("on twins")
  step("look", A)
  step("east", B)
  step("east", A)
  eq(rooms_of("twins"), 3, "the second grey room is two steps east of the first: proven another room")
  local first = M.data.twins.S.id[1]
  step("east", C)
  eq(rooms_of("twins"), 4, "east led elsewhere: two grey rooms")
  local S = M.data.twins.S
  eq(S.id[S.find(1)], first, "the first grey room keeps its number")
  eq(S.find(3) ~= S.find(1), true, "the second grey room is its own")
  eq(getRoomExits(S.id[S.find(3)]).east, S.id[S.find(4)], "its east leads to the dark room")
  -- kept with the map: worked out again from what was saved, the same rooms
  M.data = {}
  M.learn = nil
  local D = M.data.twins
  eq(D, nil, "forgotten in memory")
  elro.cmd_manual("off")
  M.belief = nil
  step("look", A)
  eq(M.belief and #M.belief, 2, "located: one of two grey rooms")
  step("east", C)
  eq(M.view, M.data.twins.S.id[M.data.twins.S.find(4)], "east to the dark room tells which")
  eq(rooms_of("twins"), 4, "locating adds nothing")
end

-- the grid: a step is a fixed move, and look-alikes the walk places apart are two rooms. A warp
-- (a loop that comes back to the start in one step east) makes a second copy; 'same' joins it.
do
  fresh()
  elro.cmd_manual("on warp")
  local P = room("A pale room.", "east.")
  local Q = room("A quiet room.", "east.")
  step("look", P)
  step("east", Q)
  step("east", P)                            -- the maze warps back to the pale room
  step("east", Q)
  eq(rooms_of("warp"), 4, "strict grid: every step east lands somewhere new")
  local S = M.data.warp.S
  local p1, p2 = S.id[S.find(1)], S.id[S.find(3)]
  elro.cmd_manual("same " .. p1 .. " " .. p2)
  eq(rooms_of("warp"), 2, "'same' joins the two pale rooms, and the quiet rooms after them follow")
  S = M.data.warp.S
  eq(getRoomExits(S.id[S.find(2)]).east, S.id[S.find(1)], "the quiet room's east warps back to the pale room")
  -- kept with the walk, and worked out again the same
  M.data = {}
  local D = load and nil
  elro.cmd_manual("off") ; elro.cmd_manual("on warp")
  step("look", P)
  eq(rooms_of("warp"), 2, "the pair is kept with the map")
end

-- 'same' refuses rooms whose ways differ: their own walks prove them two rooms
do
  fresh()
  elro.cmd_manual("on apart")
  local G = room("A green room.", "east and west.")
  local R = room("A red room.", "east and west.")
  local Y = room("A yellow room.", "east and west.")
  step("look", G)
  step("east", R)
  step("east", G)
  step("east", Y)
  step("west", G) ; step("west", R) ; step("west", G)
  step("west", Y)                            -- west of the first green room: yellow, not red
  local S = M.data.apart.S
  local g1, g2 = S.id[S.find(1)], S.id[S.find(3)]
  local before = rooms_of("apart")
  elro.cmd_manual("same " .. g1 .. " " .. g2)
  eq(rooms_of("apart"), before, "their ways differ: 'same' is refused, nothing joined")
  eq(#M.data.apart.same, 0, "...and the pair is not kept")
end

-- moved without a command of ours (a flee, a summons): no edge from where we were
do
  fresh()
  elro.cmd_manual("on moved")
  local H = room("A hall.", "north.")
  local K = room("A kitchen.", "south.")
  local W = room("A well.", "east.")
  step("look", H)
  for _, l in ipairs(W) do M.line(l) end     -- a room shown with nothing of ours waiting
  M.prompt()
  step("north", K)                           -- typed in the well, though we thought the hall
  local S = M.data.moved.S
  eq(getRoomExits(S.id[S.find(1)]).north ~= S.id[S.find(2)], true,
     "the hall's north is not the kitchen: we were moved away from the hall")
  eq(M.data.moved.nodes[2].s, true, "...the kitchen starts a walk of its own")
end

-- a way that led one place again and again and then another: that step is skipped, learning goes on
do
  fresh()
  elro.cmd_manual("on moving")
  local X = room("A round room.", "east.")
  local Y = room("A square room.", "west.")
  step("look", X)
  for _ = 1, 3 do step("east", Y) ; step("west", X) end
  local steps = #M.data.moving.nodes
  step("east", C)
  eq(M.learn, "moving", "learning goes on")
  eq(rooms_of("moving"), 2, "nothing is split")
  eq(#M.data.moving.nodes, steps, "the odd step is not kept")
  step("look", X)
  step("east", Y)
  eq(M.view, M.data.moving.S.id[M.data.moving.S.find(2)], "found again by walking on")
end

-- learning survives a restart: the maze being learned is kept with the map
do
  fresh()
  elro.cmd_manual("on kept")
  M.learn = nil
  M.boot()
  eq(M.learn, "kept", "learning again after a restart")
  elro.cmd_manual("off")
  M.boot()
  eq(M.learn, nil, "and off stays off")
end

-- a follower's arrival brings a prompt of its own; commands typed ahead still pair with their rooms
do
  fresh()
  elro.cmd_manual("on ahead")
  local P = room("A pale room.", "north.")
  local Q = room("A grey room.", "south and up.")
  local R = room("A dark room.", "down.")
  step("look", P)
  M.sent("north") ; M.sent("west") ; M.sent("up")
  for _, l in ipairs(Q) do M.line(l) end
  M.line("Rex arrives.") ; M.prompt()
  M.prompt()
  M.line("You walk into a wall.") ; M.prompt()
  for _, l in ipairs(R) do M.line(l) end
  M.line("Rex arrives.") ; M.prompt()
  local D = M.data.ahead
  local S = D.S
  local function id(g) return S.id[S.find(g)] end
  eq(getRoomExits(id(1)).north, id(2), "north to the grey room")
  eq(getRoomExits(id(2)).up, id(3), "up from it, though a wall and an extra prompt came between")
  eq(D.nodes[2].w and D.nodes[2].w.west, true, "the wall was west's")
  -- the extra room of a wrong pairing, forgotten: its sightings go, the rest folds back
  local before = rooms_of("ahead")
  elro.cmd_manual("forget " .. id(3))
  eq(rooms_of("ahead"), before - 1, "forget drops the room")
  eq(getRoomExits(id(2)).up, elro.FRONTIER_ROOM, "and the way into it is untried again")
end

-- chatter between commands is never a room's name; a look where you stand adds nothing
do
  fresh()
  elro.cmd_manual("on chatter")
  local P = room("A pale room.", "east.")
  step("look", P)
  M.line("** HP: 169/244   SP: 244/244")
  M.line("Bob grins widely at nobody in particular.")
  M.prompt()
  step("l", P)
  eq(rooms_of("chatter"), 1, "still one room")
  eq(#M.data.chatter.nodes, 1, "and one sighting")
end

-- xml mode: the tagged name and exits, the same keys as plain mode, chatter never a name
do
  fresh()
  elro.cmd_manual("on tagged")
  step("look", room("A small green room.", "meta-north, meta-west and meta-down."))
  M.sent("meta-north")
  M.line("<prompt>> </prompt>Bob grins widely.")
  M.line("<short>A small cyan room</short>.")
  M.line("<long>A small cyan room with an odd set of dimensions. Reality seems to have a very")
  M.line("thin quality about it here.</long>")
  M.line("<exit>  There are four obvious exits: west, south, meta-south and meta-down.</exit>")
  M.line("<monster_enter>Rex arrives.</monster_enter>")
  M.prompt()
  local D = M.data.tagged
  eq(D.keys[D.nodes[2].k], "A small cyan room.\tmeta-down,meta-south,south,west", "the tagged room, read as plain")
  M.sent("meta-south")
  M.line("<short>A small green room</short>.")
  M.line("<exit>  There are three obvious exits: meta-north, meta-west and meta-down.</exit>")
  M.prompt()
  eq(rooms_of("tagged"), 2, "the green room from plain mode is the same room in xml mode")
  step("meta-north", room("A small cyan room.", "west, south, meta-south and meta-down."))
  eq(M.xml, nil, "a room without tags: plain mode again")
  eq(rooms_of("tagged"), 2, "and still the same rooms")
end

-- the tags cut from the screen: where each one is, counted from 0
do
  local X = NannyXml
  local sp = X.plan("<short>A small cyan room</short>.")
  eq(#sp, 2, "two tags")
  eq(sp[1][1] == 0 and sp[1][2] == 7, true, "<short> at the start")
  eq(sp[2][1] == 24 and sp[2][2] == 8, true, "</short> before the full stop")
  eq(#X.plan("give <item> to <player>"), 0, "no close: game text, kept")
  eq(#X.plan("<long>A small room with an odd set of dimensions."), 1, "a known open, cut at once")
  eq(#X.plan("<aura>It glows faintly"), 0, "an unknown open is kept until proven")
  eq(#X.plan("and hums.</aura>"), 1, "its close proves it")
  eq(#X.plan("<aura>Again.</aura>"), 2, "and from then on it is known")
  eq(#X.plan("<b>bold</b> text"), 2, "a pair on one line")
  local snd, empty = X.plan('<sound class="combat/default/miss*" kind="sound" volume="50" repeats="1" priority="50"/>')
  eq(#snd == 1 and empty, true, "a self-closing sound tag: the whole line goes")
  local _, e2 = X.plan("<short>A small room</short>.")
  eq(e2, false, "a line with text left is kept")
end

-- two-way: the way back is assumed where the room lists it; a walk overrides it, never splits
do
  fresh()
  elro.cmd_manual("on back")
  local P = room("A pale room.", "east and meta-north.")
  local Q = room("A grey room.", "west.")
  local R = room("A dark room.", "meta-south and down.")
  step("look", P)
  step("east", Q)
  step("west", P)
  step("meta-north", R)
  local S = M.data.back.S
  local function id(g) return S.id[S.find(g)] end
  eq(getRoomExits(id(4)).down, elro.FRONTIER_ROOM, "two-way off: nothing assumed")
  eq((SPX[id(4)] or {})["meta-south"], nil, "nor a meta way back")
  elro.cmd_manual("twoway on")
  S = M.data.back.S
  eq((SPX[id(4)] or {})["meta-south"], id(1), "two-way on: meta-south back to where meta-north came from")
  eq(rooms_of("back"), 3, "no room made or split by it")
  eq(M.reverse("meta-up"), "meta-down", "the prefixed way back")
  elro.cmd_manual("twoway off")
  S = M.data.back.S
  eq((SPX[id(4)] or {})["meta-south"], nil, "and off again")
end

-- 'mapmanual on' with no name takes up the last maze learned, after a restart too
do
  fresh()
  elro.cmd_manual("on cube")
  elro.cmd_manual("off")
  M.lastArea, M.learn = nil, nil
  elro.cmd_manual("on")
  eq(M.learn, "cube", "the last maze is kept with the map")
end

-- locating speaks only when you were surely in the maze
do
  fresh()
  elro.cmd_manual("on quiet")
  local P = room("A beach.", "east and west.")
  local Q = room("A dune.", "west.")
  step("look", P)
  step("east", Q)
  step("west", P)
  elro.cmd_manual("off")
  M.belief = nil
  local said = {}
  local real = cecho
  cecho = function(s) said[#said + 1] = s end
  step("look", room("A jungle.", "north."))
  eq(#said, 0, "a room no maze knows, coming from nowhere known: silent")
  step("look", Q)
  step("west", room("A swamp.", "east."))
  eq(#said, 1, "from a known room into an unknown one: said once")
  step("east", room("A marsh.", "west."))
  eq(#said, 1, "and not again until found")
  cecho = real
end

-- off the map: the game's own rooms end it
do
  fresh()
  elro.cmd_manual("on blue")
  step("look", room("A small blue room.", "west."))
  elro.offmap = nil
  step("west", { "Somewhere mapped." })
  eq(M.view, nil, "back on the map")
  eq(M.last, nil, "the walk is broken there")
end

print(string.format("test_manual: %d check(s), %d failure(s)", ntest, fail))
os.exit(fail == 0 and 0 or 1)
