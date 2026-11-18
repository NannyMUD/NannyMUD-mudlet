# Changelog

What changed in each release of the mapper (ElrohirMapper) and NannyBasics. In the game,
'maphelp news' and 'nanny news' show the same. Written by tools/changelog.lua from
mapper/lua/changes.lua and basics/changes.lua: edit there.

## Not released yet

### Mapper

- mapmanual (experimental) maps an area the game sends no map for, from what its rooms show, taking it to be a grid; mapmanual same joins two rooms a warp makes look apart. (`maphelp mapmanual`)
- mapmobs notes the monsters each room shows in the game's xml mode, and tells wanderers from rare spawns. (`maphelp mapmobs`)
- mapnotes looks in one area with 'in <area>', and at monsters or your own notes alone with 'mobs' or 'notes'. (`maphelp mapnotes`)
- Clicking a room names the areas its exits lead to; mapflags puts that name at each blue arrow. (`maphelp mapflags`)
- A room's letter turns light blue while it has an unwalked up, down or named exit. (`maphelp mapglyphs`)
- maplevels and mapstitch now hold between logins. (`maphelp maplevels`)

### NannyBasics

- The game's xml mode in your own colours: 'nanny xml on' switches it, your 'colour list' is read by itself. (`nanny help xml`)
- Hits can be coloured by their damage tier, with the tier in front ('nanny xml hits on'). (`nanny help xml`)

## 0.9.1 (2026-11-12)

### Mapper

- A room on another level no longer gets the yellow mark of a room sitting on an edge. (`maplegend`)

## 0.9.0 (2026-11-12)

### Mapper

- maphelp is one lookup: an exact command shows it in full, any other word searches. (`maphelp`)
- mapvert stack puts each floor on its own level for Mudlet's 3D map. (`maphelp mapvert`)
- Stitching and the rings of other levels are off by default. (`maphelp maplevels`)
- A spell gate is no longer recorded as an exit. (`maphelp auto`)
- mapcoins (experimental) tells a maze's identical rooms apart by dropped coins. (`maphelp mapcoins`)

### NannyBasics

- nanny help is one lookup: an exact command shows it in full, any other word searches. (`nanny help`)
- The Cooldowns card has icons for every tome spell, 'nanny tome probe' and 'nanny tome hide/show'. (`nanny help tome`)
- Strigoi power rotation. (`nanny help rot`)
- The chat re-wraps when resized, and a tab can be dragged out into its own pane and back. (`nanny help chat`)

## 0.8.5 (2026-10-30)

### Mapper

- Room notes: mapnote, mapnotes, found by mapsearch, shown for a clicked room. (`maphelp mapnote`)
- mapimport joins another profile's map into this one, with mapimport undo. (`maphelp mapimport`)

### NannyBasics

- An X on each pane's strip closes it; right-clicking a strip or bar shows closed panes again. (`nanny help mouse`)
- Mudlet's starter interface steps aside for ours.

## 0.8.4 (2026-10-27)

### Mapper

- A room can hold several marks. (`maphelp mapmark`)

### NannyBasics

- A border width set in Mudlet's preferences is kept as a margin outside the panels.
- The score card bar fills with NP within the level and turns gold past the target.
- Guild points per hour for the Strigoi.

## 0.8.3 (2026-10-16)

### Mapper

- Two layout guards no longer let a move through that crosses a loop or bends edges.

### NannyBasics

- Other players' letters are repaired whatever encoding their client sends. (`nanny help encoding`)

## 0.8.2 (2026-10-16)

### Mapper

- A named mark saves the map at once. (`maphelp mapmark`)

## 0.8.1 (2026-10-10)

### NannyBasics

- The Strigoi stack shows as chips in each power's colour. (`nanny help stack`)

## 0.8.0 (2026-10-09)

### Mapper

- maprecordroute and maprecordundo record a way through ground that cannot be mapped. (`maphelp maprecordroute`)

### NannyBasics

- Strigoi: a bar per cooldown with lengths learned in play, and icons for the powers. (`nanny help icons`)
- Druid: a barkskin bar, an Owl chat tab, the wand's stored spells and the Elder fields.
- Vampire: a guild pane, and blood in the vitals bar.

## 0.7.1 (2026-10-06)

### Mapper

- The docked map follows you again when two characters map in the same Mudlet. (`maphelp mapwin`)

### NannyBasics

- Guild panes for Druids and Alchemists.
- nanny update <file> installs a local build. (`nanny help update`)

## 0.7.0 (2026-10-05)

### Mapper

- The mapper and NannyBasics share one repository, one version and one update command. (`maphelp mapupdate`)

### NannyBasics

- NannyBasics ships as a package with one update command, shared with the mapper. (`nanny help update`)
- Score card, party and guild panes, in a layout you arrange by dragging. (`nanny help mouse`)

## 0.6.0 (2026-10-05)

### Mapper

- The map docks in a panel on the right, shared with NannyBasics' panes. (`maphelp mapwin`)

## 0.5.0 (2026-10-04)

### Mapper

- The map is drawn from the game's GMCP room data, with exits the game declares. (`maphelp setup`)
- A speedwalk shows one prompt, not one per step. (`maphelp mapprompts`)
