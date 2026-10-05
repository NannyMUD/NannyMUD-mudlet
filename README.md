# NannyMUD-mudlet

[Mudlet](https://www.mudlet.org/) packages for [NannyMUD](https://nannymud.lysator.liu.se/).

| Folder | Package | What it does |
|---|---|---|
| [mapper](mapper) | `ElrohirMapper.mpackage` | Draws the map as you explore, from the game's map data. |
| [basics](basics) | `NannyBasics.xml` | Gauges, a score card, party and guild panes, and a tabbed chat window, from the game's GMCP data. |

Install either or both. Together they share one layout: the map and the panes sit in a panel
beside the text, and can be dragged around and resized.

## Install

Download the package from [Releases](https://github.com/NannyMUD/NannyMUD-mudlet/releases) and
drag it onto the Mudlet window. Each folder's README says what to switch on in the game.

Both packages tell you shortly after Mudlet starts when a newer release is out; `mapupdate` and
`nanny update` install it.

## Releases

The packages share one version number, and every release carries all of them, so the newest
release is always the one to get.

## Adding something

Put each new package or tool in a folder of its own, with a README, and add it to the table
above. A package that needs space on the screen can join the shared layout through `border.lua`
(a copy of it is in each package that uses it; the newest copy runs).
