# The shared layout (`border.lua`)

The map and the NannyBasics panes sit in panels beside the text, and players can drag them
around and resize them. That is one small Lua library, `border.lua`, which any package can use
to put its own windows into the same layout. This page is for developers who want to do that.

## The idea

Mudlet's main window has four borders (`setBorderLeft` and friends) that push the text inward.
Only one script can own them sensibly, so `border.lua` owns them for everybody: packages do not
call `setBorder*` or position their own windows. Instead each package **registers a pane** and
gets told where to draw it.

- Each **edge** (left, right, top, bottom) holds a **layout tree**: nested splits whose leaves
  are named **cells**. The default right edge is the map on top, over two columns (`c1`, `c2`).
- A cell holds **panes**, stacked: top to bottom on the left and right edges, left to right on
  the top and bottom edges.
- A pane with a **title** gets a thin strip above it. Players drag a pane by its strip: onto
  another pane to stack with it, near a pane's edge to split that space, or to an empty window
  edge to open a panel there.
- Thin **bars** between panes, between split columns, and at each panel's inner edge resize
  things.
- Sizes and places are saved in the profile (`MudletBorders.lua`) and come back after a
  restart. Left and right panels never take more than the window minus a minimum for the text
  (25%); the same goes for top and bottom.

The default cells are `left`, `top`, `bottom`, `map`, `c1` and `c2`. More appear when players
split things; a pane always remembers where it was put.

## A minimal pane

```lua
-- one container per pane, positioned by the layout; build your widgets inside it
local box = Geyser.Container:new({ name = "MyPkg_box", x = 0, y = 0, width = 100, height = 100 })
local text = Geyser.Label:new({ name = "MyPkg_text", x = 0, y = 0,
                                width = "100%", height = "100%" }, box)

MudletBorders.slot("mypkg:notes", {
  cell  = "c2",         -- where it starts the first time; the player's later moves win
  cross = 0.3,          -- the panel thickness it would like (0..1 = share of the window, else px)
  hint  = nil,          -- a fixed content size along the stack (px or share); nil = share the rest
  order = 50,           -- position within its cell, lower first
  title = "Notes",      -- a title strip to drag it by (Qt rich text: escape < > &)
  cb = function(x, y, w, h)
    box:show() ; box:move(x, y) ; box:resize(w, h)
  end,
})
```

`cb` is called on every layout pass (window resize, drag, another package's pane appearing),
with the rectangle below the title strip, in the same coordinates as `getMainWindowSize()`.
It must only position things. Do not call `slot`, `move` or `park` from inside it. Errors in
`cb` are caught and dropped, so a broken `cb` shows up as a pane that stays put, not as an error
message.

Give your panes ids with your package's name in front (`mypkg:...`), since every package shares
one layout.

## The functions

All on the global `MudletBorders`.

| Call | What it does |
|---|---|
| `slot(id, spec)` | Add a pane, or update an existing one's spec (`cell`, `cross`, `hint`, `order`, `title`, `cb`). A pane that was parked comes back where it was. |
| `park(id)` | Hide a pane but remember its place; `slot` brings it back there. |
| `remove(id)` | Take a pane out of the layout altogether (for example when your package is uninstalled). |
| `move(id, cell)` | Put a pane in another cell, as a drag would. |
| `where(id)` | The cell a pane is in, or nil when it is parked. |
| `parked_cell(id)` | The cell a parked pane will come back to. |
| `cells()` | Every cell name in the current layout. |
| `edge_of(cell)` | Which edge a cell is on. |
| `total(edge)` | How thick that edge's panel is right now, in px (0 when empty). |
| `set_title(id, title)` | Change a pane's strip text. Cheap: it does not lay anything out again. |
| `set_hint(id, hint)` | Change a pane's fixed size, for content that grew. |
| `clear_width(edge)` | Forget a dragged panel width, so the panes' own `cross` applies again. |
| `is_dragging()` | True while the player is dragging something. Skip expensive work in `cb` then; a final pass follows the drop. |
| `reset()` | The default layout again: default tree, no dragged sizes, every pane in its own `cell`. |
| `suspend()` / `resume()` | Hand every border back to the text and hide all panes (for a second session in MultiView), or bring them back. Saved per profile. |
| `is_suspended()` | Whether that is in force. |

The event `MudletBordersChanged` is raised after a player drops a pane somewhere and after
`reset()`. Listen for it when a pane should change its own size or content with its new place
(NannyBasics uses it to give a pane the right `cross` for the edge it landed on).

## Shipping it

Every package that uses the layout carries its own copy of `border.lua`, and must load it before
calling `MudletBorders`. The copies may differ in age: each has a `local REV = n` near the top,
and **the newest copy wins**, whatever order the packages load in. An older copy loading later
changes nothing.

That only works if the library stays compatible:

- **Raise `REV`** with every change to `border.lua`, and copy the new file into every package in
  this repo that carries it (NannyBasics' build refuses to build if its copy and the mapper's
  differ, or if the file changed without a higher `REV`).
- **Only add.** Older packages keep calling the functions above with the meanings above. A
  change that has to break something gets a new global name instead of a higher `REV`, so old
  and new packages each get the library they were written for.
- `border.lua` ends with `return MudletBorders`. If you paste it into a single script (as
  NannyBasics' `build.py` does for its XML), wrap it: `(function() ... end)()`, or the `return`
  ends your script early.

## Things that bite

- **Geyser does not clip.** A child that is bigger than its container draws over whatever is
  next to it, including the drag bars, which then cannot be grabbed. Lay your widgets out from
  the `w` and `h` you are given, and hide what does not fit.
- **Negative sizes are not "fill".** In Geyser, `height = -20` means "end 20 px above the
  parent's bottom", which leaves a dead strip. To fill the space below a header, compute the
  height from `h` yourself.
- **Reloading keeps your widgets.** Geyser windows survive a script reload, and creating one
  again under the same name misbehaves. Create them once (keep them in a global table) and only
  refresh styles and callbacks on reload.
- **Uninstalling.** Mudlet does not remove your windows when your package is uninstalled.
  Handle `sysUninstallPackage` for your own package name: `remove` your panes and hide your
  containers, or they stay on screen until Mudlet restarts.
