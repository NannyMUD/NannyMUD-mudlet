# NannyBasics

A small Mudlet package for [NannyMUD](https://nannymud.lysator.liu.se/) that draws the
game's GMCP data: health and spell-point gauges, your current foe, a score card, your party,
your guild, and channel messages in a tabbed window. Separate from the map; install both if
you want both, and they share one layout.

## What you get

- **Vitals bar** under the main text: HP and SP gauges that update as you fight and heal.
  The HP bar pulses, faster and brighter the lower it gets, once you drop below 40%. Above
  them, a **foe gauge**: who you are fighting and the shape they are in.
- **Score card**: your name, level and guild, a bar that fills with your NP within your level
  (at level 19 it shows your paragon level and the free experience toward the next, counting
  the million you keep after advancing). Past the target the rest of the bar turns gold, with
  the surplus beside it. The game stops sending a target once you reach it, so NannyBasics
  remembers each one for your character in the profile: a level it never saw short shows
  plain XP. Then gauges for
  toxicity, fullness, soak and carried weight, and gold, quest points, XP per hour and stats.
- **Party pane**: one row per member with HP and SP gauges, marked when they lead, follow,
  never follow, or are elsewhere.
- **Guild pane**, for the Strigoi, druids, alchemists and vampires. For the Strigoi: guild
  level and points, guild points per hour since your last `soultick reset`, penalty, wasp, your stack,
  and your stats with the guild's changes and harvest gains shown beside each. Cooldowns have
  a card of their own, where a bar per power fills as it recharges. The game does not say how
  long a cooldown lasts, so NannyBasics times each one as you use it; until it has, the bar
  counts up instead. Each power has an icon on its bar: dark tinted symbols by default, or emoji with 'nanny icons
  emoji' ('nanny icons dark' switches back). Your stack shows each power by a short name on
  a tinted ground; 'nanny stack icons' shows it as icons instead ('nanny stack chips' back). For a druid, barkskin
  gets a bar too, timed the same way, that empties as it wears off; the spells stored in
  your wand are listed with it, an Elder sees guild experience and place in the header,
  and what your owl reports gets a chat tab of its own. A vampire is sent no HP
  or SP, so its blood takes the whole vitals bar, and the pane shows generation, potency,
  age, veil, celerity and your vampire toggles. The vampire pane is built from the game's
  help and has not met a live vampire yet: if something looks wrong, send the
  `Guild.Vampire` line from `nanny log`.
- **Strigoi power rotation**: on the guild pane, a strip that sends the powers you listed, one
  at a time, only while you have a foe. See [Rotation](#rotation).
- **Cooldowns card**: a bar per cooldown, for the Strigoi's powers and for spells from the tome
  of spells, with the spell you have stored. See [Cooldowns](#cooldowns).
- **Chat pane**: one tab per channel, plus an "All" tab. A tab that gets a message while you
  are reading another one lights up.
- **GMCP log**, hidden by default (`nanny log`), for seeing the raw data.

## Install

Download `NannyBasics.mpackage` from the newest
[release](https://github.com/NannyMUD/NannyMUD-mudlet/releases/latest) and drag it onto the
Mudlet window. The same release has the map, `ElrohirMapper.mpackage`; drag both in together if
you want both.

**Updating.** When a newer release is out, you are told so shortly after Mudlet starts. Type
`nanny update`: it downloads the new package and swaps it in, and the map too if you have it.
If the download fails nothing is changed. Your layout is kept.

Then, in the game, switch on what you want: [In the game](#in-the-game) lists the toggles, and
each one is remembered when you log in again.

## Layout

The panes sit in a panel beside the text, by default in two columns under the map if you use
[the mapper](../mapper), with the vitals bar along the bottom.

[Dragging and clicking](#dragging-and-clicking) says how to move, resize and close them.

Newer Mudlet puts a starter interface of its own into new profiles, with a second map, chat and
bars. NannyBasics asks it to step aside the first time it loads; `baseui show` brings it back if
you prefer it.

<!-- help:begin (written by help_md.lua from nannybasics.lua: edit there) -->
## Commands

In Mudlet, `nanny help` lists these, `nanny help <command>` shows one in full and `nanny help <word>` finds every entry that mentions the word.

### Panes and layout

- **`nanny place <pane> <cell>`** Move a pane to a cell, the same as dragging it by its title strip. Bare 'nanny place' lists the cells; 'nanny layout' says where each pane is now.
- **`nanny hide <pane>`** Close a pane, the same as the X on its title strip. The panes: vitals, chat, score, cooldowns, party, guild and log.
- **`nanny show <pane>`** Bring a closed pane back, the same as its entry in the right-click menu of any strip or bar.
- **`nanny layout`** Where each pane is, and whether the GMCP log is shown.
- **`nanny chat split|join <tab>`** 'split' gives a chat tab a pane of its own, which you place like any other pane; 'join' puts it back among the tabs. The same by mouse: drag a tab out of the tab bar, or right-click it for 'Own pane'; drag the pane's strip onto the chat pane, or right-click the strip for 'Back into Chat'. Its messages still show under All. Remembered across restarts.
- **`nanny reset`** Put every pane back in its default place and size, closed ones too.
- **`nanny off`** Hide the whole panel, map and panes, so the text has the whole window: for a second session in MultiView. It stays off across restarts of this profile until 'nanny on'.
- **`nanny on`** Bring the panel back after 'nanny off'.

### The game's data

- **`nanny`** Which kinds of data the game has sent so far, and how often. A pane that stays empty usually needs its toggle in the game: 'nanny help game' lists them.
- **`nanny log`** Show or hide the GMCP log, the raw data as it arrives. Hidden by default.
- **`nanny hello`** Ask the game again for every kind of data NannyBasics reads; useful after a toggle in the game.
- **`nanny encoding [on|off]`** Players' text reaches you in whatever encoding their own client uses, so some players' letters come out wrong. With this on, the game is read as Latin-1, which keeps every byte, and UTF-8 and Windows text is turned back into the right letters; what you type goes out as Latin-1. On from the start; 'off' puts back the encoding your profile had before.

### Guilds

- **`nanny rot [set|use|del|off|key|auto|go|bind|open|trace]`** For the Strigoi: repeating a power costs you, so you mix several. Bare, your lists, the mode and the commands. 'set <name> <power>, <power>, ...' saves a list, written exactly as you would type the powers, and picks it; 'use <name>' picks one, 'del <name>' deletes one. 'off', 'key' and 'auto' set the mode: stopped, one power each time you press, or on its own. 'go' sends the next power in key mode, and 'bind <key>' puts that on a key such as F5 ('bind off' removes it). 'open <power>' starts each new fight with that power ('open off' stops). 'trace' prints every send, landing and refusal, or stops. It needs the foe gauge and the guild pane, and nothing goes out without a foe.
- **`nanny tome [probe|hide|show|relearn|forget] [spell]`** Bare, the spell you have stored and what the Cooldowns card has learned about each spell's cooldown. 'probe <spell>' learns a cooldown for you: after each release the spell is chanted every few seconds until a chant works, never while a spell is stored, and the game's refusals are hidden; it stops by itself once the cooldown is known, 'probe off' stops it at once. 'hide <spell>' hides a bar and keeps what was learned, 'show <spell>' brings it back. 'relearn' (or 'relearn <spell>') after something shortened your cooldowns: the bar says maybe from the release, and a few early tries find the new length. 'forget <spell>' wipes what was learned about a spell.
- **`nanny icons [dark|emoji]`** The icons on the cooldown bars, the Strigoi's powers and the tome's spells alike: dark symbols, or emoji.
- **`nanny stack [chips|icons]`** How the guild pane shows your stack: each power by a short name on a tinted ground (chips), or as icons.

### The package

- **`nanny help [command or word]`** Bare, this list. 'nanny help <command>' gives that command in full ('nanny help rot'); any other word lists every command and page that mentions it. The pages: 'nanny help mouse' (what dragging and clicking do) and 'nanny help game' (the toggles in the game).
- **`nanny update [file]`** Download the newest release and swap it in, the map too if you have it. If the download fails nothing is changed; your layout is kept. With a file, install that package file instead. Shortly after Mudlet starts you are told when a release is out.
- **`nanny src [path|off]`** For development: load nannybasics.lua from this path instead of the package's own copy, so 'nanny reload' picks up edits; 'off' goes back to the built-in copy from the next start.
- **`nanny reload`** Load the file set with 'nanny src' again.

## Dragging and clicking

- **Moving a pane.** Drag a pane by its title strip: onto another pane to stack with it, near a pane's edge to split that space, or to an empty edge of the window to open a panel there.
- **Resizing.** Drag the thin bars between panes, and at a panel's inner edge.
- **Closing.** The X at the right end of a title strip closes that pane. Right-click any strip or bar for a menu that shows closed panes again or resets the layout.
- **Chat tabs.** Drag a tab out of the chat's tab bar to give it a pane of its own, placed where you drop it; right-clicking the tab does the same. Drag that pane's strip back onto the chat pane, or right-click the strip, to put it back among the tabs.
- **The rotation strip.** On the Strigoi guild pane, left click steps the mode, right click picks the next list.

Sizes, places and closed panes are remembered across restarts.

## In the game

The game sends each kind of data only to players who ask. Each toggle is typed in the game and remembered when you log in again.

- `toggle gmcp`: GMCP itself; Mudlet has it on by default.
- `toggle gmcp vitals`: The HP and SP gauges and the body gauges.
- `toggle gmcp foe`: The foe gauge.
- `toggle gmcp channels`: The chat pane.
- `toggle gmcp status`: The score card.
- `toggle gmcp group`: The party pane.
- `toggle gmcp discord`: Discord status from your client.
- `toggle strigoi gmcp`: The guild pane, for the Strigoi.
- `toggle druids gmcp`: The guild pane, for druids.
- `toggle vampires gmcp`: The guild pane and your blood, for vampires.

<!-- help:end -->

## Rotation

For the Strigoi: repeating a power costs you, so you mix several. Write the commands yourself,
exactly as you would type them, and save as many lists as you like:

```
nanny rot                                     your lists, the mode, and this help
nanny rot set burn umbra, embrace, wildbound ghostveil
nanny rot use burn                            pick a list
nanny rot del burn                            delete one
nanny rot off | key | auto                    stopped, one power per press, or on its own
nanny rot go                                  send the next power, in key mode
nanny rot bind F5                             the same on a key ('nanny rot bind off' removes it)
nanny rot open wither                         start each fight with this ('nanny rot open off' stops)
nanny rot trace                               print every send, landing and refusal, or stop
```

The strip on the guild pane shows the mode, the list and the next power. Left click steps the
mode, right click the list. It needs the foe gauge and the guild pane on (`toggle gmcp foe`,
`toggle strigoi gmcp`), and nothing goes out without a foe.

A power counts as used when it shows up in your stack, and the next one goes out then. The game
updates the stack about one round late, so a power is only given up on after three updates. If
the game refuses a power, because it is on cooldown or you are out of spell points, the line
is hidden and the next power is tried at once. Refused for being too soon, the same power is
tried again a few times. The game says the same thing in a room without magic, so if every
power in the list is refused that way, the strip says "blocked", the line is shown again, and
only one try goes out every ten seconds until a power works or your foe changes.

An opener belongs to the rotation that is picked when you set it. It goes out when you get a
new foe, unless your stack already holds it, and does not move your place in the list. A new foe
is one with another name: the next of several guards with the same name does not count unless
the fight stopped in between.

You can still type powers yourself during a fight. Whichever reaches the game first goes off,
and the rotation carries on a round later.

## Cooldowns

A card with a bar for each cooldown: the Strigoi's powers, and spells chanted from the tome of
spells. For the Strigoi, harvest's bonus to your stats gets a bar while it lasts, its length
learned the same way as a cooldown's, from the game's line when a harvest works to its line
when the power fades. A second harvest starts the bar again. For the
tome it also shows the spell you have stored. Not every tome spell has a
cooldown, so a spell gets a bar the first time the game refuses it as too soon, named by the word
you chant. The cooldown starts when you release the spell, not when you chant it.

The game does not say how long a cooldown lasts or when it ends, so the card learns from what you
do. A chant refused as too soon shows the cooldown is longer than the time since you released the
spell; a chant that works shows it is no longer than that. A refusal is free, so to learn a spell
quickly, release it and try again every few seconds, or let `nanny tome probe <spell>` do that
for you: after each release it chants the spell every three seconds until a chant works, hides
the refusals, never chants while a spell is stored, and stops once the cooldown is known.
Until the two limits are within five
seconds of each other the bar says "maybe"; after that it is a plain countdown. If a spell is refused after its limit, something changed its length, and it is learned
again.

A cooldown that got shorter cannot show itself that way, since you have no reason to try early.
After learning something that shortens cooldowns, `nanny tome relearn` (or `nanny tome relearn
<spell>`) makes the bar say "maybe" from the release, and a few tries find the new length.

`nanny tome` lists what has been learned. `nanny tome hide <spell>` hides a bar you do not want
and keeps what was learned, `nanny tome show <spell>` brings it back, and `nanny tome forget
<spell>` wipes what was learned. The word
has to reach Mudlet as `chant <word>`, typed or from a Mudlet alias: a spell chanted through an
in-game alias is stored without a name and gets no bar.

## Development

The package is built from `nannybasics.lua` and `border.lua` by `build.py`:

```
python build.py        # -> NannyBasics.mpackage
```

`border.lua` is the layout coordinator. The mapper carries an identical copy, and whichever
copy has the higher `REV` runs, whatever order the packages load in. Raise `REV` whenever the
file changes, and only ever add to what it offers: older packages keep calling it.

While developing, `nanny src <path to your checkout's basics/nannybasics.lua>` makes the
package load that file instead of its built-in copy, so `nanny reload` picks up edits without
reinstalling; `nanny src off` goes back to the built-in copy. Tests:
`luajit basics/tests/test_<name>.lua` for each file in `tests/`.

The command reference above is written from the help tables in `nannybasics.lua` by
`luajit basics/help_md.lua`; run it after changing them, and `tests/test_help.lua` fails until
you do.

## License

MIT — see [LICENSE](LICENSE).
