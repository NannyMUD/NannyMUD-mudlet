# NannyBasics

A small Mudlet package for [NannyMUD](https://nannymud.lysator.liu.se/) that draws the
game's GMCP data: health and spell-point gauges, your current foe, and channel messages in
a tabbed window. Separate from the map; install both if you want both.

## What you get

- **Vitals bar** under the main text: HP and SP gauges that update as you fight and heal.
  The HP bar pulses, faster and brighter the lower it gets, once you drop below 40%.
- **Foe gauge** above them: who you are fighting and the shape they are in.
- **Channel pane**, docked on the right: one tab per channel, plus an "All" tab. A tab that
  gets a message while you are reading another one lights up.
- **GMCP log**, hidden by default (`nanny log`), for seeing the raw data.

## Install

Download `NannyBasics.xml` from [Releases](../../releases) and drag it onto the Mudlet
window.

Then, in the game, switch on what you want. Each setting is remembered when you log in again:

```
toggle gmcp            GMCP itself (Mudlet has it on by default)
toggle gmcp vitals     the HP/SP gauges
toggle gmcp foe        the foe gauge
toggle gmcp channels   the channel window
toggle gmcp discord    Discord status from your client
```

## Commands

```
nanny          what has arrived, and which toggles to turn on
nanny log      show or hide the GMCP log
nanny hello    ask the game for the packages again
```

## Development

The package is built from `nannybasics.lua` by `build.py`:

```
python build.py        # -> NannyBasics.xml
```

While developing, the package loads `nannybasics.lua` from disk first when it is present, so
`nanny reload` picks up edits without reinstalling. A normal install has no such file and
runs the copy built into the package.

## License

MIT — see [LICENSE](LICENSE).
