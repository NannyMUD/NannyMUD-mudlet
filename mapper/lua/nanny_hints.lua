-- NannyMUD's merge hints, shipped with the client: rooms the server files under one area that
-- belong on another area's map. The server sends no hints, so onRoom uses these in place of
-- the wire's mha= (a whole area) and mh= (one room, by its number in mapd's registry).
-- 'mapmerges' lists them; 'maphints off <area>' and 'mapunmerge' still overrule them.

elro = elro or {}

elro.shippedHints = {
  areas = {
    ingis    = "world",
    catwoman = "world",
    chrisp   = "world",
  },
  -- room number = "canvas"; look a number up in game with
  --   eval return "/obj/daemon/mapd"->query_known_id("<path>")
  rooms = {
    [660] = "world",   -- naketa's wedding shop
    [219] = "world",   -- taren's claim shop
    [156] = "world",   -- banshee's road room
    [213] = "world",   -- caution's hair salon
    [139] = "world",   -- a tsc path room
  },
}

-- a reload or mapupdate keeps the loaded hints: read them again, so a changed list takes hold
elro.hints_loaded = nil
