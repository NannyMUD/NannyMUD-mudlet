# NannyBasics

A small Mudlet package for [NannyMUD](https://nannymud.lysator.liu.se/) that draws the
game's GMCP data: health and spell-point gauges, your current foe, a score card, your party,
your guild, and channel messages in a tabbed window. Separate from the map; install both if
you want both, and they share one layout.

## What you get

- **Vitals bar** under the main text: HP and SP gauges that update as you fight and heal.
  The HP bar pulses, faster and brighter the lower it gets, once you drop below 40%. Above
  them, a **foe gauge**: who you are fighting and the shape they are in.
- **Score card**: your name, level and guild, an XP bar that fills within your level (at
  level 19 it shows your paragon level and the free experience toward the next), gauges for
  toxicity, fullness, soak and carried weight, and gold, quest points, XP per hour and stats.
- **Party pane**: one row per member with HP and SP gauges, marked when they lead, follow,
  never follow, or are elsewhere.
- **Guild pane**, for the Strigoi so far: guild level and points, penalty, wasp, your stack,
  and your stats with the guild's changes and harvest gains shown beside each.
- **Chat pane**: one tab per channel, plus an "All" tab. A tab that gets a message while you
  are reading another one lights up.
- **GMCP log**, hidden by default (`nanny log`), for seeing the raw data.

## Install

Download `NannyBasics.xml` from [Releases](https://github.com/NannyMUD/NannyMUD-mudlet/releases) and drag it onto the Mudlet
window.

**Updating.** When a newer release is out, NannyBasics says so shortly after Mudlet starts.
Type `nanny update`: it downloads the new package and swaps it in, and if the download fails
nothing is changed. Your layout is kept.

Then, in the game, switch on what you want. Each setting is remembered when you log in again:

```
toggle gmcp            GMCP itself (Mudlet has it on by default)
toggle gmcp vitals     the HP/SP gauges and the body gauges
toggle gmcp foe        the foe gauge
toggle gmcp channels   the chat pane
toggle gmcp status     the score card
toggle gmcp group      the party pane
toggle gmcp discord    Discord status from your client
toggle strigoi gmcp    the guild pane, for the Strigoi
```

## Layout

The panes sit in a panel beside the text, by default in two columns under the map if you use
[the mapper](../mapper), with the vitals bar along the bottom.

- Drag a pane by its title strip to move it: onto another pane to stack with it, near a
  pane's edge to split that space, or to an empty edge of the window to open a panel there.
- Drag the thin bars between panes, and at a panel's inner edge, to resize them.
- Sizes and places are remembered across restarts.

## Commands

```
nanny                      what has arrived, and which toggles to turn on
nanny place <pane> <cell>  move a pane by name; 'nanny layout' lists where each one is
nanny reset                put every pane back in its default place and size
nanny off / nanny on       hide the whole panel (for a second session in MultiView) / bring it back
nanny log                  show or hide the GMCP log
nanny hello                ask the game for the packages again
nanny update               install the newest release
```

## Development

The package is built from `nannybasics.lua` and `border.lua` by `build.py`:

```
python build.py        # -> NannyBasics.xml
```

`border.lua` is the layout coordinator. The mapper carries an identical copy, and whichever
copy has the higher `REV` runs, whatever order the packages load in. Raise `REV` whenever the
file changes, and only ever add to what it offers: older packages keep calling it.

While developing, the package loads `nannybasics.lua` from disk first when it is present, so
`nanny reload` picks up edits without reinstalling. A normal install has no such file and
runs the copy built into the package.

## License

MIT — see [LICENSE](LICENSE).
