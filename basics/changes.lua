-- What changed, release by release: 'nanny news' shows it, and tools/changelog.lua writes
-- CHANGELOG.md from it. An item is { what changed, the help that tells more }. The top entry
-- is "next" until a release gives it a number and a date.

NannyBasics = NannyBasics or {}
NannyBasics.CHANGES = {
  { version = "next", items = {
    { "The game's xml mode in your own colours: 'nanny xml on' switches it, your 'colour list' is read by itself.", "nanny help xml" },
    { "Hits can be coloured by their damage tier, with the tier in front ('nanny xml hits on').", "nanny help xml" },
  } },
  { version = "0.9.0", date = "2026-11-12", items = {
    { "nanny help is one lookup: an exact command shows it in full, any other word searches.", "nanny help" },
    { "The Cooldowns card has icons for every tome spell, 'nanny tome probe' and 'nanny tome hide/show'.", "nanny help tome" },
    { "Strigoi power rotation.", "nanny help rot" },
    { "The chat re-wraps when resized, and a tab can be dragged out into its own pane and back.", "nanny help chat" },
  } },
  { version = "0.8.5", date = "2026-10-30", items = {
    { "An X on each pane's strip closes it; right-clicking a strip or bar shows closed panes again.", "nanny help mouse" },
    { "Mudlet's starter interface steps aside for ours.", nil },
  } },
  { version = "0.8.4", date = "2026-10-27", items = {
    { "A border width set in Mudlet's preferences is kept as a margin outside the panels.", nil },
    { "The score card bar fills with NP within the level and turns gold past the target.", nil },
    { "Guild points per hour for the Strigoi.", nil },
  } },
  { version = "0.8.3", date = "2026-10-16", items = {
    { "Other players' letters are repaired whatever encoding their client sends.", "nanny help encoding" },
  } },
  { version = "0.8.1", date = "2026-10-10", items = {
    { "The Strigoi stack shows as chips in each power's colour.", "nanny help stack" },
  } },
  { version = "0.8.0", date = "2026-10-09", items = {
    { "Strigoi: a bar per cooldown with lengths learned in play, and icons for the powers.", "nanny help icons" },
    { "Druid: a barkskin bar, an Owl chat tab, the wand's stored spells and the Elder fields.", nil },
    { "Vampire: a guild pane, and blood in the vitals bar.", nil },
  } },
  { version = "0.7.1", date = "2026-10-06", items = {
    { "Guild panes for Druids and Alchemists.", nil },
    { "nanny update <file> installs a local build.", "nanny help update" },
  } },
  { version = "0.7.0", date = "2026-10-05", items = {
    { "NannyBasics ships as a package with one update command, shared with the mapper.", "nanny help update" },
    { "Score card, party and guild panes, in a layout you arrange by dragging.", "nanny help mouse" },
  } },
}
return NannyBasics.CHANGES
