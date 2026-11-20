"""Build NannyBasics.mpackage (config.lua + NannyBasics.xml) from nannybasics.lua.

Two shared files are vendored identically with the mapper and prepended into the single
shipped script, so an installed copy carries them without needing separate files: the border
coordinator (border.lua) and the xml tag reader (xmlcore.lua). Each is wrapped in an
immediately-called function because it ends with a `return`, which would otherwise abort the
combined chunk. In the monorepo the mapper's copies are diffed against ours to catch drift.
xmlcolours.lua, NannyBasics' own, goes after the body.

Run from anywhere:  python basics/build.py
"""
import os
import sys
import re
import shutil
import subprocess
import tempfile
from xml.sax.saxutils import escape

here = os.path.dirname(os.path.abspath(__file__))

def rev_of(src):
    m = re.search(r'^local REV = (\d+)$', src, re.M)
    return int(m.group(1)) if m else 0

def vendored(name):
    src = open(os.path.join(here, name), encoding='utf-8').read()
    # Vendoring discipline: the copies must stay byte-identical. The mapper's copy is at
    # ../nmp/client/lua in the MUD repo and at ../mapper/lua in the public NannyMUD-mudlet repo.
    for mirror in (os.path.join(here, '..', 'nmp', 'client', 'lua', name),
                   os.path.join(here, '..', 'mapper', 'lua', name)):
        mirror = os.path.normpath(mirror)
        if os.path.isfile(mirror) and open(mirror, encoding='utf-8').read() != src:
            sys.exit('build: %s has drifted from\n  %s\nresync the two copies before building.' % (name, mirror))
    # The newest copy wins at load by its REV, so a changed file must carry a higher REV than
    # the committed one, or an older copy in another package could beat it. Checked against git
    # HEAD when there is one.
    try:
        # HEAD:./ is relative to cwd, so this works wherever the folder sits in its repo
        committed = subprocess.run(['git', 'show', 'HEAD:./' + name], cwd=here,
                                   capture_output=True, text=True, encoding='utf-8')
    except OSError:
        committed = None
    if committed and committed.returncode == 0 and committed.stdout.replace('\r\n', '\n') != src.replace('\r\n', '\n'):
        if rev_of(src) <= rev_of(committed.stdout):
            sys.exit('build: %s changed since the last commit but its REV is still %d; raise it.'
                     % (name, rev_of(src)))
    return src

border = vendored('border.lua')
xmlcore = vendored('xmlcore.lua')

body = open(os.path.join(here, 'nannybasics.lua'), encoding='utf-8').read()
colours = open(os.path.join(here, 'xmlcolours.lua'), encoding='utf-8').read()
changes = open(os.path.join(here, 'changes.lua'), encoding='utf-8').read()
# '_ =' keeps Lua 5.1 from reading '(function()' as a call of the line before. The parts that
# do not need the body go first: an error in the body's start-up then cannot skip them.
lua = '-- vendored border coordinator (see border.lua); shared byte-for-byte with the mapper.\n' \
      'local _ = (function()\n' + border + '\nend)()\n\n' \
      '-- vendored xml tag reader (see xmlcore.lua); shared byte-for-byte with the mapper.\n' \
      '_ = (function()\n' + xmlcore + '\nend)()\n\n' \
      '-- the game\'s colours in xml mode (see xmlcolours.lua)\n' \
      '_ = (function()\n' + colours + '\nend)()\n\n' \
      '-- what changed, release by release (see changes.lua)\n' \
      '_ = (function()\n' + changes + '\nend)()\n\n' + body

# the whole script must compile, or Mudlet runs none of it
lj = shutil.which('luajit')
if lj:
    with tempfile.NamedTemporaryFile('w', suffix='.lua', delete=False, encoding='utf-8') as t:
        t.write(lua)
    chunk = 'assert(loadfile([[' + t.name.replace('\\', '/') + ']]))'
    r = subprocess.run([lj, '-e', chunk], capture_output=True, text=True)
    os.remove(t.name)
    if r.returncode != 0:
        sys.exit('build: the script does not compile:\n' + r.stderr)
else:
    print('build: no luajit on PATH, the script was not compiled')

xml = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE MudletPackage>
<MudletPackage version="1.001">
\t<ScriptPackage>
\t\t<Script isActive="yes" isFolder="no">
\t\t\t<name>NannyBasics</name>
\t\t\t<packageName></packageName>
\t\t\t<script>%s</script>
\t\t\t<eventHandlerList />
\t\t</Script>
\t</ScriptPackage>
</MudletPackage>
''' % escape(lua)

out = os.path.join(here, 'NannyBasics.xml')
with open(out, 'w', encoding='utf-8', newline='\n') as f:
    f.write(xml)

# The .mpackage is what ships: the script plus a config.lua, whose version is what Mudlet's
# package manager (mpkg) compares. That version is N.VERSION, so it lives in one place.
import zipfile
m = re.search(r'^N\.VERSION = "([^"]+)"', body, re.M)
if not m:
    sys.exit('build: no N.VERSION = "..." line in nannybasics.lua')
config = '''mpackage = "NannyBasics"
title = "NannyBasics: gauges, score card, party, guild and chat panes for NannyMUD"
description = [[Draws NannyMUD's GMCP data: HP/SP and foe gauges, a score card, your party, your
guild, and a tabbed chat window. Shares one layout with the ElrohirMapper map. Type `nanny` once
installed, and `nanny update` to get a newer version.]]
version = "%s"
author = "Elrohir"
''' % m.group(1)
pkg = os.path.join(here, 'NannyBasics.mpackage')
with zipfile.ZipFile(pkg, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('config.lua', config)
    z.writestr('NannyBasics.xml', xml)
print('build: %s (version %s; %d bytes of Lua: %d border + %d body)'
      % (pkg, m.group(1), len(lua), len(border), len(body)))
